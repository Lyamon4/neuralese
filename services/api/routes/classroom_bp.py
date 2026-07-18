import asyncio
import json
import uuid
from sanic import Blueprint
from sanic.views import stream
from sanic.response import text
from sanic.response import json as sanic_json
from common.utils import kief, load_classroom, classroom_data
import common.tools as tools
import storage

bp_classroom = Blueprint("classroom", url_prefix="/classroom")

_classroom_subs: dict[str, set[asyncio.Queue]] = {}
HEARTBEAT_SEC = 50


def classroom_root(app):
	return app.ctx.database["/classrooms/"]


import random
def generate_classroom_id(app) -> str:
	root = classroom_root(app)

	for _ in range(50):
		cid = f"{random.randint(0, 999999):06d}"
		if not root.exists_rel(f"{cid}/meta.doc"):
			return cid

	raise RuntimeError("Failed to allocate classroom id")


def _subscribe(classroom_id: str) -> asyncio.Queue:
	q: asyncio.Queue = asyncio.Queue()
	if classroom_id not in _classroom_subs:
		_classroom_subs[classroom_id] = set()
	_classroom_subs[classroom_id].add(q)
	return q


def _unsubscribe(classroom_id: str, q: asyncio.Queue) -> None:
	subs = _classroom_subs.get(classroom_id)
	if not subs:
		return
	subs.discard(q)
	if not subs:
		_classroom_subs.pop(classroom_id, None)


def emit_classroom_event(classroom_id: str, type: str = "snapshot", data=None) -> None:
	frame = {"type": type, "data": data or {}}
	subs = _classroom_subs.get(classroom_id)
	if not subs:
		return
	# fan-out to all connected SSE clients
	for q in list(subs):
		q.put_nowait(frame)


def try_login(app, data: dict) -> storage.Node | None:
	db = app.ctx.database
	user, pw = kief(data["user"]), data["pass"]
	root = db[f"/{user}/"]
	if not root.exists_rel("user.doc"):
		return None
	if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]):
		return None
	return root


def auth_from_headers(app, request) -> tuple[str, storage.Node] | None:
	user = request.headers.get("X-Auth-User")
	pw = request.headers.get("X-Auth-Pass")
	if not user or not pw:
		return None

	node = try_login(app, {"user": user, "pass": pw})
	if not node:
		return None
	return user, node


def snapshot_classroom(root: storage.Node) -> dict:
	students_raw = root.read_rel("students.doc") or {}
	return {
		"classroom_id": root.name,
		"meta": root.read_rel("meta.doc"),
		"students": students_raw,
	}


@bp_classroom.post("/create")
async def create_classroom(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	teacher = node.name
	classroom_id = generate_classroom_id(request.app)

	node.update_doc_rel("config.doc", {"my_classroom": classroom_id})
	root = classroom_root(request.app)[classroom_id]
	meta = {"teacher": teacher, "name": "", "classroom_data": {}, "lesson_customs": {}}
	meta.update(request.json.get("meta", {}))
	root.write_rel("meta.doc", meta)
	root.write_rel("students.doc", {})

	return sanic_json({"ok": True, "classroom_id": classroom_id, "data": classroom_data(root)})


@bp_classroom.post("/join")
async def join_classroom(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"]
	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False, "error": "not_found"})

	node.update_doc_rel("config.doc", {"my_classroom": classroom_id})
	students = root.read_rel("students.doc") or {}
	display_name = request.json["user"]
	students[display_name] = {"awaiting": False}
	root.write_rel("students.doc", students)

	emit_classroom_event(classroom_id)
	return sanic_json({"ok": True, "data": classroom_data(root)})


@bp_classroom.post("/meta")
async def get_classroom_data(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"] or node.read_rel("config.doc")["my_classroom"]
	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False, "error": "not_found"})

	return sanic_json({"ok": True, "data": classroom_data(root), "classroom_id": classroom_id})


