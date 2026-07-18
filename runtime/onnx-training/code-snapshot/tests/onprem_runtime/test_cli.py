from __future__ import annotations

import os
from pathlib import Path

from onprem_runtime.cli import main


def test_cli_configures_local_school_env_and_runs_uvicorn(monkeypatch, tmp_path) -> None:
    calls = []
    monkeypatch.delenv("NEURALESE_RUNTIME_MODE", raising=False)
    monkeypatch.delenv("NEURALESE_STORAGE_DIR", raising=False)
    monkeypatch.delenv("NEURALESE_PUBLIC_DATASET_DIR", raising=False)
    monkeypatch.delenv("NEURALESE_MAX_PARALLEL_JOBS", raising=False)
    monkeypatch.setenv("NEURALESE_AUTH_TOKEN", "stale-token")
    monkeypatch.delenv("NEURALESE_AUTH_TOKEN", raising=False)

    exit_code = main(
        [
            "--mode",
            "local_school",
            "--host",
            "0.0.0.0",
            "--port",
            "8011",
            "--storage-dir",
            str(tmp_path / "school"),
            "--public-dataset-dir",
            str(tmp_path / "datasets"),
            "--auth-token",
            "school-secret",
        ],
        run_server=lambda app_path, **kwargs: calls.append((app_path, kwargs)),
    )

    assert exit_code == 0
    assert os.environ["NEURALESE_RUNTIME_MODE"] == "local_school"
    assert os.environ["NEURALESE_STORAGE_DIR"] == str(tmp_path / "school")
    assert os.environ["NEURALESE_PUBLIC_DATASET_DIR"] == str(tmp_path / "datasets")
    assert os.environ["NEURALESE_MAX_PARALLEL_JOBS"] == "1"
    assert os.environ["NEURALESE_AUTH_TOKEN"] == "school-secret"
    assert calls == [
        (
            "onprem_runtime.api.server:app",
            {"host": "0.0.0.0", "port": 8011, "reload": False},
        )
    ]


def test_cli_configures_cloud_node_env(monkeypatch, tmp_path) -> None:
    calls = []
    monkeypatch.delenv("NEURALESE_RUNTIME_MODE", raising=False)
    monkeypatch.delenv("NEURALESE_STORAGE_DIR", raising=False)
    monkeypatch.delenv("NEURALESE_PUBLIC_DATASET_DIR", raising=False)
    monkeypatch.delenv("NEURALESE_MAX_PARALLEL_JOBS", raising=False)

    exit_code = main(
        [
            "--mode",
            "cloud_node",
            "--port",
            "9000",
            "--storage-dir",
            str(tmp_path / "cloud"),
            "--max-parallel-jobs",
            "4",
            "--reload",
        ],
        run_server=lambda app_path, **kwargs: calls.append((app_path, kwargs)),
    )

    assert exit_code == 0
    assert os.environ["NEURALESE_RUNTIME_MODE"] == "cloud_node"
    assert os.environ["NEURALESE_STORAGE_DIR"] == str(tmp_path / "cloud")
    assert Path(os.environ["NEURALESE_PUBLIC_DATASET_DIR"]) == Path(
        "local_runtime/datasets"
    )
    assert os.environ["NEURALESE_MAX_PARALLEL_JOBS"] == "4"
    assert "NEURALESE_AUTH_TOKEN" not in os.environ
    assert calls == [
        (
            "onprem_runtime.api.server:app",
            {"host": "127.0.0.1", "port": 9000, "reload": True},
        )
    ]
