import os
from typing import Any
try:
    from .fs_utils import normalize_path
except:
    from fs_utils import normalize_path
import json

try:
	import common.logger; has_logger = True
	log = common.logger.get_logger()
except:
	import logging
	import sys
	def get_logger(subname: str = None) -> logging.Logger:
		name = "Database" if not subname else subname
		log = logging.getLogger(name)
		if not log.handlers:
			handler = logging.StreamHandler(sys.stdout)
			handler.setFormatter(logging.Formatter(
				"%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
				datefmt="%H:%M:%S"
			))
			log.addHandler(handler)
			log.setLevel(logging.DEBUG)
			log.propagate = False
		return log
	log = get_logger()


class Node:
    def __init__(self, fs, path: str):
        self.fs = fs
        self.path = normalize_path(path)

    @property
    def name(self):
        return os.path.basename(self.path.rstrip("/"))

    @property
    def is_dir(self):
        return "." not in self.name

    @property
    def is_doc(self):
        return self.name.endswith(".doc")

    @property
    def is_file(self):
        return "." in self.name and not self.is_doc

    def read(self) -> Any:
        entry = self.fs._get_entry(self.path)
        if not entry:
            return None
        meta = entry["meta"]
        if meta["kind"] in ("blob", "doc"):
            return entry.get("content")
        return None

    def write(self, data: Any) -> str:
        if self.is_dir:
            raise TypeError(f"{self.path} is a directory")
        meta_kind = "doc" if self.is_doc else "blob"
        self.fs._save_entry(self.path, {"kind": meta_kind}, data)
        return self.path

    def ls(self):
        if not self.is_dir:
            return []
        return self.fs.list(self.path)

    def iterdir(self):
        for name in self.ls():
            yield Node(self.fs, f"{self.path.rstrip('/')}/{name}")

    def _resolve_rel(self, rel: str) -> str:
        if not rel or rel == ".":
            return self.path
        if rel.startswith("/"):
            raise ValueError("Absolute paths are not allowed in relative operations")
        parts = [p for p in rel.split("/") if p not in ("", ".")]
        if any(p == ".." for p in parts):
            raise ValueError("Parent traversal ('..') is not allowed")

        joined = self.path.rstrip("/") + "/" + "/".join(parts)
        full = normalize_path(joined)

        base = self.path.rstrip("/") + "/"
        if not full.startswith(base):
            raise ValueError("Resolved path escapes base node")
        return full

    def __getitem__(self, rel: str) -> "Node":
        return Node(self.fs, self._resolve_rel(rel))

    def child(self, rel: str) -> "Node":
        return self[rel]

    def __truediv__(self, rel: str) -> "Node":
        return self[rel]

    def read_rel(self, rel: str) -> Any:
        return self[rel].read()

    def write_rel(self, rel: str, data: Any) -> str:
        n = self[rel]
        if n.is_dir:
            raise TypeError(f"{rel} resolves to a directory")
        meta_kind = "doc" if n.is_doc else "blob"
        self.fs._save_entry(n.path, {"kind": meta_kind}, data)
        return n.path

    def update_doc(self, new_data: dict) -> str:
        if not self.is_doc:
            raise TypeError(f"{self.path} is not a JSON document (.doc)")

        current = self.read()
        if current is None:
            current = {}

        if not isinstance(current, dict):
            raise TypeError(f"Existing document at {self.path} is not a JSON object")

        if not isinstance(new_data, dict):
            raise TypeError("update_doc() requires a dict argument")

        current.update(new_data)
        self.fs._save_entry(self.path, {"kind": "doc"}, current)
        return self.path

    def update_doc_rel(self, rel: str, new_data: dict) -> str:
        n = self[rel]
        if not n.is_doc:
            raise TypeError(f"{rel} is not a JSON document (.doc)")

        current = n.read()
        if current is None:
            current = {}

        if not isinstance(current, dict):
            raise TypeError(f"Existing document at {n.path} is not a JSON object")

        if not isinstance(new_data, dict):
            raise TypeError("update_doc_rel() requires a dict argument")

        current.update(new_data)
        self.fs._save_entry(n.path, {"kind": "doc"}, current)
        return n.path


    def exists_rel(self, rel: str) -> bool:
        return self.fs.exists(self._resolve_rel(rel))

    def delete_rel(self, rel: str):
        self.fs.delete(self._resolve_rel(rel))

    def ls_rel(self, rel: str = ""):
        n = self[rel] if rel else self
        if not n.is_dir:
            return []
        return self.fs.list(n.path)

    def iterdir_rel(self, rel: str = ""):
        n = self[rel] if rel else self
        for name in n.ls():
            yield Node(self.fs, f"{n.path.rstrip('/')}/{name}")
