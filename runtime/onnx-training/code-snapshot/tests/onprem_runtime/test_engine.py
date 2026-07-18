import asyncio
import os

from onprem_runtime.core.engine import TrainingEngine
from onprem_runtime.core.events import TrainingEvent


class FakeTrainer:
    async def train(self, job, emit, stop_requested):
        await emit(TrainingEvent(job.job_id, "started", {"backend": "fake"}))
        await emit(TrainingEvent(job.job_id, "epoch", {"epoch": 1, "epochs": 1}))
        snapshot_path = job.workspace / "snapshot.zip"
        snapshot_path.write_bytes(b"snapshot")
        return {"status": "completed", "snapshot_path": str(snapshot_path)}


class MissingSnapshotTrainer:
    async def train(self, job, emit, stop_requested):
        await emit(TrainingEvent(job.job_id, "started", {"backend": "fake"}))
        return {"status": "completed"}


def test_training_engine_runs_job_and_streams_events(tmp_path):
    async def run():
        engine = TrainingEngine(root_dir=tmp_path, trainer=FakeTrainer())
        job = await engine.submit_extracted(job_name="fake", extracted_bundle=None)

        phases = []
        async for event in engine.subscribe(job.job_id):
            phases.append(event.phase)

        assert phases == ["queued", "started", "epoch", "completed"]
        assert engine.get_job(job.job_id).state == "completed"

    asyncio.run(run())


def test_training_engine_fails_completed_job_without_snapshot(tmp_path):
    async def run():
        engine = TrainingEngine(root_dir=tmp_path, trainer=MissingSnapshotTrainer())
        job = await engine.submit_extracted(job_name="fake", extracted_bundle=None)

        phases = []
        failed_payload = None
        async for event in engine.subscribe(job.job_id):
            phases.append(event.phase)
            if event.phase == "failed":
                failed_payload = event.data

        assert phases == ["queued", "started", "failed"]
        assert engine.get_job(job.job_id).state == "failed"
        assert "snapshot" in failed_payload["error"]

    asyncio.run(run())


def test_training_engine_cleanup_removes_old_terminal_jobs(tmp_path):
    async def run():
        engine = TrainingEngine(root_dir=tmp_path, trainer=FakeTrainer())
        job = await engine.submit_extracted(job_name="fake", extracted_bundle=None)

        async for event in engine.subscribe(job.job_id):
            if event.phase == "completed":
                break

        job.updated_at = 10.0
        workspace = job.workspace

        result = engine.cleanup_jobs(max_age_seconds=5.0, now=20.0)

        assert result == {
            "removed_jobs": [job.job_id],
            "removed_orphan_workspaces": [],
            "retention_seconds": 5.0,
        }
        assert engine.list_jobs() == []
        assert not workspace.exists()

    asyncio.run(run())


def test_training_engine_cleanup_keeps_recent_or_active_jobs(tmp_path):
    async def run():
        engine = TrainingEngine(root_dir=tmp_path, trainer=FakeTrainer())
        job = await engine.submit_extracted(job_name="fake", extracted_bundle=None)

        async for event in engine.subscribe(job.job_id):
            if event.phase == "completed":
                break

        job.updated_at = 19.0
        job.state = "running"
        workspace = job.workspace

        result = engine.cleanup_jobs(max_age_seconds=5.0, now=20.0)

        assert result["removed_jobs"] == []
        assert engine.get_job(job.job_id) is job
        assert workspace.exists()

    asyncio.run(run())


def test_training_engine_cleanup_removes_old_orphan_workspaces_after_restart(tmp_path):
    engine = TrainingEngine(root_dir=tmp_path, trainer=FakeTrainer())
    orphan = tmp_path / "jobs" / "job_orphan"
    orphan.mkdir(parents=True)
    (orphan / "snapshot.zip").write_bytes(b"old")
    os.utime(orphan, (10.0, 10.0))

    result = engine.cleanup_jobs(max_age_seconds=5.0, now=20.0)

    assert result == {
        "removed_jobs": [],
        "removed_orphan_workspaces": ["job_orphan"],
        "retention_seconds": 5.0,
    }
    assert not orphan.exists()
