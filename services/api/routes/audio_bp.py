from sanic import Blueprint
from sanic.response import json as sanic_json
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
import asyncio
from collections import deque
import io

import worker.worker_pebble as wp
import worker.worker_tasks as wt
import storage

bp_audio = Blueprint("audio", url_prefix="")

# batching control
_transcribe_queue = deque()
_batch_lock = asyncio.Lock()
per_audio_batch = 8
batch_timeout = 0.25


@bp_audio.post("/transcribe_file")
async def transcribe_file(request):
    db = request.app.ctx.database
    user = try_login(db, request.headers)
    if not user:
        return sanic_json({"answer": "wrong"})

    ctype = (request.headers.get("content-type") or "").lower()
    xdtype = (request.headers.get("x-dtype") or "").lower()
    body = request.body

    # --- Decode to float32 mono ---
    if "audio/wav" in ctype or xdtype == "wav":
        data, sr = sf.read(io.BytesIO(body), dtype="float32", always_2d=True)
        if data.shape[1] > 1:
            data = data.mean(axis=1)
        else:
            data = data[:, 0]
    else:
        sr = int(request.headers.get("X-Sample-Rate", "16000"))
        ch = int(request.headers.get("X-Channels", "1"))
        if xdtype == "int16":
            arr = np.frombuffer(body, dtype="<i2").astype(np.float32) / 32768.0
        elif xdtype == "float32":
            arr = np.frombuffer(body, dtype="<f4")
        else:
            return sanic_json({"answer": "unsupported_dtype"})
        if ch == 2:
            arr = arr.reshape(-1, 2).mean(axis=1)
        data = arr

    if not np.isfinite(data).all() or data.size == 0:
        return sanic_json({"ok": True, "text": "", "lang": "en"})

    peak = np.max(np.abs(data))
    if peak > 1e-6:
        data = np.clip(data / peak, -1.0, 1.0)

    TARGET_SR = 16000
    if sr != TARGET_SR:
        data = resample_poly(data, TARGET_SR, sr).astype(np.float32)
        sr = TARGET_SR

    loop = asyncio.get_event_loop()
    fut = loop.create_future()
    _transcribe_queue.append((data, "float32", sr, fut))

    if len(_transcribe_queue) >= per_audio_batch:
        loop.create_task(launch_batch())
    else:
        loop.create_task(schedule_batch())

    result = await fut
    return sanic_json(result)


def try_login(db, headers) -> storage.Node:
    from common.utils import kief
    import common.tools as tools

    if "user" not in headers or "pass" not in headers:
        return None
    user, pw = kief(headers["user"]), headers["pass"]
    root = db[f"/{user}/"]
    if not root.exists_rel("user.doc"):
        return None
    if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]):
        return None
    return root


async def schedule_batch():
    await asyncio.sleep(batch_timeout)
    if not _batch_lock.locked() and _transcribe_queue:
        await launch_batch()


async def launch_batch():
    if _batch_lock.locked():
        return
    async with _batch_lock:
        if not _transcribe_queue:
            return

        batch = [
            _transcribe_queue.popleft()
            for _ in range(min(per_audio_batch, len(_transcribe_queue)))
        ]
        packed = [{"audio": a, "dtype": d, "sample_rate": sr} for (a, d, sr, fut) in batch]

        job_id = wp.submit(wt.transcribe_batch_task, {"batch": packed})
        res = await wp.wait_done(job_id)

        if res and res[1] and "batch" in res[1]:
            for fut, r in zip((f for _, _, _, f in batch), res[1]["batch"]):
                if not fut.done():
                    fut.set_result(r)
