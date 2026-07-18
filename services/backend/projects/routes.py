from __future__ import annotations

from sanic import Blueprint, Request

from auth.dependencies import AuthError, require_account
from common.responses import legacy_ok, legacy_wrong

from .service import ProjectService, validate_scene_id


bp_projects = Blueprint("projects", url_prefix="")
project_service = ProjectService()


@bp_projects.post("/api/projects/save", name="save_scene_api")
@bp_projects.post("/save", name="save_scene_legacy")
async def save_scene(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    body = request.json or {}
    scene_id = str(body.get("scene", ""))
    if not validate_scene_id(scene_id):
        return legacy_ok({"answer": "invalid"})
    project_service.save_project(
        account.root,
        scene_id=scene_id,
        name=str(body.get("name", "")),
        blob=body.get("blob"),
        chat_id=str(body.get("chat_id", "")),
        last_id=int(body.get("last_id", -1)),
    )
    return legacy_ok()


@bp_projects.post("/api/projects/get", name="get_project_api")
@bp_projects.post("/project", name="get_project_legacy")
async def get_project(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    scene_id = str((request.json or {}).get("scene", ""))
    project = project_service.get_project(account.root, scene_id)
    if not project:
        return legacy_wrong()
    scene, name = project
    return legacy_ok({"scene": scene, "name": name})


@bp_projects.post("/api/projects/delete", name="delete_project_api")
@bp_projects.post("/delete_project", name="delete_project_legacy")
async def delete_project(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    project_service.delete_project(account.root, str((request.json or {}).get("scene", "")))
    return legacy_ok()


@bp_projects.post("/api/projects/list", name="project_list_api")
@bp_projects.post("/project_list", name="project_list_legacy")
async def project_list(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    return legacy_ok({"list": project_service.list_projects(account.root)})


@bp_projects.post("/api/projects/get-chat", name="get_chat_api")
@bp_projects.post("/get_chat", name="get_chat_legacy")
async def get_chat(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    body = request.json or {}
    scene_id = str(body.get("scene", ""))
    if not validate_scene_id(scene_id):
        return legacy_ok({"answer": "invalid"})
    chat_id = str(body.get("chat_id", ""))
    data = account.root.read_rel(f"projects/{scene_id}/chats/{chat_id}.doc") or {}
    messages = project_service.update_last_id(account.root, scene_id, chat_id, int(body.get("last_id", data.get("last_id", 0))))
    return legacy_ok({"messages": messages})


@bp_projects.post("/api/projects/clear-chat", name="clear_chat_api")
@bp_projects.post("/clear_chat", name="clear_chat_legacy")
async def clear_chat(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return legacy_wrong()
    body = request.json or {}
    scene_id = str(body.get("scene", ""))
    chat_id = str(body.get("chat_id", ""))
    account.root.write_rel(f"projects/{scene_id}/chats/{chat_id}.doc", {"messages": [], "last_id": 0})
    return legacy_ok()


@bp_projects.post("/api/projects/register-dataset", name="register_dataset_api")
@bp_projects.post("/reg_dataset", name="register_dataset_legacy")
async def register_dataset(request: Request):
    try:
        require_account(request)
    except AuthError:
        return legacy_wrong()
    return legacy_ok()
