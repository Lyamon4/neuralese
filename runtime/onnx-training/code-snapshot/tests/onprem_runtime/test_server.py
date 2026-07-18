from __future__ import annotations

from fastapi.testclient import TestClient

from onprem_runtime.api.profiles import RuntimeProfile
from onprem_runtime.api.server import build_runtime_app
from onprem_runtime.core.dataset_sync import build_dataset_frame
from onprem_runtime.core.ort_trainer import OrtBundleTrainer


class NoopTrainer:
    async def train(self, job, emit, stop_requested):
        raise RuntimeError("not used in this test")


def test_build_runtime_app_uses_env_profile_for_cloud_node(monkeypatch, tmp_path) -> None:
    storage_dir = tmp_path / "cloud-runtime"
    monkeypatch.setenv("NEURALESE_RUNTIME_MODE", "cloud_node")
    monkeypatch.setenv("NEURALESE_STORAGE_DIR", str(storage_dir))
    monkeypatch.setenv("NEURALESE_MAX_PARALLEL_JOBS", "4")

    app = build_runtime_app(trainer=NoopTrainer())
    client = TestClient(app)

    assert app.state.profile.mode == "cloud_node"
    assert app.state.engine.root_dir == storage_dir
    assert storage_dir.exists()
    assert client.get("/api/health").json() == {"status": "ok", "mode": "cloud_node"}
    assert client.get("/api/capacity").json()["max_parallel_jobs"] == 4
    assert client.get("/").status_code == 404


def test_build_runtime_app_accepts_explicit_local_school_profile(tmp_path) -> None:
    profile = RuntimeProfile.local_school(storage_dir=tmp_path / "school-runtime")

    app = build_runtime_app(profile=profile, trainer=NoopTrainer())
    client = TestClient(app)

    assert app.state.profile.mode == "local_school"
    assert app.state.engine.root_dir == profile.storage_dir
    assert profile.storage_dir.exists()
    assert client.get("/api/health").json() == {"status": "ok", "mode": "local_school"}
    assert client.get("/").status_code == 200


def test_build_runtime_app_uses_ort_trainer_by_default(tmp_path) -> None:
    profile = RuntimeProfile.local_school(storage_dir=tmp_path / "runtime")

    app = build_runtime_app(profile=profile)

    assert isinstance(app.state.engine.trainer, OrtBundleTrainer)


def test_build_runtime_app_persists_dataset_sync_cache_in_storage_dir(tmp_path) -> None:
    profile = RuntimeProfile.local_school(storage_dir=tmp_path / "runtime")
    first_app = build_runtime_app(profile=profile)
    payload = b"\x00\x01"
    import hashlib

    digest = hashlib.sha256(payload).hexdigest()
    header = {"rows": 1, "inputs_count": 1, "outputs_count": 0, "columns": {}}
    hashes = {"inputs": [[digest]], "outputs": []}
    first_app.state.dataset_sync.prepare_sync("teacher", "local-1", header, hashes)
    synced = first_app.state.dataset_sync.apply_frames(
        "teacher",
        "local-1",
        [build_dataset_frame("inputs", 0, 0, payload)],
    )

    restarted_app = build_runtime_app(profile=profile)
    restored = restarted_app.state.dataset_sync.get_synced_dataset("teacher", "local-1")

    assert restored.fingerprint == synced.fingerprint
    assert restored.packet == synced.packet
