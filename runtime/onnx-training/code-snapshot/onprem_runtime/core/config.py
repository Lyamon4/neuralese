from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class TrainingConfig:
    model_name: str
    loss: str
    optimizer: str
    learning_rate: float | None
    epochs: int
    batch_size: int
    trainable_parameters: list[str]
    task: str = "classification"
    input_name: str | None = None
    label_name: str | None = None
    output_names: list[str] | None = None

    @classmethod
    def from_manifest(cls, manifest: dict[str, Any]) -> "TrainingConfig":
        epochs = int(manifest.get("epochs", 1))
        batch_size = int(manifest.get("batch_size", 128))
        if epochs < 1:
            raise ValueError("epochs must be >= 1")
        if batch_size < 1:
            raise ValueError("batch_size must be >= 1")

        trainable_parameters = [str(item) for item in manifest.get("trainable_parameters", [])]
        if not trainable_parameters:
            raise ValueError("trainable_parameters must contain at least one parameter name")

        learning_rate = manifest.get("learning_rate")
        output_names_raw = manifest.get("output_names")
        output_names = None
        if output_names_raw is not None:
            output_names = [str(item) for item in output_names_raw]

        return cls(
            model_name=str(manifest.get("model_name") or "onnx-model"),
            task=str(manifest.get("task") or "classification"),
            loss=str(manifest.get("loss") or "cross_entropy"),
            optimizer=str(manifest.get("optimizer") or "adamw"),
            learning_rate=None if learning_rate in (None, "") else float(learning_rate),
            epochs=epochs,
            batch_size=batch_size,
            trainable_parameters=trainable_parameters,
            input_name=_optional_string(manifest.get("input_name")),
            label_name=_optional_string(manifest.get("label_name")),
            output_names=output_names,
        )


def _optional_string(value: Any) -> str | None:
    if value in (None, ""):
        return None
    return str(value)
