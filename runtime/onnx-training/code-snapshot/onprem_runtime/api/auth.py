from __future__ import annotations

import secrets
from typing import Any

from fastapi import Header, HTTPException, Request, WebSocket


AUTH_ERROR = "missing or invalid auth token"
AUTH_WS_CLOSE_CODE = 1008


def auth_enabled(profile: Any) -> bool:
    return bool(getattr(profile, "auth_token", None))


def require_http_auth(
    request: Request,
    authorization: str | None = Header(default=None),
    x_neuralese_token: str | None = Header(default=None),
) -> None:
    profile = request.app.state.profile
    expected = getattr(profile, "auth_token", None)
    if not expected:
        return
    if _token_matches(expected, _extract_http_token(authorization, x_neuralese_token)):
        return
    raise HTTPException(status_code=401, detail=AUTH_ERROR)


async def require_ws_auth(ws: WebSocket) -> bool:
    expected = getattr(ws.app.state.profile, "auth_token", None)
    if not expected:
        return True
    supplied = _extract_ws_token(ws)
    if _token_matches(expected, supplied):
        return True
    await ws.close(code=AUTH_WS_CLOSE_CODE)
    return False


def _extract_http_token(
    authorization: str | None,
    x_neuralese_token: str | None,
) -> str | None:
    if x_neuralese_token:
        return x_neuralese_token
    return _extract_bearer_token(authorization)


def _extract_ws_token(ws: WebSocket) -> str | None:
    query_token = ws.query_params.get("token")
    if query_token:
        return query_token
    header_token = ws.headers.get("x-neuralese-token")
    if header_token:
        return header_token
    return _extract_bearer_token(ws.headers.get("authorization"))


def _extract_bearer_token(value: str | None) -> str | None:
    if not value:
        return None
    prefix = "bearer "
    if value.lower().startswith(prefix):
        return value[len(prefix) :].strip()
    return None


def _token_matches(expected: str, supplied: str | None) -> bool:
    return bool(supplied) and secrets.compare_digest(expected, supplied)
