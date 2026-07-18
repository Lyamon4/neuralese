import sys
import json
from typing import Any

from fs_core import Database
from fs_utils import normalize_path

# =========================
# Context
# =========================

class Context:
	def __init__(self, db: Database):
		self.db = db
		self.cwd = "/"

	def resolve(self, path: str) -> str:
		if not path or path == ".":
			return self.cwd
		if path.startswith("/"):
			return normalize_path(path)
		return normalize_path(self.cwd.rstrip("/") + "/" + path)

# =========================
# Helpers
# =========================

def die(msg: str):
	print(f"[error] {msg}", file=sys.stderr)
	raise RuntimeError(msg)

def pretty(obj: Any):
	print(json.dumps(obj, indent=2, ensure_ascii=False))

# =========================
# Commands
# =========================

def cmd_pwd(ctx: Context, *_):
	print(ctx.cwd)

def cmd_cd(ctx: Context, path: str):
	target = ctx.resolve(path)
	if not ctx.db.exists(target):
		die("No such directory")
	ctx.cwd = target.rstrip("/") or "/"

def cmd_ls(ctx: Context, path: str = ""):
	p = ctx.resolve(path)
	n = ctx.db[p]
	if not n.is_dir:
		die("Not a directory")
	for name in n.ls():
		print(name)

def cmd_tree(ctx: Context, path: str = "", indent: str = ""):
	p = ctx.resolve(path)
	n = ctx.db[p]
	print(f"{indent}{n.name or '/'}")
	if not n.is_dir:
		return
	for c in n.iterdir():
		cmd_tree(ctx, c.path, indent + "  ")

def cmd_inspect(ctx: Context, path: str):
	n = ctx.db[ctx.resolve(path)]
	val = n.read()
	if val is None:
		print("null")
	elif isinstance(val, (dict, list)):
		pretty(val)
	else:
		print(f"<{type(val).__name__}> {len(val)} bytes")

def cmd_exists(ctx: Context, path: str):
	print(ctx.db.exists(ctx.resolve(path)))

def cmd_delete(ctx: Context, path: str, yes=False):
	p = ctx.resolve(path)
	if not yes:
		resp = input(f"Delete '{p}' recursively? [y/N]: ").lower()
		if resp != "y":
			print("aborted")
			return
	ctx.db.delete(p)
	print("deleted")

def cmd_set_doc(ctx: Context, path: str, raw: str):
	p = ctx.resolve(path)
	n = ctx.db[p]
	if not n.is_doc:
		die("Target is not .doc")
	data = json.loads(raw)
	n.write(data)
	print("written")

def cmd_update_doc(ctx: Context, path: str, raw: str):
	p = ctx.resolve(path)
	n = ctx.db[p]
	if not n.is_doc:
		die("Target is not .doc")
	data = json.loads(raw)
	n.update_doc(data)
	print("updated")

def cmd_dump(ctx: Context, path: str):
	pretty(ctx.db._get_entry(ctx.resolve(path)))

# =========================
# Dispatch table
# =========================

COMMANDS = {
	"pwd": cmd_pwd,
	"cd": cmd_cd,
	"ls": cmd_ls,
	"tree": cmd_tree,
	"inspect": cmd_inspect,
	"exists": cmd_exists,
	"delete": cmd_delete,
	"set-doc": cmd_set_doc,
	"update-doc": cmd_update_doc,
	"dump": cmd_dump,
}

# =========================
# Shell
# =========================

def shell(ctx: Context):
	while True:
		try:
			line = input(f"db:{ctx.cwd} > ").strip()
			if not line:
				continue
			if line in ("exit", "quit"):
				return

			parts = line.split()
			cmd = parts[0]
			args = parts[1:]

			if cmd not in COMMANDS:
				print("unknown command")
				continue

			COMMANDS[cmd](ctx, *args)

		except KeyboardInterrupt:
			print()
			return
		except Exception as e:
			print(f"[error] {e}")

# =========================
# Entry
# =========================

def main():
	if len(sys.argv) < 3:
		print("Usage: tools.py <command|shell> <db_path> [args]")
		sys.exit(1)

	mode = sys.argv[1]
	db_path = sys.argv[2]

	ctx = Context(Database(db_path))

	if mode == "shell":
		shell(ctx)
		return

	if mode not in COMMANDS:
		die("Unknown command")

	COMMANDS[mode](ctx, *sys.argv[3:])

if __name__ == "__main__":
	main()
