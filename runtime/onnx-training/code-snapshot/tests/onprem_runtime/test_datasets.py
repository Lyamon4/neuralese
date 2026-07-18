from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from onprem_runtime.core.bundle import ExtractedBundle
from onprem_runtime.core.config import TrainingConfig
from onprem_runtime.core.dataset_sync import DatasetSyncCache, build_dataset_frame
from onprem_runtime.core.datasets import (
    DatasetNotFoundError,
    DatasetResolver,
    IncrementalLocalDatasetProvider,
    NeuralesePublicDatasetProvider,
    NpzPublicDatasetEngine,
    UploadedDatasetProvider,
)


def _config() -> TrainingConfig:
    return TrainingConfig(
        model_name="demo",
        loss="cross_entropy",
        optimizer="adamw",
        learning_rate=0.001,
        epochs=1,
        batch_size=2,
        trainable_parameters=["W"],
    )


def _bundle() -> ExtractedBundle:
    return ExtractedBundle(
        root=Path("/tmp/job"),
        config=_config(),
        model_path=Path("/tmp/job/model.onnx"),
        train_x=np.array([[1, 2], [3, 4]], dtype=np.float32),
        train_y=np.array([0, 1], dtype=np.int64),
        val_x=np.array([[5, 6]], dtype=np.float32),
        val_y=np.array([1], dtype=np.int64),
    )


class _PublicEngine:
    def __init__(self) -> None:
        self.calls: list[tuple[str, bool]] = []
        self.train = {
            "mnist": (
                np.array([[0.0, 1.0], [1.0, 0.0]], dtype=np.float32),
                np.array([7, 3], dtype=np.int64),
            )
        }
        self.val = {
            "mnist": {
                "x": np.array([[0.5, 0.5]], dtype=np.float32),
                "y": np.array([9], dtype=np.int64),
            }
        }

    def has_dataset(self, dataset_id: str) -> bool:
        return dataset_id in self.train

    def has_test_dataset(self, dataset_id: str) -> bool:
        return dataset_id in self.val

    def read_dataset(self, dataset_id: str, test: bool = False):
        self.calls.append((dataset_id, test))
        return self.val[dataset_id] if test else self.train[dataset_id]


def test_uploaded_dataset_provider_returns_bundle_arrays() -> None:
    provider = UploadedDatasetProvider()

    dataset = provider.load(bundle=_bundle())

    assert dataset.source == "uploaded"
    assert dataset.dataset_id is None
    assert dataset.train_x.dtype == np.float32
    assert dataset.train_x.tolist() == [[1.0, 2.0], [3.0, 4.0]]
    assert dataset.train_y.tolist() == [0, 1]
    assert dataset.val_x.tolist() == [[5.0, 6.0]]
    assert dataset.val_y.tolist() == [1]


def test_uploaded_dataset_provider_requires_bundle() -> None:
    provider = UploadedDatasetProvider()

    with pytest.raises(DatasetNotFoundError, match="uploaded dataset requires bundle"):
        provider.load(bundle=None)


def test_public_dataset_provider_uses_backend_engine_adapter() -> None:
    engine = _PublicEngine()
    provider = NeuralesePublicDatasetProvider(engine)

    dataset = provider.load({"type": "public", "id": "mnist"})

    assert dataset.source == "public"
    assert dataset.dataset_id == "mnist"
    assert dataset.train_x.tolist() == [[0.0, 1.0], [1.0, 0.0]]
    assert dataset.train_y.tolist() == [7, 3]
    assert dataset.val_x.tolist() == [[0.5, 0.5]]
    assert dataset.val_y.tolist() == [9]
    assert engine.calls == [("mnist", False), ("mnist", True)]


def test_public_dataset_provider_raises_when_backend_does_not_have_dataset() -> None:
    provider = NeuralesePublicDatasetProvider(_PublicEngine())

    with pytest.raises(DatasetNotFoundError, match="public dataset not found"):
        provider.load({"type": "public", "id": "unknown"})


