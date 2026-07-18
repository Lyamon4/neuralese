from __future__ import annotations

import secrets
import time
from dataclasses import dataclass
from typing import Any

import jwt
from sanic import Request


ALGORITHM = "HS256"


@dataclass(frozen=True)
class AuthPrincipal:
    user_id: str
    clerk_user_id: str
    email: str
    display_name: str
    token_id: str


def now() -> int:
    return int(time.time())


def issue_token_pair(settings, clerk_user: dict[str, Any]) -> dict[str, Any]:
    clerk_user_id = str(clerk_user.get("clerk_user_id") or "")
    if not clerk_user_id:
        raise ValueError("missing clerk_user_id")
    issued_at = now()
    user_id = "clerk:" + clerk_user_id
    email = str(clerk_user.get("email") or "")
    display_name = str(clerk_user.get("display_name") or email or clerk_user_id)
    common = {
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "sub": user_id,
        "clerk_user_id": clerk_user_id,
        "email": email,
        "display_name": display_name,
        "iat": issued_at,
        "nbf": issued_at,
    }
    access_payload = {**common, "typ": "access", "jti": secrets.token_urlsafe(24), "exp": issued_at + settings.access_token_ttl_seconds}
    refresh_payload = {**common, "typ": "refresh", "jti": secrets.token_urlsafe(24), "exp": issued_at + settings.refresh_token_ttl_seconds}
    return {
        "access_token": jwt.encode(access_payload, settings.jwt_secret, algorithm=ALGORITHM),
        "refresh_token": jwt.encode(refresh_payload, settings.jwt_secret, algorithm=ALGORITHM),
        "token_type": "Bearer",
        "expires_in": settings.access_token_ttl_seconds,
        "refresh_expires_in": settings.refresh_token_ttl_seconds,
        "user": {"id": user_id, "clerk_user_id": clerk_user_id, "email": email, "display_name": display_name},
    }


def decode_token(settings, token: str, expected_type: str = "access") -> dict[str, Any]:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM], audience=settings.jwt_audience, issuer=settings.jwt_issuer)
    if payload.get("typ") != expected_type:
        raise jwt.InvalidTokenError(f"expected {expected_type} token")
    return payload


def principal_from_payload(payload: dict[str, Any]) -> AuthPrincipal:
    user_id = str(payload.get("sub") or "")
    if not user_id:
        raise jwt.InvalidTokenError("missing subject")
    return AuthPrincipal(
        user_id=user_id,
        clerk_user_id=str(payload.get("clerk_user_id") or ""),
        email=str(payload.get("email") or ""),
        display_name=str(payload.get("display_name") or ""),
        token_id=str(payload.get("jti") or ""),
    )


def bearer_token(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    return auth.split(" ", 1)[1].strip() if auth.lower().startswith("bearer ") else ""


def require_principal(request: Request) -> AuthPrincipal | None:
    token = bearer_token(request)
    if not token:
        return None
    return principal_from_payload(decode_token(request.app.ctx.settings, token, "access"))
