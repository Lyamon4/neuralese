from __future__ import annotations

import hashlib
import math
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


def decompress_dataset_packet(packet: dict[str, Any]) -> list[tuple[list[float], Any]]:
    header = _packet_header(packet)
    rows = _godot_int(header.get("rows", 0))
    inputs_count = _godot_int(header.get("inputs_count", 0))
    outputs_count = _godot_int(header.get("outputs_count", 0))
    if rows < 0:
        raise ValueError("dataset packet rows must be >= 0")
    if inputs_count < 0 or outputs_count < 0:
        raise ValueError("dataset packet column counts must be >= 0")

    data = packet.get("data")
    if not isinstance(data, list) or len(data) != 2:
        raise ValueError("dataset packet data must contain input and output columns")

    input_columns = _decode_packet_side(
        data[0],
        header=header,
        column_offset=0,
        expected_columns=inputs_count,
        rows=rows,
        side_name="inputs",
    )
    output_columns = _decode_packet_side(
        data[1],
        header=header,
        column_offset=inputs_count,
        expected_columns=outputs_count,
        rows=rows,
        side_name="outputs",
    )

    decoded_rows: list[tuple[list[float], Any]] = []
    for row_index in range(rows):
        features = _flatten_feature_values(column[row_index] for column in input_columns)
        labels = [_to_training_value(column[row_index]) for column in output_columns]
        decoded_rows.append((features, labels[0] if len(labels) == 1 else labels))
    return decoded_rows


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


def _packet_header(packet: dict[str, Any]) -> dict[str, Any]:
    header = packet.get("header")
    if not isinstance(header, dict):
        raise ValueError("dataset packet header must be an object")
    return header


def _decode_packet_side(
    columns: Any,
    *,
    header: dict[str, Any],
    column_offset: int,
    expected_columns: int,
    rows: int,
    side_name: str,
) -> list[list[Any]]:
    if not isinstance(columns, list):
        raise ValueError(f"dataset packet {side_name} columns must be a list")
    if len(columns) != expected_columns:
        raise ValueError(
            f"dataset packet {side_name} column count mismatch: "
            f"{len(columns)} != {expected_columns}"
        )

    decoded_columns: list[list[Any]] = []
    for side_column, column in enumerate(columns):
        global_column = column_offset + side_column
        metadata = _packet_column_metadata(header, global_column)
        dtype = str(metadata.get("dtype", "text"))
        rows_per_block = _packet_rows_per_block(header, column)
        values: list[Any] = []
        for block_index, block in enumerate(_packet_column_blocks(column)):
            block_rows = min(rows_per_block, max(0, rows - block_index * rows_per_block))
            values.extend(_decode_column_block(block, dtype, metadata, block_rows))
        if len(values) < rows:
            raise ValueError(
                f"dataset packet {side_name}[{side_column}] has {len(values)} rows, "
                f"expected {rows}"
            )
        decoded_columns.append(values[:rows])
    return decoded_columns


def _packet_column_metadata(header: dict[str, Any], column: int) -> dict[str, Any]:
    columns = header.get("columns", {})
    if not isinstance(columns, dict):
        raise ValueError("dataset packet header.columns must be an object")
    metadata = columns.get(str(column), {})
    if not isinstance(metadata, dict):
        raise ValueError(f"dataset packet column {column} metadata must be an object")
    return metadata


def _packet_rows_per_block(header: dict[str, Any], column: Any) -> int:
    raw_value = column.get("rows_per_block") if isinstance(column, dict) else None
    rows_per_block = _godot_int(raw_value or header.get("rows_per_block", BLOCK_ROWS_DEFAULT))
    if rows_per_block <= 0:
        raise ValueError("dataset packet rows_per_block must be > 0")
    return rows_per_block


def _packet_column_blocks(column: Any) -> list[bytes]:
    blocks = column.get("blocks", []) if isinstance(column, dict) else column
    if not isinstance(blocks, list):
        raise ValueError("dataset packet column blocks must be a list")
    return [_packet_block_bytes(block) for block in blocks]


def _packet_block_bytes(block: Any) -> bytes:
    if isinstance(block, bytes):
        return block
    if isinstance(block, bytearray):
        return bytes(block)
    if isinstance(block, str):
        try:
            return bytes.fromhex(block)
        except ValueError as exc:
            raise ValueError("dataset packet block must be hex encoded") from exc
    raise ValueError("dataset packet block must be bytes or hex")


def _decode_column_block(
    block: bytes,
    dtype: str,
    metadata: dict[str, Any],
    rows: int,
) -> list[Any]:
    raw = _decode_adaptive_block(block)
    if dtype == "num":
        return _decode_num_values(raw, metadata, rows)
    if dtype == "float":
        return _decode_float_values(raw, rows)
    if dtype == "text":
        return _decode_text_values(raw, rows)
    if dtype == "image":
        return _decode_fixed_bytes_values(raw, rows)
    raise ValueError(f"unsupported dataset packet dtype: {dtype}")


