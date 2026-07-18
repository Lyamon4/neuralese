import os
import json
from rocksdict import Rdict, Options
has_logger = False
try:
	from .fs_utils import normalize_path, normalize_prefix
	from .fs_node import Node
except:
	from fs_utils import normalize_path, normalize_prefix
	from fs_node import Node

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




class Database:
	def __init__(self, path: str):
		self.path = path
		fresh_init = not os.path.exists(path)

		opts = Options()
		opts.create_if_missing(True)
		opts.set_enable_blob_files(True)
		opts.set_min_blob_size(1024 * 512)
		opts.set_blob_file_size(1024 * 1024 * 64)
		opts.set_enable_blob_gc(True)
		self.db = Rdict(path, options=opts)

		if fresh_init:
			log.info(f"Initialized new RocksDB at {path}")
		else:
			log.info(f"Using existing RocksDB directory: {path}")

	def __getitem__(self, path: str):
		return Node(self, normalize_path(path))

	def _get_entry(self, key: str):
		raw = self.db.get(key)
		if raw is None:
			return None
		if key.endswith(".blob"):
			return {"meta": {"kind": "blob"}, "content": raw}
		return json.loads(raw)

	def _save_entry(self, key: str, meta: dict, content=None):
		if key.endswith(".blob"):
			if not isinstance(content, (bytes, bytearray)):
				raise TypeError(f"Expected bytes for blob entry: {key}")
			self.db[key] = bytes(content)
			return

		self.db[key] = json.dumps({"meta": meta, "content": content})

	def list(self, prefix: str):
		prefix = normalize_prefix(prefix)
		results = set()
		for k in self.db.keys():
			if k.startswith(prefix) and k != prefix:
				remainder = k[len(prefix):].strip("/")
				if not remainder:
					continue
				first = remainder.split("/", 1)[0]
				results.add(first)
		return sorted(results)

	def exists(self, key: str) -> bool:
		key = normalize_path(key)
		if key in self.db:
			return True
		prefix = key.rstrip("/") + "/"
		for k in self.db.keys():
			if k.startswith(prefix):
				return True
		return False

	def delete(self, path: str):
		path = normalize_path(path)
		if path in self.db:
			del self.db[path]
		prefix = path.rstrip("/") + "/"
		to_del = []
		for k in self.db.keys():
			if k.startswith(prefix):
				to_del.append(k)

		if to_del:
			for k in to_del:
				del self.db[k]
			#log.debug(f"Recursively deleted {len(to_del)} entries under {path}")

	def batch_get(self, paths) -> dict[str, dict] | None:
		if not paths:
			return {}
		keys = [normalize_path(p) for p in paths]
		results = self.db.multi_get(keys)
		out: dict[str, dict] = {}
		for k, v in zip(keys, results):
			if v is None:
				continue
			try:
				out[k] = json.loads(v)
			except Exception:
				continue
		return out if out else None
