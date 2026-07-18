import json
import zipfile

import pytest

from onprem_runtime.core.snapshot import SnapshotValidationError, create_snapshot_zip


def test_create_snapshot_zip_contains_model_metrics_and_manifest(tmp_path):
    job_dir = tmp_path / "job"
    job_dir.mkdir()
    inference = job_dir / "inference.onnx"
    metrics = job_dir / "metrics.jsonl"
    inference.write_bytes(b"trained-model")
    metrics.write_text('{"epoch":1,"train_loss":0.5}\n', encoding="utf-8")

    snapshot = create_snapshot_zip(
        job_dir=job_dir,
        job_id="job_123",
        manifest={"status": "completed"},
        inference_model=inference,
        metrics_jsonl=metrics,
        checkpoint_dir=None,
    )

    with zipfile.ZipFile(snapshot) as zf:
        assert sorted(zf.namelist()) == ["inference.onnx", "manifest.json", "metrics.jsonl"]
        assert json.loads(zf.read("manifest.json")) == {"status": "completed"}
        assert zf.read("inference.onnx") == b"trained-model"


def test_create_snapshot_zip_allows_missing_checkpoint_dir(tmp_path):
    job_dir = tmp_path / "job"
    job_dir.mkdir()
    inference = job_dir / "inference.onnx"
    metrics = job_dir / "metrics.jsonl"
    inference.write_bytes(b"trained-model")
    metrics.write_text('{"epoch":1}\n', encoding="utf-8")

    snapshot = create_snapshot_zip(
        job_dir=job_dir,
        job_id="job_123",
        manifest={"status": "completed"},
        inference_model=inference,
        metrics_jsonl=metrics,
        checkpoint_dir=job_dir / "missing-checkpoint",
    )

    with zipfile.ZipFile(snapshot) as zf:
        assert "checkpoint/" not in zf.namelist()
        assert "inference.onnx" in zf.namelist()
        assert "metrics.jsonl" in zf.namelist()


def test_create_snapshot_zip_requires_trained_model(tmp_path):
    job_dir = tmp_path / "job"
    job_dir.mkdir()
    metrics = job_dir / "metrics.jsonl"
    metrics.write_text('{"epoch":1}\n', encoding="utf-8")

    with pytest.raises(SnapshotValidationError, match="trained model"):
        create_snapshot_zip(
            job_dir=job_dir,
            job_id="job_123",
            manifest={"status": "completed"},
            inference_model=job_dir / "missing.onnx",
            metrics_jsonl=metrics,
            checkpoint_dir=None,
        )


def test_create_snapshot_zip_requires_metrics(tmp_path):
    job_dir = tmp_path / "job"
    job_dir.mkdir()
    inference = job_dir / "inference.onnx"
    inference.write_bytes(b"trained-model")

    with pytest.raises(SnapshotValidationError, match="metrics"):
        create_snapshot_zip(
            job_dir=job_dir,
            job_id="job_123",
            manifest={"status": "completed"},
            inference_model=inference,
            metrics_jsonl=job_dir / "missing.jsonl",
            checkpoint_dir=None,
        )
