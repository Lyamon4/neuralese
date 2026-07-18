import os, shutil, pathlib

BASE = pathlib.Path(__file__).parent.resolve()
SRC = BASE
DST = BASE / "local_runner"

# 1. Directories to copy (keep code identical)
COPY_DIRS = [
    "common",
    "worker",
    "nns",
]

# 2. Minimal new directories to generate
NEW_DIRS = [
    "app",
    "core",
    "config",
]

# 3. Template stubs (to be populated from configs/templates)
TEMPLATES = {
    "app/__main__.py": "templates/tpl_main.py",
    "app/app.py": "templates/tpl_app.py",
    "app/trio_bp.py": "templates/tpl_trio_bp.py",
    "core/context_cache.py": "templates/tpl_context_cache.py",
    "core/database.py": "templates/tpl_database.py",
    "config/settings.toml": "templates/settings.toml",
}

def mkdir(path: pathlib.Path):
    path.mkdir(parents=True, exist_ok=True)

def safe_copy(src, dst):
    if not os.path.exists(src):
        print(f"[skip] {src} not found")
        return
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    print(f"[copy] {src} -> {dst}")

def main():
    print(f"Creating local_runner at: {DST}")
    mkdir(DST)

    # Copy dirs
    for d in COPY_DIRS:
        safe_copy(str(SRC / d), str(DST / d))

    # Create new dirs
    for d in NEW_DIRS:
        mkdir(DST / d)

    # Generate placeholder files from templates
    for relpath, tpl in TEMPLATES.items():
        target = DST / relpath
        src_tpl = SRC / "configs" / tpl
        if src_tpl.exists():
            content = src_tpl.read_text()
        else:
            content = f"# generated placeholder for {relpath}\n"
        target.write_text(content)
        print(f"[create] {target}")
    with open("local_runner/app/__init__.py", "w+") as f:
        f.write("pass")
    with open("local_runner/__init__.py", "w+") as f:
        f.write("pass")


    print("\nlocal_runner scaffold created successfully.")

if __name__ == "__main__":
    main()
