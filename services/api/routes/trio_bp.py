from sanic import Blueprint
from sanic.response import raw, json as sanic_json
from common.utils import graceful_close, kief
import common.tools as tools
import storage, json
from common.stream_progressor import get_body
from common.trio_exec import train_ws_exec, infer_ws_exec, export_exec
from common.context_cache import contexts
from common.context_cache import task_state
import nns.model_core as nodes
from worker import worker_pebble as wp
from worker import worker_tasks as wt
from nns.sections.hooks import prepare_ctx_for_sections, maybe_register_sections_after_training


bp_trio = Blueprint("trio", url_prefix="/")

def try_login(app, data) -> storage.Node:
	db = app.ctx.database
	user, pw = kief(data["user"]), data["pass"]
	root = db[f"/{user}/"]
	if not root.exists_rel("user.doc"): return None
	if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]): return None
	return root

import io
from common.context_cache import _make_ctx_key
def get_or_load_ctx(node, scene_id: str, ctx_name: str, graph: dict):
	key = _make_ctx_key(node, scene_id, ctx_name)
	if key in contexts:
		return contexts[key]
	ctx = nodes.gen_context()
	blob = node.child(f"projects/{scene_id}/contexts").read_rel(f"{ctx_name}.blob")
	if blob:
		nodes.load_model(ctx, io.BytesIO(blob))
		nodes.execute_graph(graph, ctx)
	contexts[key] = ctx
	return ctx

from common.context_cache import is_training, is_inferring, infer_mark_started, training_mark_started, training_mark_stopped, infer_mark_stopped
@bp_trio.post("/delete_ctx")
async def delete_ctx(request):
    node = try_login(request.app, request.json)
    if node is None:
        return sanic_json({"answer": "wrong"})

    scene_id = request.json["scene"]
    if not scene_id.isdigit():
        return sanic_json({"answer": "invalid"})

    root = node.child(f"projects/{scene_id}/contexts/")
    for i in request.json["contexts"]:
	    name = str(i)
	    key = _make_ctx_key(node, scene_id, name)
	    if is_training(key) or is_inferring(key):
		    return sanic_json({"answer": "busy"})
    for ctx_id in request.json["contexts"]:
        name = str(ctx_id)
        root.delete_rel(name + ".blob")
        key = _make_ctx_key(node, scene_id, name)
        if key in contexts:
            contexts.pop(key)

    return sanic_json({"answer": "ok"})


from common.utils import kief
async def perform_ds_load(request, ws, base_message: bytes):

	body = get_body(base_message)
	user_id = kief(body.get("user") or body.get("session") or "anon")
	header = body.get("header", {}) or {}
	dataset_id = header.get("name", "unnamed")
	client_hashes = body.get("block_hashes", {}) or {}
	hash_algo = body.get("hash_algo", "fasthex")

	cache_root = request.app.ctx.ds_cache.setdefault(user_id, {})
	ds_entry = cache_root.setdefault(dataset_id, {
		"inputs": [], "outputs": [], "header": {},
		"hash_algo": hash_algo,
		"hashes": {"inputs": [], "outputs": []}
	})

	if ds_entry.get("hash_algo") != hash_algo:
		ds_entry["inputs"].clear()
		ds_entry["outputs"].clear()
		ds_entry["hashes"] = {"inputs": [], "outputs": []}
		ds_entry["hash_algo"] = hash_algo

	need = {"inputs": {}, "outputs": {}}
	for side in ("inputs", "outputs"):
		client_cols = client_hashes.get(side, [])
		cached_cols = ds_entry["hashes"].get(side, [])
		while len(cached_cols) < len(client_cols):
			cached_cols.append([])
		ds_entry["hashes"][side] = cached_cols

		for col_i, col_hashes in enumerate(client_cols):
			need[side][str(col_i)] = []
			while len(cached_cols[col_i]) < len(col_hashes):
				cached_cols[col_i].append("")
			for blk_i, blk_hash in enumerate(col_hashes):
				if cached_cols[col_i][blk_i] != blk_hash:
					need[side][str(col_i)].append(blk_i)

	await ws.send(json.dumps(need))

	frames = []
	while True:
		msg = await ws.recv()
		if msg == b"__end__":
			break
		frames.append(msg)

	args = {
		"user_id": user_id,
		"dataset_id": dataset_id,
		"client_hashes": client_hashes,
		"hash_algo": hash_algo,
		"header": header,
		"frames": frames,
		"app_ctx": request.app.ctx,
	}

	job_id = wp.submit(wt.ds_load_task, args)
	result = await wp.wait_done(job_id)

	if not result or not result[1]:
		await ws.send(b'{"ok": false, "error": "no result"}')
		return None

	summary: dict = result[1]
	#print(result[1])
	dataset = summary["dataset"]
	summary.pop("dataset")
	await ws.send(json.dumps(result[1]))
	return dataset

