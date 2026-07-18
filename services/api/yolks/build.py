

import os
import json
import subprocess
import shutil
import datetime
from pathlib import Path

BASE = Path(__file__).parent.resolve()
SRC = BASE / "src"
BASE_BINARIES = BASE / "base_binaries"
BASE_BINARIES.mkdir(exist_ok=True)

# ---------- Metadata injection ----------
def inject_metadata():
	meta = {
		"version": "1.0.0",
		"build_time": datetime.datetime.now(datetime.UTC).isoformat(),
		"description": "Yolk base executable",
	}
	meta_path = SRC / "meta.rs"
	meta_json = json.dumps(meta, separators=(",", ":"))
	meta_path.write_text(f'pub const META_JSON: &str = r#"{meta_json}"#;\n')
	print(f"[*] Injected metadata into {meta_path}")

# ---------- Helpers ----------
def run_cmd(cmd, cwd=None):
	print(f"[+] Running: {' '.join(cmd)}")
	subprocess.check_call(cmd, cwd=cwd)

def copy_out(target_dir, binary_name, dest_name):
	src = target_dir / "release" / binary_name
	dest = BASE_BINARIES / dest_name
	shutil.copy2(src, dest)
	print(f"    Copied -> {dest}")

def build_windows():
	run_cmd(["cargo", "build", "--release"])
	copy_out(BASE / "target", "yolk.exe", "yolk_win64.exe")

def build_linux_gnu():
	run_cmd(["cargo", "build", "--target", "x86_64-unknown-linux-gnu", "--release"])
	copy_out(BASE / "target" / "x86_64-unknown-linux-gnu", "yolk", "yolk_linux_gnu")

import sys
def main():
	inject_metadata()

	match sys.argv[1]:
		case "win":
			build_windows()
		case "lin":
			build_linux_gnu()

if __name__ == "__main__":
	main()