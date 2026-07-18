from __future__ import annotations

import json
import zipfile

import numpy as np
from fastapi.testclient import TestClient

from onprem_runtime.api.profiles import RuntimeProfile
from onprem_runtime.api.server import build_runtime_app
from onprem_runtime.core.dataset_compression import compress_blocks
from onprem_runtime.core.dataset_sync import build_dataset_frame
from onprem_runtime.core.ort_trainer import OrtBundleTrainer
from onprem_runtime.examples.make_dummy_bundle import create_dummy_bundle


def test_upload_bundle_streams_training_events_and_downloads_snapshot(tmp_path) -> None:
    bundle_path = create_dummy_bundle(tmp_path / "dummy_bundle.zip", epochs=2)
    app = build_runtime_app(
        profile=RuntimeProfile.local_school(storage_dir=tmp_path / "runtime"),
        trainer=OrtBundleTrainer(seed=123),
    )

    with TestClient(app) as client:
        with bundle_path.open("rb") as bundle_file:
            created = client.post(
                "/api/jobs",
                files={"bundle": ("dummy_bundle.zip", bundle_file, "application/zip")},
            )

        assert created.status_code == 200
        job_id = created.json()["job_id"]
        assert created.json()["state"] == "queued"

        phases = []
        with client.websocket_connect(f"/ws/jobs/{job_id}") as ws:
            while True:
                event = ws.receive_json()
                phases.append(event["phase"])
                if event["phase"] in {"completed", "failed", "stopped"}:
                    final_event = event
                    break

        assert phases == ["queued", "started", "epoch", "epoch", "completed"]
        assert final_event["data"]["status"] == "completed"

        jobs = client.get("/api/jobs")
        assert jobs.status_code == 200
        assert jobs.json()[0]["snapshot_ready"] is True

        snapshot = client.get(f"/api/jobs/{job_id}/snapshot")
        assert snapshot.status_code == 200
        snapshot_path = tmp_path / "snapshot.zip"
        snapshot_path.write_bytes(snapshot.content)

    with zipfile.ZipFile(snapshot_path) as zf:
        assert {"manifest.json", "inference.onnx", "metrics.jsonl"}.issubset(zf.namelist())
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
        metrics = zf.read("metrics.jsonl").decode("utf-8").splitlines()

    assert manifest["status"] == "completed"
    assert manifest["backend"] == "onnxruntime_training"
    assert len(metrics) == 2


def test_public_dataset_ref_bundle_uses_server_side_public_dataset_cache(tmp_path) -> None:
    public_dataset_dir = tmp_path / "public_datasets"
    _write_tiny_public_dataset(public_dataset_dir / "tiny_public")
    bundle_path = create_dummy_bundle(
        tmp_path / "public_ref_bundle.zip",
        epochs=1,
        dataset_ref={"type": "public", "id": "tiny_public"},
        include_dataset=False,
    )
    app = build_runtime_app(
        profile=RuntimeProfile.local_school(storage_dir=tmp_path / "runtime"),
        public_dataset_dir=public_dataset_dir,
    )

    with TestClient(app) as client:
        catalog = client.get("/api/datasets")
        assert catalog.status_code == 200
        assert "tiny_public" in catalog.json()["public"]

        with bundle_path.open("rb") as bundle_file:
            created = client.post(
                "/api/jobs",
                files={"bundle": ("public_ref_bundle.zip", bundle_file, "application/zip")},
            )
        job_id = created.json()["job_id"]

        with client.websocket_connect(f"/ws/jobs/{job_id}") as ws:
            while True:
                event = ws.receive_json()
                if event["phase"] in {"completed", "failed", "stopped"}:
                    final_event = event
                    break

        assert final_event["phase"] == "completed"
        assert final_event["data"]["status"] == "completed"
        snapshot = client.get(f"/api/jobs/{job_id}/snapshot")
        assert snapshot.status_code == 200
        snapshot_path = tmp_path / "public_snapshot.zip"
        snapshot_path.write_bytes(snapshot.content)

    with zipfile.ZipFile(snapshot_path) as zf:
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    assert manifest["dataset_source"] == "public"
    assert manifest["dataset_id"] == "tiny_public"


