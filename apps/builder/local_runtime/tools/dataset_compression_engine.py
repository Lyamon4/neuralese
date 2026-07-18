"""Pure-Python mirror of scripts/ds_obj_serialize.gd block compression.

The implementation intentionally uses only the Python standard library so it
can be copied into another repository and unit-tested without Neuralese.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


BLOCK_ROWS_DEFAULT = 256


def derive_column_dtypes(column_names: list[Any]) -> list[str]:
    result: list[str] = []
    for name in column_names:
        parts = str(name).rsplit(":", 1)
        result.append(parts[1] if len(parts) > 1 else "text")
    return result


def choose_block_rows(rows: int) -> int:
    if rows <= 100_000:
        return 256
    if rows <= 300_000:
        return 512
    return 1024


def integer_width(minimum: int, maximum: int) -> int:
    value_range = max(1, maximum - minimum)
    if value_range <= 255:
        return 1
    if value_range <= 65_535:
        return 2
    return 4


def _rle_encode(raw: bytes) -> bytes:
    if not raw:
        return b""

    result = bytearray()
    last = raw[0]
    count = 1
    for value in raw[1:]:
        if value == last and count < 65_535:
            count += 1
            continue
        result.extend(((count >> 8) & 0xFF, count & 0xFF, last))
        last = value
        count = 1
    result.extend(((count >> 8) & 0xFF, count & 0xFF, last))
    return bytes(result)


def _adaptive_block(raw: bytes) -> bytes:
    encoded = _rle_encode(raw)
    if 1 + len(encoded) < 1 + len(raw):
        return b"\x01" + encoded
    return b"\x00" + raw


def _godot_int(value: Any) -> int:
    # Godot int(float) and Python int(float) both truncate toward zero.
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _cell_num(cell: Any) -> int:
    return _godot_int(cell.get("num", 0)) if isinstance(cell, dict) else 0


def _cell_float(cell: Any) -> float:
    if not isinstance(cell, dict):
        return 0.0
    try:
        return float(cell.get("val", 0.0))
    except (TypeError, ValueError):
        return 0.0


def _encode_num_block(
    rows: list[list[Any]],
    column: int,
    start: int,
    end: int,
    bias: int,
    width: int,
) -> bytes:
    raw = bytearray()
    max_value = (1 << (width * 8)) - 1
    for row in rows[start:end]:
        value = _cell_num(row[column]) - bias
        if width == 1:
            value = min(max(value, 0), 255)
        else:
            # Godot masks each emitted byte in the 16/32-bit paths rather
            # than clamping the value first.
            value &= max_value
        raw.extend(value.to_bytes(width, byteorder="big", signed=False))
    return _adaptive_block(bytes(raw))


def _encode_float_block(
    rows: list[list[Any]], column: int, start: int, end: int
) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        quantized = min(max(int(_cell_float(row[column]) * 255.0), 0), 255)
        raw.append(quantized)
    return _adaptive_block(bytes(raw))


def _encode_text_block(
    rows: list[list[Any]], column: int, start: int, end: int
) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        cell = row[column]
        value = cell.get("text", "") if isinstance(cell, dict) else ""
        raw.extend(str(value).encode("utf-8"))
        raw.append(0)
    return b"\x00" + bytes(raw)


def _image_bytes(cell: Any) -> bytes:
    if not isinstance(cell, dict):
        return b""
    value = cell.get("image_bytes_hex", "")
    if not value:
        return b""
    return bytes.fromhex(str(value))


def _encode_image_block(
    rows: list[list[Any]], column: int, start: int, end: int
) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        raw.extend(_image_bytes(row[column]))
    return b"\x00" + bytes(raw)


def _column_args(dataset: dict[str, Any], column: int) -> dict[str, Any]:
    args = dataset.get("col_args", [])
    if isinstance(args, list) and column < len(args) and isinstance(args[column], dict):
        return args[column]
    return {}


def _build_column(
    dataset: dict[str, Any],
    column: int,
    dtype: str,
    rows_per_block: int,
) -> dict[str, Any]:
    rows = dataset["arr"]
    total_blocks = math.ceil(len(rows) / rows_per_block)
    blocks: list[str] = []
    hashes: list[str] = []
    args = _column_args(dataset, column)
    minimum = _godot_int(args.get("min", 0))
    maximum = _godot_int(args.get("max", 100))
    width = integer_width(minimum, maximum)

    for block_index in range(total_blocks):
        start = block_index * rows_per_block
        end = min(start + rows_per_block, len(rows))
        if dtype == "num":
            block = _encode_num_block(rows, column, start, end, minimum, width)
        elif dtype == "float":
            block = _encode_float_block(rows, column, start, end)
        elif dtype == "text":
            block = _encode_text_block(rows, column, start, end)
        else:
            block = _encode_image_block(rows, column, start, end)
        blocks.append(block.hex())
        hashes.append(hashlib.sha256(block).hexdigest())

    return {
        "blocks": blocks,
        "hashes": hashes,
        "rows_per_block": rows_per_block,
        "dtype": dtype,
    }


def compress_blocks(dataset: dict[str, Any]) -> dict[str, Any]:
    rows = dataset.get("arr", [])
    if not rows:
        return {
            "header": {
                "rows": 0,
                "inputs_count": 0,
                "outputs_count": 0,
                "columns": {},
                "dirty_from": -1,
                "rows_per_block": BLOCK_ROWS_DEFAULT,
            },
            "data": [[], []],
        }

    columns = len(rows[0])
    outputs_from = _godot_int(dataset.get("outputs_from", 0))
    dtypes = derive_column_dtypes(dataset.get("col_names", []))
    rows_per_block = choose_block_rows(len(rows))
    header: dict[str, Any] = {
        "rows": len(rows),
        "inputs_count": outputs_from,
        "outputs_count": columns - outputs_from,
        "columns": {},
        "rows_per_block": rows_per_block,
        "dirty_from": -1,
    }
    inputs: list[dict[str, Any]] = []
    outputs: list[dict[str, Any]] = []

    for column in range(columns):
        dtype = dtypes[column]
        encoded = _build_column(dataset, column, dtype, rows_per_block)
        (inputs if column < outputs_from else outputs).append(encoded)

        metadata: dict[str, Any] = {"dtype": dtype}
        if dtype == "num":
            args = _column_args(dataset, column)
            minimum = _godot_int(args.get("min", 0))
            maximum = _godot_int(args.get("max", 100))
            metadata.update(
                {
                    "min": minimum,
                    "max": maximum,
                    "bits": integer_width(minimum, maximum) * 8,
                }
            )
        header["columns"][str(column)] = metadata

    return {"header": header, "data": [inputs, outputs]}


def compare_results(expected: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    differences: list[str] = []

    def walk(left: Any, right: Any, path: str) -> None:
        if type(left) is not type(right):
            differences.append(
                f"{path}: type differs ({type(left).__name__} != {type(right).__name__})"
            )
            return
        if isinstance(left, dict):
            for key in sorted(set(left) | set(right)):
                child = f"{path}.{key}"
                if key not in left:
                    differences.append(f"{child}: missing from expected")
                elif key not in right:
                    differences.append(f"{child}: missing from actual")
                else:
                    walk(left[key], right[key], child)
        elif isinstance(left, list):
            if len(left) != len(right):
                differences.append(f"{path}: length differs ({len(left)} != {len(right)})")
            for index, (left_item, right_item) in enumerate(zip(left, right)):
                walk(left_item, right_item, f"{path}[{index}]")
        elif left != right:
            differences.append(f"{path}: {left!r} != {right!r}")

    walk(expected, actual, "$")
    return differences


def _main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="Canonical dataset JSON")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected", type=Path)
    args = parser.parse_args()

    dataset = json.loads(args.input.read_text(encoding="utf-8"))
    result = compress_blocks(dataset)
    output_text = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    if args.output:
        args.output.write_text(output_text, encoding="utf-8")
    else:
        print(output_text)

    if args.expected:
        expected = json.loads(args.expected.read_text(encoding="utf-8"))
        differences = compare_results(expected, result)
        if differences:
            for difference in differences[:100]:
                print(difference)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