def test_npz_public_dataset_engine_reads_train_val_and_catalog(tmp_path) -> None:
    dataset_dir = tmp_path / "tiny_public"
    dataset_dir.mkdir()
    train_x = np.array([[0.0, 1.0], [1.0, 0.0]], dtype=np.float32)
    train_y = np.array([0, 1], dtype=np.int64)
    val_x = np.array([[1.0, 1.0]], dtype=np.float32)
    val_y = np.array([1], dtype=np.int64)
    np.savez(dataset_dir / "train.npz", x=train_x, y=train_y, val_x=val_x, val_y=val_y)
    (dataset_dir / "meta.json").write_text('{"name":"Tiny Public"}', encoding="utf-8")

    engine = NpzPublicDatasetEngine(tmp_path)

    assert engine.has_dataset("tiny_public") is True
    assert engine.has_test_dataset("tiny_public") is True
    assert engine.catalog() == {"tiny_public": {"id": "tiny_public", "name": "Tiny Public"}}
    assert engine.read_dataset("tiny_public", test=False)[0].tolist() == train_x.tolist()
    assert engine.read_dataset("tiny_public", test=True)[1].tolist() == val_y.tolist()


def test_local_dataset_provider_reads_synced_dataset_and_checks_fingerprint() -> None:
    cache = DatasetSyncCache()
    header = {"rows": 2, "inputs_count": 1, "outputs_count": 1, "columns": {}}
    payload = b"encoded-block"
    hashes = {"inputs": [[_sha(payload)]], "outputs": []}
    cache.prepare_sync("teacher", "local-1", header, hashes, hash_algo="sha256")
    synced = cache.apply_frames(
        "teacher",
        "local-1",
        [build_dataset_frame("inputs", 0, 0, payload)],
    )

    def decompress(packet: dict):
        assert packet == synced.packet
        return [([1.0, 2.0], [0]), ([3.0, 4.0], [1])]

    provider = IncrementalLocalDatasetProvider(cache, decompress_dataset=decompress)
    dataset = provider.load(
        {
            "type": "local",
            "id": "local-1",
            "fingerprint": synced.fingerprint,
        },
        user_id="teacher",
    )

    assert dataset.source == "local"
    assert dataset.dataset_id == "local-1"
    assert dataset.fingerprint == synced.fingerprint
    assert dataset.train_x.tolist() == [[1.0, 2.0], [3.0, 4.0]]
    assert dataset.train_y.tolist() == [0, 1]


def test_local_dataset_provider_rejects_fingerprint_mismatch() -> None:
    cache = DatasetSyncCache()
    payload = b"encoded-block"
    hashes = {"inputs": [[_sha(payload)]], "outputs": []}
    cache.prepare_sync("teacher", "local-1", {"rows": 1}, hashes, hash_algo="sha256")
    cache.apply_frames("teacher", "local-1", [build_dataset_frame("inputs", 0, 0, payload)])
    provider = IncrementalLocalDatasetProvider(cache, decompress_dataset=lambda packet: [])

    with pytest.raises(DatasetNotFoundError, match="fingerprint mismatch"):
        provider.load(
            {"type": "local", "id": "local-1", "fingerprint": "sha256:wrong"},
            user_id="teacher",
        )


def test_dataset_resolver_routes_by_dataset_ref_type() -> None:
    public_engine = _PublicEngine()
    cache = DatasetSyncCache()
    resolver = DatasetResolver(
        uploaded=UploadedDatasetProvider(),
        public=NeuralesePublicDatasetProvider(public_engine),
        local=IncrementalLocalDatasetProvider(cache, decompress_dataset=lambda packet: []),
    )

    uploaded = resolver.resolve(None, bundle=_bundle())
    public = resolver.resolve({"type": "public", "id": "mnist"})

    assert uploaded.source == "uploaded"
    assert public.source == "public"
    assert public.dataset_id == "mnist"


def _sha(payload: bytes) -> str:
    import hashlib

    return hashlib.sha256(payload).hexdigest()