from nns.sections.hooks import (
	prepare_ctx_for_sections,
	maybe_register_sections_after_training,
)

@bp_trio.websocket("/ws/train")
async def ws_train(request, ws):
	node = try_login(request.app, request.headers)
	if not node:
		await graceful_close(ws, {"answer": "wrong"})
		return

	raw = await ws.recv()
	body = get_body(raw)

	scene_id = str(body["scene_id"])
	ctx_name = str(body["context"])
	graph = body["graph"]

	key = _make_ctx_key(node, scene_id, ctx_name)
	if is_training(key) or is_inferring(key):
		await graceful_close(ws, {})
		return

	# ---- authoritative user id (for sections) ----
	username = kief(request.headers.get("user"))

	ds = None
	if body.get("local"):
		new = await ws.recv()
		ds = await perform_ds_load(request, ws, new)

	training_mark_started(key)

	ctx = get_or_load_ctx(node, scene_id, ctx_name, graph)

	# ---- prepare ctx for sections (isolated hook) ----
	prepare_ctx_for_sections(
		ctx=ctx,
		user_id=username,
		local_dataset=bool(ds),
	)

	body["local_dataset"] = ds
	await train_ws_exec(ws, graph, ctx, body)

	training_mark_stopped(key)
	try:
		dataset_stamp = str(body.get("dataset") or body.get("name") or "")
		acc = float(
			ctx.extra.get("_sections_max_acc",
			ctx.extra.get("_sections_last_acc", 0.0))
		)

		maybe_register_sections_after_training(
			ctx=ctx,
			graph=graph,
			dataset_stamp=dataset_stamp,
			acc=acc,
		)
	except Exception as e:
		import traceback
		traceback.print_exc(e)

	# ---- save updated context ----
	bytes_io = io.BytesIO()
	nodes.save_model(ctx, bytes_io)
	bytes_io.seek(0)
	node.child(f"projects/{scene_id}/contexts").write_rel(
		f"{ctx_name}.blob",
		bytes_io.read()
	)

	await graceful_close(ws, {})


@bp_trio.websocket("/ws/infer")
async def ws_infer(request, ws):
	node = try_login(request.app, request.headers)
	if not node:
		await graceful_close(ws, {"answer": "wrong"})
		return

	raw = await ws.recv()
	await ws.send(json.dumps({"ack": True}))
	args = get_body(raw)

	scene_id = str(args["scene_id"])
	ctx_name = str(args["context"])
	graph = args["graph"]

	key = _make_ctx_key(node, scene_id, ctx_name)
	if is_training(key) or is_inferring(key):
		await graceful_close(ws, {})
		return
	infer_mark_started(key)
	ctx = get_or_load_ctx(node, scene_id, ctx_name, graph)
	await infer_ws_exec(ws, graph, ctx, args)
	infer_mark_stopped(key)
	await graceful_close(ws, {})


@bp_trio.post("/export")
async def export_model(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})

	scene_id = str(request.json["scene_id"])
	ctx_name = str(request.json["context"])
	graph = request.json["graph"]

	key = _make_ctx_key(node, scene_id, ctx_name)
	if is_training(key) or is_inferring(key):
		return raw(b"", status=200)

	ctx = get_or_load_ctx(node, scene_id, ctx_name, graph)

	result = await export_exec(graph, ctx, {"to_app": request.json["platform"], "quant": request.json["quant"]})
	if not result[0] or not result[1].get("bytes"):
		print(result)
		return raw(b"", status=200)

	data = bytes(result[1]["bytes"])
	headers = {
		"Content-Disposition": f'attachment; filename="export_{scene_id}.onnx"',
		"Content-Type": "application/octet-stream",
		"Content-Length": len(data),
	}
	return raw(data, status=200, headers=headers)




def garbage_collection(contexts_scene: dict, scene_id: str, node: storage.Node):
	root = node.child(f"projects/{scene_id}/contexts/")
	result = {}
	for i in root.ls():
		if i == "meta.doc":
			continue
		unsuf = i.removesuffix(".blob")
		key = _make_ctx_key(node, scene_id, unsuf)
		if not int(unsuf) in contexts_scene:
			root.delete_rel(i)
			if key in contexts:
				contexts.pop(key)
	else:
		result[key] = contexts[key] if key in contexts else root.child(i).read()
	return result

@bp_trio.post("/get_ctxs")
async def get_ctxs(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id = request.json["scene"]
	if not scene_id.isdigit():
		return sanic_json({"answer": "invalid"})
	node.write_rel(f"projects/{scene_id}/contexts/meta.doc", {})
	res = garbage_collection(request.json["contexts"], scene_id, node)
	return sanic_json({"answer": "ok"})