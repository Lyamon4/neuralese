from __future__ import annotations

import json
import shutil
import sys
import types
from pathlib import Path
from time import perf_counter
from typing import Any

import numpy as np
import onnx
import onnxruntime as ort

from .bundle import ExtractedBundle
from .datasets import DatasetResolver, TrainingDataset, UploadedDatasetProvider
from .events import TrainingEvent
from .snapshot import create_snapshot_zip


class OrtBundleTrainer:
    def __init__(
        self,
        *,
        dataset_resolver: DatasetResolver | None = None,
        device: str = "cpu",
        seed: int | None = None,
    ) -> None:
        self._dataset_resolver = dataset_resolver
        self._device = device
        self._rng = np.random.default_rng(seed)

    async def train(self, job: Any, emit: Any, stop_requested: Any) -> dict[str, Any]:
        bundle = _require_bundle(job.extracted_bundle)
        config = bundle.config
        dataset = self._load_dataset(bundle)
        train_x, train_y, val_x, val_y = _prepare_arrays(dataset, config.loss)
        if len(train_x) == 0:
            raise ValueError("training dataset is empty")

        await emit(
            TrainingEvent(
                job.job_id,
                "started",
                {
                    "backend": "onnxruntime_training",
                    "model_name": config.model_name,
                    "epochs": config.epochs,
                    "batch_size": config.batch_size,
                    "dataset_source": dataset.source,
                },
            )
        )

        if stop_requested():
            return {"status": "stopped"}

        artifact_dir = Path(job.workspace) / "ort_artifacts"
        checkpoint_dir = Path(job.workspace) / "checkpoint"
        output_dir = Path(job.workspace) / "outputs"
        metrics_path = Path(job.workspace) / "metrics.jsonl"
        _reset_dir(artifact_dir)
        _reset_dir(checkpoint_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        metrics_path.write_text("", encoding="utf-8")

        api_mod, artifacts_mod = _load_ort_training_api()
        model = onnx.load(bundle.model_path)
        output_names = config.output_names or [item.name for item in model.graph.output]
        _validate_trainable_parameters(model, config.trainable_parameters)
        _validate_model_io(model, input_name=config.input_name, output_names=output_names)
        _validate_classification_labels(model, output_names=output_names, train_y=train_y, val_y=val_y, loss_name=config.loss)

        artifacts_mod.generate_artifacts(
            model,
            requires_grad=config.trainable_parameters,
            loss=_loss_type(artifacts_mod, config.loss),
            optimizer=_optimizer_type(artifacts_mod, config.optimizer),
            artifact_directory=str(artifact_dir),
        )

        state = api_mod.CheckpointState.load_checkpoint(str(artifact_dir / "checkpoint"))
        session = api_mod.Module(
            str(artifact_dir / "training_model.onnx"),
            state,
            str(artifact_dir / "eval_model.onnx"),
            device=self._device,
        )
        optimizer = api_mod.Optimizer(str(artifact_dir / "optimizer_model.onnx"), session)
        _apply_learning_rate(optimizer, config.learning_rate)

        inference_path = output_dir / "inference.onnx"
        last_record: dict[str, Any] | None = None
        for epoch_index in range(config.epochs):
            if stop_requested():
                return {"status": "stopped"}

            started_at = perf_counter()
            session.train()
            loss_total = 0.0
            batches = 0
            order = self._rng.permutation(len(train_x))
            for start in range(0, len(order), config.batch_size):
                if stop_requested():
                    return {"status": "stopped"}
                batch_idx = order[start : start + config.batch_size]
                session.lazy_reset_grad()
                loss = session(train_x[batch_idx], train_y[batch_idx])
                optimizer.step()
                loss_total += float(np.asarray(loss).reshape(-1)[0])
                batches += 1

            train_loss = loss_total / max(1, batches)
            session.export_model_for_inferencing(str(inference_path), output_names)
            eval_metrics = _evaluate(
                inference_path,
                input_name=config.input_name,
                output_names=output_names,
                x=val_x,
                y=val_y,
                loss_name=config.loss,
            )
            last_record = {
                "epoch": epoch_index + 1,
                "epochs": config.epochs,
                "train_loss": train_loss,
                "val_loss": eval_metrics["val_loss"],
                "train_acc": eval_metrics["val_acc"],
                "val_acc": eval_metrics["val_acc"],
                "batches": batches,
                "batch_size": config.batch_size,
                "epoch_seconds": perf_counter() - started_at,
            }
            _append_jsonl(metrics_path, last_record)
            await emit(TrainingEvent(job.job_id, "epoch", last_record))

        checkpoint_saved = _save_checkpoint(api_mod, state, checkpoint_dir)
        manifest = {
            "status": "completed",
            "backend": "onnxruntime_training",
            "job_id": job.job_id,
            "model_name": config.model_name,
            "epochs": config.epochs,
            "batch_size": config.batch_size,
            "loss": config.loss,
            "optimizer": config.optimizer,
            "learning_rate": config.learning_rate,
            "dataset_source": dataset.source,
            "dataset_id": dataset.dataset_id,
            "dataset_fingerprint": dataset.fingerprint,
            "checkpoint_saved": checkpoint_saved,
            "final_metrics": last_record or {},
        }
        snapshot_path = create_snapshot_zip(
            job_dir=job.workspace,
            job_id=job.job_id,
            manifest=manifest,
            inference_model=inference_path,
            metrics_jsonl=metrics_path,
            checkpoint_dir=checkpoint_dir,
        )
        return {
            "status": "completed",
            "backend": "onnxruntime_training",
            "snapshot_path": str(snapshot_path),
            "inference_model": str(inference_path),
            "metrics_path": str(metrics_path),
            "checkpoint_dir": str(checkpoint_dir),
            "final_metrics": last_record or {},
        }

    def _load_dataset(self, bundle: ExtractedBundle) -> TrainingDataset:
        if self._dataset_resolver is not None:
            return self._dataset_resolver.resolve(bundle.dataset_ref, bundle=bundle, user_id="local")
        if bundle.dataset_ref is not None and str(bundle.dataset_ref.get("type")) != "uploaded":
            raise ValueError("dataset_resolver is required for public or local dataset_ref")
        return UploadedDatasetProvider().load(bundle.dataset_ref, bundle=bundle, user_id="local")


def _require_bundle(value: Any) -> ExtractedBundle:
    if not isinstance(value, ExtractedBundle):
        raise ValueError("OrtBundleTrainer requires job.extracted_bundle")
    return value


def _load_ort_training_api() -> tuple[Any, Any]:
    training_dir = Path(ort.__file__).resolve().parent / "training"
    if "onnxruntime.training" not in sys.modules:
        pkg = types.ModuleType("onnxruntime.training")
        pkg.__path__ = [str(training_dir)]
        sys.modules["onnxruntime.training"] = pkg

    from importlib import import_module

    return import_module("onnxruntime.training.api"), import_module("onnxruntime.training.artifacts")


def _prepare_arrays(
    dataset: TrainingDataset,
    loss_name: str,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    train_x = np.ascontiguousarray(dataset.train_x, dtype=np.float32)
    train_y = _prepare_targets(dataset.train_y, loss_name)
    val_x = train_x if dataset.val_x is None else np.ascontiguousarray(dataset.val_x, dtype=np.float32)
    val_y = train_y if dataset.val_y is None else _prepare_targets(dataset.val_y, loss_name)
    if len(train_x) != len(train_y):
        raise ValueError(f"training x/y length mismatch: {len(train_x)} != {len(train_y)}")
    if len(val_x) != len(val_y):
        raise ValueError(f"validation x/y length mismatch: {len(val_x)} != {len(val_y)}")
    return train_x, train_y, val_x, val_y


def _prepare_targets(targets: Any, loss_name: str) -> np.ndarray:
    values = np.asarray(targets)
    if _is_mse(loss_name):
        arr = np.asarray(values, dtype=np.float32)
        if arr.ndim == 1:
            arr = arr.reshape((-1, 1))
        return np.ascontiguousarray(arr)
    if values.ndim > 1:
        values = np.argmax(values, axis=1)
    return np.ascontiguousarray(values.astype(np.int64))


def _loss_type(artifacts_mod: Any, name: str) -> Any:
    normalized = str(name).lower()
    if normalized in {"cross_entropy", "crossentropyloss", "ce"}:
        return artifacts_mod.LossType.CrossEntropyLoss
    if _is_mse(normalized):
        for attr in ("MSELoss", "MeanSquaredError"):
            if hasattr(artifacts_mod.LossType, attr):
                return getattr(artifacts_mod.LossType, attr)
    raise ValueError(f"unsupported loss: {name}")


def _optimizer_type(artifacts_mod: Any, name: str) -> Any:
    normalized = str(name).lower()
    if normalized in {"adam", "adamw"}:
        return artifacts_mod.OptimType.AdamW
    if normalized in {"sgd", "stochastic_gradient_descent"}:
        for attr in ("SGD", "SGDOptimizer"):
            if hasattr(artifacts_mod.OptimType, attr):
                return getattr(artifacts_mod.OptimType, attr)
    raise ValueError(f"unsupported optimizer: {name}")


def _validate_trainable_parameters(model: Any, trainable_parameters: list[str]) -> None:
    initializers = {item.name for item in model.graph.initializer}
    missing = [name for name in trainable_parameters if name not in initializers]
    if missing:
        available = _format_available(sorted(initializers))
        if len(missing) == 1:
            raise ValueError(
                f"trainable parameter '{missing[0]}' was not found in model initializers; "
                f"available initializers: {available}"
            )
        raise ValueError(
            f"trainable parameters {missing} were not found in model initializers; "
            f"available initializers: {available}"
        )


def _validate_model_io(model: Any, *, input_name: str | None, output_names: list[str]) -> None:
    model_inputs = [item.name for item in model.graph.input]
    model_outputs = [item.name for item in model.graph.output]
    if input_name and input_name not in model_inputs:
        raise ValueError(
            f"input_name '{input_name}' is not a model input; "
            f"available inputs: {_format_available(model_inputs)}"
        )
    for output_name in output_names:
        if output_name not in model_outputs:
            raise ValueError(
                f"output_name '{output_name}' is not a model output; "
                f"available outputs: {_format_available(model_outputs)}"
            )


def _validate_classification_labels(
    model: Any,
    *,
    output_names: list[str],
    train_y: np.ndarray,
    val_y: np.ndarray,
    loss_name: str,
) -> None:
    if _is_mse(loss_name):
        return
    class_count = _class_count_for_output(model, output_names[0] if output_names else "")
    if class_count is None:
        return
    labels = np.concatenate([np.asarray(train_y).reshape(-1), np.asarray(val_y).reshape(-1)])
    if labels.size == 0:
        return
    min_label = int(np.min(labels))
    max_label = int(np.max(labels))
    if min_label < 0:
        raise ValueError(
            f"classification label {min_label} is outside output class range 0..{class_count - 1}"
        )
    if max_label >= class_count:
        raise ValueError(
            f"classification label {max_label} is outside output class range 0..{class_count - 1}"
        )


def _class_count_for_output(model: Any, output_name: str) -> int | None:
    for output in model.graph.output:
        if output.name != output_name:
            continue
        dims = output.type.tensor_type.shape.dim
        if len(dims) < 2:
            return None
        value = int(dims[-1].dim_value)
        return value if value > 0 else None
    return None


def _format_available(values: list[str]) -> str:
    return ", ".join(values) if values else "<none>"


def _apply_learning_rate(optimizer: Any, learning_rate: float | None) -> None:
    if learning_rate is None:
        return
    for method_name in ("set_learning_rate", "set_lr"):
        method = getattr(optimizer, method_name, None)
        if callable(method):
            method(float(learning_rate))
            return


def _evaluate(
    inference_path: Path,
    *,
    input_name: str | None,
    output_names: list[str],
    x: np.ndarray,
    y: np.ndarray,
    loss_name: str,
) -> dict[str, float]:
    session = ort.InferenceSession(str(inference_path), providers=["CPUExecutionProvider"])
    actual_input_name = input_name or session.get_inputs()[0].name
    outputs = session.run(output_names or None, {actual_input_name: x})
    preds = np.asarray(outputs[0])
    if _is_mse(loss_name):
        target = np.asarray(y, dtype=np.float32)
        if target.shape != preds.shape and target.size == preds.size:
            target = target.reshape(preds.shape)
        loss = float(np.mean(np.square(preds - target)))
        return {"val_loss": loss, "val_acc": max(0.0, 1.0 / (1.0 + loss))}

    labels = y
    if labels.ndim > 1:
        labels = np.argmax(labels, axis=1)
    labels = labels.astype(np.int64)
    predicted = np.argmax(preds, axis=1)
    accuracy = float(np.mean(predicted == labels))
    probs = _softmax_if_needed(preds)
    ce = -np.log(np.clip(probs[np.arange(len(labels)), labels], 1e-9, 1.0))
    return {"val_loss": float(np.mean(ce)), "val_acc": accuracy}


def _softmax_if_needed(preds: np.ndarray) -> np.ndarray:
    sums = np.sum(preds, axis=1)
    if np.all(preds >= 0.0) and np.allclose(sums, 1.0, atol=1e-3):
        return preds
    shifted = preds - np.max(preds, axis=1, keepdims=True)
    exp = np.exp(shifted)
    return exp / np.sum(exp, axis=1, keepdims=True)


def _append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")


def _save_checkpoint(api_mod: Any, state: Any, checkpoint_dir: Path) -> bool:
    try:
        api_mod.CheckpointState.save_checkpoint(state, str(checkpoint_dir / "checkpoint"), False)
        return True
    except Exception:
        return False


def _reset_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _is_mse(name: str) -> bool:
    return str(name).lower() in {"mse", "mse_loss", "mean_squared_error"}
