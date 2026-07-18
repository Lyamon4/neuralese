from sanic import Blueprint
from sanic.response import json as sanic_json
from common.utils import kief, load_classroom, classroom_data
import common.tools as tools
import storage

bp_auth = Blueprint("auth", url_prefix="")

def try_login(app, data: dict) -> storage.Node:
	db = app.ctx.database
	user, pw = kief(data["user"]), data["pass"]
	root = db[f"/{user}/"]
	if not root.exists_rel("user.doc"):
		return None
	if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]): return None
	return root




@bp_auth.post("/login")
async def login(request):
	node = try_login(request.app, request.json)
	data = {}; config = {}
	if node:
		config = node.read_rel("config.doc")
		if config.get("my_classroom", ""):
			loaded = load_classroom(request.app, config["my_classroom"])
			if loaded:
				data = classroom_data(loaded)
			else:
				node.update_doc_rel("config.doc", {"my_classroom": ""})
	return sanic_json({"answer": "ok", "config": config, "classroom_data": data} if node else {"answer": "wrong"})

import sys
@bp_auth.post("/create_user")
async def create_user(request):
	db = request.app.ctx.database
	user, pw = kief(request.json["user"]), request.json["pass"]
	root = db[f"/{user}/"]
	if root.exists_rel("user.doc"):
		return sanic_json({"answer": "exists"})
	root.write_rel("user.doc", {"hash": tools.hash_password(pw)})
	cfg = request.json.get("config", {"teacher": False, "my_classroom": ""})
	root.write_rel("config.doc", cfg)
	root.write_rel("projects/metas.doc", {"meta": ""})
	root.write_rel("datasets/metas.doc", {"meta": ""})
	return sanic_json({"answer": "ok"})
