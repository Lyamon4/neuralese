from sanic import Blueprint
from sanic.response import json as sanic_json
from common.utils import graceful_close, kief
from google import genai
from google.genai import types
import json, ast, os, dotenv
import common.tools as tools
import storage
import worker.worker_pebble as wp
import worker.worker_tasks as wt
from common.stream_progressor import stream_progress, get_body

bp_chat = Blueprint("chat", url_prefix="/")

dotenv.load_dotenv()
client = genai.Client(api_key=os.environ["API_KEY"])

def try_login(app, data) -> storage.Node:
	db = app.ctx.database
	user, pw = kief(data["user"]), data["pass"]
	root = db[f"/{user}/"]
	if not root.exists_rel("user.doc"): return None
	if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]): return None
	return root


def _stable_json(obj) -> str:
    # deterministic keys, full precision
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def _sha256_text(s: str) -> str:
    import hashlib
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


import asyncio
import hashlib
async def run_llm(*, ws, content, summary=None, system=None, builder=None, model=None):
	job_id = wp.submit(wt.talk_task, {
		"client": client,
		"content": content,
		"summary": summary or {"nodes": {}, "edges": {}},
		"system": system or tools.get_start_prompt(),
		"for_builder": builder or tools.get_builder_prompt(),
		"model": model
	})
	await stream_progress(ws, job_id)
	return await wp.wait_done(job_id)


def build_content(messages):
	return [
		types.Content(
			role=m["role"],
			parts=[types.Part(text=m["text"])]
		)
		for m in messages
	]



@bp_chat.websocket("/ws/talk")
async def ws_talk(request, ws):
	first = json.loads(await ws.recv())

	node = try_login(request.app, first)
	if not node:
		await graceful_close(ws, {"status": "wrong"})
		return

	scene = str(first["scene"])
	chat  = str(first["chat_id"])
	chats = node.child(f"projects/{scene}/chats")

	data = chats.read_rel(chat + ".doc") or {
		"messages": [],
		"graph_state": {"nodes": {}, "edges": {}},
		"graph_state_hash": "",
		"last_id": 0,
	}

	if first.get("_clear"):
		data["messages"].clear()

	stored = data.get("graph_state_hash", "")
	client_hash = first.get("summary_hash", "")
	await ws.send(json.dumps({"server_hash": stored}))
	summary = data.setdefault("graph_state", {"nodes": {}, "edges": {}})

	if client_hash != stored and "summary" not in first:
		await ws.send(json.dumps({"need_summary": True}))
		try:
			second = json.loads(await asyncio.wait_for(ws.recv(), 5))
		except asyncio.TimeoutError:
			await graceful_close(ws, {"error": "summary_timeout"})
			return
		summary = second.get("summary", summary)
		data["graph_state_hash"] = second.get("summary_hash", client_hash)
	elif "summary" in first:
		summary = first["summary"]
		data["graph_state_hash"] = client_hash

	data["graph_state"] = summary
	chats.update_doc_rel(chat + ".doc", data)
	await ws.send(json.dumps({"updated": True}))

	data["messages"].append({
		"role": "user",
		"text": first.get("text", ""),
		"id": first.get("user_id", 0),
	})
	chats.update_doc_rel(chat + ".doc", data)

	result = await run_llm(
		ws=ws,
		content=build_content(data["messages"]),
		summary=summary,
	)

	if result[1] and "text" in result[1]:
		text = tools.remove_tag_blocks(
			result[1]["text"],
			["change_nodes", "connect_ports", "disconnect_ports", "delete_nodes", "thinking"]
		)
		data["messages"].append({
			"role": "model",
			"text": text,
			"func_called": result[1]["func_called"],
			"id": first.get("ai_id", 0),
		})
		chats.update_doc_rel(chat + ".doc", data)

	await graceful_close(ws, {})


@bp_chat.post("/ask_once")
async def post_ask_once(request):
	data = request.json
	node = try_login(request.app, data)
	if not node:
		return sanic_json({"answer": "wrong"}, status=403)

	content = [
		types.Content(
			role="user",
			parts=[types.Part(text=data.get("text", ""))]
		)
	]

	class MockStreamer:
		def __init__(self): self.text = ""

		async def send(self, msg):
			payload = json.loads(msg)
			if "text" in payload: self.text += payload["text"]

	streamer = MockStreamer()

	system
	result = await run_llm(
		ws=streamer,
		content=content,
		summary=None,
		system="You are a concise AI assistant.",
		builder=None,
	)

	final_text = result[1].get("text", "") if result and result[1] else streamer.text

	return sanic_json({
		"answer": "ok",
		"text": final_text
	})



from common.project_utils import update_last_id
@bp_chat.post("/get_chat")
async def get_chat(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id = request.json["scene"]
	chats_dir = node.child(f"projects/{scene_id}/chats")
	if not scene_id.isdigit(): return sanic_json({"answer": "invalid"})
	data = chats_dir.read_rel(request.json["chat_id"] + ".doc") or {}
	msgs = update_last_id(node, scene_id, request.json["chat_id"], data.get("last_id", 0))
	return sanic_json({"answer": "ok", "messages": msgs})


@bp_chat.post("/clear_chat")
async def clear_chat(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id = request.json["scene"]
	chats_dir = node.child(f"projects/{scene_id}/chats")
	data = chats_dir.read_rel(request.json["chat_id"] + ".doc") or {}
	data["messages"] = []
	data["last_id"] = 0
	chats_dir.write_rel(request.json["chat_id"] + ".doc", data)
	return sanic_json({"answer": "ok"})
