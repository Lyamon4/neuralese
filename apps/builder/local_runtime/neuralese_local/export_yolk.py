from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List

import onnx
from onnx import TensorProto

MAGIC = b"NLESE_YOLK_v001!"


def _runtime_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _dtype_name(elem_type: int) -> str:
    if elem_type == TensorProto.FLOAT:
        return "f32"
    if elem_type == TensorProto.INT8:
        return "i8"
    if elem_type == TensorProto.UINT8:
        return "u8"
    raise ValueError(f"Unsupported executable export input dtype: {elem_type}")


def _dim_value(dim) -> int:
    if dim.HasField("dim_value") and dim.dim_value > 0:
        return int(dim.dim_value)
    # Neuralese models often use symbolic batch_size. The runner consumes one
    # sample from stdin, so dynamic/unknown dimensions collapse to 1.
    return 1


def _model_meta(model_path: Path) -> Dict[str, Any]:
    model = onnx.load(model_path)
    initializer_names = {init.name for init in model.graph.initializer}
    inputs = [value for value in model.graph.input if value.name not in initializer_names]
    if not inputs:
        raise ValueError("ONNX model has no runtime inputs")

    input_info = inputs[0]
    tensor_type = input_info.type.tensor_type
    shape = [_dim_value(dim) for dim in tensor_type.shape.dim]
    return {
        "format": "neuralese_yolk_v1",
        "input_name": input_info.name,
        "input_shape": shape,
        "input_dtype": _dtype_name(tensor_type.elem_type),
        "output_names": [out.name for out in model.graph.output],
    }


def _core_path(platform: str) -> Path:
    root = _runtime_root()
    if platform == "windows":
        return root / "export_cores" / "windows-x64" / "neuralese_yolk_runner.exe"
    if platform == "linux":
        return root / "export_cores" / "linux-x64" / "neuralese_yolk_runner"
    raise ValueError(f"Unsupported local executable export platform: {platform}")


def _validate_core(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Runner core not found: {path}")
    data = path.read_bytes()
    if MAGIC not in data:
        raise ValueError(
            f"Runner core is incompatible with Neuralese Yolk v1 payloads: {path}. "
            "Rebuild local_runtime/yolk_runner_proto for this platform and copy it here."
        )


def _pack_executable(model_path: Path, platform: str, out_path: Path) -> Dict[str, Any]:
    core = _core_path(platform)
    _validate_core(core)
    meta = _model_meta(model_path)
    core_bytes = core.read_bytes()
    model_bytes = model_path.read_bytes()
    meta_bytes = json.dumps(meta, separators=(",", ":")).encode("utf-8")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(
        core_bytes
        + model_bytes
        + meta_bytes
        + struct.pack("<Q", len(meta_bytes))
        + struct.pack("<Q", len(model_bytes))
        + MAGIC
    )
    return {
        "status": "ok",
        "platform": platform,
        "output_path": str(out_path),
        "bytes": out_path.stat().st_size,
        "model_bytes": len(model_bytes),
        "meta": meta,
    }


def export_from_request(request: Dict[str, Any]) -> Dict[str, Any]:
    model_path = Path(request["model_path"]).resolve()
    out_path = Path(request["output_path"]).resolve()
    platform = str(request.get("platform", "onnx")).lower()
    if not model_path.exists():
        raise FileNotFoundError(f"Local inference model not found: {model_path}")

    if platform == "onnx":
        out_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(model_path, out_path)
        return {
            "status": "ok",
            "platform": "onnx",
            "output_path": str(out_path),
            "bytes": out_path.stat().st_size,
            "meta": _model_meta(model_path),
        }

    return _pack_executable(model_path, platform, out_path)


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        print("usage: export_yolk.py <request.json>", file=sys.stderr)
        return 2
    request_path = Path(argv[1]).resolve()
    response_path = request_path.with_name("response.json")
    try:
        request = json.loads(request_path.read_text(encoding="utf-8-sig"))
        result = export_from_request(request)
        response_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result))
        return 0
    except Exception as exc:
        result = {"status": "error", "error": str(exc)}
        response_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
