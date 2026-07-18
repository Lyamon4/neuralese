from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

try:
    import numpy as np
except Exception:  # pragma: no cover - import guard for tiny tooling scripts
    np = None


def _json_default(value: Any) -> Any:
    if np is not None:
        if isinstance(value, np.generic):
            return value.item()
        if isinstance(value, np.ndarray):
            return value.tolist()
    if isinstance(value, memoryview):
        return value.tobytes().hex()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


class ProgressJsonl:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.touch(exist_ok=True)

    def emit(self, packet: Dict[str, Any]) -> None:
        text = json.dumps(packet, ensure_ascii=False, default=_json_default)
        with self.path.open("a", encoding="utf-8", newline="\n") as f:
            f.write(text)
            f.write("\n")
            f.flush()

