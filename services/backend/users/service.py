from __future__ import annotations

from auth.jwt import AuthPrincipal
from storage.account_paths import account_id_for_user_id, account_root

from .models import UserProfile, normalize_account_type, utc_now, validate_username


class UserService:
    def __init__(self, db):
        self.db = db

    def profile_path(self, account_id: str) -> str:
        return f"/profiles/{account_id}.doc"

    def username_path(self, username: str) -> str:
        return f"/usernames/{username}.doc"

    def get_profile_by_account_id(self, account_id: str) -> UserProfile | None:
        payload = self.db[self.profile_path(account_id)].read()
        return UserProfile.from_payload(payload) if isinstance(payload, dict) else None

    def get_or_create_from_principal(self, principal: AuthPrincipal) -> UserProfile:
        account_id = account_id_for_user_id(principal.user_id)
        profile = self.get_profile_by_account_id(account_id)
        if profile is None:
            now = utc_now()
            profile = UserProfile(
                user_id=principal.user_id,
                account_id=account_id,
                clerk_user_id=principal.clerk_user_id,
                email=principal.email,
                display_name=principal.display_name or principal.email or principal.clerk_user_id,
                created_at=now,
                updated_at=now,
            )
            self.save_profile(profile)
            self.ensure_account_defaults(profile)
            return profile

        changed = False
        for field, value in {
            "email": principal.email,
            "display_name": principal.display_name,
            "clerk_user_id": principal.clerk_user_id,
        }.items():
            if value and getattr(profile, field) != value:
                setattr(profile, field, value)
                changed = True
        if changed:
            profile.updated_at = utc_now()
            self.save_profile(profile)
        self.ensure_account_defaults(profile)
        return profile

    def save_profile(self, profile: UserProfile) -> None:
        self.db[self.profile_path(profile.account_id)].write(profile.public_payload())

    def public_payload(self, profile: UserProfile) -> dict:
        payload = profile.public_payload()
        config = account_root(self.db, profile.user_id).read_rel("config.doc") or {}
        if isinstance(config, dict):
            payload["my_classroom"] = str(config.get("my_classroom") or "")
        return payload

    def ensure_account_defaults(self, profile: UserProfile) -> None:
        root = account_root(self.db, profile.user_id)
        if not root.exists_rel("config.doc"):
            root.write_rel("config.doc", {"my_classroom": ""})
        if not root.exists_rel("projects/metas.doc"):
            root.write_rel("projects/metas.doc", {"meta": ""})
        if not root.exists_rel("datasets/metas.doc"):
            root.write_rel("datasets/metas.doc", {"meta": ""})

    def claim_username(self, principal: AuthPrincipal, username: str, account_type: str = "student") -> UserProfile:
        normalized = validate_username(username)
        profile = self.get_or_create_from_principal(principal)
        existing = self.db[self.username_path(normalized)].read()
        if isinstance(existing, dict) and existing.get("account_id") != profile.account_id:
            raise ValueError("Username is already taken.")
        if profile.username and profile.username != normalized:
            self.db.delete(self.username_path(profile.username))
        profile.username = normalized
        profile.type = normalize_account_type(account_type)
        profile.updated_at = utc_now()
        self.save_profile(profile)
        self.db[self.username_path(normalized)].write({"account_id": profile.account_id, "user_id": profile.user_id})
        return profile

    def username_available(self, principal: AuthPrincipal, username: str) -> tuple[str, bool]:
        normalized = validate_username(username)
        profile = self.get_or_create_from_principal(principal)
        existing = self.db[self.username_path(normalized)].read()
        return normalized, not isinstance(existing, dict) or existing.get("account_id") == profile.account_id
