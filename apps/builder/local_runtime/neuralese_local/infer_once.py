from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List

import numpy as np
import onnxruntime as ort


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: infer_once.py <request.json>", file=sys.stderr)
        return 2

    request_path = Path(sys.argv[1])
    request = json.loads(request_path.read_text(encoding="utf-8-sig"))
    response = run_inference(request)

    response_path = request.get("response_path")
    if response_path:
        Path(response_path).write_text(json.dumps(response), encoding="utf-8")
    else:
        print(json.dumps(response))
    return 0 if response.get("ok", False) else 1


def run_inference(request: Dict[str, Any]) -> Dict[str, Any]:
    try:
        model_path = Path(request["model_path"])
        if not model_path.exists():
            raise FileNotFoundError(f"Local inference model not found: {model_path}")

        session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        input_info = session.get_inputs()[0]
        raw_values = _extract_raw_values(request)
        input_array = _shape_input(raw_values, input_info.shape)
        preds = session.run(None, {input_info.name: input_array})[0]
        final_node_id = str(request.get("output_node_id") or _find_final_node_id(request.get("graph", {})))
        packet = {
            "phase": "inference",
            "ok": True,
            "index": int(request.get("index", 0)),
            "result": {
                final_node_id: {
                    "model_out": [preds.tolist()]
                }
            },
        }
        return packet
    except Exception as exc:
        return {
            "phase": "error",
            "ok": False,
            "error": {"type": "InferenceError", "message": str(exc)},
            "result": {},
        }


def _extract_raw_values(request: Dict[str, Any]) -> List[float]:
    data = request.get("data", {}) or {}
    if "raw_values" in data:
        return _flatten(data["raw_values"])
    full_graph = data.get("full_graph") or request.get("graph") or {}
    for page in full_graph.get("pages", {}).values():
        for node in page.values():
            if str(node.get("type", "")) in {"InputNode", "input_1d", "input_2d"}:
                props = node.get("props", {}) or {}
                if "raw_values" in props:
                    return _flatten(props["raw_values"])
    raise ValueError("No raw_values found in local inference request")


def _flatten(value: Any) -> List[float]:
    if isinstance(value, list):
        out: List[float] = []
        for item in value:
            out.extend(_flatten(item))
        return out
    return [float(value)]


def _shape_input(raw_values: List[float], input_shape: List[Any]) -> np.ndarray:
    arr = np.asarray(raw_values, dtype=np.float32)
    dims = list(input_shape[1:]) if input_shape and len(input_shape) > 1 else []
    if dims and all(isinstance(d, int) and d > 0 for d in dims):
        expected = int(np.prod(dims))
        if expected == arr.size:
            return arr.reshape([1, *dims])
    return arr.reshape(1, -1)


def _find_final_node_id(graph: Dict[str, Any]) -> str:
    pages = graph.get("pages", {}) or {}
    if not pages:
        return "0"
    page_keys = sorted(pages.keys(), key=lambda k: int(k) if str(k).isdigit() else str(k))
    ignored = {"TrainInput", "TrainBegin", "RunModel", "DatasetName", "ModelName"}
    for page_key in reversed(page_keys):
        page = pages.get(page_key, {}) or {}
        for node_id in reversed(list(page.keys())):
            if str(page[node_id].get("type", "")) not in ignored:
                return str(node_id)
    return str(next(iter(pages[page_keys[-1]].keys())))


if __name__ == "__main__":
    raise SystemExit(main())

