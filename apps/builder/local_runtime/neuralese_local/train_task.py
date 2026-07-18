from __future__ import annotations

import json
import os
import shutil
import tempfile
import traceback
from pathlib import Path
from time import perf_counter
from typing import Any, Callable, Dict, Optional

import numpy as np
import onnx
import onnxruntime as ort

ort_train, artifacts = None, None

from .dataset_store import ArrayDataset, load_builtin_dataset, load_godot_json_dataset
from .onnx_compiler import build_onnx_model_from_graph

Emit = Callable[[Dict[str, Any]], None]
DEFAULT_BATCH_SIZE = 128
EXPORT_EVAL_INTERVAL = 5
EVAL_MAX_SAMPLES = 2048


def _load_ort_training_api():
    """Load ORT Training API without importing its legacy Torch-facing package init."""
    global ort_train, artifacts
    if ort_train is not None and artifacts is not None:
        return ort_train, artifacts

    import sys
    import types
    from importlib import import_module

    training_dir = Path(ort.__file__).resolve().parent / "training"
    if "onnxruntime.training" not in sys.modules:
        pkg = types.ModuleType("onnxruntime.training")
        pkg.__path__ = [str(training_dir)]
        sys.modules["onnxruntime.training"] = pkg

    api_mod = import_module("onnxruntime.training.api")
    artifacts_mod = import_module("onnxruntime.training.artifacts")

    class _OrtTrain:
        CheckpointState = api_mod.CheckpointState
        Module = api_mod.Module
        Optimizer = api_mod.Optimizer

    ort_train = _OrtTrain
    artifacts = artifacts_mod
    return ort_train, artifacts


