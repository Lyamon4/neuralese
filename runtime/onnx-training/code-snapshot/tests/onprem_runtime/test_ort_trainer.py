from __future__ import annotations

import asyncio
import json
import zipfile
from types import SimpleNamespace

import numpy as np
import onnx
import pytest
from onnx import TensorProto, helper, numpy_helper

from onprem_runtime.core.bundle import ExtractedBundle
from onprem_runtime.core.config import TrainingConfig
from onprem_runtime.core.ort_trainer import OrtBundleTrainer


def test_ort_bundle_trainer_trains_uploaded_classification_bundle_and_returns_snapshot(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=2)
        events = []

        async def emit(event):
            events.append(event)

        result = await OrtBundleTrainer(seed=123).train(job, emit, lambda: False)

        snapshot_path = tmp_path / "job" / "job_ort_snapshot.zip"
        assert result["status"] == "completed"
        assert result["backend"] == "onnxruntime_training"
        assert result["snapshot_path"] == str(snapshot_path)
        assert snapshot_path.is_file()
        assert [event.phase for event in events] == ["started", "epoch", "epoch"]
        assert events[-1].data["epoch"] == 2
        assert events[-1].data["epochs"] == 2
        assert events[-1].data["train_loss"] >= 0.0
        assert 0.0 <= events[-1].data["val_acc"] <= 1.0

        with zipfile.ZipFile(snapshot_path) as zf:
            assert {"manifest.json", "inference.onnx", "metrics.jsonl"}.issubset(zf.namelist())
            metrics = [
                json.loads(line)
                for line in zf.read("metrics.jsonl").decode("utf-8").splitlines()
            ]
            manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

        assert [item["epoch"] for item in metrics] == [1, 2]
        assert manifest["status"] == "completed"
        assert manifest["model_name"] == "tiny-linear"

    asyncio.run(run())


def test_ort_bundle_trainer_returns_stopped_without_completed_snapshot(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=3)
        events = []
        should_stop = False

        async def emit(event):
            nonlocal should_stop
            events.append(event)
            if event.phase == "epoch":
                should_stop = True

        result = await OrtBundleTrainer(seed=123).train(job, emit, lambda: should_stop)

        assert result["status"] == "stopped"
        assert [event.phase for event in events] == ["started", "epoch"]
        assert not (tmp_path / "job" / "job_ort_snapshot.zip").exists()

    asyncio.run(run())


def test_ort_bundle_trainer_rejects_missing_trainable_parameter_with_actionable_message(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=1, trainable_parameters=["missing_weight"])

        with pytest.raises(ValueError, match="trainable parameter 'missing_weight' was not found"):
            await OrtBundleTrainer(seed=123).train(job, _noop_emit, lambda: False)

    asyncio.run(run())


def test_ort_bundle_trainer_rejects_unknown_input_name_before_training(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=1, input_name="missing_input")

        with pytest.raises(ValueError, match="input_name 'missing_input' is not a model input"):
            await OrtBundleTrainer(seed=123).train(job, _noop_emit, lambda: False)

    asyncio.run(run())


def test_ort_bundle_trainer_rejects_unknown_output_name_before_training(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=1, output_names=["missing_logits"])

        with pytest.raises(ValueError, match="output_name 'missing_logits' is not a model output"):
            await OrtBundleTrainer(seed=123).train(job, _noop_emit, lambda: False)

    asyncio.run(run())


def test_ort_bundle_trainer_rejects_classification_labels_outside_output_range(tmp_path) -> None:
    async def run():
        job = _make_job(tmp_path, epochs=1, train_y=np.array([0, 1, 2, 1], dtype=np.int64))

        with pytest.raises(ValueError, match="classification label 2 is outside output class range 0..1"):
            await OrtBundleTrainer(seed=123).train(job, _noop_emit, lambda: False)

    asyncio.run(run())


async def _noop_emit(event):
    return None


def _make_job(
    tmp_path,
    *,
    epochs: int,
    trainable_parameters: list[str] | None = None,
    input_name: str = "input",
    output_names: list[str] | None = None,
    train_y: np.ndarray | None = None,
):
    workspace = tmp_path / "job"
    bundle_root = workspace / "bundle"
    bundle_root.mkdir(parents=True)
    model_path = bundle_root / "model.onnx"
    _write_linear_classifier(model_path)

    train_x = np.array(
        [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]],
        dtype=np.float32,
    )
    train_y = train_y if train_y is not None else np.array([0, 1, 1, 1], dtype=np.int64)
    config = TrainingConfig(
        model_name="tiny-linear",
        loss="cross_entropy",
        optimizer="adamw",
        learning_rate=0.01,
        epochs=epochs,
        batch_size=2,
        trainable_parameters=trainable_parameters or ["W", "b"],
        input_name=input_name,
        label_name="target",
        output_names=output_names or ["logits"],
    )
    bundle = ExtractedBundle(
        root=bundle_root,
        config=config,
        model_path=model_path,
        train_x=train_x,
        train_y=train_y,
    )
    return SimpleNamespace(job_id="job_ort", workspace=workspace, extracted_bundle=bundle)


def _write_linear_classifier(path) -> None:
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
