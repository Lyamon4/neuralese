from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import numpy as np

from .bundle import ExtractedBundle
from .dataset_sync import DatasetSyncCache, DatasetSyncError


class DatasetNotFoundError(ValueError):
    pass


@dataclass(frozen=True)
class TrainingDataset:
    source: str
    train_x: np.ndarray
    train_y: np.ndarray
    val_x: np.ndarray | None = None
    val_y: np.ndarray | None = None
    dataset_id: str | None = None
    fingerprint: str | None = None


class UploadedDatasetProvider:
    def load(
        self,
        dataset_ref: dict[str, Any] | None = None,
        *,
        bundle: ExtractedBundle | None,
        user_id: str | None = None,
    ) -> TrainingDataset:
        if bundle is None:
            raise DatasetNotFoundError("uploaded dataset requires bundle")
        return TrainingDataset(
            source="uploaded",
            dataset_id=None,
            fingerprint=None,
            train_x=_as_train_x(bundle.train_x),
            train_y=np.asarray(bundle.train_y),
            val_x=None if bundle.val_x is None else _as_train_x(bundle.val_x),
            val_y=None if bundle.val_y is None else np.asarray(bundle.val_y),
        )


class NeuralesePublicDatasetProvider:
    def __init__(self, dataset_engine: Any) -> None:
        self._engine = dataset_engine

    def load(
        self,
        dataset_ref: dict[str, Any],
        *,
        bundle: ExtractedBundle | None = None,
        user_id: str | None = None,
    ) -> TrainingDataset:
        dataset_id = _required_ref_value(dataset_ref, "id")
        if not self._engine.has_dataset(dataset_id):
            raise DatasetNotFoundError(f"public dataset not found: {dataset_id}")

        train_x, train_y = _coerce_xy(self._engine.read_dataset(dataset_id, test=False))
        val_x = None
        val_y = None
        has_test = getattr(self._engine, "has_test_dataset", None)
        if callable(has_test) and has_test(dataset_id):
            val_x, val_y = _coerce_xy(self._engine.read_dataset(dataset_id, test=True))

        return TrainingDataset(
            source="public",
            dataset_id=dataset_id,
            fingerprint=_optional_ref_value(dataset_ref, "checksum"),
            train_x=_as_train_x(train_x),
            train_y=np.asarray(train_y),
            val_x=None if val_x is None else _as_train_x(val_x),
            val_y=None if val_y is None else np.asarray(val_y),
        )


class NpzPublicDatasetEngine:
    def __init__(self, root_dir: str | Path) -> None:
        self.root_dir = Path(root_dir)

    def has_dataset(self, dataset_id: str) -> bool:
        return self._dataset_path(dataset_id).is_file()

    def has_test_dataset(self, dataset_id: str) -> bool:
        path = self._dataset_path(dataset_id)
        if not path.is_file():
            return False
        arrays = np.load(path, allow_pickle=False)
        return "val_x" in arrays and "val_y" in arrays

    def read_dataset(self, dataset_id: str, test: bool = False) -> tuple[np.ndarray, np.ndarray]:
        path = self._dataset_path(dataset_id)
        if not path.is_file():
            raise DatasetNotFoundError(f"public dataset not found: {dataset_id}")
        arrays = np.load(path, allow_pickle=False)
        if test:
            if "val_x" not in arrays or "val_y" not in arrays:
                raise DatasetNotFoundError(f"public validation dataset not found: {dataset_id}")
            return np.asarray(arrays["val_x"]), np.asarray(arrays["val_y"])
        if "x" not in arrays or "y" not in arrays:
            raise DatasetNotFoundError(f"public dataset {dataset_id} must contain x and y")
        return np.asarray(arrays["x"]), np.asarray(arrays["y"])

    def catalog(self) -> dict[str, dict[str, Any]]:
        if not self.root_dir.exists():
            return {}
        catalog: dict[str, dict[str, Any]] = {}
        for dataset_dir in sorted(item for item in self.root_dir.iterdir() if item.is_dir()):
            if not (dataset_dir / "train.npz").is_file():
                continue
            dataset_id = dataset_dir.name
            catalog[dataset_id] = {"id": dataset_id, "name": self._dataset_name(dataset_dir)}
        return catalog

    def _dataset_path(self, dataset_id: str) -> Path:
        safe_id = Path(str(dataset_id)).name
        return self.root_dir / safe_id / "train.npz"

    def _dataset_name(self, dataset_dir: Path) -> str:
        meta_path = dataset_dir / "meta.json"
        if meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                if isinstance(meta, dict) and meta.get("name"):
                    return str(meta["name"])
            except Exception:
                pass
        return dataset_dir.name


