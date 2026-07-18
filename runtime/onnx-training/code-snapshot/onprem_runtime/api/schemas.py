from __future__ import annotations

from pydantic import BaseModel


class JobSummary(BaseModel):
    job_id: str
    name: str
    state: str
    created_at: float
    updated_at: float
    latest: dict
    snapshot_ready: bool
