from __future__ import annotations

import asyncio

from sanic import Blueprint, Request
from sanic.log import logger
from sanic.response import text
from sanic.views import stream

from auth.dependencies import AuthError, require_account
from common.responses import fail, ok

from .events import sse


bp_classrooms = Blueprint("classrooms", url_prefix="/classroom")
bp_classrooms_api = Blueprint("classrooms_api", url_prefix="/api/classrooms")
HEARTBEAT_SEC = 50


def auth_or_error(request: Request):
    try:
        return require_account(request), None
    except AuthError as exc:
        logger.warning("classroom auth failed path=%s error=%s", request.path, exc)
        return None, fail(str(exc), exc.status)


@bp_classrooms_api.post("/create")
@bp_classrooms.post("/create")
async def create_classroom(request: Request):
    logger.info("classroom/create request")
    account, err = auth_or_error(request)
    if err:
        return err
    try:
        classroom_id, data = request.app.ctx.classroom_service.create(account, (request.json or {}).get("meta", {}))
    except PermissionError as exc:
        logger.warning(
            "classroom/create denied account_id=%s username=%s type=%s error=%s",
            account.profile.account_id,
            account.profile.username,
            account.profile.type,
            exc,
        )
        return fail(str(exc), 403)
    logger.info(
        "classroom/create ok classroom_id=%s account_id=%s username=%s",
        classroom_id,
        account.profile.account_id,
        account.profile.username,
    )
    return ok({"classroom_id": classroom_id, "data": data})


