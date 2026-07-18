from __future__ import annotations

from typing import Any

from fastapi import Depends, WebSocket, WebSocketDisconnect

from onprem_runtime.core.dataset_sync import DatasetSyncCache, DatasetSyncError


DEFAULT_PUBLIC_DATASETS: dict[str, dict[str, Any]] = {
    "mnist": {"id": "mnist", "name": "MNIST"},
    "titanic": {"id": "titanic", "name": "Titanic"},
    "iris": {"id": "iris", "name": "Iris"},
    "car_track": {"id": "car_track", "name": "Car Track"},
}


def register_dataset_routes(
    app: Any,
    *,
    dataset_sync: DatasetSyncCache,
    public_datasets: dict[str, Any] | None = None,
    auth_dependency: Any | None = None,
    websocket_auth: Any | None = None,
) -> None:
    catalog = public_datasets if public_datasets is not None else DEFAULT_PUBLIC_DATASETS
    app.state.dataset_sync = dataset_sync
    app.state.public_datasets = catalog
    dependencies = [Depends(auth_dependency)] if auth_dependency is not None else []

    @app.get("/api/datasets", dependencies=dependencies)
    def list_datasets():
        return {
            "status": "ok",
            "public": app.state.public_datasets,
            "cached_local_fingerprints": app.state.dataset_sync.cached_fingerprints(),
        }

    @app.websocket("/ws/datasets/sync")
    async def dataset_sync_ws(ws: WebSocket):
        if websocket_auth is not None and not await websocket_auth(ws):
            return
        await ws.accept()
        try:
            metadata = await ws.receive_json()
            user_id = str(metadata.get("user_id") or metadata.get("session") or "local")
            dataset_id = str(metadata.get("dataset_id") or metadata.get("name") or "unnamed")
            header = metadata.get("header") or {}
            block_hashes = metadata.get("block_hashes") or {"inputs": [], "outputs": []}
            hash_algo = str(metadata.get("hash_algo") or "sha256")

            need = app.state.dataset_sync.prepare_sync(
                user_id=user_id,
                dataset_id=dataset_id,
                header=header,
                block_hashes=block_hashes,
                hash_algo=hash_algo,
            )
            await ws.send_json(need)

            frames = await _receive_dataset_frames(ws)
            synced = app.state.dataset_sync.apply_frames(user_id, dataset_id, frames)
            await ws.send_json(
                {
                    "status": "ok",
                    "user_id": synced.user_id,
                    "dataset_id": synced.dataset_id,
                    "rows": synced.rows,
                    "fingerprint": synced.fingerprint,
                    "cached_local_fingerprints": app.state.dataset_sync.cached_fingerprints(),
                }
            )
        except WebSocketDisconnect:
            return
        except DatasetSyncError as exc:
            await ws.send_json({"status": "error", "error": str(exc)})
        except Exception as exc:
            await ws.send_json({"status": "error", "error": str(exc)})


async def _receive_dataset_frames(ws: WebSocket) -> list[bytes]:
    frames: list[bytes] = []
    while True:
        message = await ws.receive()
        if message.get("bytes") == b"__end__" or message.get("text") == "__end__":
            return frames
        if message.get("bytes") is not None:
            frames.append(message["bytes"])
