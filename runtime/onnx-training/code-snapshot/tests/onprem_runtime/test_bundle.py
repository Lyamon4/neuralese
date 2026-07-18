import json
import zipfile
from pathlib import Path

import numpy as np
import pytest

from onprem_runtime.core.bundle import BundleValidationError, extract_training_bundle


def _write_bundle(path: Path, manifest: dict):
    train_npz = path.parent / "train.npz"
    np.savez(
        train_npz,
        x=np.zeros((4, 2), dtype=np.float32),
        y=np.array([0, 1, 0, 1], dtype=np.int64),
    )
    model_path = path.parent / "model.onnx"
    model_path.write_bytes(b"fake-model")
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        zf.write(model_path, "model.onnx")
        zf.write(train_npz, "data/train.npz")


def _write_bundle_without_dataset(path: Path, manifest: dict):
    model_path = path.parent / "model.onnx"
    model_path.write_bytes(b"fake-model")
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        zf.write(model_path, "model.onnx")


def test_extract_training_bundle_reads_manifest_and_dataset(tmp_path):
    bundle = tmp_path / "bundle.zip"
    _write_bundle(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "digits",
            "loss": "cross_entropy",
            "optimizer": "adamw",
            "learning_rate": 0.001,
            "epochs": 2,
            "batch_size": 2,
            "trainable_parameters": ["W", "B"],
            "output_names": ["logits"],
        },
    )

    extracted = extract_training_bundle(bundle, tmp_path / "job")

    assert extracted.config.model_name == "digits"
    assert extracted.config.epochs == 2
    assert extracted.config.batch_size == 2
    assert extracted.train_x.shape == (4, 2)
    assert extracted.train_y.tolist() == [0, 1, 0, 1]
    assert extracted.model_path.name == "model.onnx"
    assert extracted.dataset_ref is None


def test_extract_training_bundle_accepts_public_dataset_ref_without_npz(tmp_path):
    bundle = tmp_path / "bundle.zip"
    dataset_ref = {"type": "public", "id": "mnist", "version": "1"}
    _write_bundle_without_dataset(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "digits",
            "epochs": 2,
            "batch_size": 2,
            "trainable_parameters": ["W", "B"],
            "dataset_ref": dataset_ref,
        },
    )

    extracted = extract_training_bundle(bundle, tmp_path / "job")

    assert extracted.dataset_ref == dataset_ref
    assert extracted.train_x is None
    assert extracted.train_y is None


def test_extract_training_bundle_accepts_local_dataset_ref_without_npz(tmp_path):
    bundle = tmp_path / "bundle.zip"
    dataset_ref = {
        "type": "local",
        "id": "school-dataset-42",
        "fingerprint": "sha256:abc",
    }
    _write_bundle_without_dataset(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "local",
            "epochs": 1,
            "batch_size": 1,
            "trainable_parameters": ["W"],
            "dataset_ref": dataset_ref,
        },
    )

    extracted = extract_training_bundle(bundle, tmp_path / "job")

    assert extracted.dataset_ref == dataset_ref
    assert extracted.train_x is None
    assert extracted.train_y is None


def test_extract_training_bundle_rejects_missing_dataset_and_dataset_ref(tmp_path):
    bundle = tmp_path / "bundle.zip"
    _write_bundle_without_dataset(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "bad",
            "epochs": 1,
            "batch_size": 1,
            "trainable_parameters": ["W"],
        },
    )

    with pytest.raises(BundleValidationError, match="data/train.npz or dataset_ref"):
        extract_training_bundle(bundle, tmp_path / "job")


def test_extract_training_bundle_rejects_invalid_dataset_ref(tmp_path):
    bundle = tmp_path / "bundle.zip"
    _write_bundle_without_dataset(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "bad",
            "epochs": 1,
            "batch_size": 1,
            "trainable_parameters": ["W"],
            "dataset_ref": {"type": "public"},
        },
    )

    with pytest.raises(BundleValidationError, match="dataset_ref.id"):
        extract_training_bundle(bundle, tmp_path / "job")


def test_extract_training_bundle_rejects_missing_manifest(tmp_path):
    bundle = tmp_path / "bundle.zip"
    with zipfile.ZipFile(bundle, "w") as zf:
        zf.writestr("model.onnx", b"fake")

    with pytest.raises(BundleValidationError, match="manifest.json"):
        extract_training_bundle(bundle, tmp_path / "job")


def test_extract_training_bundle_rejects_empty_trainable_parameters(tmp_path):
    bundle = tmp_path / "bundle.zip"
    _write_bundle(
        bundle,
        {
            "bundle_version": 1,
            "model_name": "bad",
            "epochs": 1,
            "batch_size": 1,
            "trainable_parameters": [],
        },
    )

    with pytest.raises(BundleValidationError, match="trainable_parameters"):
        extract_training_bundle(bundle, tmp_path / "job")
