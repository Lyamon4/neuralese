from __future__ import annotations

import base64
import json
from functools import lru_cache
from typing import Any

import jwt
import requests
from jwt.algorithms import RSAAlgorithm


class ClerkAuthError(ValueError):
    pass


def _display_name(user: dict[str, Any], email: str) -> str:
    first = str(user.get("first_name") or "").strip()
    last = str(user.get("last_name") or "").strip()
    full = " ".join([p for p in [first, last] if p]).strip()
    return full or str(user.get("username") or "").strip() or email or "Neuralese user"


def _primary_email(user: dict[str, Any]) -> str:
    primary_id = user.get("primary_email_address_id")
    for item in user.get("email_addresses") or []:
        if item.get("id") == primary_id:
            return str(item.get("email_address") or "").strip()
    for item in user.get("email_addresses") or []:
        email = str(item.get("email_address") or "").strip()
        if email:
            return email
    return ""


def _clerk_frontend_api(publishable_key: str) -> str:
    try:
        encoded = publishable_key.split("_")[2]
        padding = "=" * (-len(encoded) % 4)
        decoded = base64.b64decode(encoded + padding).decode("utf-8")
        return decoded.rstrip("$").strip()
    except Exception:
        return ""


@lru_cache(maxsize=16)
def _fetch_jwks(url: str, secret_key: str = "") -> dict[str, Any]:
    headers = {"Authorization": f"Bearer {secret_key}"} if secret_key else {}
    response = requests.get(url, headers=headers, timeout=10)
    if response.status_code < 200 or response.status_code >= 300:
        raise ClerkAuthError(f"JWKS fetch failed: HTTP {response.status_code} from {url}")
    return response.json()


def _candidate_jwks(settings) -> list[tuple[str, str]]:
    urls: list[tuple[str, str]] = []
    frontend_api = _clerk_frontend_api(settings.clerk_publishable_key)
    if frontend_api:
        urls.append((f"https://{frontend_api}/.well-known/jwks.json", ""))
    if settings.clerk_secret_key:
        urls.append(("https://api.clerk.com/v1/jwks", settings.clerk_secret_key))
    return urls


def _signing_key(settings, token: str):
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise ClerkAuthError(f"invalid Clerk session token header: {exc}") from exc
    kid = header.get("kid")
    if not kid:
        raise ClerkAuthError("Clerk session token has no key id")

    errors: list[str] = []
    for url, secret in _candidate_jwks(settings):
        try:
            jwks = _fetch_jwks(url, secret)
            for key in jwks.get("keys", []):
                if key.get("kid") == kid:
                    return RSAAlgorithm.from_jwk(json.dumps(key))
            errors.append(f"no matching key in {url}")
        except Exception as exc:
            errors.append(str(exc))
    raise ClerkAuthError("could not find Clerk signing key: " + "; ".join(errors))


def verify_session_token(settings, session_token: str) -> dict[str, Any]:
    if not session_token:
        raise ClerkAuthError("missing Clerk session token")
    try:
        unverified = jwt.decode(session_token, options={"verify_signature": False})
    except jwt.PyJWTError as exc:
        raise ClerkAuthError(f"invalid Clerk session token: {exc}") from exc

    issuer = str(unverified.get("iss") or "").rstrip("/")
    if not issuer:
        raise ClerkAuthError("Clerk session token has no issuer")

    try:
        payload = jwt.decode(
            session_token,
            _signing_key(settings, session_token),
            algorithms=["RS256"],
            issuer=issuer,
            leeway=60,
            options={"verify_aud": False},
        )
    except jwt.PyJWTError as exc:
        raise ClerkAuthError(f"could not verify Clerk session token: {exc}") from exc
    if payload.get("sts") == "pending":
        raise ClerkAuthError("Clerk session is pending")
    return payload


def get_user(settings, clerk_user_id: str) -> dict[str, Any]:
    if not settings.clerk_secret_key:
        raise ClerkAuthError("missing CLERK_SECRET_KEY")
    response = requests.get(
        f"https://api.clerk.com/v1/users/{clerk_user_id}",
        headers={"Authorization": f"Bearer {settings.clerk_secret_key}"},
        timeout=10,
    )
    if response.status_code == 404:
        raise ClerkAuthError("Clerk user not found; sign out and sign in again")
    if response.status_code < 200 or response.status_code >= 300:
        raise ClerkAuthError(f"Clerk user lookup failed: HTTP {response.status_code}")
    return response.json()


def user_payload_from_session(settings, session_token: str) -> dict[str, str]:
    payload = verify_session_token(settings, session_token)
    clerk_user_id = str(payload.get("sub") or "")
    if not clerk_user_id:
        raise ClerkAuthError("Clerk session token has no user id")
    user = get_user(settings, clerk_user_id)
    email = _primary_email(user)
    return {
        "clerk_user_id": clerk_user_id,
        "email": email,
        "display_name": _display_name(user, email),
    }
