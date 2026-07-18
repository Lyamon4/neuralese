from __future__ import annotations

from types import SimpleNamespace

from fastapi.testclient import TestClient

from onprem_runtime.api.app import create_app
from onprem_runtime.api.profiles import RuntimeProfile
from onprem_runtime.core.dataset_sync import DatasetSyncCache, build_dataset_frame


class ProfileEngine:
    def __init__(self, states: list[str] | None = None) -> None:
        self.states = states or []
        self.submit_calls = 0

    def list_jobs(self):
        return [
            SimpleNamespace(
                job_id=f"job_{index}",
                name=f"job {index}",
                state=state,
                created_at=1.0,
                updated_at=2.0,
                latest={},
                snapshot_path=None,
            )
            for index, state in enumerate(self.states)
        ]

    def get_job(self, job_id):
        raise KeyError(job_id)

    def stop(self, job_id):
        return False

    async def submit_bundle(self, upload_path, job_name):
        self.submit_calls += 1
        return SimpleNamespace(job_id="job_new", state="queued")


def test_runtime_profile_defaults_for_local_school_and_cloud_node() -> None:
    local = RuntimeProfile.local_school()
    cloud = RuntimeProfile.cloud_node(max_parallel_jobs=3)

    assert local.mode == "local_school"
    assert local.enable_dashboard is True
    assert local.enable_direct_upload is True
    assert local.enable_cloud_registration is False
    assert local.auth_token is None
    assert cloud.mode == "cloud_node"
    assert cloud.enable_dashboard is False
    assert cloud.enable_direct_upload is False
    assert cloud.enable_cloud_registration is True
    assert cloud.max_parallel_jobs == 3


def test_runtime_profile_reads_optional_auth_token_from_env(monkeypatch) -> None:
    monkeypatch.setenv("NEURALESE_AUTH_TOKEN", "school-secret")

    profile = RuntimeProfile.from_env()

    assert profile.auth_token == "school-secret"


def test_health_and_capacity_reflect_profile_jobs_and_dataset_cache() -> None:
    sync_cache = DatasetSyncCache()
    payload = b"cached"
    import hashlib

    digest = hashlib.sha256(payload).hexdigest()
    sync_cache.prepare_sync("teacher", "local", {"rows": 1}, {"inputs": [[digest]], "outputs": []})
    synced = sync_cache.apply_frames("teacher", "local", [build_dataset_frame("inputs", 0, 0, payload)])
    client = TestClient(
        create_app(
            ProfileEngine(["running", "queued", "completed"]),
            profile=RuntimeProfile.cloud_node(max_parallel_jobs=2),
            dataset_sync=sync_cache,
            public_datasets={"mnist": {}, "iris": {}},
        )
    )

    health = client.get("/api/health")
    capacity = client.get("/api/capacity")

    assert health.status_code == 200
    assert health.json() == {"status": "ok", "mode": "cloud_node"}
    assert capacity.status_code == 200
    assert capacity.json() == {
        "mode": "cloud_node",
        "active_jobs": 1,
        "max_parallel_jobs": 2,
        "available_slots": 1,
        "cached_public_datasets": ["iris", "mnist"],
        "cached_local_fingerprints": [synced.fingerprint],
    }


def test_cloud_node_can_disable_direct_upload() -> None:
    engine = ProfileEngine()
    client = TestClient(
        create_app(engine, profile=RuntimeProfile.cloud_node(enable_direct_upload=False))
    )

    response = client.post(
        "/api/jobs",
        files={"bundle": ("bundle.zip", b"fake", "application/zip")},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "direct upload disabled"
    assert engine.submit_calls == 0


def test_cloud_node_can_disable_dashboard() -> None:
    client = TestClient(create_app(ProfileEngine(), profile=RuntimeProfile.cloud_node()))

    response = client.get("/")

    assert response.status_code == 404
