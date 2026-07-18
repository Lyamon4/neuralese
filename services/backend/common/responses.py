from __future__ import annotations

from sanic.response import json


def ok(data: dict | None = None, status: int = 200):
    return json({"ok": True, **(data or {})}, status=status)


def fail(error: str, status: int = 400, **extra):
    return json({"ok": False, "error": error, **extra}, status=status)


def legacy_ok(data: dict | None = None):
    return json({"answer": "ok", **(data or {})})


def legacy_wrong(status: int = 200):
    return json({"answer": "wrong"}, status=status)
