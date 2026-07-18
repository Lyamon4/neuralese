from __future__ import annotations

from dataclasses import dataclass

import jwt
from sanic import Request

from auth.jwt import AuthPrincipal, require_principal
from storage.account_paths import account_root
from users.models import UserProfile


@dataclass(frozen=True)
class AccountContext:
    principal: AuthPrincipal
    profile: UserProfile
    root: object


class AuthError(Exception):
    def __init__(self, message: str, status: int = 401):
        super().__init__(message)
        self.status = status


def require_account(request: Request) -> AccountContext:
    try:
        principal = require_principal(request)
    except jwt.PyJWTError as exc:
        raise AuthError(f"invalid token: {exc}", 401) from exc
    if principal is None:
        raise AuthError("missing bearer token", 401)
    profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
    return AccountContext(principal=principal, profile=profile, root=account_root(request.app.ctx.db, principal.user_id))


def handoff_allowed(request: Request) -> bool:
    provided = request.headers.get("x-neuralese-clerk-handoff-secret", "")
    return bool(request.app.ctx.settings.clerk_handoff_secret) and provided == request.app.ctx.settings.clerk_handoff_secret


def handoff_principal(body: dict) -> AuthPrincipal:
    clerk_user_id = str(body.get("clerk_user_id", ""))
    return AuthPrincipal(
        user_id="clerk:" + clerk_user_id,
        clerk_user_id=clerk_user_id,
        email=str(body.get("email", "")),
        display_name=str(body.get("display_name", "")),
        token_id="server_handoff",
    )
