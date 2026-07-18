from __future__ import annotations

import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

from onprem_runtime.deployment import smoke_test


ROOT = Path(__file__).resolve().parents[2]


def test_local_launcher_command_uses_current_runtime_cli(tmp_path) -> None:
    config = smoke_test.SmokeConfig(
        launcher="local",
        host="127.0.0.1",
        port=8123,
        workspace=tmp_path,
        auth_token="school-secret",
    )

    command = smoke_test.local_server_command(config, python_executable="/python")

    assert command == [
        "/python",
        "-m",
        "onprem_runtime",
        "--mode",
        "local_school",
        "--host",
        "127.0.0.1",
        "--port",
        "8123",
        "--storage-dir",
        str(tmp_path / "jobs"),
        "--public-dataset-dir",
        str(tmp_path / "datasets"),
        "--auth-token",
        "school-secret",
    ]


def test_smoke_script_can_be_run_directly_as_a_file() -> None:
    script = ROOT / "onprem_runtime" / "deployment" / "smoke_test.py"

    result = subprocess.run(
        [sys.executable, str(script), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "--launcher" in result.stdout


def test_docker_launcher_uses_compose_file_and_port_env(tmp_path) -> None:
    config = smoke_test.SmokeConfig(
        launcher="docker",
        host="127.0.0.1",
        port=8124,
        workspace=tmp_path,
        max_parallel_jobs=3,
        auth_token="school-secret",
    )

    up = smoke_test.docker_compose_up_command(config)
    down = smoke_test.docker_compose_down_command(config)
    env = smoke_test.docker_compose_environment(config, base_env={"PATH": "/bin"})

    assert up[:4] == ["docker", "compose", "-f", str(config.compose_file)]
    assert up[-3:] == ["--build", "--remove-orphans", "runtime"]
    assert down == ["docker", "compose", "-f", str(config.compose_file), "down"]
    assert env["PATH"] == "/bin"
    assert env["NEURALESE_RUNTIME_MODE"] == "local_school"
    assert env["NEURALESE_PORT"] == "8124"
    assert env["NEURALESE_MAX_PARALLEL_JOBS"] == "3"
    assert env["NEURALESE_AUTH_TOKEN"] == "school-secret"


def test_multipart_bundle_request_contains_zip_payload(tmp_path) -> None:
    bundle = tmp_path / "bundle.zip"
    bundle.write_bytes(b"zip-bytes")

    request = smoke_test.build_bundle_upload_request(
        "http://127.0.0.1:8010",
        bundle,
        boundary="boundary-for-test",
        auth_token="school-secret",
    )
    body = request.data

    assert request.full_url == "http://127.0.0.1:8010/api/jobs"
    assert request.headers["Content-type"] == "multipart/form-data; boundary=boundary-for-test"
    assert request.headers["Authorization"] == "Bearer school-secret"
    assert b'name="bundle"; filename="bundle.zip"' in body
    assert b"Content-Type: application/zip" in body
    assert b"zip-bytes" in body


def test_verify_snapshot_requires_manifest_model_and_metrics(tmp_path) -> None:
    snapshot = tmp_path / "snapshot.zip"
    with zipfile.ZipFile(snapshot, "w") as zf:
        zf.writestr("manifest.json", json.dumps({"status": "completed"}))
        zf.writestr("inference.onnx", b"model")
        zf.writestr("metrics.jsonl", "{}\n")

    manifest = smoke_test.verify_snapshot(snapshot)

    assert manifest["status"] == "completed"


def test_verify_snapshot_rejects_missing_artifact(tmp_path) -> None:
    snapshot = tmp_path / "snapshot.zip"
    with zipfile.ZipFile(snapshot, "w") as zf:
        zf.writestr("manifest.json", json.dumps({"status": "completed"}))
        zf.writestr("metrics.jsonl", "{}\n")

    with pytest.raises(RuntimeError, match="missing inference.onnx"):
        smoke_test.verify_snapshot(snapshot)
