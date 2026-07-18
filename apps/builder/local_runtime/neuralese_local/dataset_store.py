from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import numpy as np


@dataclass
class ArrayDataset:
    name: str
    x: np.ndarray
    y: np.ndarray
    val_x: Optional[np.ndarray] = None
    val_y: Optional[np.ndarray] = None
    meta: Optional[Dict[str, Any]] = None

    def __post_init__(self) -> None:
        self.x = np.asarray(self.x, dtype=np.float32)
        self.y = _normalize_targets(self.y)
        if self.val_x is not None:
            self.val_x = np.asarray(self.val_x, dtype=np.float32)
        if self.val_y is not None:
            self.val_y = _normalize_targets(self.val_y)

    def __len__(self) -> int:
        return int(self.x.shape[0])

    def batch(self, start: int, end: int) -> tuple[np.ndarray, np.ndarray]:
        return self.x[start:end], self.y[start:end]

    def validation_arrays(self) -> tuple[np.ndarray, np.ndarray]:
        if self.val_x is not None and self.val_y is not None and len(self.val_x) > 0:
            return self.val_x, self.val_y
        return self.x, self.y


def _normalize_targets(y: Any) -> np.ndarray:
    arr = np.asarray(y)
    if arr.ndim > 1 and arr.shape[-1] == 1:
        arr = arr.reshape((-1,))
    if arr.dtype.kind == "f":
        return arr.astype(np.float32)
    if arr.dtype.kind in {"i", "u", "b"}:
        if arr.ndim == 1:
            return arr.astype(np.int64)
        return arr.astype(np.float32)
    return arr.astype(np.int64)


def _load_meta(base: Path) -> Dict[str, Any]:
    meta_path = base / "meta.json"
    if not meta_path.exists():
        return {}
    with meta_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_builtin_dataset(runtime_root: str | Path, name: str) -> ArrayDataset:
    base = Path(runtime_root) / "datasets" / name
    if not base.exists():
        raise FileNotFoundError(
            f"Builtin dataset '{name}' is not installed at {base}. "
            "Expected train.npz or train_x.npy/train_y.npy."
        )

    meta = _load_meta(base)

    train_npz = base / "train.npz"
    if train_npz.exists():
        data = np.load(train_npz, allow_pickle=False)
        x = data["x"] if "x" in data else data["train_x"]
        y = data["y"] if "y" in data else data["train_y"]
        val_x = data["val_x"] if "val_x" in data else (data["test_x"] if "test_x" in data else None)
        val_y = data["val_y"] if "val_y" in data else (data["test_y"] if "test_y" in data else None)
        return ArrayDataset(name=name, x=x, y=y, val_x=val_x, val_y=val_y, meta=meta)

    x_path = base / "train_x.npy"
    y_path = base / "train_y.npy"
    if not x_path.exists() or not y_path.exists():
        raise FileNotFoundError(
            f"Builtin dataset '{name}' is missing {x_path.name} or {y_path.name}."
        )

    val_x = np.load(base / "val_x.npy", allow_pickle=False) if (base / "val_x.npy").exists() else None
    val_y = np.load(base / "val_y.npy", allow_pickle=False) if (base / "val_y.npy").exists() else None
    test_x = np.load(base / "test_x.npy", allow_pickle=False) if (base / "test_x.npy").exists() else None
    test_y = np.load(base / "test_y.npy", allow_pickle=False) if (base / "test_y.npy").exists() else None

    return ArrayDataset(
        name=name,
        x=np.load(x_path, allow_pickle=False),
        y=np.load(y_path, allow_pickle=False),
        val_x=val_x if val_x is not None else test_x,
        val_y=val_y if val_y is not None else test_y,
        meta=meta,
    )


def load_godot_json_dataset(path: str | Path, name: str = "") -> ArrayDataset:
    dataset_path = Path(path)
    if not dataset_path.exists():
        raise FileNotFoundError(f"Local Godot dataset JSON does not exist: {dataset_path}")

    with dataset_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    x = data.get("x")
    y = data.get("y")
    if x is None or y is None:
        raise ValueError(f"Local Godot dataset JSON is missing x/y arrays: {dataset_path}")

    dataset_name = name or str(data.get("name") or dataset_path.stem)
    return ArrayDataset(
        name=dataset_name,
        x=np.asarray(x, dtype=np.float32),
        y=np.asarray(y),
        meta=data.get("meta") or {},
    )
