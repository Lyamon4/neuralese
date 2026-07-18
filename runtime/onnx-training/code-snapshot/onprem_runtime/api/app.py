from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from typing import Any

import psutil
from fastapi import Depends, FastAPI, File, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from onprem_runtime.api.auth import require_http_auth, require_ws_auth
from onprem_runtime.api.dataset_routes import register_dataset_routes
from onprem_runtime.api.profiles import RuntimeProfile
from onprem_runtime.core.dataset_sync import DatasetSyncCache
from onprem_runtime.core.engine import TrainingEngine

from .schemas import JobSummary


def create_app(
    engine: Any,
    *,
    profile: RuntimeProfile | None = None,
    dataset_sync: DatasetSyncCache | None = None,
    public_datasets: dict[str, Any] | None = None,
) -> FastAPI:
    profile = profile or RuntimeProfile.local_school()
    app = FastAPI(title="Neuralese On-Prem Training Runtime")
    app.state.engine = engine
    app.state.profile = profile

    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException):
        return JSONResponse(
            status_code=exc.status_code,
            content=_error_payload(exc.detail),
            headers=getattr(exc, "headers", None),
        )

    register_dataset_routes(
        app,
        dataset_sync=dataset_sync or DatasetSyncCache(),
        public_datasets=public_datasets,
        auth_dependency=require_http_auth,
        websocket_auth=require_ws_auth,
    )

    auth = [Depends(require_http_auth)]

    @app.post("/api/jobs", dependencies=auth)
    async def create_job(bundle: UploadFile = File(...)):
        if not app.state.profile.enable_direct_upload:
            raise HTTPException(status_code=403, detail="direct upload disabled")
        if not bundle.filename or not bundle.filename.endswith(".zip"):
            raise HTTPException(status_code=400, detail="Upload must be a .zip ONNX training bundle")

        upload_dir = app.state.profile.storage_dir / "uploads"
        upload_dir.mkdir(parents=True, exist_ok=True)
        upload_path = upload_dir / Path(bundle.filename).name
        with upload_path.open("wb") as f:
            shutil.copyfileobj(bundle.file, f)

        job = await app.state.engine.submit_bundle(upload_path, job_name=upload_path.stem)
        return {"job_id": job.job_id, "state": job.state}

    @app.get("/api/jobs", response_model=list[JobSummary], dependencies=auth)
    def list_jobs():
        return [
            JobSummary(
                job_id=job.job_id,
                name=job.name,
                state=job.state,
                created_at=job.created_at,
                updated_at=job.updated_at,
                latest=job.latest,
                snapshot_ready=job.snapshot_path is not None and job.snapshot_path.exists(),
            )
            for job in app.state.engine.list_jobs()
        ]

    @app.post("/api/jobs/{job_id}/stop", dependencies=auth)
    def stop_job(job_id: str):
        if not app.state.engine.stop(job_id):
            raise HTTPException(status_code=404, detail="job not found")
        return {"ok": True}

    @app.post("/api/jobs/cleanup", dependencies=auth)
    def cleanup_jobs(max_age_seconds: float = 7 * 24 * 60 * 60):
        if max_age_seconds < 0:
            raise HTTPException(status_code=400, detail="max_age_seconds must be >= 0")
        return app.state.engine.cleanup_jobs(max_age_seconds=max_age_seconds)

    @app.get("/api/jobs/{job_id}/snapshot", dependencies=auth)
    def download_snapshot(job_id: str):
        job = _get_job_or_404(app.state.engine, job_id)
        if job.snapshot_path is None or not job.snapshot_path.exists():
            raise HTTPException(status_code=404, detail="snapshot not ready")
        return FileResponse(job.snapshot_path, filename=job.snapshot_path.name)

    @app.get("/api/stats", dependencies=auth)
    def stats():
        jobs = app.state.engine.list_jobs()
        return {
            "cpu_percent": psutil.cpu_percent(interval=0.0),
            "memory_percent": psutil.virtual_memory().percent,
            "active_jobs": len([job for job in jobs if job.state == "running"]),
            "total_jobs": len(jobs),
        }

    @app.get("/api/health")
    def health():
        return {"status": "ok", "mode": app.state.profile.mode}

    @app.get("/api/capacity", dependencies=auth)
    def capacity():
        jobs = app.state.engine.list_jobs()
        active_jobs = len([job for job in jobs if job.state == "running"])
        public_datasets = getattr(app.state, "public_datasets", {})
        return {
            "mode": app.state.profile.mode,
            "active_jobs": active_jobs,
            "max_parallel_jobs": app.state.profile.max_parallel_jobs,
            "available_slots": max(0, app.state.profile.max_parallel_jobs - active_jobs),
            "cached_public_datasets": sorted(public_datasets.keys()),
            "cached_local_fingerprints": app.state.dataset_sync.cached_fingerprints(),
        }

    @app.websocket("/ws/jobs/{job_id}")
    async def job_ws(ws: WebSocket, job_id: str):
        if not await require_ws_auth(ws):
            return
        await ws.accept()
        receive_task = asyncio.create_task(_receive_ws_commands(ws, app.state.engine, job_id))
        try:
            async for event in app.state.engine.subscribe(job_id):
                await ws.send_json(event.to_json())
                if event.phase in {"completed", "failed", "stopped"}:
                    return
        except WebSocketDisconnect:
            return
        finally:
            receive_task.cancel()

    if app.state.profile.enable_dashboard:
        dashboard_dir = Path(__file__).resolve().parents[1] / "dashboard"
        app.mount("/", StaticFiles(directory=dashboard_dir, html=True), name="dashboard")
    return app


