from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any, Callable, Sequence


APP_PATH = "onprem_runtime.api.server:app"


def main(
    argv: Sequence[str] | None = None,
    *,
    run_server: Callable[..., Any] | None = None,
) -> int:
    args = _build_parser().parse_args(argv)
    _configure_env(args)
    runner = run_server or _uvicorn_run
    runner(
        APP_PATH,
        host=args.host,
        port=args.port,
        reload=args.reload,
    )
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the Neuralese on-prem ONNX training runtime.")
    parser.add_argument("--mode", choices=("local_school", "cloud_node"), default="local_school")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    parser.add_argument("--storage-dir", default=".neuralese_onprem")
    parser.add_argument("--public-dataset-dir", default="local_runtime/datasets")
    parser.add_argument("--max-parallel-jobs", type=int, default=1)
    parser.add_argument("--auth-token", default=None)
    parser.add_argument("--reload", action="store_true")
    return parser


def _configure_env(args: argparse.Namespace) -> None:
    os.environ["NEURALESE_RUNTIME_MODE"] = args.mode
    os.environ["NEURALESE_STORAGE_DIR"] = str(Path(args.storage_dir))
    os.environ["NEURALESE_PUBLIC_DATASET_DIR"] = str(Path(args.public_dataset_dir))
    os.environ["NEURALESE_MAX_PARALLEL_JOBS"] = str(max(1, int(args.max_parallel_jobs)))
    if args.auth_token:
        os.environ["NEURALESE_AUTH_TOKEN"] = args.auth_token
    else:
        os.environ.pop("NEURALESE_AUTH_TOKEN", None)


def _uvicorn_run(app_path: str, **kwargs: Any) -> None:
    import uvicorn

    uvicorn.run(app_path, **kwargs)


if __name__ == "__main__":
    raise SystemExit(main())
