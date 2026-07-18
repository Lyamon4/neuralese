from sanic import Blueprint
from sanic.response import raw
from common.stream_progressor import get_body, graceful_close
from common.trio_exec import train_ws_exec, infer_ws_exec, export_exec
from common.context_cache import get_or_load_ctx
import io, json, nns.model_core as nodes

bp_trio = Blueprint("trio", url_prefix="/ws")

@bp_trio.websocket("/train")
async def ws_train(request, ws):
	raw_data = await ws.recv()
	body = get_body(raw_data)
	ctx = get_or_load_ctx(request.app.ctx.database, body)
	await train_ws_exec(ws, body["graph"], ctx, body)
	io_buf = io.BytesIO()
	nodes.save_model(ctx, io_buf)
	request.app.ctx.database.put(body["ctx_key"], io_buf.getvalue())
	await graceful_close(ws, {})

@bp_trio.websocket("/infer")
async def ws_infer(request, ws):
	raw_data = await ws.recv()
	await ws.send(json.dumps({"ack": True}))
	body = get_body(raw_data)
	ctx = get_or_load_ctx(request.app.ctx.database, body)
	await infer_ws_exec(ws, body["graph"], ctx, body)
	await graceful_close(ws, {})

@bp_trio.post("/export")
async def export_model(request):
	body = request.json
	ctx = get_or_load_ctx(request.app.ctx.database, body)
	result = await export_exec(body["graph"], ctx, {"to_app": body["platform"], "quant": body["quant"]})
	data = result.get("bytes", b"")
	return raw(data, headers={
		"Content-Disposition": f'attachment; filename=\"export_{body["scene_id"]}.onnx\"',
		"Content-Type": "application/octet-stream"
	})
