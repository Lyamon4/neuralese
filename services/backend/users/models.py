from __future__ import annotations

import re
import time
from dataclasses import dataclass
from typing import Any


USERNAME_RE = re.compile(r"^[a-z0-9_]{3,20}$")
RESERVED_USERNAMES = {
    "admin", "administrator", "api", "auth", "billing", "clerk", "help",
    "login", "logout", "me", "neuralese", "null", "owner", "root",
    "settings", "support", "system", "teacher", "undefined", "user",
}


def utc_now() -> float:
    return time.time()


def validate_username(username: str) -> str:
    normalized = username.strip().lower()
    if "@" in normalized or "." in normalized:
        raise ValueError("Username cannot be an email address.")
    if not USERNAME_RE.match(normalized):
        raise ValueError("Username must be 3-20 characters: lowercase letters, numbers, and underscore only.")
    if normalized in RESERVED_USERNAMES:
        raise ValueError("This username is reserved.")
    return normalized


def normalize_account_type(value: str) -> str:
    return "teacher" if str(value).strip().lower() == "teacher" else "student"


@dataclass
class UserProfile:
    user_id: str
    account_id: str
    clerk_user_id: str
    email: str = ""
    display_name: str = ""
    username: str = ""
    type: str = "student"
    created_at: float = 0.0
    updated_at: float = 0.0

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "UserProfile":
        return cls(
            user_id=str(payload.get("id") or payload.get("user_id") or ""),
            account_id=str(payload.get("account_id") or ""),
            clerk_user_id=str(payload.get("clerk_user_id") or ""),
            email=str(payload.get("email") or ""),
            display_name=str(payload.get("display_name") or ""),
            username=str(payload.get("username") or ""),
            type=normalize_account_type(str(payload.get("type") or "student")),
            created_at=float(payload.get("created_at") or utc_now()),
            updated_at=float(payload.get("updated_at") or utc_now()),
        )

    def public_payload(self) -> dict[str, Any]:
        return {
            "id": self.user_id,
            "account_id": self.account_id,
            "clerk_user_id": self.clerk_user_id,
            "email": self.email,
            "display_name": self.display_name,
            "username": self.username,
            "username_set": self.username != "",
            "type": self.type,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }
