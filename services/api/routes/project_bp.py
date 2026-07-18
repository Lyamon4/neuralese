from sanic import Blueprint
from sanic.response import json as sanic_json
import io
import record.ds_route as dsr
import storage
from common.context_cache import contexts
from common.trio_handlers import get_old_context
from common.utils import kief

bp_project = Blueprint("project", url_prefix="")

def try_login(app, data) -> storage.Node:
	db = app.ctx.database
	user, pw = kief(data["user"]), data["pass"]
	root = db[f"/{user}/"]
	if not root.exists_rel("user.doc"): return None
	from common import tools
	if not tools.verify_password(pw, root.read_rel("user.doc")["hash"]): return None
	return root


from common.context_cache import _make_ctx_key


def garbage_collection(contexts_scene: dict, scene_id: str, node: storage.Node):
    root = node.child(f"projects/{scene_id}/contexts/")
    for i in root.ls():
        if i == "meta.doc":
            continue
        unsuf = i.removesuffix(".blob")
        if not int(unsuf) in contexts_scene:
            root.delete_rel(i)
            key = _make_ctx_key(node, scene_id, unsuf)
            if key in contexts:
                contexts.pop(key)






@bp_project.post("/save")
async def save_scene(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id, chat_id, last_id = request.json["scene"], request.json["chat_id"], request.json["last_id"]
	if not scene_id.isdigit():
		return sanic_json({"answer": "invalid"})
	from common.project_utils import update_last_id

	garbage_collection(request.json["contexts"], scene_id, node)
	node.write_rel(f"projects/{scene_id}/data.scn", request.json["blob"])
	node.write_rel(f"projects/{scene_id}/meta.doc", {"name": request.json["name"]})
	node.write_rel(f"projects/{scene_id}/contexts/meta.doc", {})
	node.write_rel(f"projects/{scene_id}/chats/metas.doc", {})
	if last_id != -1:
		update_last_id(node, scene_id, chat_id, last_id)
	return sanic_json({"answer": "ok"})


@bp_project.post("/project")
async def get_project(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id = request.json["scene"]
	data = node.read_rel(f"projects/{scene_id}/data.scn")
	scene_name = node.read_rel(f"projects/{scene_id}/meta.doc")
	if not scene_name:
		return sanic_json({"answer": "wrong"})
	scene_name = scene_name["name"]
	return sanic_json({"answer": "ok", "scene": data, "name": scene_name})


@bp_project.post("/delete_project")
async def delete_project(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	scene_id = request.json["scene"]
	node.delete_rel(f"projects/{scene_id}")
	return sanic_json({"answer": "ok"})


@bp_project.post("/project_list")
async def project_list(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	data = node.child("projects").ls()
	result = {i: node.read_rel(f"projects/{i}/meta.doc") for i in data if not i.endswith(".doc")}
	return sanic_json({"answer": "ok", "list": result})


@bp_project.get("/datasets")
async def request_datasets(request):
	query = request.args.get("query", "")
	datasets = ["mnist", "titanic", "iris", "car_track"]
	results = {}
	for i in datasets:
		if not query or query in i:
			results[i] = dsr.get_pub(i)
	return sanic_json({"status": "ok", "results": results})


@bp_project.post("/reg_dataset")
async def register_dataset(request):
	node = try_login(request.app, request.json)
	if node is None:
		return sanic_json({"answer": "wrong"})
	return sanic_json({"answer": "ok"})
