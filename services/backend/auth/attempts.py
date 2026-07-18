from __future__ import annotations

import asyncio
import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass, field
from typing import Any

from auth.jwt import issue_token_pair


def now() -> float:
    return time.time()


def hash_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


@dataclass
class LoginAttempt:
    attempt_id: str
    device_secret_hash: str
    created_at: float
    expires_at: float
    status: str = "pending"
    token_pair: dict[str, Any] = field(default_factory=dict)
    clerk_user: dict[str, Any] = field(default_factory=dict)
    profile: dict[str, Any] = field(default_factory=dict)
    completed_at: float = 0.0
    event: asyncio.Event = field(default_factory=asyncio.Event)

    def is_expired(self) -> bool:
        return now() >= self.expires_at


class AuthAttemptStore:
    def __init__(self) -> None:
        self.attempts: dict[str, LoginAttempt] = {}

    def create(self, ttl_seconds: int = 300) -> tuple[LoginAttempt, str]:
        attempt_id = "login_" + secrets.token_urlsafe(24)
        device_secret = secrets.token_urlsafe(48)
        attempt = LoginAttempt(attempt_id=attempt_id, device_secret_hash=hash_secret(device_secret), created_at=now(), expires_at=now() + ttl_seconds)
        self.attempts[attempt_id] = attempt
        return attempt, device_secret

    def get(self, attempt_id: str) -> LoginAttempt | None:
        attempt = self.attempts.get(attempt_id)
        if attempt and attempt.status == "pending" and attempt.is_expired():
            attempt.status = "expired"
            attempt.event.set()
        return attempt

    def verify_device_secret(self, attempt: LoginAttempt, device_secret: str) -> bool:
        return hmac.compare_digest(attempt.device_secret_hash, hash_secret(device_secret))

    def complete(self, attempt_id: str, settings, clerk_user: dict[str, Any], profile, profile_payload: dict[str, Any] | None = None) -> LoginAttempt:
        attempt = self.get(attempt_id)
        if not attempt:
            raise ValueError("login attempt not found")
        if attempt.status == "expired" or attempt.is_expired():
            attempt.status = "expired"
            attempt.event.set()
            raise ValueError("login attempt expired")
        if attempt.status == "canceled":
            raise ValueError("login attempt canceled")
        if attempt.status == "complete":
            return attempt
        if not profile.username:
            raise ValueError("username_required")
        attempt.token_pair = issue_token_pair(settings, clerk_user)
        attempt.clerk_user = {
            "id": f"clerk:{clerk_user.get('clerk_user_id', '')}",
            "clerk_user_id": clerk_user.get("clerk_user_id", ""),
            "email": clerk_user.get("email", ""),
            "display_name": clerk_user.get("display_name", ""),
        }
        attempt.profile = profile_payload or profile.public_payload()
        attempt.status = "complete"
        attempt.completed_at = now()
        attempt.event.set()
        return attempt

    def cancel(self, attempt_id: str, device_secret: str) -> LoginAttempt:
        attempt = self.get(attempt_id)
        if not attempt:
            raise ValueError("login attempt not found")
        if not self.verify_device_secret(attempt, device_secret):
            raise PermissionError("invalid device secret")
        if attempt.status == "pending":
            attempt.status = "canceled"
            attempt.event.set()
        return attempt

    def signed_out(self, attempt_id: str) -> LoginAttempt:
        attempt = self.get(attempt_id)
        if not attempt:
            raise ValueError("login attempt not found")
        if attempt.status == "pending":
            attempt.status = "signed_out"
            attempt.event.set()
        return attempt

    def result_payload(self, attempt: LoginAttempt) -> dict[str, Any]:
        if attempt.status == "complete":
            return {"status": "complete", **attempt.token_pair, "user": attempt.clerk_user, "profile": attempt.profile}
        return {"status": attempt.status, "expires_at": attempt.expires_at}
