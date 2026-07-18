import asyncio
import json
import traceback
from contextlib import suppress
from sanic.log import logger
import zstd

import worker.worker_pebble as wp


async def graceful_close(ws, args: dict):
	if ws.closed:
		return
	args["_close_request"] = ""
	try:
	    await ws.send(json.dumps(args))
	    await asyncio.sleep(0.3)
	    await ws.drain()
	    a = await ws.recv()
	    await asyncio.sleep(0.3)
	    #print(a)
	except Exception as e:
	    print(e)
	await ws.close()



async def _flush_and_close(ws, delay: float = 0.05):
	with suppress(Exception):
		await asyncio.sleep(delay)
		transport = getattr(ws, "_writer", None)
		if transport and hasattr(transport, "drain"):
			with suppress(Exception):
				await transport.drain()
	with suppress(Exception):
		await graceful_close(ws, {})



def get_body(frame):
	return json.loads(zstd.decompress(frame))


try:
	from websockets.exceptions import ConnectionClosed, ConnectionClosedOK, ConnectionClosedError
	_ClosedErrors = (ConnectionClosed, ConnectionClosedOK, ConnectionClosedError)
except Exception:
	_ClosedErrors = (Exception,)


async def _safe_send(ws, payload: dict) -> bool:
	try:
		await ws.send(json.dumps(payload))
		return True
	except _ClosedErrors:
		return False
	except Exception:
		logger.exception("ws.send failed")
		return False


async def _ping_task(ws, interval: float = 20.0):
	try:
		while True:
			await asyncio.sleep(interval)
			with suppress(Exception):
				await ws.ping()
	except asyncio.CancelledError:
		pass


async def stream_progress(ws, job_id: str):
	q = wp.progress_queue(job_id)
	killed = False

	pending_msgs: list[dict] = []
	worker_ready: bool = False

	if not await _safe_send(ws, {"job_id": job_id, "phase": "connected"}):
		wp.kill(job_id)
		killed = True
		return False

	async def recv_loop():
		nonlocal killed, worker_ready, pending_msgs
		try:
			async for raw in ws:
				try:
					msg = get_body(raw)
				except Exception:
					logger.warning("Bad frame from client\n%s", "".join(traceback.format_exc()))
					continue

				if isinstance(msg, dict) and msg.get("stop"):
					logger.info(f"recv_loop: stop signal from client for job {job_id}")
					wp.stop(job_id)
					killed = True
					break

				with suppress(Exception):
					if not worker_ready:
						pending_msgs.append(msg)
						logger.debug(f"Queued message before ready (job {job_id})")
					else:
						wp.send(job_id, msg)

		except _ClosedErrors:
			logger.info(f"recv_loop: client closed ({job_id})")
			wp.kill(job_id)
			killed = True
		except Exception:
			logger.exception("recv_loop crashed")
			wp.kill(job_id)
			killed = True

	recv_task = asyncio.create_task(recv_loop(), name=f"recv:{job_id}")
	ping_task = asyncio.create_task(_ping_task(ws), name=f"ping:{job_id}")

	try:
		while True:
			update = await q.get()
			if update is None:
				await asyncio.sleep(0)
				continue

			phase = update.get("phase")
			if phase == "start" and not worker_ready:
				worker_ready = True
				if pending_msgs:
					logger.info(f"Worker ready, flushing {len(pending_msgs)} queued messages for job {job_id}")
					with suppress(Exception):
						for msg in pending_msgs:
							wp.send(job_id, msg)
					pending_msgs.clear()

			if not await _safe_send(ws, update):
				logger.info(f"stream_progress: send failed, killing {job_id}")
				wp.kill(job_id)
				killed = True
				break

			if phase in ("done", "error", "stopped"):
				break

			done, result, err = wp.poll_result(job_id)
			if done:
				final = {"job_id": job_id}
				if err:
					final.update({"phase": "error", "error": err})
				else:
					final.update({"phase": "done", "result": result})
				await _safe_send(ws, final)
				break

			await asyncio.sleep(0)

	except asyncio.CancelledError:
		pass

	finally:
		for t in (recv_task, ping_task):
			t.cancel()
		with suppress(asyncio.CancelledError):
			await asyncio.gather(recv_task, ping_task)

		with suppress(Exception):
			if not getattr(ws, "closed", False):
				await _flush_and_close(ws, delay=0.1)

		with suppress(Exception):
			if not killed:
				wp.kill(job_id)
				logger.info(f"stream_progress: cleaned up naturally for {job_id}")
			else:
				logger.info(f"stream_progress: worker {job_id} was killed")

	return not killed
