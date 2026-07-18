from __future__ import annotations

import argparse
import json
import tempfile
import zipfile
from pathlib import Path
from typing import Any

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper


def create_dummy_bundle(
    output_path: str | Path,
    *,
    epochs: int = 2,
    dataset_ref: dict[str, Any] | None = None,
    include_dataset: bool = True,
) -> Path:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neuralese_dummy_bundle_") as temp_dir_s:
        temp_dir = Path(temp_dir_s)
        _write_manifest(temp_dir / "manifest.json", epochs=epochs, dataset_ref=dataset_ref)
        _write_model(temp_dir / "model.onnx")
        data_dir = temp_dir / "data"
        if include_dataset:
            data_dir.mkdir()
            _write_dataset(data_dir / "train.npz")

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(temp_dir / "manifest.json", "manifest.json")
            zf.write(temp_dir / "model.onnx", "model.onnx")
            if include_dataset:
                zf.write(data_dir / "train.npz", "data/train.npz")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a tiny Neuralese ONNX training bundle.")
    parser.add_argument(
        "output",
        nargs="?",
        default="dummy_bundle.zip",
        help="Output .zip path. Defaults to dummy_bundle.zip.",
    )
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--public-dataset-id", default="")
    parser.add_argument(
        "--no-embedded-dataset",
        action="store_true",
        help="Write dataset_ref only and omit data/train.npz.",
    )
    args = parser.parse_args()
    dataset_ref = None
    if args.public_dataset_id:
        dataset_ref = {"type": "public", "id": args.public_dataset_id}
    path = create_dummy_bundle(
        args.output,
        epochs=args.epochs,
        dataset_ref=dataset_ref,
        include_dataset=not args.no_embedded_dataset,
    )
    print(path)


def _write_manifest(path: Path, *, epochs: int, dataset_ref: dict[str, Any] | None) -> None:
    manifest = {
        "bundle_version": 1,
        "model_name": "tiny-linear",
        "task": "classification",
        "loss": "cross_entropy",
        "optimizer": "adamw",
        "learning_rate": 0.01,
        "epochs": int(epochs),
        "batch_size": 2,
        "trainable_parameters": ["W", "b"],
        "input_name": "input",
        "label_name": "target",
        "output_names": ["logits"],
    }
    if dataset_ref is not None:
        manifest["dataset_ref"] = dataset_ref
    path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def _write_model(path: Path) -> None:
    x = helper.make_tensor_value_info("input", TensorProto.FLOAT, [None, 2])
    logits = helper.make_tensor_value_info("logits", TensorProto.FLOAT, [None, 2])
    weights = np.array([[0.1, -0.1], [0.0, 0.1]], dtype=np.float32)
    bias = np.array([0.0, 0.0], dtype=np.float32)
    graph = helper.make_graph(
        [
            helper.make_node("MatMul", ["input", "W"], ["mm"]),
            helper.make_node("Add", ["mm", "b"], ["logits"]),
        ],
        "tiny-linear",
        [x],
        [logits],
        [
            numpy_helper.from_array(weights, "W"),
            numpy_helper.from_array(bias, "b"),
        ],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_operatorsetid("", 17)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    onnx.save(model, path)


def _write_dataset(path: Path) -> None:
    x = np.array(
        [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]],
        dtype=np.float32,
    )
    y = np.array([0, 1, 1, 1], dtype=np.int64)
    np.savez(path, x=x, y=y)


if __name__ == "__main__":
    main()
