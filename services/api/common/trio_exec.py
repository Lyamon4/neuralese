
from __future__ import annotations
from typing import Dict, Any
import nns.model_core as nodes
from worker import worker_pebble as wp
from worker import trio_tasks as tt
from common.stream_progressor import stream_progress

# ---- core primitives ----
async def train_ws_exec(ws, graph: dict, ctx, args: Dict[str, Any]) -> object:
	args2 = dict(args)
	args2["graph"] = graph
	args2["context"] = ctx

	job_id = wp.submit(tt.train_task, args2)
	await stream_progress(ws, job_id)
	await wp.wait_done(job_id)
	return ctx


async def infer_ws_exec(ws, graph: dict, ctx, args: Dict[str, Any]) -> None:
	args2 = dict(args)
	args2["graph"] = graph
	args2["context"] = ctx

	job_id = wp.submit(tt.infer_task, args2)
	await stream_progress(ws, job_id)


async def export_exec(graph: dict, ctx, flags: Dict[str, Any]) -> Dict[str, Any]:
	payload = {"graph": graph, "ctx": ctx, "flags": flags}
	job_id = wp.submit(tt.export_nn_task, payload)
	return await wp.wait_done(job_id)

def get_contexts():
	pass
