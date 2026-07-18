contexts = {}
currently_training = {}
task_state = {"training": set(), "infer": set()}


def training_mark_started(key):
	task_state["training"].add(key)


def is_training(key) -> bool: return key in task_state["training"]
def is_inferring(key) -> bool: return key in task_state["infer"]

def training_mark_stopped(key):
	if key in task_state["training"]:
		task_state["training"].remove(key)
	else:
		print("[ERR] No key found", str(key), "training")


def infer_mark_started(key):
	task_state["infer"].add(key)


def infer_mark_stopped(key):
	if key in task_state["infer"]:
		task_state["infer"].remove(key)
	else:
		print("[ERR] No key found", str(key), "infer")

import io, threading, nns.model_core as nodes

_lock = threading.Lock()

def make_key(user, scene, ctx): return f"{user}:{scene}:{ctx}"

def _make_ctx_key(node, scene_id: str, ctx_name: str) -> tuple:
    return (node.path, str(scene_id), str(ctx_name))

def get_or_load_ctx(db, body):
	key = make_key(body.get("user", "anon"), body["scene_id"], body["context"])
	with _lock:
		if key in contexts:
			return contexts[key]
	blob = db.get(key)
	ctx = nodes.gen_context()
	if blob:
		nodes.load_model(ctx, io.BytesIO(blob))
	with _lock:
		contexts[key] = ctx
	return ctx
