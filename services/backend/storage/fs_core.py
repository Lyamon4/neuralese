from __future__ import annotations

import json
import os
from typing import Any

from rocksdict import Options, Rdict

from .fs_node import Node
from .fs_utils import normalize_path, normalize_prefix


class Database:
    def __init__(self, path: str):
        self.path = path
        os.makedirs(path, exist_ok=True)
        opts = Options()
        opts.create_if_missing(True)
        opts.set_enable_blob_files(True)
        opts.set_min_blob_size(1024 * 512)
        opts.set_blob_file_size(1024 * 1024 * 64)
        opts.set_enable_blob_gc(True)
        self.db = Rdict(path, options=opts)

    def __getitem__(self, path: str) -> Node:
        return Node(self, normalize_path(path))

    def _get_entry(self, key: str) -> dict[str, Any] | None:
        raw = self.db.get(normalize_path(key))
        if raw is None:
            return None
        if key.endswith(".blob"):
            return {"meta": {"kind": "blob"}, "content": raw}
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        return json.loads(raw)

    def _save_entry(self, key: str, meta: dict, content: Any = None) -> None:
        key = normalize_path(key)
        if key.endswith(".blob"):
            if not isinstance(content, (bytes, bytearray)):
                raise TypeError(f"blob entries require bytes: {key}")
            self.db[key] = bytes(content)
            return
        self.db[key] = json.dumps({"meta": meta, "content": content}, ensure_ascii=False)

    def list(self, prefix: str) -> list[str]:
        prefix = normalize_prefix(prefix)
        results = set()
        for key in self.db.keys():
            key = key.decode("utf-8") if isinstance(key, bytes) else str(key)
            if key.startswith(prefix) and key != prefix:
                rest = key[len(prefix):].strip("/")
                if rest:
                    results.add(rest.split("/", 1)[0])
        return sorted(results)

    def exists(self, key: str) -> bool:
        key = normalize_path(key)
        if key in self.db:
            return True
        prefix = key.rstrip("/") + "/"
        for existing in self.db.keys():
            existing = existing.decode("utf-8") if isinstance(existing, bytes) else str(existing)
            if existing.startswith(prefix):
                return True
        return False

    def delete(self, path: str) -> None:
        path = normalize_path(path)
        if path in self.db:
            del self.db[path]
        prefix = path.rstrip("/") + "/"
        for key in list(self.db.keys()):
            key = key.decode("utf-8") if isinstance(key, bytes) else str(key)
            if key.startswith(prefix):
                del self.db[key]

    def close(self) -> None:
        close = getattr(self.db, "close", None)
        if callable(close):
            close()
