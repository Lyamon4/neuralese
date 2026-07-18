from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from time import time
from typing import Any

from .events import TrainingEvent


@dataclass
class TrainingJob:
    job_id: str
    name: str
    workspace: Path
    extracted_bundle: Any
    state: str = "queued"
    created_at: float = field(default_factory=time)
    updated_at: float = field(default_factory=time)
    latest: dict[str, Any] = field(default_factory=dict)
    snapshot_path: Path | None = None
    stop_event: asyncio.Event = field(default_factory=asyncio.Event)
    queue: asyncio.Queue[TrainingEvent] = field(default_factory=asyncio.Queue)

    async def emit(self, event: TrainingEvent) -> None:
        self.updated_at = time()
        self.latest = event.data
        await self.queue.put(event)


def create_job(root_dir: str | Path, name: str, extracted_bundle: Any) -> TrainingJob:
    root_dir = Path(root_dir)
    job_id = "job_" + uuid.uuid4().hex[:12]
    workspace = root_dir / "jobs" / job_id
    workspace.mkdir(parents=True, exist_ok=True)
    return TrainingJob(
        job_id=job_id,
        name=name,
        workspace=workspace,
        extracted_bundle=extracted_bundle,
    )