def _get_job_or_404(engine: Any, job_id: str):
    try:
        return engine.get_job(job_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="job not found") from exc


def _error_payload(detail: Any) -> dict[str, Any]:
    if isinstance(detail, dict):
        message = str(detail.get("message") or detail.get("detail") or "request failed")
        code = str(detail.get("code") or _error_code_for_message(message))
        action = str(detail.get("action") or _error_action_for_message(message))
    else:
        message = str(detail)
        code = _error_code_for_message(message)
        action = _error_action_for_message(message)
    return {
        "detail": message,
        "error": {
            "code": code,
            "message": message,
            "action": action,
        },
    }


def _error_code_for_message(message: str) -> str:
    return {
        "Upload must be a .zip ONNX training bundle": "invalid_bundle_type",
        "direct upload disabled": "direct_upload_disabled",
        "job not found": "job_not_found",
        "snapshot not ready": "snapshot_not_ready",
        "max_age_seconds must be >= 0": "invalid_retention",
        "missing or invalid auth token": "auth_required",
    }.get(message, "request_failed")


def _error_action_for_message(message: str) -> str:
    return {
        "Upload must be a .zip ONNX training bundle": (
            "Select a .zip bundle generated by Neuralese and upload it again."
        ),
        "direct upload disabled": (
            "Run the node in local_school mode or submit jobs through the cloud scheduler."
        ),
        "job not found": "Check the job id and retry after the job has been created.",
        "snapshot not ready": "Wait until the job reaches completed and try downloading again.",
        "max_age_seconds must be >= 0": "Use a non-negative retention value in seconds.",
        "missing or invalid auth token": "Enter the API token configured for this runtime.",
    }.get(message, "Check the request and retry.")


async def _receive_ws_commands(ws: WebSocket, engine: Any, job_id: str) -> None:
    while True:
        try:
            message = await ws.receive_json()
        except WebSocketDisconnect:
            return
        if isinstance(message, dict) and message.get("type") == "stop":
            engine.stop(job_id)


class _NotConfiguredTrainer:
    async def train(self, job, emit, stop_requested):
        raise RuntimeError("Training backend is not configured yet")


app = create_app(TrainingEngine(Path(".neuralese_onprem"), _NotConfiguredTrainer()))
