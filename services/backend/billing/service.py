from __future__ import annotations

import hashlib
import hmac
import time
from typing import Any


def hash_license_key(license_key: str, secret: str) -> str:
    return hmac.new(secret.encode("utf-8"), license_key.encode("utf-8"), hashlib.sha256).hexdigest()


def purchase_is_inactive(purchase: dict[str, Any]) -> bool:
    return any(bool(purchase.get(flag)) for flag in [
        "refunded", "disputed", "chargebacked", "subscription_cancelled",
        "subscription_failed", "ended",
    ])


class BillingService:
    def __init__(self, db):
        self.db = db

    def license_path(self, license_hash: str) -> str:
        return f"/billing/gumroad/licenses/{license_hash}.doc"

    def event_path(self, provider: str, event_id: str) -> str:
        return f"/billing/events/{provider}/{event_id}.doc"

    def user_entitlement_path(self, account_id: str) -> str:
        return f"/billing/users/{account_id}/entitlement.doc"

    def bind_gumroad_license(self, *, account_id: str, license_hash: str, sale: dict[str, Any], product_id: str, product_permalink: str) -> dict[str, Any]:
        existing = self.db[self.license_path(license_hash)].read()
        if isinstance(existing, dict) and existing.get("account_id") not in ("", account_id):
            raise ValueError("This Gumroad license is already bound to another account.")
        sale_id = str(sale.get("id") or sale.get("sale_id") or license_hash)
        binding = {
            "provider": "gumroad",
            "account_id": account_id,
            "license_hash": license_hash,
            "sale_id": sale_id,
            "buyer_email": str(sale.get("email") or ""),
            "product_id": product_id or str(sale.get("product_id") or ""),
            "product_permalink": product_permalink,
            "active": not purchase_is_inactive(sale),
            "sale": sale,
            "updated_at": time.time(),
        }
        self.db[self.license_path(license_hash)].write(binding)
        self.db[self.user_entitlement_path(account_id)].write(binding)
        return binding

    def entitlement_status(self, account_id: str) -> dict[str, Any]:
        ent = self.db[self.user_entitlement_path(account_id)].read()
        if not isinstance(ent, dict):
            return {"active": False, "provider": "", "reason": "none"}
        return {"active": bool(ent.get("active")), "provider": ent.get("provider", ""), "binding": ent}

    def remember_event(self, provider: str, event_id: str, event_type: str, payload: dict[str, Any]) -> bool:
        path = self.event_path(provider, event_id)
        if self.db[path].read():
            return False
        self.db[path].write({"provider": provider, "event_id": event_id, "type": event_type, "payload": payload, "created_at": time.time()})
        return True

    def deactivate_by_sale_id(self, sale_id: str) -> None:
        root = self.db["/billing/gumroad/licenses/"]
        for name in root.ls():
            binding = root.read_rel(name)
            if isinstance(binding, dict) and binding.get("sale_id") == sale_id:
                binding["active"] = False
                binding["updated_at"] = time.time()
                root.write_rel(name, binding)
                account_id = str(binding.get("account_id", ""))
                if account_id:
                    self.db[self.user_entitlement_path(account_id)].write(binding)
