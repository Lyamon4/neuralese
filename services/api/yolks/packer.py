#!/usr/bin/env python3
"""
packer_mem.py — platform-aware, fully in-memory Yolk packer.

Produces a single-file executable as bytes:
[base][onnx_model][meta_json][meta_len:u64][model_len:u64][MAGIC]
"""

import os
import json
import struct
import mmap
from io import BytesIO
from pathlib import Path
from time import perf_counter

MAGIC = b"YOLK_FOOTER_v1__"
ROOT = Path(__file__).parent.resolve()
BASE_DIR = ROOT / "base_binaries"

BASES = {
    "win": BASE_DIR / "yolk_win64.exe",
    "linux": BASE_DIR / "yolk_linux_gnu",
}

# verify presence
for name, path in list(BASES.items()):
    if not path.exists():
        print(f"[!] Base yolk missing: {path}")
        BASES.pop(name, None)

if not BASES:
    raise FileNotFoundError("No base yolks found")

BASE_MM = {}
for name, path in BASES.items():
    f = open(path, "rb")
    BASE_MM[name] = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)

def get_base(platform: str = None):
    if platform is None:
        # auto detect
        return BASE_MM["win"] if os.name == "nt" else BASE_MM.get("linux") or next(iter(BASE_MM.values()))
    if platform not in BASE_MM:
        raise KeyError(f"No base yolk for platform {platform}")
    return BASE_MM[platform]


def pack_to_bytes(model_bytes: bytes, meta: dict, platform: str = None) -> bytes:
    meta_bytes = json.dumps(meta, separators=(",", ":")).encode("utf-8")
    meta_len = len(meta_bytes)
    model_len = len(model_bytes)

    base = get_base(platform)
    buf = BytesIO()
    buf.write(base)
    buf.write(model_bytes)
    buf.write(meta_bytes)
    buf.write(struct.pack("<Q", meta_len))
    buf.write(struct.pack("<Q", model_len))
    buf.write(MAGIC)
#    print(len(buf))
    return buf.getvalue()