class IncrementalLocalDatasetProvider:
    def __init__(
        self,
        sync_cache: DatasetSyncCache,
        *,
        decompress_dataset: Callable[[dict[str, Any]], Any],
    ) -> None:
        self._sync_cache = sync_cache
        self._decompress_dataset = decompress_dataset

    def load(
        self,
        dataset_ref: dict[str, Any],
        *,
        bundle: ExtractedBundle | None = None,
        user_id: str | None = None,
    ) -> TrainingDataset:
        dataset_id = _required_ref_value(dataset_ref, "id")
        user = str(user_id or "local")
        try:
            synced = self._sync_cache.get_synced_dataset(user, dataset_id)
        except DatasetSyncError as exc:
            raise DatasetNotFoundError(f"local dataset not found: {dataset_id}") from exc

        expected_fingerprint = _optional_ref_value(dataset_ref, "fingerprint")
        if expected_fingerprint and expected_fingerprint != synced.fingerprint:
            raise DatasetNotFoundError(
                f"fingerprint mismatch for local dataset {dataset_id}: "
                f"{synced.fingerprint} != {expected_fingerprint}"
            )

        rows = self._decompress_dataset(synced.packet)
        train_x, train_y = _rows_to_xy(rows)
        return TrainingDataset(
            source="local",
            dataset_id=dataset_id,
            fingerprint=synced.fingerprint,
            train_x=_as_train_x(train_x),
            train_y=train_y,
        )


class DatasetResolver:
    def __init__(
        self,
        *,
        uploaded: UploadedDatasetProvider,
        public: NeuralesePublicDatasetProvider,
        local: IncrementalLocalDatasetProvider,
    ) -> None:
        self._uploaded = uploaded
        self._public = public
        self._local = local

    def resolve(
        self,
        dataset_ref: dict[str, Any] | None,
        *,
        bundle: ExtractedBundle | None = None,
        user_id: str | None = None,
    ) -> TrainingDataset:
        if dataset_ref is None:
            return self._uploaded.load(None, bundle=bundle, user_id=user_id)

        ref_type = str(dataset_ref.get("type") or "uploaded")
        if ref_type == "uploaded":
            return self._uploaded.load(dataset_ref, bundle=bundle, user_id=user_id)
        if ref_type == "public":
            return self._public.load(dataset_ref, bundle=bundle, user_id=user_id)
        if ref_type == "local":
            return self._local.load(dataset_ref, bundle=bundle, user_id=user_id)
        raise DatasetNotFoundError(f"unsupported dataset_ref type: {ref_type}")


def _required_ref_value(dataset_ref: dict[str, Any], key: str) -> str:
    value = dataset_ref.get(key)
    if value in (None, ""):
        raise DatasetNotFoundError(f"dataset_ref.{key} is required")
    return str(value)


def _optional_ref_value(dataset_ref: dict[str, Any], key: str) -> str | None:
    value = dataset_ref.get(key)
    if value in (None, ""):
        return None
    return str(value)


def _coerce_xy(raw_dataset: Any) -> tuple[np.ndarray, np.ndarray]:
    if isinstance(raw_dataset, dict) and "x" in raw_dataset and "y" in raw_dataset:
        return np.asarray(raw_dataset["x"]), np.asarray(raw_dataset["y"])

    if isinstance(raw_dataset, tuple) and len(raw_dataset) == 2:
        return np.asarray(raw_dataset[0]), np.asarray(raw_dataset[1])

    if hasattr(raw_dataset, "x") and hasattr(raw_dataset, "y"):
        return np.asarray(raw_dataset.x), np.asarray(raw_dataset.y)

    rows = list(raw_dataset)
    return _rows_to_xy(rows)


def _rows_to_xy(rows: Any) -> tuple[np.ndarray, np.ndarray]:
    materialized = list(rows)
    if not materialized:
        raise DatasetNotFoundError("dataset contains no rows")
    train_x = np.asarray([row[0] for row in materialized], dtype=np.float32)
    train_y = _normalize_y([row[1] for row in materialized])
    return train_x, train_y


def _normalize_y(values: list[Any]) -> np.ndarray:
    raw = np.asarray(values)
    if raw.ndim == 2 and raw.shape[1] == 1:
        raw = raw.reshape(-1)
    return raw


def _as_train_x(values: Any) -> np.ndarray:
    return np.ascontiguousarray(values, dtype=np.float32)
