from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dataset_compression_engine import compare_results, compress_blocks


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("dataset_compression_fixture.json")
GODOT_RUNNER = Path(__file__).with_name("dataset_compression_godot_runner.gd")
GODOT_COMPRESSOR = ROOT / "scripts" / "ds_obj_serialize.gd"

MINIMAL_PROJECT = """[application]
config/name="Neuralese Dataset Compression Parity"

[rendering]
renderer/rendering_method="gl_compatibility"
"""

GLOB_STUB = """extends RefCounted
static var rle_cache: Dictionary = {}
"""


def stress_dataset() -> dict:
    rows = []
    for index in range(513):
        rows.append(
            [
                {"type": "num", "num": -10 + (index % 256)},
                {"type": "num", "num": -100 + (index % 1101)},
                {"type": "num", "num": -100_000 + index * 257},
                {"type": "float", "val": (index % 17) / 16.0},
                {"type": "text", "text": "ряд" if index % 5 else ""},
                {"type": "num", "num": index % 4},
            ]
        )
    return {
        "arr": rows,
        "col_names": [
            "Byte:num",
            "Word:num",
            "DWord:num",
            "Ratio:float",
            "Text:text",
            "Output:num",
        ],
        "outputs_from": 5,
        "col_args": [
            {"min": -10, "max": 245},
            {"min": -100, "max": 1000},
            {"min": -100000, "max": 100000},
            {},
            {},
            {"min": 0, "max": 3},
        ],
    }


def main() -> int:
    godot = Path(
        r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
    )
    if len(sys.argv) > 1:
        godot = Path(sys.argv[1])
    if not godot.is_file():
        raise SystemExit(f"Godot executable not found: {godot}")

    cases = {
        "mixed": json.loads(FIXTURE.read_text(encoding="utf-8")),
        "multiblock": stress_dataset(),
        "wide_integer_wrap": {
            "arr": [
                [{"type": "num", "num": -1}, {"type": "num", "num": -1}],
                [{"type": "num", "num": 70000}, {"type": "num", "num": 2**32}],
            ],
            "col_names": ["Word:num", "DWord:num"],
            "outputs_from": 2,
            "col_args": [
                {"min": 0, "max": 1000},
                {"min": 0, "max": 100000},
            ],
        },
    }
    with tempfile.TemporaryDirectory(prefix="neuralese_ds_parity_") as temp:
        harness = Path(temp)
        (harness / "project.godot").write_text(MINIMAL_PROJECT, encoding="utf-8")
        (harness / "glob_stub.gd").write_text(GLOB_STUB, encoding="utf-8")
        compressor_source = GODOT_COMPRESSOR.read_text(encoding="utf-8")
        compressor_source = compressor_source.replace(
            "class_name DsObjRLE",
            'class_name DsObjRLE\nconst glob := preload("res://glob_stub.gd")',
            1,
        )
        (harness / "ds_obj_serialize.gd").write_text(
            compressor_source, encoding="utf-8"
        )
        shutil.copy2(GODOT_RUNNER, harness / "runner.gd")
        for case_name, dataset in cases.items():
            fixture_path = harness / f"{case_name}.json"
            godot_output = harness / f"{case_name}_godot.json"
            fixture_path.write_text(
                json.dumps(dataset, ensure_ascii=False), encoding="utf-8"
            )
            command = [
                str(godot),
                "--headless",
                "--path",
                str(harness),
                "--script",
                "res://runner.gd",
                "--",
                str(fixture_path),
                str(godot_output),
            ]
            try:
                completed = subprocess.run(
                    command,
                    check=True,
                    timeout=30,
                    capture_output=True,
                    text=True,
                )
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                print(getattr(error, "stdout", "") or "")
                print(getattr(error, "stderr", "") or "")
                debug_dir = Path(tempfile.gettempdir()) / "neuralese_ds_parity_failed"
                if debug_dir.exists():
                    shutil.rmtree(debug_dir)
                shutil.copytree(harness, debug_dir)
                print(f"Preserved failed Godot harness at: {debug_dir}")
                return 2
            if completed.stdout:
                print(completed.stdout)
            if completed.stderr:
                print(completed.stderr)

            godot_result = json.loads(godot_output.read_text(encoding="utf-8"))
            python_result = compress_blocks(dataset)
            differences = compare_results(godot_result, python_result)
            if differences:
                print(f"Dataset compression parity FAILED case={case_name}")
                for difference in differences:
                    print(difference)
                return 1
            print(f"Dataset compression parity MATCHED case={case_name}")

    print("All dataset compression cases matched bit-for-bit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
