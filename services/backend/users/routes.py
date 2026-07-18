from __future__ import annotations

from sanic import Blueprint, Request

from auth.dependencies import AuthError, require_account
from common.responses import fail, ok


bp_users = Blueprint("users", url_prefix="/api/users")


def account_type_from_body(body: dict) -> str:
    teacher = body.get("teacher", False)
    if isinstance(teacher, str):
        teacher = teacher.strip().lower() in {"1", "true", "yes", "teacher"}
    return "teacher" if bool(teacher) else "student"


@bp_users.get("/me")
async def users_me(request: Request):
    try:
        account = require_account(request)
    except AuthError as exc:
        return fail(str(exc), exc.status)
    return ok({"profile": request.app.ctx.user_service.public_payload(account.profile), "needs_username": account.profile.username == ""})


@bp_users.post("/claim-username")
async def claim_username(request: Request):
    try:
        account = require_account(request)
        body = request.json or {}
        profile = request.app.ctx.user_service.claim_username(account.principal, str(body.get("username", "")), account_type_from_body(body))
    except AuthError as exc:
        return fail(str(exc), exc.status)
    except ValueError as exc:
        return fail(str(exc), 400)
    return ok({"profile": request.app.ctx.user_service.public_payload(profile), "needs_username": False})


@bp_users.get("/username-available")
async def username_available(request: Request):
    try:
        account = require_account(request)
        username, available = request.app.ctx.user_service.username_available(account.principal, str(request.args.get("username", "")))
    except AuthError as exc:
        return fail(str(exc), exc.status)
    except ValueError as exc:
        return fail(str(exc), 400, available=False)
    return ok({"username": username, "available": available})
