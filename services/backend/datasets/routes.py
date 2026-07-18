from __future__ import annotations

import json

from sanic import Blueprint, Request
from sanic.response import json as sanic_json


bp_datasets = Blueprint("datasets", url_prefix="")


@bp_datasets.get("/api/datasets", name="request_datasets_api")
@bp_datasets.get("/datasets", name="request_datasets_legacy")
async def request_datasets(request: Request):
    query = str(request.args.get("query", "")).lower()
    results = {}
    base = request.app.ctx.settings.datasets_dir
    builtins = ["mnist", "titanic", "iris", "car_track"]
    for name in builtins:
        if query and query not in name.lower():
            continue
        pub = base / name / ".pub"
        if pub.exists():
            try:
                results[name] = json.loads(pub.read_text(encoding="utf-8"))
                continue
            except Exception:
                pass
        results[name] = {"name": name, "builtin": True}
    return sanic_json({"status": "ok", "results": results})
