from __future__ import annotations

import os
from typing import Any

from .fs_utils import normalize_path


class Node:
    def __init__(self, fs, path: str):
        self.fs = fs
        self.path = normalize_path(path)

    @property
    def name(self) -> str:
        return os.path.basename(self.path.rstrip("/"))

    @property
    def is_dir(self) -> bool:
        return "." not in self.name

    @property
    def is_doc(self) -> bool:
        return self.name.endswith(".doc")

    def read(self) -> Any:
        entry = self.fs._get_entry(self.path)
        if not entry:
            return None
        return entry.get("content")

    def write(self, data: Any) -> str:
        if self.is_dir:
            raise TypeError(f"{self.path} is a directory")
        kind = "doc" if self.is_doc else "blob"
        self.fs._save_entry(self.path, {"kind": kind}, data)
        return self.path

    def ls(self) -> list[str]:
        return self.fs.list(self.path) if self.is_dir else []

    def _resolve_rel(self, rel: str) -> str:
        if not rel or rel == ".":
            return self.path
        if rel.startswith("/"):
            raise ValueError("absolute relative path is not allowed")
        parts = [part for part in rel.replace("\\", "/").split("/") if part and part != "."]
        if any(part == ".." for part in parts):
            raise ValueError("parent traversal is not allowed")
        full = normalize_path(self.path.rstrip("/") + "/" + "/".join(parts))
        base = self.path.rstrip("/") + "/"
        if not full.startswith(base):
            raise ValueError("resolved path escapes base node")
        return full

    def __getitem__(self, rel: str) -> "Node":
        return Node(self.fs, self._resolve_rel(rel))

    def child(self, rel: str) -> "Node":
        return self[rel]

    def read_rel(self, rel: str) -> Any:
        return self[rel].read()

    def write_rel(self, rel: str, data: Any) -> str:
        return self[rel].write(data)

    def update_doc(self, new_data: dict) -> str:
        if not self.is_doc:
            raise TypeError(f"{self.path} is not a .doc")
        current = self.read()
        if current is None:
            current = {}
        if not isinstance(current, dict):
            raise TypeError(f"{self.path} does not contain a dict")
        current.update(new_data)
        self.write(current)
        return self.path

    def update_doc_rel(self, rel: str, new_data: dict) -> str:
        return self[rel].update_doc(new_data)

    def exists_rel(self, rel: str) -> bool:
        return self.fs.exists(self._resolve_rel(rel))

    def delete_rel(self, rel: str) -> None:
        self.fs.delete(self._resolve_rel(rel))

    def ls_rel(self, rel: str = "") -> list[str]:
        return (self[rel] if rel else self).ls()
