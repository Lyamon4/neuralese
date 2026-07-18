from __future__ import annotations

import json
import zipfile

from onprem_runtime.core.bundle import extract_training_bundle
from onprem_runtime.examples.make_dummy_bundle import create_dummy_bundle


def test_create_dummy_bundle_writes_valid_training_zip(tmp_path) -> None:
    bundle_path = create_dummy_bundle(tmp_path / "dummy_bundle.zip", epochs=2)

    assert bundle_path == tmp_path / "dummy_bundle.zip"
    assert bundle_path.is_file()
    with zipfile.ZipFile(bundle_path) as zf:
        assert {"manifest.json", "model.onnx", "data/train.npz"}.issubset(zf.namelist())
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    extracted = extract_training_bundle(bundle_path, tmp_path / "extracted")

    assert manifest["model_name"] == "tiny-linear"
    assert manifest["epochs"] == 2
    assert extracted.config.trainable_parameters == ["W", "b"]
    assert extracted.train_x.shape == (4, 2)
    assert extracted.train_y.shape == (4,)


def test_create_dummy_bundle_can_reference_public_dataset_without_embedding_npz(tmp_path) -> None:
    bundle_path = create_dummy_bundle(
        tmp_path / "public_ref_bundle.zip",
        epochs=1,
        dataset_ref={"type": "public", "id": "tiny_public"},
        include_dataset=False,
    )

    with zipfile.ZipFile(bundle_path) as zf:
        assert "data/train.npz" not in zf.namelist()
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    extracted = extract_training_bundle(bundle_path, tmp_path / "extracted_public")

    assert manifest["dataset_ref"] == {"type": "public", "id": "tiny_public"}
    assert extracted.dataset_ref == {"type": "public", "id": "tiny_public"}
    assert extracted.train_x is None
    assert extracted.train_y is None
