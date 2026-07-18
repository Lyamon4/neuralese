from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

MAGIC = b"NLESE_YOLK_v001!"


def pack(base_exe: Path, model_path: Path, meta_path: Path, out_path: Path) -> None:
    base = base_exe.read_bytes()
    model = model_path.read_bytes()
    meta_obj = json.loads(meta_path.read_text(encoding="utf-8"))
    meta = json.dumps(meta_obj, separators=(",", ":")).encode("utf-8")
    out_path.write_bytes(base + model + meta + struct.pack("<Q", len(meta)) + struct.pack("<Q", len(model)) + MAGIC)


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: pack_yolk.py <base_exe> <model.onnx> <meta.json> <out_exe>", file=sys.stderr)
        return 2
    pack(*(Path(x) for x in argv[1:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
