from __future__ import annotations

import json
import zipfile
from pathlib import Path


class SnapshotValidationError(ValueError):
    pass


def create_snapshot_zip(
    *,
    job_dir: str | Path,
    job_id: str,
    manifest: dict,
    inference_model: str | Path,
    metrics_jsonl: str | Path,
    checkpoint_dir: str | Path | None,
) -> Path:
    job_dir = Path(job_dir)
    job_dir.mkdir(parents=True, exist_ok=True)
    inference_model = _required_file(inference_model, "trained model")
    metrics_jsonl = _required_file(metrics_jsonl, "metrics")
    snapshot_path = job_dir / f"{job_id}_snapshot.zip"
    manifest_path = job_dir / "snapshot_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    with zipfile.ZipFile(snapshot_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(manifest_path, "manifest.json")
        zf.write(inference_model, "inference.onnx")
        zf.write(metrics_jsonl, "metrics.jsonl")
        if checkpoint_dir is not None:
            checkpoint_root = Path(checkpoint_dir)
            if checkpoint_root.exists():
                for path in checkpoint_root.rglob("*"):
                    if path.is_file():
                        zf.write(path, "checkpoint/" + path.relative_to(checkpoint_root).as_posix())

    return snapshot_path


def _required_file(path: str | Path, label: str) -> Path:
    resolved = Path(path)
    if not resolved.is_file():
        raise SnapshotValidationError(f"required {label} file is missing: {resolved}")
    return resolved