def test_local_dataset_ref_bundle_uses_incrementally_synced_dataset(tmp_path) -> None:
    compressed = _compressed_tiny_local_dataset()
    app = build_runtime_app(profile=RuntimeProfile.local_school(storage_dir=tmp_path / "runtime"))

    with TestClient(app) as client:
        with client.websocket_connect("/ws/datasets/sync") as ws:
            ws.send_json(
                {
                    "user_id": "local",
                    "dataset_id": "local-or",
                    "header": compressed["header"],
                    "block_hashes": _block_hashes(compressed),
                    "hash_algo": "sha256",
                }
            )
            need = ws.receive_json()
            assert need == {
                "inputs": {"0": [0], "1": [0]},
                "outputs": {"0": [0]},
            }
            _send_missing_blocks(ws, compressed, need)
            ws.send_text("__end__")
            synced = ws.receive_json()

        assert synced["status"] == "ok"
        fingerprint = synced["fingerprint"]
        bundle_path = create_dummy_bundle(
            tmp_path / "local_ref_bundle.zip",
            epochs=1,
            dataset_ref={
                "type": "local",
                "id": "local-or",
                "fingerprint": fingerprint,
            },
            include_dataset=False,
        )

        with bundle_path.open("rb") as bundle_file:
            created = client.post(
                "/api/jobs",
                files={"bundle": ("local_ref_bundle.zip", bundle_file, "application/zip")},
            )
        assert created.status_code == 200
        job_id = created.json()["job_id"]

        with client.websocket_connect(f"/ws/jobs/{job_id}") as ws:
            while True:
                event = ws.receive_json()
                if event["phase"] in {"completed", "failed", "stopped"}:
                    final_event = event
                    break

        assert final_event["phase"] == "completed"
        snapshot = client.get(f"/api/jobs/{job_id}/snapshot")
        assert snapshot.status_code == 200
        snapshot_path = tmp_path / "local_snapshot.zip"
        snapshot_path.write_bytes(snapshot.content)

    with zipfile.ZipFile(snapshot_path) as zf:
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    assert manifest["dataset_source"] == "local"
    assert manifest["dataset_id"] == "local-or"
    assert manifest["dataset_fingerprint"] == fingerprint


def test_invalid_bundle_streams_readable_failed_event(tmp_path) -> None:
    bundle_path = create_dummy_bundle(tmp_path / "invalid_bundle.zip", epochs=1)
    _rewrite_manifest(
        bundle_path,
        lambda manifest: {**manifest, "trainable_parameters": ["missing_weight"]},
    )
    app = build_runtime_app(
        profile=RuntimeProfile.local_school(storage_dir=tmp_path / "runtime"),
        trainer=OrtBundleTrainer(seed=123),
    )

    with TestClient(app) as client:
        with bundle_path.open("rb") as bundle_file:
            created = client.post(
                "/api/jobs",
                files={"bundle": ("invalid_bundle.zip", bundle_file, "application/zip")},
            )
        job_id = created.json()["job_id"]

        with client.websocket_connect(f"/ws/jobs/{job_id}") as ws:
            while True:
                event = ws.receive_json()
                if event["phase"] in {"completed", "failed", "stopped"}:
                    final_event = event
                    break

        assert final_event["phase"] == "failed"
        assert "trainable parameter 'missing_weight' was not found" in final_event["data"]["error"]
        assert "available initializers: W, b" in final_event["data"]["error"]


def _write_tiny_public_dataset(dataset_dir) -> None:
    dataset_dir.mkdir(parents=True)
    x = np.array(
        [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]],
        dtype=np.float32,
    )
    y = np.array([0, 1, 1, 1], dtype=np.int64)
    np.savez(dataset_dir / "train.npz", x=x, y=y, val_x=x, val_y=y)
    (dataset_dir / "meta.json").write_text(
        json.dumps({"id": "tiny_public", "name": "Tiny Public"}),
        encoding="utf-8",
    )


def _compressed_tiny_local_dataset() -> dict:
    return compress_blocks(
        {
            "arr": [
                [{"type": "num", "num": 0}, {"type": "num", "num": 0}, {"type": "num", "num": 0}],
                [{"type": "num", "num": 0}, {"type": "num", "num": 1}, {"type": "num", "num": 1}],
                [{"type": "num", "num": 1}, {"type": "num", "num": 0}, {"type": "num", "num": 1}],
                [{"type": "num", "num": 1}, {"type": "num", "num": 1}, {"type": "num", "num": 1}],
            ],
            "col_names": ["X0:num", "X1:num", "Class:num"],
            "outputs_from": 2,
            "col_args": [
                {"min": 0, "max": 1},
                {"min": 0, "max": 1},
                {"min": 0, "max": 1},
            ],
        }
    )


def _block_hashes(compressed: dict) -> dict:
    return {
        "inputs": [column["hashes"] for column in compressed["data"][0]],
        "outputs": [column["hashes"] for column in compressed["data"][1]],
    }


def _send_missing_blocks(ws, compressed: dict, need: dict) -> None:
    for side_name, side_index in (("inputs", 0), ("outputs", 1)):
        for col_index, column in enumerate(compressed["data"][side_index]):
            for block_index in need[side_name][str(col_index)]:
                ws.send_bytes(
                    build_dataset_frame(
                        side_name,
                        col_index,
                        block_index,
                        bytes.fromhex(column["blocks"][block_index]),
                    )
                )


def _rewrite_manifest(bundle_path, update):
    rewritten_path = bundle_path.with_suffix(".rewritten.zip")
    with zipfile.ZipFile(bundle_path) as source, zipfile.ZipFile(
        rewritten_path,
        "w",
        compression=zipfile.ZIP_DEFLATED,
    ) as target:
        manifest = json.loads(source.read("manifest.json").decode("utf-8"))
        manifest = update(manifest)
        for item in source.infolist():
            if item.filename == "manifest.json":
                target.writestr("manifest.json", json.dumps(manifest).encode("utf-8"))
            else:
                target.writestr(item, source.read(item.filename))
    rewritten_path.replace(bundle_path)
