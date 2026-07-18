from __future__ import annotations

from typing import Any

import requests


GUMROAD_API_BASE = "https://api.gumroad.com/v2"


class GumroadApiError(RuntimeError):
    pass


def verify_gumroad_license(*, license_key: str, product_permalink: str = "", product_id: str = "", increment_uses_count: bool = False) -> dict[str, Any]:
    payload: dict[str, Any] = {"license_key": license_key, "increment_uses_count": "true" if increment_uses_count else "false"}
    if product_permalink:
        payload["product_permalink"] = product_permalink
    if product_id:
        payload["product_id"] = product_id
    response = requests.post(f"{GUMROAD_API_BASE}/licenses/verify", data=payload, timeout=30)
    try:
        body = response.json()
    except Exception:
        body = {"success": False, "message": response.text}
    if response.status_code >= 400:
        raise GumroadApiError(f"Gumroad license verification failed {response.status_code}: {body}")
    return body


def gumroad_success(body: dict[str, Any]) -> bool:
    return bool(body.get("success"))


def gumroad_purchase(body: dict[str, Any]) -> dict[str, Any]:
    purchase = body.get("purchase") or body.get("sale") or {}
    return purchase if isinstance(purchase, dict) else {}
