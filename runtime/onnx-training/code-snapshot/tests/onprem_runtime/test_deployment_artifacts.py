from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENT = ROOT / "onprem_runtime" / "deployment"


def test_dockerfile_packages_runtime_for_school_server() -> None:
    dockerfile = (DEPLOYMENT / "Dockerfile").read_text(encoding="utf-8")

    assert "FROM python:3.11-slim" in dockerfile
    assert "COPY onprem_runtime/requirements-runtime.txt" in dockerfile
    assert "pip install --no-cache-dir" in dockerfile
    assert "COPY onprem_runtime /app/onprem_runtime" in dockerfile
    assert "NEURALESE_STORAGE_DIR=/data/jobs" in dockerfile
    assert "NEURALESE_PUBLIC_DATASET_DIR=/data/datasets" in dockerfile
    assert "EXPOSE 8010" in dockerfile
    assert "onprem_runtime.api.server:app" in dockerfile
    assert '"0.0.0.0"' in dockerfile


def test_dockerignore_keeps_image_context_small() -> None:
    dockerignore = (ROOT / ".dockerignore").read_text(encoding="utf-8")

    assert ".git" in dockerignore
    assert ".venv-onprem" in dockerignore
    assert "__pycache__" in dockerignore
    assert "docs/superpowers" in dockerignore
    assert "game_assets" in dockerignore
    assert "*.zip" in dockerignore


def test_github_actions_runs_onprem_runtime_tests() -> None:
    workflow = ROOT / ".github" / "workflows" / "onprem-runtime-tests.yml"
    content = workflow.read_text(encoding="utf-8")

    assert "actions/checkout" in content
    assert "actions/setup-python" in content
    assert "python-version: '3.11'" in content
    assert "PYTHONPATH: code-snapshot" in content
    assert "pip install -r code-snapshot/onprem_runtime/requirements.txt" in content
    assert "python -m pytest code-snapshot/tests/onprem_runtime -v" in content


def test_deployment_runtime_state_is_ignored_but_mountpoint_is_kept() -> None:
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

    assert "onprem_runtime/deployment/data/jobs/*" in gitignore
    assert "!onprem_runtime/deployment/data/jobs/.gitkeep" in gitignore
    assert (DEPLOYMENT / "data" / "jobs" / ".gitkeep").exists()


def test_runtime_requirements_do_not_include_dev_only_packages() -> None:
    requirements = (ROOT / "onprem_runtime" / "requirements-runtime.txt").read_text(
        encoding="utf-8"
    )

    for package in (
        "fastapi",
        "uvicorn[standard]",
        "python-multipart",
        "numpy",
        "onnx",
        "onnxruntime-training-cpu",
        "psutil",
        "lmdb",
    ):
        assert package in requirements

    assert "pytest" not in requirements
    assert "httpx" not in requirements
    assert "torch" not in requirements


def test_docker_compose_local_school_mounts_jobs_and_public_datasets() -> None:
    compose = (DEPLOYMENT / "docker-compose.local.yml").read_text(encoding="utf-8")

    assert "dockerfile: onprem_runtime/deployment/Dockerfile" in compose
    assert "platform: linux/amd64" in compose
    assert "${NEURALESE_PORT:-8010}:8010" in compose
    assert "./data/jobs:/data/jobs" in compose
    assert "./data/datasets:/data/datasets:ro" in compose
    assert "NEURALESE_RUNTIME_MODE" in compose
    assert "NEURALESE_PORT" in compose
    assert "NEURALESE_MAX_PARALLEL_JOBS" in compose
    assert "NEURALESE_AUTH_TOKEN" in compose


def test_env_example_documents_local_school_defaults() -> None:
    env_example = (DEPLOYMENT / ".env.example").read_text(encoding="utf-8")

    assert "NEURALESE_RUNTIME_MODE=local_school" in env_example
    assert "NEURALESE_STORAGE_DIR=/data/jobs" in env_example
    assert "NEURALESE_PUBLIC_DATASET_DIR=/data/datasets" in env_example
    assert "NEURALESE_MAX_PARALLEL_JOBS=1" in env_example
    assert "NEURALESE_PORT=8010" in env_example
    assert "NEURALESE_AUTH_TOKEN=" in env_example


def test_deployment_readme_includes_local_and_cloud_launches() -> None:
    readme = (DEPLOYMENT / "README.md").read_text(encoding="utf-8")

    assert "docker compose -f docker-compose.local.yml up --build" in readme
    assert "python smoke_test.py --launcher local" in readme
    assert "python smoke_test.py --launcher docker" in readme
    assert "NEURALESE_RUNTIME_MODE=cloud_node" in readme
    assert "local_school" in readme
    assert "cloud_node" in readme
    assert "local-or/train.npz" in readme


def test_smoke_script_is_packaged_with_deployment_docs() -> None:
    smoke_script = (DEPLOYMENT / "smoke_test.py").read_text(encoding="utf-8")

    assert "--launcher" in smoke_script
    assert "docker compose" in smoke_script
    assert "create_dummy_bundle" in smoke_script
    assert "/api/jobs" in smoke_script
    assert "/ws/jobs" in smoke_script
    assert "/snapshot" in smoke_script


def test_public_dataset_example_layout_is_documented() -> None:
    dataset_readme = (DEPLOYMENT / "data" / "datasets" / "README.md").read_text(
        encoding="utf-8"
    )

    assert "dataset_id/train.npz" in dataset_readme
    assert "x" in dataset_readme
    assert "y" in dataset_readme
    assert "val_x" in dataset_readme
    assert "val_y" in dataset_readme


def test_systemd_deployment_docs_include_service_env_and_commands() -> None:
    systemd_dir = DEPLOYMENT / "systemd"
    service = (systemd_dir / "neuralese-onprem.service").read_text(encoding="utf-8")
    env = (systemd_dir / "neuralese-onprem.env.example").read_text(encoding="utf-8")
    readme = (systemd_dir / "README.md").read_text(encoding="utf-8")

    assert "ExecStart=" in service
    assert "python -m onprem_runtime" in service
    assert "EnvironmentFile=/etc/neuralese/onprem.env" in service
    assert "Restart=on-failure" in service
    assert "NEURALESE_AUTH_TOKEN=" in env
    assert "NEURALESE_STORAGE_DIR=/var/lib/neuralese-onprem/jobs" in env
    assert "systemctl enable --now neuralese-onprem" in readme
    assert "journalctl -u neuralese-onprem -f" in readme
