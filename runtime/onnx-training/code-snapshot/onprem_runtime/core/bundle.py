from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .config import TrainingConfig


class BundleValidationError(ValueError):
    pass


@dataclass(frozen=True)
class ExtractedBundle:
    root: Path
    config: TrainingConfig
    model_path: Path
    train_x: np.ndarray | None = None
    train_y: np.ndarray | None = None
    val_x: np.ndarray | None = None
    val_y: np.ndarray | None = None
    dataset_ref: dict[str, Any] | None = None


def extract_training_bundle(bundle_path: str | Path, workspace: str | Path) -> ExtractedBundle:
    bundle_path = Path(bundle_path)
    workspace = Path(workspace)
    workspace.mkdir(parents=True, exist_ok=True)

    if not zipfile.is_zipfile(bundle_path):
        raise BundleValidationError(f"Training bundle is not a zip file: {bundle_path}")

    try:
        with zipfile.ZipFile(bundle_path) as zf:
            names = set(zf.namelist())
            _require(names, "manifest.json")
            _require(names, "model.onnx")
            manifest = _read_manifest(zf)
            config = TrainingConfig.from_manifest(manifest)
            dataset_ref = _normalize_dataset_ref(manifest.get("dataset_ref"))
            has_train_npz = "data/train.npz" in names
            if not has_train_npz and dataset_ref is None:
                raise BundleValidationError("Training bundle must include data/train.npz or dataset_ref")
            _safe_extract(zf, workspace)
    except BundleValidationError:
        raise
    except Exception as exc:
        raise BundleValidationError(str(exc)) from exc

    train_x = None
    train_y = None
    val_x = None
    val_y = None
    if has_train_npz:
        train_x, train_y = _load_npz_xy(workspace / "data" / "train.npz")
        val_path = workspace / "data" / "val.npz"
        if val_path.exists():
            val_x, val_y = _load_npz_xy(val_path)

    return ExtractedBundle(
        root=workspace,
        config=config,
        model_path=workspace / "model.onnx",
        train_x=None if train_x is None else np.ascontiguousarray(train_x, dtype=np.float32),
        train_y=None if train_y is None else np.asarray(train_y),
        val_x=None if val_x is None else np.ascontiguousarray(val_x, dtype=np.float32),
        val_y=None if val_y is None else np.asarray(val_y),
        dataset_ref=dataset_ref,
    )


def _require(names: set[str], name: str) -> None:
    if name not in names:
        raise BundleValidationError(f"Training bundle is missing {name}")


def _read_manifest(zf: zipfile.ZipFile) -> dict[str, Any]:
    raw = zf.read("manifest.json").decode("utf-8-sig")
    manifest = json.loads(raw)
    if not isinstance(manifest, dict):
        raise BundleValidationError("manifest.json must contain a JSON object")
    return manifest


def _normalize_dataset_ref(value: Any) -> dict[str, Any] | None:
    if value in (None, ""):
        return None
    if not isinstance(value, dict):
        raise BundleValidationError("dataset_ref must be an object")

    ref_type = str(value.get("type") or "")
    if ref_type not in {"public", "local", "uploaded"}:
        raise BundleValidationError("dataset_ref.type must be public, local, or uploaded")
    if not value.get("id") and ref_type in {"public", "local"}:
        raise BundleValidationError("dataset_ref.id is required")
    if ref_type == "local" and not value.get("fingerprint"):
        raise BundleValidationError("dataset_ref.fingerprint is required for local datasets")
    return dict(value)


def _load_npz_xy(path: Path) -> tuple[np.ndarray, np.ndarray]:
    arrays = np.load(path, allow_pickle=False)
    if "x" not in arrays or "y" not in arrays:
        raise BundleValidationError(f"{path} must include x and y arrays")
    return arrays["x"], arrays["y"]


def _safe_extract(zf: zipfile.ZipFile, workspace: Path) -> None:
    root = workspace.resolve()
    for member in zf.infolist():
        target = (workspace / member.filename).resolve()
        if root != target and root not in target.parents:
            raise BundleValidationError(f"Unsafe zip path: {member.filename}")
    zf.extractall(workspace)