def run_training(request: Dict[str, Any], emit: Emit, stop) -> Dict[str, Any]:
    ort_train_api, ort_artifacts = _load_ort_training_api()
    emit({"phase": "start", "mode": "train", "backend": "fullylocal_ort"})

    graph = request["graph"]
    train_graph = request.get("train_graph", {})
    epochs = max(1, int(request.get("epochs", 1)))
    batch_size = int(request.get("batch_size", 0)) or DEFAULT_BATCH_SIZE
    runtime_root = request.get("runtime_root") or str(Path(__file__).resolve().parents[1])
    job_dir = Path(request["job_dir"])
    artifact_dir = job_dir / "artifacts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_dir = Path(request.get("checkpoint_dir") or artifact_dir)
    checkpoint_dir.mkdir(parents=True, exist_ok=True)

    dataset = _load_dataset(request, runtime_root)
    if len(dataset) <= 0:
        raise ValueError(f"Dataset '{dataset.name}' is empty")

    training_config = _extract_training_config(train_graph)
    loss_name = training_config.get("loss", "cross_entropy")
    optimizer_name = training_config.get("optimizer", "adam")
    learning_rate = _parse_float(training_config.get("lr"), None)
    _coerce_targets_for_loss(dataset, loss_name)

    optimizer_type, actual_optimizer_name, optimizer_warning, optimizer_fallback = _resolve_optimizer_type(optimizer_name)
    if optimizer_warning:
        emit({"phase": "warning", "warning": optimizer_warning})
    if optimizer_fallback and learning_rate is not None and learning_rate > 1e-3:
        emit({
            "phase": "warning",
            "warning": (
                f"Requested optimizer '{optimizer_name}' is using AdamW fallback; "
                f"clamping learning rate from {learning_rate:g} to 0.001 for stability."
            ),
        })
        learning_rate = 1e-3

    model_proto, trainable_params = build_onnx_model_from_graph(graph, loss_name=loss_name)
    model_output_names = [out.name for out in model_proto.graph.output]
    if not trainable_params:
        raise ValueError("The graph has no trainable parameters")

    killed = False

    def _on_kill() -> None:
        nonlocal killed
        killed = True
        emit({"phase": "stopped"})

    stop.on_kill(_on_kill)

    final_inference_path: Optional[Path] = None
    try:
        with tempfile.TemporaryDirectory(prefix="neuralese_ort_") as temp_dir_s:
            temp_dir = Path(temp_dir_s)
            checkpoint_path = temp_dir / "checkpoint"
            training_model_path = temp_dir / "training_model.onnx"
            optimizer_model_path = temp_dir / "optimizer_model.onnx"
            eval_model_path = temp_dir / "eval_model.onnx"

            ort_artifacts.generate_artifacts(
                model_proto,
                requires_grad=trainable_params,
                loss=_loss_type(loss_name),
                optimizer=optimizer_type,
                artifact_directory=str(temp_dir),
            )

            for path in (training_model_path, optimizer_model_path, eval_model_path):
                if path.exists():
                    model = onnx.load(path)
                    model.ir_version = 7
                    onnx.save(model, path)

            state = ort_train_api.CheckpointState.load_checkpoint(str(checkpoint_path))
            session = ort_train_api.Module(str(training_model_path), state, str(eval_model_path), device="cpu")
            optimizer = ort_train_api.Optimizer(str(optimizer_model_path), session)
            _apply_learning_rate(optimizer, learning_rate)
            last_metrics: Dict[str, float] = {}
            last_export_epoch = -1

            for epoch in range(epochs):
                if killed or stop.closed:
                    break

                epoch_started = perf_counter()
                session.train()
                epoch_loss = 0.0
                batches_count = 0
                order = np.arange(len(dataset))
                np.random.shuffle(order)

                for start in range(0, len(dataset), batch_size):
                    if killed or stop.closed:
                        break

                    end = min(start + batch_size, len(dataset))
                    batch_indices = order[start:end]
                    bx, by = dataset.x[batch_indices], dataset.y[batch_indices]
                    session.lazy_reset_grad()
                    loss = session(bx, by)
                    optimizer.step()
                    epoch_loss += float(np.asarray(loss).reshape(-1)[0])
                    batches_count += 1

                if killed or stop.closed:
                    break

                avg_loss = epoch_loss / max(1, batches_count)
                should_export = (
                    epoch == 0
                    or ((epoch + 1) % EXPORT_EVAL_INTERVAL == 0)
                    or epoch == epochs - 1
                )
                metrics = last_metrics
                eval_seconds = 0.0
                if should_export:
                    eval_started = perf_counter()
                    inference_path = temp_dir / "inference.onnx"
                    session.export_model_for_inferencing(str(inference_path), model_output_names)
                    _restore_visual_output_softmax_for_inference(inference_path, graph, loss_name)
                    final_inference_path = artifact_dir / "inference.onnx"
                    final_inference_path.write_bytes(inference_path.read_bytes())
                    checkpoint_inference_path = checkpoint_dir / "inference.onnx"
                    if final_inference_path.resolve() != checkpoint_inference_path.resolve():
                        shutil.copy2(final_inference_path, checkpoint_inference_path)
                    max_eval = None if epoch == epochs - 1 else EVAL_MAX_SAMPLES
                    metrics = _evaluate(final_inference_path, dataset, loss_name, max_samples=max_eval)
                    last_metrics = metrics
                    last_export_epoch = epoch
                    eval_seconds = perf_counter() - eval_started
                epoch_seconds = perf_counter() - epoch_started
                emit({
                    "phase": "state",
                    "data": {
                        "epoch": epoch,
                        "left": epochs - epoch - 1,
                        "type": "loss",
                        "data": {
                            "train_loss": avg_loss,
                            "val_loss": metrics.get("val_loss", avg_loss),
                            "train_acc": metrics.get("train_acc", 0.0),
                            "val_acc": metrics.get("val_acc", 0.0),
                            "length": batches_count,
                            "batch_size": batch_size,
                            "evaluated": should_export,
                            "last_evaluated_epoch": last_export_epoch,
                            "epoch_seconds": epoch_seconds,
                            "eval_seconds": eval_seconds,
                        },
                    },
                })

        if killed or stop.closed:
            return {"status": "stopped"}

        if final_inference_path:
            checkpoint_inference_path = checkpoint_dir / "inference.onnx"
            if final_inference_path.resolve() != checkpoint_inference_path.resolve():
                shutil.copy2(final_inference_path, checkpoint_inference_path)
        try:
            ort_train_api.CheckpointState.save_checkpoint(state, str(checkpoint_dir / "checkpoint"), False)
        except Exception:
            traceback.print_exc()

        result = {
            "status": "ok",
            "backend": "fullylocal_ort",
            "artifact": str(checkpoint_dir / "inference.onnx") if final_inference_path else "",
            "checkpoint_dir": str(checkpoint_dir),
            "dataset": dataset.name,
        }
        manifest = {
            **result,
            "context": request.get("context", ""),
            "scene_id": request.get("scene_id", ""),
            "model_outputs": model_output_names,
            "loss": loss_name,
            "optimizer": optimizer_name,
            "actual_optimizer": actual_optimizer_name,
            "learning_rate": learning_rate,
            "export_eval_interval": EXPORT_EVAL_INTERVAL,
        }
        (checkpoint_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        (job_dir / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        emit({"phase": "done"})
        return result

    except Exception as exc:
        traceback.print_exc()
        emit({"phase": "error", "error": {"type": "TrainError", "message": str(exc)}})
        return {"status": "error", "error": str(exc)}


def _load_dataset(request: Dict[str, Any], runtime_root: str | Path) -> ArrayDataset:
    dataset_ref = request.get("dataset_ref") or {}
    kind = str(dataset_ref.get("kind", ""))
    if kind == "builtin_numpy":
        return load_builtin_dataset(runtime_root, str(dataset_ref.get("name", "")))
    if kind == "godot_json":
        return load_godot_json_dataset(
            dataset_ref.get("path", ""),
            name=str(dataset_ref.get("name", "")),
        )
    raise ValueError(f"Unsupported FullyLocal dataset ref kind '{kind}'")


def _coerce_targets_for_loss(dataset: ArrayDataset, loss_name: str) -> None:
    normalized = str(loss_name).lower()
    if normalized in {"mse", "mse_loss", "mean_squared_error"}:
        dataset.y = _as_regression_targets(dataset.y)
        if dataset.val_y is not None:
            dataset.val_y = _as_regression_targets(dataset.val_y)
        return
    if dataset.y.ndim > 1:
        dataset.y = np.argmax(dataset.y, axis=1).astype(np.int64)
    else:
        dataset.y = dataset.y.astype(np.int64)
    if dataset.val_y is not None:
        if dataset.val_y.ndim > 1:
            dataset.val_y = np.argmax(dataset.val_y, axis=1).astype(np.int64)
        else:
            dataset.val_y = dataset.val_y.astype(np.int64)


def _as_regression_targets(targets: np.ndarray) -> np.ndarray:
    arr = np.asarray(targets, dtype=np.float32)
    if arr.ndim == 1:
        return arr.reshape((-1, 1))
    return arr


def _extract_training_config(train_graph: Dict[str, Any]) -> Dict[str, Any]:
    config: Dict[str, Any] = {"optimizer": "adam", "lr": None, "loss": "cross_entropy"}
    for page in train_graph.get("pages", {}).values():
        for node in page.values():
            ntype = str(node.get("type", ""))
            props = node.get("props", {}) or {}
            node_config = props.get("config", {}) or {}
            if ntype == "RunModel":
                branch_losses = node_config.get("branch_losses", {}) or {}
                if branch_losses:
                    first_loss = next(iter(branch_losses.values()))
                    config["loss"] = str(first_loss)
            elif ntype == "TrainInput":
                config["optimizer"] = str(node_config.get("optimizer", config["optimizer"]))
                config["lr"] = node_config.get("lr", config["lr"])
                config["weight_decay"] = node_config.get("weight_decay", "")
                config["momentum"] = node_config.get("momentum", 0.0)
    return config


def _loss_type(name: str):
    _, ort_artifacts = _load_ort_training_api()
    normalized = str(name).lower()
    if normalized in {"cross_entropy", "crossentropyloss", "ce"}:
        return ort_artifacts.LossType.CrossEntropyLoss
    if normalized in {"mse", "mse_loss", "mean_squared_error"}:
        for attr in ("MSELoss", "MeanSquaredError"):
            if hasattr(ort_artifacts.LossType, attr):
                return getattr(ort_artifacts.LossType, attr)
        raise ValueError("This onnxruntime-training build does not expose MSELoss artifacts")
    raise ValueError(f"Unsupported FullyLocal loss '{name}'")


def _optimizer_type(name: str):
    _, ort_artifacts = _load_ort_training_api()
    normalized = str(name).lower()
    if normalized in {"adam", "adamw"}:
        return ort_artifacts.OptimType.AdamW
    if normalized in {"sgd", "stochastic_gradient_descent"}:
        for attr in ("SGD", "SGDOptimizer"):
            if hasattr(ort_artifacts.OptimType, attr):
                return getattr(ort_artifacts.OptimType, attr)
        raise ValueError("This onnxruntime-training build does not expose SGD artifacts")
    raise ValueError(f"Unsupported FullyLocal optimizer '{name}'")


def _resolve_optimizer_type(name: str):
    _, ort_artifacts = _load_ort_training_api()
    normalized = str(name).lower()
    if normalized in {"adam", "adamw"}:
        return ort_artifacts.OptimType.AdamW, "adamw", "", False
    if normalized in {"sgd", "stochastic_gradient_descent"}:
        for attr in ("SGD", "SGDOptimizer"):
            if hasattr(ort_artifacts.OptimType, attr):
                return getattr(ort_artifacts.OptimType, attr), "sgd", "", False
        return (
            ort_artifacts.OptimType.AdamW,
            "adamw",
            "This onnxruntime-training build does not expose SGD artifacts; using AdamW fallback.",
            True,
        )
    raise ValueError(f"Unsupported FullyLocal optimizer '{name}'")


def _graph_has_output_softmax(graph: Dict[str, Any]) -> bool:
    for page in graph.get("pages", {}).values():
        for node in page.values():
            ntype = str(node.get("type", ""))
            props = node.get("props", {}) or {}
            config = props.get("config", {}) or {}
            if ntype in {"SoftmaxNode", "softmax"} and str(config.get("role", "")).lower() == "output":
                return True
    return False


def _restore_visual_output_softmax_for_inference(inference_path: Path, graph: Dict[str, Any], loss_name: str) -> None:
    if not _is_cross_entropy_name(loss_name) or not _graph_has_output_softmax(graph):
        return
    model = onnx.load(inference_path)
    if len(model.graph.output) != 1:
        return
    old_output = model.graph.output[0]
    logits_name = old_output.name
    softmax_name = f"{logits_name}_visual_softmax"
    if any(node.output and node.output[0] == softmax_name for node in model.graph.node):
        return
    model.graph.node.append(
        onnx.helper.make_node(
            "Softmax",
            inputs=[logits_name],
            outputs=[softmax_name],
            axis=1,
            name="visual_output_softmax",
        )
    )
    old_output.name = softmax_name
    onnx.save(model, inference_path)


def _is_cross_entropy_name(name: str) -> bool:
    return str(name).lower() in {"cross_entropy", "crossentropyloss", "ce"}


def _parse_float(value: Any, default: Optional[float]) -> Optional[float]:
    if value in (None, ""):
        return default
    try:
        return float(value)
    except Exception:
        return default


def _apply_learning_rate(optimizer: Any, learning_rate: Optional[float]) -> None:
    if learning_rate is None:
        return
    for method_name in ("set_learning_rate", "set_lr"):
        method = getattr(optimizer, method_name, None)
        if callable(method):
            method(float(learning_rate))
            return


def _evaluate(inference_path: Path, dataset: ArrayDataset, loss_name: str, max_samples: Optional[int] = None) -> Dict[str, float]:
    providers = ["CPUExecutionProvider"]
    sess = ort.InferenceSession(str(inference_path), providers=providers)
    input_name = sess.get_inputs()[0].name
    vx, vy = dataset.validation_arrays()
    if max_samples is not None and max_samples > 0 and len(vx) > max_samples:
        sample_idx = np.linspace(0, len(vx) - 1, max_samples, dtype=np.int64)
        vx = vx[sample_idx]
        vy = vy[sample_idx]
    preds = sess.run(None, {input_name: vx})[0]

    if str(loss_name).lower() in {"mse", "mse_loss", "mean_squared_error"}:
        target = _as_regression_targets(vy)
        if target.shape != preds.shape and target.size == preds.size:
            target = target.reshape(preds.shape)
        val_loss = float(np.mean(np.square(preds - target)))
        return {"val_loss": val_loss, "train_acc": 0.0, "val_acc": max(0.0, 1.0 / (1.0 + val_loss))}

    labels = vy
    if labels.ndim > 1:
        labels = np.argmax(labels, axis=1)
    predicted_labels = np.argmax(preds, axis=1)
    accuracy = float(np.mean(predicted_labels == labels.astype(np.int64)))
    probs = _softmax_if_needed(preds)
    ce = -np.log(np.clip(probs[np.arange(len(labels)), labels.astype(np.int64)], 1e-9, 1.0))
    return {"val_loss": float(np.mean(ce)), "train_acc": accuracy, "val_acc": accuracy}


def _softmax_if_needed(preds: np.ndarray) -> np.ndarray:
    sums = np.sum(preds, axis=1)
    if np.all(preds >= 0.0) and np.allclose(sums, 1.0, atol=1e-3):
        return preds
    shifted = preds - np.max(preds, axis=1, keepdims=True)
    exp = np.exp(shifted)
    return exp / np.sum(exp, axis=1, keepdims=True)
