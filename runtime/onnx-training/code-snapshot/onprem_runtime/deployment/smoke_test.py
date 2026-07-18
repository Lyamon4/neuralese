from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterator, Sequence
from urllib import parse, request

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from onprem_runtime.examples.make_dummy_bundle import create_dummy_bundle


TERMINAL_PHASES = {"completed", "failed", "stopped"}


def _default_compose_file() -> Path:
    return Path(__file__).resolve().parent / "docker-compose.local.yml"


def _repo_root() -> Path:
    return REPO_ROOT


@dataclass
class SmokeConfig:
    launcher: str = "local"
    host: str = "127.0.0.1"
    port: int = 8010
    workspace: Path = field(default_factory=lambda: Path(".neuralese_smoke"))
    runtime_mode: str = "local_school"
    max_parallel_jobs: int = 1
    timeout_seconds: float = 120.0
    epochs: int = 2
    compose_file: Path = field(default_factory=_default_compose_file)
    keep_runtime: bool = False
    auth_token: str | None = None

    def __post_init__(self) -> None:
        self.workspace = Path(self.workspace)
        self.compose_file = Path(self.compose_file)

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    @property
    def ws_url(self) -> str:
        return f"ws://{self.host}:{self.port}"


def local_server_command(
    config: SmokeConfig,
    *,
    python_executable: str | None = None,
) -> list[str]:
    command = [
        python_executable or sys.executable,
        "-m",
        "onprem_runtime",
        "--mode",
        config.runtime_mode,
        "--host",
        config.host,
        "--port",
        str(config.port),
        "--storage-dir",
        str(config.workspace / "jobs"),
        "--public-dataset-dir",
        str(config.workspace / "datasets"),
    ]
    if config.auth_token:
        command.extend(["--auth-token", config.auth_token])
    return command


def docker_compose_up_command(config: SmokeConfig) -> list[str]:
    return [
        "docker",
        "compose",
        "-f",
        str(config.compose_file),
        "up",
        "--build",
        "--remove-orphans",
        "runtime",
    ]


def docker_compose_down_command(config: SmokeConfig) -> list[str]:
    return ["docker", "compose", "-f", str(config.compose_file), "down"]


def docker_compose_environment(
    config: SmokeConfig,
    *,
    base_env: dict[str, str] | None = None,
) -> dict[str, str]:
    env = dict(base_env or os.environ)
    env.update(
        {
            "NEURALESE_RUNTIME_MODE": config.runtime_mode,
            "NEURALESE_PORT": str(config.port),
            "NEURALESE_STORAGE_DIR": "/data/jobs",
            "NEURALESE_PUBLIC_DATASET_DIR": "/data/datasets",
            "NEURALESE_MAX_PARALLEL_JOBS": str(max(1, int(config.max_parallel_jobs))),
            "NEURALESE_AUTH_TOKEN": config.auth_token or "",
        }
    )
    return env


def build_bundle_upload_request(
    base_url: str,
    bundle_path: str | Path,
    *,
    boundary: str | None = None,
    auth_token: str | None = None,
) -> request.Request:
    bundle_path = Path(bundle_path)
    boundary = boundary or f"neuralese-smoke-{uuid.uuid4().hex}"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode("utf-8"),
            (
                'Content-Disposition: form-data; name="bundle"; '
                f'filename="{bundle_path.name}"\r\n'
            ).encode("utf-8"),
            b"Content-Type: application/zip\r\n\r\n",
            bundle_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode("utf-8"),
        ]
    )
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    return request.Request(
        f"{base_url.rstrip('/')}/api/jobs",
        data=body,
        headers=headers,
        method="POST",
    )


