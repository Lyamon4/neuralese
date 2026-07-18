from __future__ import annotations

import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from neuralese_local.progress_jsonl import ProgressJsonl
from neuralese_local.stop_flag import StopFlag


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: train_entry.py <job_dir>", file=sys.stderr)
        return 2

    job_dir = Path(sys.argv[1]).resolve()
    request_path = job_dir / "request.json"
    progress = ProgressJsonl(job_dir / "progress.jsonl")

    try:
        from neuralese_local.train_task import run_training

        request = json.loads(request_path.read_text(encoding="utf-8-sig"))
        stop = StopFlag(job_dir / "stop", parent_pid=request.get("parent_pid"))
        request["job_dir"] = str(job_dir)
        run_training(request, progress.emit, stop)
        return 0
    except Exception as exc:
        progress.emit({"phase": "error", "error": {"type": "LocalRuntimeError", "message": str(exc)}})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