@bp_classrooms_api.post("/join")
@bp_classrooms.post("/join")
async def join_classroom(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    classroom_id = str((request.json or {}).get("classroom_id", ""))
    try:
        data = request.app.ctx.classroom_service.join(account, classroom_id)
    except FileNotFoundError:
        logger.warning("classroom/join not_found classroom_id=%s account_id=%s", classroom_id, account.profile.account_id)
        return fail("not_found", 404)
    logger.info("classroom/join ok classroom_id=%s account_id=%s", classroom_id, account.profile.account_id)
    request.app.ctx.classroom_events.emit(classroom_id)
    return ok({"data": data})


@bp_classrooms_api.post("/meta")
@bp_classrooms.post("/meta")
async def get_classroom_data(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    body = request.json or {}
    config = account.root.read_rel("config.doc") or {}
    classroom_id = str(body.get("classroom_id") or config.get("my_classroom") or "")
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        return fail("not_found", 404)
    return ok({"data": request.app.ctx.classroom_service.public_data(root), "classroom_id": classroom_id})


@bp_classrooms_api.post("/leave")
@bp_classrooms.post("/leave")
async def leave_classroom(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    classroom_id = str((request.json or {}).get("classroom_id", ""))
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        return ok()
    account.root.update_doc_rel("config.doc", {"my_classroom": ""})
    students = root.read_rel("students.doc") or {}
    students.pop(account.profile.account_id, None)
    root.write_rel("students.doc", students)
    request.app.ctx.classroom_events.emit(classroom_id)
    return ok()


@bp_classrooms_api.post("/update-meta")
@bp_classrooms.post("/update_meta")
async def update_classroom_meta(request: Request):
    return await _update_classroom_meta_field(request, "meta")


@bp_classrooms_api.post("/update-lessons")
@bp_classrooms.post("/update_lessons")
async def update_classroom_lessons(request: Request):
    return await _update_classroom_meta_field(request, "lesson_customs")


@bp_classrooms_api.post("/lesson-auto-project")
@bp_classrooms.post("/lesson_auto_project")
async def lesson_auto_project(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    body = request.json or {}
    classroom_id = str(body.get("classroom_id", ""))
    lesson_key = str(body.get("lesson_key", ""))
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        return fail("not_found", 404)
    meta = root.read_rel("meta.doc") or {}
    students = root.read_rel("students.doc") or {}
    is_teacher = meta.get("teacher_account_id") == account.profile.account_id
    is_student = account.profile.account_id in students
    if not is_teacher and not is_student:
        return fail("forbidden", 403)
    blob = request.app.ctx.classroom_service.lesson_auto_project_blob(root, lesson_key)
    if not blob:
        return fail("not_found", 404)
    return ok({"blob": blob})


async def _update_classroom_meta_field(request: Request, mode: str):
    account, err = auth_or_error(request)
    if err:
        return err
    body = request.json or {}
    root = request.app.ctx.classroom_service.load(str(body.get("classroom_id", "")))
    if not root:
        return fail("not_found", 404)
    try:
        request.app.ctx.classroom_service.require_teacher(account, root)
    except PermissionError as exc:
        return fail(str(exc), 403)
    payload = body.get("payload", {})
    if not isinstance(payload, dict):
        return fail("invalid_payload", 400)
    meta = root.read_rel("meta.doc") or {}
    if mode == "lesson_customs":
        meta.setdefault("lesson_customs", {}).update(payload)
    else:
        meta.update(payload)
        meta = request.app.ctx.classroom_service.store_lesson_auto_projects(root, meta)
    root.write_rel("meta.doc", meta)
    request.app.ctx.classroom_events.emit(root.name)
    return ok()


@bp_classrooms_api.post("/update-state")
@bp_classrooms.post("/update_state")
async def update_student_state(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    body = request.json or {}
    classroom_id = str(body.get("classroom_id", ""))
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        return fail("not_found", 404)
    payload = body.get("payload", {})
    target = str(body.get("target_account_id") or account.profile.account_id)
    meta = root.read_rel("meta.doc") or {}
    if target != account.profile.account_id and meta.get("teacher_account_id") != account.profile.account_id:
        return fail("forbidden", 403)
    students = root.read_rel("students.doc") or {}
    if target not in students:
        return fail("not_joined", 404)
    students[target].update(payload)
    root.write_rel("students.doc", students)
    request.app.ctx.classroom_events.emit(classroom_id)
    return ok()


@bp_classrooms_api.post("/mark-explanation-made")
@bp_classrooms.post("/mark_explanation_made")
async def mark_explanation_made(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    body = request.json or {}
    classroom_id = str(body.get("classroom_id", ""))
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        return fail("not_found", 404)
    try:
        request.app.ctx.classroom_service.require_teacher(account, root)
    except PermissionError as exc:
        return fail(str(exc), 403)
    students = root.read_rel("students.doc") or {}
    lesson_idx = int(body.get("lesson_idx", -1))
    for state in students.values():
        if lesson_idx == -1 or lesson_idx == state.get("on_lesson", 0):
            state["awaiting"] = False
    root.write_rel("students.doc", students)
    request.app.ctx.classroom_events.emit(classroom_id)
    request.app.ctx.classroom_events.emit(classroom_id, "event", {"end": True})
    return ok()


@bp_classrooms_api.post("/get-state")
@bp_classrooms.post("/get_state")
async def request_classroom_state(request: Request):
    account, err = auth_or_error(request)
    if err:
        return err
    root = request.app.ctx.classroom_service.load(str((request.json or {}).get("classroom_id", "")))
    if not root:
        return fail("not_found", 404)
    return ok({"state": request.app.ctx.classroom_service.snapshot(root)})


@bp_classrooms_api.get("/events")
@bp_classrooms.get("/events")
@stream
async def classroom_event_stream(request: Request):
    account, err = auth_or_error(request)
    if err:
        return text("unauthorized", status=401)
    classroom_id = str(request.args.get("classroom_id", ""))
    root = request.app.ctx.classroom_service.load(classroom_id)
    if not root:
        logger.warning("classroom/events not_found classroom_id=%s account_id=%s", classroom_id, account.profile.account_id)
        return text("not found", status=404)
    logger.info("classroom/events connected classroom_id=%s account_id=%s", classroom_id, account.profile.account_id)
    response = await request.respond(content_type="text/event-stream", headers={"Cache-Control": "no-cache", "Connection": "keep-alive"})
    q = request.app.ctx.classroom_events.subscribe(classroom_id)
    await response.send(sse("snapshot", request.app.ctx.classroom_service.snapshot(root)))
    try:
        while True:
            try:
                frame = await asyncio.wait_for(q.get(), timeout=HEARTBEAT_SEC)
                data = request.app.ctx.classroom_service.snapshot(root) if frame["type"] == "snapshot" else frame["data"]
                await response.send(sse(frame["type"], data))
            except asyncio.TimeoutError:
                await response.send(": ping\n\n")
    finally:
        request.app.ctx.classroom_events.unsubscribe(classroom_id, q)