def wait_for_health(base_url: str, timeout_seconds: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with request.urlopen(f"{base_url.rstrip('/')}/api/health", timeout=2.0) as response:
                payload = json.loads(response.read().decode("utf-8"))
            if payload.get("status") == "ok":
                return payload
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    detail = f": {last_error}" if last_error is not None else ""
    raise RuntimeError(f"runtime did not become healthy within {timeout_seconds:.0f}s{detail}")


def upload_bundle(
    base_url: str,
    bundle_path: str | Path,
    timeout_seconds: float,
    *,
    auth_token: str | None = None,
) -> str:
    req = build_bundle_upload_request(base_url, bundle_path, auth_token=auth_token)
    with request.urlopen(req, timeout=timeout_seconds) as response:
        payload = json.loads(response.read().decode("utf-8"))
    job_id = payload.get("job_id")
    if not job_id:
        raise RuntimeError(f"runtime did not return job_id: {payload}")
    return str(job_id)


def wait_for_terminal_event(
    ws_url: str,
    job_id: str,
    timeout_seconds: float,
    *,
    auth_token: str | None = None,
) -> dict[str, Any]:
    from websockets.sync.client import connect

    deadline = time.monotonic() + timeout_seconds
    with connect(
        _with_token_query(f"{ws_url.rstrip('/')}/ws/jobs/{job_id}", auth_token),
        open_timeout=min(10.0, timeout_seconds),
        close_timeout=2.0,
    ) as websocket:
        while time.monotonic() < deadline:
            remaining = max(0.1, deadline - time.monotonic())
            event = json.loads(websocket.recv(timeout=remaining))
            phase = str(event.get("phase") or "")
            print(f"[smoke] event: {phase}")
            if phase in TERMINAL_PHASES:
                if phase != "completed":
                    error = event.get("data", {}).get("error", event)
                    raise RuntimeError(f"job ended with {phase}: {error}")
                return event
    raise RuntimeError(f"job {job_id} did not finish within {timeout_seconds:.0f}s")


def download_snapshot(
    base_url: str,
    job_id: str,
    output_path: str | Path,
    timeout_seconds: float,
    *,
    auth_token: str | None = None,
) -> Path:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    headers = {}
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    req = request.Request(
        f"{base_url.rstrip('/')}/api/jobs/{job_id}/snapshot",
        headers=headers,
    )
    with request.urlopen(req, timeout=timeout_seconds) as response:
        output_path.write_bytes(response.read())
    return output_path


def verify_snapshot(snapshot_path: str | Path) -> dict[str, Any]:
    snapshot_path = Path(snapshot_path)
    with zipfile.ZipFile(snapshot_path) as zf:
        names = set(zf.namelist())
        for required in ("manifest.json", "inference.onnx", "metrics.jsonl"):
            if required not in names:
                raise RuntimeError(f"snapshot is missing {required}")
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    if manifest.get("status") != "completed":
        raise RuntimeError(f"snapshot manifest status is not completed: {manifest}")
    return manifest


def run_smoke(config: SmokeConfig) -> dict[str, Any]:
    config.workspace.mkdir(parents=True, exist_ok=True)
    (config.workspace / "datasets").mkdir(parents=True, exist_ok=True)
    bundle_path = create_dummy_bundle(config.workspace / "dummy_bundle.zip", epochs=config.epochs)
    snapshot_path = config.workspace / "snapshot.zip"

    print(f"[smoke] launcher={config.launcher} base_url={config.base_url}")
    with launch_runtime(config):
        wait_for_health(config.base_url, config.timeout_seconds)
        print("[smoke] runtime is healthy")
        job_id = upload_bundle(
            config.base_url,
            bundle_path,
            config.timeout_seconds,
            auth_token=config.auth_token,
        )
        print(f"[smoke] job_id={job_id}")
        final_event = wait_for_terminal_event(
            config.ws_url,
            job_id,
            config.timeout_seconds,
            auth_token=config.auth_token,
        )
        download_snapshot(
            config.base_url,
            job_id,
            snapshot_path,
            config.timeout_seconds,
            auth_token=config.auth_token,
        )
        manifest = verify_snapshot(snapshot_path)

    result = {
        "job_id": job_id,
        "snapshot_path": str(snapshot_path),
        "final_event": final_event,
        "manifest": manifest,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return result


@contextmanager
def launch_runtime(config: SmokeConfig) -> Iterator[None]:
    if config.launcher == "external":
        yield
        return
    if config.launcher == "local":
        with _local_runtime_process(config):
            yield
        return
    if config.launcher == "docker":
        with _docker_runtime_process(config):
            yield
        return
    raise RuntimeError(f"unsupported launcher: {config.launcher}")


@contextmanager
def _local_runtime_process(config: SmokeConfig) -> Iterator[None]:
    process = subprocess.Popen(local_server_command(config), cwd=_repo_root())
    try:
        yield
    finally:
        if not config.keep_runtime:
            _stop_process(process)


@contextmanager
def _docker_runtime_process(config: SmokeConfig) -> Iterator[None]:
    if shutil.which("docker") is None:
        raise RuntimeError("docker compose CLI was not found; install Docker or use --launcher local")

    env = docker_compose_environment(config)
    process = subprocess.Popen(docker_compose_up_command(config), cwd=_repo_root(), env=env)
    try:
        yield
    finally:
        if not config.keep_runtime:
            _stop_process(process)
            subprocess.run(
                docker_compose_down_command(config),
                cwd=_repo_root(),
                env=env,
                check=False,
            )


def _stop_process(process: subprocess.Popen[Any]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10.0)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5.0)


def _with_token_query(url: str, auth_token: str | None) -> str:
    if not auth_token:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}token={parse.quote(auth_token)}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a Neuralese on-prem runtime smoke test.")
    parser.add_argument("--launcher", choices=("local", "docker", "external"), default="local")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    parser.add_argument("--workspace", default="")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--max-parallel-jobs", type=int, default=1)
    parser.add_argument("--runtime-mode", choices=("local_school", "cloud_node"), default="local_school")
    parser.add_argument("--compose-file", default=str(_default_compose_file()))
    parser.add_argument("--auth-token", default=None)
    parser.add_argument("--keep-runtime", action="store_true")
    return parser


def config_from_args(args: argparse.Namespace, workspace: Path) -> SmokeConfig:
    return SmokeConfig(
        launcher=args.launcher,
        host=args.host,
        port=args.port,
        workspace=workspace,
        runtime_mode=args.runtime_mode,
        max_parallel_jobs=args.max_parallel_jobs,
        timeout_seconds=args.timeout,
        epochs=args.epochs,
        compose_file=Path(args.compose_file),
        keep_runtime=args.keep_runtime,
        auth_token=args.auth_token,
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.workspace:
            run_smoke(config_from_args(args, Path(args.workspace)))
        else:
            with tempfile.TemporaryDirectory(prefix="neuralese_smoke_") as tmp_dir:
                run_smoke(config_from_args(args, Path(tmp_dir)))
    except Exception as exc:
        print(f"[smoke] failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
