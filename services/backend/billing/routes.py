from __future__ import annotations

import hashlib
from typing import Any

from sanic import Blueprint, Request

from auth.dependencies import AuthError, require_account
from common.responses import fail, ok

from .gumroad_client import gumroad_purchase, gumroad_success, verify_gumroad_license
from .service import hash_license_key, purchase_is_inactive


bp_billing = Blueprint("billing", url_prefix="/api/billing")


@bp_billing.get("/gumroad/checkout-url")
async def gumroad_checkout_url(request: Request):
    try:
        require_account(request)
    except AuthError as exc:
        return fail(str(exc), exc.status)
    url = request.app.ctx.settings.gumroad_product_url
    if not url:
        return fail("GUMROAD_PRODUCT_URL is not configured", 500)
    return ok({"provider": "gumroad", "checkout_url": url})


@bp_billing.post("/gumroad/verify-license")
async def gumroad_verify_license(request: Request):
    try:
        account = require_account(request)
    except AuthError as exc:
        return fail(str(exc), exc.status)
    body = request.json or {}
    license_key = str(body.get("license_key", "")).strip()
    if not license_key:
        return fail("missing license_key", 400)
    settings = request.app.ctx.settings
    try:
        result = verify_gumroad_license(
            license_key=license_key,
            product_permalink=settings.gumroad_product_permalink,
            product_id=settings.gumroad_product_id,
        )
    except Exception as exc:
        return fail(f"gumroad license verification failed: {exc}", 502)
    if not gumroad_success(result):
        return fail(result.get("message", "invalid Gumroad license"), 400, gumroad=result)
    purchase = gumroad_purchase(result)
    if purchase_is_inactive(purchase):
        return fail("Gumroad purchase is inactive.", 403, gumroad=result)
    license_hash = hash_license_key(license_key, settings.dev_shared_secret)
    try:
        binding = request.app.ctx.billing_service.bind_gumroad_license(
            account_id=account.profile.account_id,
            license_hash=license_hash,
            sale=purchase,
            product_id=settings.gumroad_product_id,
            product_permalink=settings.gumroad_product_permalink,
        )
    except ValueError as exc:
        return fail(str(exc), 409)
    event_id = str(purchase.get("id") or purchase.get("sale_id") or license_hash)
    request.app.ctx.billing_service.remember_event("gumroad", event_id, "license.verified", {"purchase": purchase})
    return ok({"provider": "gumroad", "binding": binding, "entitlement": request.app.ctx.billing_service.entitlement_status(account.profile.account_id)})


@bp_billing.post("/gumroad/ping")
async def gumroad_ping(request: Request):
    settings = request.app.ctx.settings
    secret = str(request.args.get("secret", ""))
    if settings.gumroad_ping_secret and secret != settings.gumroad_ping_secret:
        return fail("forbidden", 403)
    payload: dict[str, Any]
    if isinstance(request.json, dict):
        payload = request.json
    else:
        payload = {key: request.form.get(key) for key in request.form.keys()} if request.form else {}
    sale_id = str(payload.get("sale_id") or payload.get("id") or hashlib.sha256(repr(sorted(payload.items())).encode("utf-8")).hexdigest())
    if not request.app.ctx.billing_service.remember_event("gumroad", sale_id, "gumroad.ping", payload):
        return ok({"duplicate": True})
    if purchase_is_inactive(payload):
        request.app.ctx.billing_service.deactivate_by_sale_id(sale_id)
    return ok()


@bp_billing.get("/status")
async def billing_status(request: Request):
    try:
        account = require_account(request)
    except AuthError as exc:
        return fail(str(exc), exc.status)
    return ok({"entitlement": request.app.ctx.billing_service.entitlement_status(account.profile.account_id)})


@bp_billing.post("/dev/mock-license")
async def dev_mock_license(request: Request):
    body = request.json or {}
    settings = request.app.ctx.settings
    if str(body.get("secret", "")) != settings.dev_shared_secret:
        return fail("forbidden", 403)
    try:
        account = require_account(request)
    except AuthError as exc:
        return fail(str(exc), exc.status)
    binding = request.app.ctx.billing_service.bind_gumroad_license(
        account_id=account.profile.account_id,
        license_hash=hash_license_key(str(body.get("license_key", "DEV-LICENSE")), settings.dev_shared_secret),
        sale={"id": "sale_dev_mock", "email": account.profile.email},
        product_id=settings.gumroad_product_id,
        product_permalink=settings.gumroad_product_permalink,
    )
    return ok({"binding": binding, "entitlement": request.app.ctx.billing_service.entitlement_status(account.profile.account_id)})
