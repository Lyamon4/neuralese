# worker/trio_tasks.py
from __future__ import annotations
from typing import Any, Dict, Callable
import traceback, io
from contextlib import suppress
from time import perf_counter

import nns.model_core as nodes
import nns.onnx_exporter as onnx_exporter

Emit = Callable[[Dict[str, Any]], Any]

# ---- helpers used by handlers ----
def load_ctx_from_blob(graph: dict, blob: bytes | None):
    ctx = nodes.gen_context()
    if blob:
        nodes.load_model(ctx, io.BytesIO(blob))
        # optional: execute graph once to ensure shapes/buffers exist
        with suppress(Exception):
            nodes.execute_graph(graph, ctx)
    return ctx

def dump_ctx_to_blob(ctx) -> bytes:
    buff = io.BytesIO()
    nodes.save_model(ctx, buff)
    return buff.getvalue()

# ---- tasks ----
def load_graph_task(emit: Emit, recv, arguments: Dict[str, Any]) -> Dict[str, Any]:
    nodes.execute_graph(arguments["graph"], arguments["context"])
    if "train_graph" in arguments:
        nodes.execute_graph(arguments["train_graph"], arguments["context"].nested)
    nodes.load_model(arguments["context"], arguments["load_from"])
    return {"status": "ok"}

def train_task(emit: Emit, recv, arguments: Dict[str, Any]) -> Dict[str, Any]:
    emit({"phase": "start", "mode": "train"})
    graph, ctx = arguments["graph"], arguments["context"]
    killed = False

    def _on_kill():
        nonlocal killed
        killed = True
        emit({"phase": "stopped"})

    # Register kill hook
    recv.on_kill(_on_kill)

    try:
        nodes.execute_graph(graph, ctx)
        if "train_graph" in arguments:
            nodes.execute_graph(arguments["train_graph"], ctx.nested)

        gen = nodes.train(
            arguments,
            ctx,
            arguments["epochs"],
            arguments["dataset"],
            batching_size=arguments.get("batch_size", 16),
        )

        for report in gen:
            if killed or recv.closed:
                emit({"phase": "stopped"})
                break
            emit({"phase": "state", "data": report})

    except Exception as e:
        traceback.print_exc()
        emit({"phase": "error", "error": {"type": "TrainError", "message": str(e)}})
        return {"status": "error"}

    if killed:
        return {"status": "stopped"}
    emit({"phase": "done"})
    return {"status": "ok"}

from queue import Empty

def infer_task(emit: Emit, recv, arguments: Dict[str, Any]) -> Dict[str, Any]:
    emit({"phase": "start", "mode": "infer"})
    graph, ctx = arguments["graph"], arguments["context"]
    try:
        nodes.set_eval_mode(ctx)
        nodes.execute_graph(graph, ctx)
    except Exception as e:
        emit({"phase": "error", "error": {"type": "InitError", "message": str(e)}})
        return {"status": "error"}

    idx = 0
    while not recv.closed:
        try:
            msg = recv.pop(timeout=0.1)   # <— blocks, releases GIL
        except Empty:
            continue
        except EOFError:
            break
        except Exception:
            continue

        try:
            payload = msg
            g = graph
            if "full_graph" in payload["data"]:
                g = payload["data"]["full_graph"]
            else:
                if g.get("pages"):
                    with suppress(Exception):
                        for _, who in g["pages"].get("0", {}).items():
                            if who["type"] == "InputNode":
                                who["props"]["raw_values"] = payload["data"]["raw_values"]

            res = nodes.execute_graph(g, ctx)
            out = {}
            for node_id, port_map in res.endings.items():
                for port, packs in port_map.items():
                    for pack in packs:
                        out.setdefault(node_id, {}).setdefault(port, []).append(pack["tensor"].tolist())
            idx += 1
            emit({"phase": "inference", "result": out, "index": idx, "ok": True})
        except Exception as e:
            emit({"phase": "error", "error": {"type": "InferenceError", "message": str(e), "index": idx + 1}})
    return {"status": "ok"}


import yolks.packer as appify
def export_nn_task(emit, recv, arguments: Dict[str, Any]) -> Dict[str, Any]:
	graph = arguments["graph"]
	ctx = arguments["ctx"]
	flags = arguments.get("flags", {})
	to_app = flags.get("to_app", "")
	quant_mode = flags.get("quant", "none")

	def _input_shape(g: dict) -> int:
		try:
			first_node = list(g["pages"]["0"].values())[0]
			return int(first_node["props"]["shape"])
		except Exception:
			return 1

	input_shape = (1, _input_shape(graph))
	t0 = perf_counter()

	try:
		# ----- Core export -----
		if to_app == "tensorrt":
			result = onnx_exporter.export_to_tensorrt(
				graph=graph,
				ctx=ctx,
				input_shape=input_shape,
				output_branches=None,
				quantization=quant_mode,
				fp16=True,
				int8=(quant_mode.lower() == "int8"),
				verbose=False,
			)
		else:
			result = onnx_exporter.export_to_onnx(
				graph=graph,
				ctx=ctx,
				input_shape=input_shape,
				verbose=False,
				quantization=quant_mode,
			)
	except Exception as e:
		traceback.print_exc()
		return {"status": "err", "error": f"Export failed: {e}"}

	if not result.get("success"):
		return {"status": "err", "error": result.get("error", "unknown export error")}

	# ----- Get bytes -----
	out_bytes = result["bytes"]
	if isinstance(out_bytes, io.BytesIO):
		out_bytes = out_bytes.getvalue()

	# ----- Optional app packaging -----
	try:
		if quant_mode.lower() in ("float16", "fp16"):
			dtype = "f16"
		elif quant_mode.lower() in ("int8", "int16"):
			dtype = "i8"
		elif result.get("precision") == "fp16":
			dtype = "f16"
		else:
			dtype = "f32"

		meta = {
			"input_shape": list(input_shape),
			"input_dtype": dtype,
			"quantization": quant_mode,
			"backend": result.get("backend", "onnx"),
		}
		if to_app == "windows":
			out_bytes = appify.pack_to_bytes(out_bytes, meta, "win")
		elif to_app == "linux":
			out_bytes = appify.pack_to_bytes(out_bytes, meta, "linux")
	except Exception as e:
		traceback.print_exc()
		return {"status": "err", "error": f"Packaging failed: {e}"}

	# ----- Return unified output schema -----
	return {
		"status": "ok",
		"bytes": memoryview(out_bytes),
		"time": perf_counter() - t0,
		"backend": (
			"tensorrt" if to_app == "tensorrt"
			else "onnx"
		),
	}

