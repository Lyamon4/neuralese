from __future__ import annotations

import asyncio

import jwt
from sanic import Blueprint, Request
from sanic.log import logger

from auth.dependencies import handoff_allowed, handoff_principal
from auth.jwt import decode_token, issue_token_pair, principal_from_payload, require_principal
from common.responses import fail, ok


bp_auth = Blueprint("auth", url_prefix="/api/auth")


def device_secret(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("device "):
        return auth.split(" ", 1)[1].strip()
    return request.headers.get("x-neuralese-device-secret", "").strip()


@bp_auth.post("/device/start")
async def device_start(request: Request):
    body = request.json or {}
    ttl = min(max(int(body.get("ttl_seconds", 300)), 30), 600)
    attempt, secret = request.app.ctx.auth_attempts.create(ttl)
    auth_base_url = request.app.ctx.settings.auth_public_base_url.strip().rstrip("/")
    separator = "&" if "?" in auth_base_url else "?"
    login_url = f"{auth_base_url}{separator}attempt_id={attempt.attempt_id}&fresh=1"
    logger.info("auth device start attempt_id=%s login_url=%s", attempt.attempt_id, login_url)
    return ok({
        "attempt_id": attempt.attempt_id,
        "device_secret": secret,
        "login_url": login_url,
        "expires_in": ttl,
        "wait_url": f"/api/auth/device/wait?attempt_id={attempt.attempt_id}",
    })


@bp_auth.get("/device/wait")
async def device_wait(request: Request):
    attempt_id = str(request.args.get("attempt_id", ""))
    attempt = request.app.ctx.auth_attempts.get(attempt_id)
    if not attempt:
        return fail("login attempt not found", 404)
    if not request.app.ctx.auth_attempts.verify_device_secret(attempt, device_secret(request)):
        return fail("invalid device secret", 403)
    if attempt.status == "pending":
        timeout = min(max(float(request.args.get("timeout", 60)), 1.0), 90.0)
        logger.info("auth device wait pending attempt_id=%s timeout=%s", attempt_id, timeout)
        try:
            await asyncio.wait_for(attempt.event.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            pass
        attempt = request.app.ctx.auth_attempts.get(attempt_id) or attempt
    return ok(request.app.ctx.auth_attempts.result_payload(attempt))


@bp_auth.post("/device/complete")
async def device_complete(request: Request):
    if not handoff_allowed(request):
        return fail("forbidden", 403)
    body = request.json or {}
    attempt_id = str(body.get("attempt_id", ""))
    logger.info("auth device complete attempt_id=%s", attempt_id)
    principal = handoff_principal(body)
    try:
        profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
        attempt = request.app.ctx.auth_attempts.complete(attempt_id, request.app.ctx.settings, {
            "clerk_user_id": principal.clerk_user_id,
            "email": principal.email,
            "display_name": principal.display_name,
        }, profile, request.app.ctx.user_service.public_payload(profile))
    except ValueError as exc:
        return fail(str(exc), 409 if str(exc) == "username_required" else 400)
    return ok(request.app.ctx.auth_attempts.result_payload(attempt))


@bp_auth.post("/device/cancel")
async def device_cancel(request: Request):
    body = request.json or {}
    try:
        attempt = request.app.ctx.auth_attempts.cancel(str(body.get("attempt_id", "")), device_secret(request))
    except PermissionError as exc:
        return fail(str(exc), 403)
    except ValueError as exc:
        return fail(str(exc), 404)
    return ok(request.app.ctx.auth_attempts.result_payload(attempt))


@bp_auth.get("/me")
async def auth_me(request: Request):
    try:
        principal = require_principal(request)
    except jwt.PyJWTError as exc:
        return fail(f"invalid token: {exc}", 401)
    if principal is None:
        return fail("missing bearer token", 401)
    profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
    return ok({"user": {
        "id": principal.user_id,
        "clerk_user_id": principal.clerk_user_id,
        "email": principal.email,
        "display_name": principal.display_name,
    }, "profile": request.app.ctx.user_service.public_payload(profile)})


@bp_auth.post("/refresh")
async def auth_refresh(request: Request):
    body = request.json or {}
    token = str(body.get("refresh_token", ""))
    if not token:
        return fail("missing refresh_token", 400)
    try:
        payload = decode_token(request.app.ctx.settings, token, "refresh")
        principal = principal_from_payload(payload)
        pair = issue_token_pair(request.app.ctx.settings, {
            "clerk_user_id": principal.clerk_user_id,
            "email": principal.email,
            "display_name": principal.display_name,
        })
        profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
        pair["profile"] = request.app.ctx.user_service.public_payload(profile)
    except (jwt.PyJWTError, ValueError) as exc:
        return fail(str(exc), 401)
    return ok(pair)