@bp_classroom.post("/leave")
async def leave_classroom(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"]
	root = load_classroom(request.app, classroom_id)
	display_name = request.json["user"]
	if not root:
		return sanic_json({"ok": False})

	node.update_doc_rel("config.doc", {"my_classroom": ""})
	students = root.read_rel("students.doc") or {}
	if display_name in students:
		del students[display_name]
		root.write_rel("students.doc", students)
		emit_classroom_event(classroom_id)

	return sanic_json({"ok": True})


@bp_classroom.post("/update_meta")
async def update_classroom_meta(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json.get("classroom_id")
	payload = request.json.get("payload")

	if not isinstance(payload, dict):
		return sanic_json({"ok": False, "error": "invalid_payload"})

	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False, "error": "not_found"})

	meta = root.read_rel("meta.doc") or {}
	if meta.get("teacher") != node.name:
		return sanic_json({"ok": False, "error": "not_teacher"})

	meta.update(payload)
	root.write_rel("meta.doc", meta)

	emit_classroom_event(classroom_id)
	return sanic_json({"ok": True})

@bp_classroom.post("/update_lessons")
async def update_classroom_lessons(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json.get("classroom_id")
	payload = request.json.get("payload")

	if not isinstance(payload, dict):
		return sanic_json({"ok": False, "error": "invalid_payload"})

	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False, "error": "not_found"})

	meta = root.read_rel("meta.doc") or {}
	if meta.get("teacher") != node.name:
		return sanic_json({"ok": False, "error": "not_teacher"})
	if not "lesson_customs" in meta: meta["lesson_customs"] = {}

	meta["lesson_customs"].update(payload)
	print(list(meta.keys()))
	root.write_rel("meta.doc", meta)

	emit_classroom_event(classroom_id)
	return sanic_json({"ok": True})


@bp_classroom.post("/update_state")
async def update_student_state(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"]
	payload = request.json["payload"]

	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False})

	students = root.read_rel("students.doc") or {}
	display_user = request.json["target"]
	if display_user != request.json["user"] and not kief(request.json["user"]) == root.read_rel("meta.doc")["teacher"]:
		print("nah", root.read_rel("meta.doc")["teacher"], request.json["user"])
		return sanic_json({"ok": False, "error": "no"})
	if display_user not in students:
		return sanic_json({"ok": False, "error": "not_joined"})

	students[display_user].update(payload)
	print(students)
	root.write_rel("students.doc", students)

	emit_classroom_event(classroom_id)
	return sanic_json({"ok": True})


@bp_classroom.post("/mark_explanation_made")
async def mark_explanation_made(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"]
	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False})

	meta = root.read_rel("meta.doc")
	if meta.get("teacher") != node.name:
		return sanic_json({"ok": False, "error": "not_teacher"})

	students = root.read_rel("students.doc") or {}
	for s in students.values():
		if request.json["lesson_idx"] == -1 or request.json["lesson_idx"] == s.get("on_lesson", 0):
			s["awaiting"] = False

	root.write_rel("students.doc", students)
	emit_classroom_event(classroom_id)
	emit_classroom_event(classroom_id, "event", {"end": True})

	return sanic_json({"ok": True})


@bp_classroom.post("/get_state")
async def request_classroom_state(request):
	node = try_login(request.app, request.json)
	if not node:
		return sanic_json({"ok": False, "error": "auth"})

	classroom_id = request.json["classroom_id"]
	root = load_classroom(request.app, classroom_id)
	if not root:
		return sanic_json({"ok": False})

	return sanic_json({"ok": True, "state": snapshot_classroom(root)})


@bp_classroom.get("/events")
@stream
async def classroom_event_stream(request):
	auth = auth_from_headers(request.app, request)
	if not auth:
		return text("unauthorized", status=401)

	_user, _node = auth
	classroom_id = request.args.get("classroom_id")

	if not classroom_id:
		return text("missing classroom_id", status=400)

	root = load_classroom(request.app, classroom_id)
	if not root:
		return text("not found", status=404)

	response = await request.respond(
		content_type="text/event-stream",
		headers={
			"Cache-Control": "no-cache",
			"Connection": "keep-alive",
		},
	)

	q = _subscribe(classroom_id)

	# Initial snapshot
	snap = snapshot_classroom(root)
	await response.send(
		"event: snapshot\n"
		f"data: {json.dumps(snap)}\n\n"
	)

	try:
		while True:
			try:
				frame = await asyncio.wait_for(q.get(), timeout=HEARTBEAT_SEC)

				if frame["type"] == "snapshot":
					data = snapshot_classroom(root)
				else:
					data = frame["data"]

				await response.send(
					f"event: {frame['type']}\n"
					f"data: {json.dumps(data)}\n\n"
				)

			except asyncio.TimeoutError:
				await response.send(": ping\n\n")

	except asyncio.CancelledError:
		pass
	finally:
		_unsubscribe(classroom_id, q)