def _decode_adaptive_block(block: bytes) -> bytes:
    if not block:
        raise ValueError("dataset packet block is empty")
    mode = block[0]
    payload = block[1:]
    if mode == 0:
        return payload
    if mode == 1:
        return _rle_decode(payload)
    raise ValueError(f"unsupported dataset packet block mode: {mode}")


def _rle_decode(payload: bytes) -> bytes:
    if len(payload) % 3 != 0:
        raise ValueError("dataset packet RLE payload is malformed")
    raw = bytearray()
    for index in range(0, len(payload), 3):
        count = int.from_bytes(payload[index : index + 2], "big")
        if count <= 0:
            raise ValueError("dataset packet RLE count must be > 0")
        raw.extend([payload[index + 2]] * count)
    return bytes(raw)


def _decode_num_values(raw: bytes, metadata: dict[str, Any], rows: int) -> list[int]:
    minimum = _godot_int(metadata.get("min", 0))
    bits = _godot_int(metadata.get("bits", 0))
    width = bits // 8 if bits in {8, 16, 32} else integer_width(
        minimum,
        _godot_int(metadata.get("max", 100)),
    )
    expected = rows * width
    if len(raw) < expected:
        raise ValueError(f"numeric block has {len(raw)} bytes, expected {expected}")
    return [
        int.from_bytes(raw[index : index + width], "big", signed=False) + minimum
        for index in range(0, expected, width)
    ]


def _decode_float_values(raw: bytes, rows: int) -> list[float]:
    if len(raw) < rows:
        raise ValueError(f"float block has {len(raw)} bytes, expected {rows}")
    return [value / 255.0 for value in raw[:rows]]


def _decode_text_values(raw: bytes, rows: int) -> list[str]:
    parts = raw.split(b"\x00")
    if parts and parts[-1] == b"":
        parts = parts[:-1]
    if len(parts) < rows:
        raise ValueError(f"text block has {len(parts)} values, expected {rows}")
    return [part.decode("utf-8") for part in parts[:rows]]


def _decode_fixed_bytes_values(raw: bytes, rows: int) -> list[list[float]]:
    if rows == 0:
        return []
    if len(raw) % rows != 0:
        raise ValueError("image block cannot be split into fixed-size rows")
    stride = len(raw) // rows
    return [
        [value / 255.0 for value in raw[index : index + stride]]
        for index in range(0, len(raw), stride)
    ]


def _flatten_feature_values(values: Any) -> list[float]:
    features: list[float] = []
    for value in values:
        converted = _to_training_value(value)
        if isinstance(converted, list):
            features.extend(float(item) for item in converted)
        else:
            features.append(float(converted))
    return features


def _to_training_value(value: Any) -> Any:
    if isinstance(value, list):
        return [float(item) for item in value]
    if isinstance(value, tuple):
        return [float(item) for item in value]
    if isinstance(value, bytes):
        return [item / 255.0 for item in value]
    if isinstance(value, str):
        raise ValueError("text columns are not supported for numeric ONNX training")
    return value


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


def _column_args(dataset: dict[str, Any], column: int) -> dict[str, Any]:
    args = dataset.get("col_args", [])
    if isinstance(args, list) and column < len(args) and isinstance(args[column], dict):
        return args[column]
    return {}


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
            value &= max_value
        raw.extend(value.to_bytes(width, byteorder="big", signed=False))
    return _adaptive_block(bytes(raw))


def _encode_float_block(rows: list[list[Any]], column: int, start: int, end: int) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        quantized = min(max(int(_cell_float(row[column]) * 255.0), 0), 255)
        raw.append(quantized)
    return _adaptive_block(bytes(raw))


def _encode_text_block(rows: list[list[Any]], column: int, start: int, end: int) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        cell = row[column]
        value = cell.get("text", "") if isinstance(cell, dict) else ""
        raw.extend(str(value).encode("utf-8"))
        raw.append(0)
    return b"\x00" + bytes(raw)


def _encode_image_block(rows: list[list[Any]], column: int, start: int, end: int) -> bytes:
    raw = bytearray()
    for row in rows[start:end]:
        raw.extend(_image_bytes(row[column]))
    return b"\x00" + bytes(raw)


def _adaptive_block(raw: bytes) -> bytes:
    encoded = _rle_encode(raw)
    if 1 + len(encoded) < 1 + len(raw):
        return b"\x01" + encoded
    return b"\x00" + raw


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


def _image_bytes(cell: Any) -> bytes:
    if not isinstance(cell, dict):
        return b""
    value = cell.get("image_bytes_hex", "")
    if not value:
        return b""
    return bytes.fromhex(str(value))


def _cell_num(cell: Any) -> int:
    return _godot_int(cell.get("num", 0)) if isinstance(cell, dict) else 0


def _cell_float(cell: Any) -> float:
    if not isinstance(cell, dict):
        return 0.0
    try:
        return float(cell.get("val", 0.0))
    except (TypeError, ValueError):
        return 0.0


def _godot_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
