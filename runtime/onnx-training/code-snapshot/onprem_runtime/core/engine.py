from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from time import time
from typing import Any, AsyncIterator

from .bundle import extract_training_bundle
from .events import TrainingEvent
from .jobs import TrainingJob, create_job


class TrainingEngine:
    def __init__(self, root_dir: str | Path, trainer: Any):
        self.root_dir = Path(root_dir)
        self.root_dir.mkdir(parents=True, exist_ok=True)
        self.trainer = trainer
        self._jobs: dict[str, TrainingJob] = {}

    async def submit_bundle(self, bundle_path: str | Path, job_name: str | None = None) -> TrainingJob:
        bundle_path = Path(bundle_path)
        job = create_job(self.root_dir, job_name or bundle_path.stem, None)
        job.extracted_bundle = extract_training_bundle(bundle_path, job.workspace / "bundle")
        self._jobs[job.job_id] = job
        await job.emit(TrainingEvent(job.job_id, "queued", {"name": job.name}))
        asyncio.create_task(self._run_job(job))
        return job

    async def submit_extracted(self, job_name: str, extracted_bundle: Any) -> TrainingJob:
        job = create_job(self.root_dir, job_name, extracted_bundle)
        self._jobs[job.job_id] = job
        await job.emit(TrainingEvent(job.job_id, "queued", {"name": job.name}))
        asyncio.create_task(self._run_job(job))
        return job

    async def _run_job(self, job: TrainingJob) -> None:
        try:
            job.state = "running"

            async def emit(event: TrainingEvent) -> None:
                await job.emit(event)

            result = await self.trainer.train(job, emit, job.stop_event.is_set)
            if job.stop_event.is_set() or result.get("status") == "stopped":
                job.state = "stopped"
                await job.emit(TrainingEvent(job.job_id, "stopped", result))
                return

            snapshot_path = result.get("snapshot_path")
            if not snapshot_path:
                raise RuntimeError("completed training did not produce a snapshot")
            snapshot_path = Path(snapshot_path)
            if not snapshot_path.is_file():
                raise RuntimeError(f"completed training snapshot is missing: {snapshot_path}")
            job.snapshot_path = snapshot_path
            job.state = "completed"
            await job.emit(TrainingEvent(job.job_id, "completed", result))
        except Exception as exc:
            job.state = "failed"
            await job.emit(TrainingEvent(job.job_id, "failed", {"error": str(exc)}))

    def stop(self, job_id: str) -> bool:
        job = self._jobs.get(job_id)
        if job is None:
            return False
        job.stop_event.set()
        return True

    def get_job(self, job_id: str) -> TrainingJob:
        return self._jobs[job_id]

    def list_jobs(self) -> list[TrainingJob]:
        return sorted(self._jobs.values(), key=lambda item: item.created_at, reverse=True)

    def cleanup_jobs(
        self,
        *,
        max_age_seconds: float,
        now: float | None = None,
    ) -> dict[str, Any]:
        now_value = time() if now is None else float(now)
        retention = max(0.0, float(max_age_seconds))
        terminal_states = {"completed", "failed", "stopped"}
        removed_jobs: list[str] = []

        for job_id, job in list(self._jobs.items()):
            if job.state not in terminal_states:
                continue
            if now_value - job.updated_at < retention:
                continue
            shutil.rmtree(job.workspace, ignore_errors=True)
            removed_jobs.append(job_id)
            del self._jobs[job_id]

        tracked_workspaces = {job.workspace.resolve() for job in self._jobs.values()}
        removed_orphans: list[str] = []
        jobs_dir = self.root_dir / "jobs"
        if jobs_dir.is_dir():
            for workspace in sorted(item for item in jobs_dir.iterdir() if item.is_dir()):
                resolved = workspace.resolve()
                if resolved in tracked_workspaces:
                    continue
                try:
                    age = now_value - workspace.stat().st_mtime
                except FileNotFoundError:
                    continue
                if age < retention:
                    continue
                shutil.rmtree(workspace, ignore_errors=True)
                removed_orphans.append(workspace.name)

        return {
            "removed_jobs": removed_jobs,
            "removed_orphan_workspaces": removed_orphans,
            "retention_seconds": retention,
        }

    async def subscribe(self, job_id: str) -> AsyncIterator[TrainingEvent]:
        job = self._jobs[job_id]
        while True:
            event = await job.queue.get()
            yield event
            if event.phase in {"completed", "failed", "stopped"}:
                break
