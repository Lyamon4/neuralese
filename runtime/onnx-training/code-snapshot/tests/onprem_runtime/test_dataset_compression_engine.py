from __future__ import annotations

import hashlib

import onprem_runtime.core.dataset_compression as compression


def test_mixed_columns_match_godot_block_bytes() -> None:
    dataset = {
        "arr": [
            [
                {"type": "num", "num": 5},
                {"type": "float", "val": 0.0},
                {"type": "text", "text": "a"},
                {"type": "image", "image_bytes_hex": "ff0000ff00ff00ff"},
                {"type": "num", "num": 10},
            ],
            [
                {"type": "num", "num": 5},
                {"type": "float", "val": 0.5},
                {"type": "text", "text": "б"},
                {"type": "image", "image_bytes_hex": "0000ffffffffffff"},
                {"type": "num", "num": 11},
            ],
            [
                {"type": "num", "num": 5},
                {"type": "float", "val": 1.0},
                {"type": "text", "text": ""},
                {"type": "image", "image_bytes_hex": "0000000000000000"},
                {"type": "num", "num": 12},
            ],
        ],
        "col_names": ["Count:num", "Ratio:float", "Text:text", "Pixels:image", "Output:num"],
        "outputs_from": 4,
        "col_args": [
            {"min": 0, "max": 255},
            {},
            {},
            {},
            {"min": 10, "max": 20},
        ],
    }

    result = compression.compress_blocks(dataset)

    assert result["header"]["rows"] == 3
    assert result["header"]["inputs_count"] == 4
    assert result["header"]["outputs_count"] == 1
    assert result["header"]["rows_per_block"] == 256
    assert result["header"]["columns"]["0"] == {"dtype": "num", "min": 0, "max": 255, "bits": 8}
    assert result["header"]["columns"]["3"] == {"dtype": "image"}
    assert result["data"][0][0]["blocks"] == ["00050505"]
    assert result["data"][0][1]["blocks"] == ["00007fff"]
    assert result["data"][0][2]["blocks"] == ["006100d0b10000"]
    assert result["data"][0][3]["blocks"] == ["00ff0000ff00ff00ff0000ffffffffffff0000000000000000"]
    assert result["data"][1][0]["blocks"] == ["00000102"]


def test_rle_is_selected_only_when_strictly_smaller() -> None:
    repeated = {
        "arr": [[{"type": "num", "num": 0}] for _ in range(8)],
        "col_names": ["Value:num"],
        "outputs_from": 1,
        "col_args": [{"min": 0, "max": 1}],
    }
    not_smaller = {
        "arr": [[{"type": "num", "num": value}] for value in [0, 1, 0]],
        "col_names": ["Value:num"],
        "outputs_from": 1,
        "col_args": [{"min": 0, "max": 1}],
    }

    repeated_result = compression.compress_blocks(repeated)
    not_smaller_result = compression.compress_blocks(not_smaller)

    assert repeated_result["data"][0][0]["blocks"] == ["01000800"]
    assert not_smaller_result["data"][0][0]["blocks"] == ["00000100"]


def test_empty_dataset_contract() -> None:
    result = compression.compress_blocks({"arr": []})

    assert result == {
        "header": {
            "rows": 0,
            "inputs_count": 0,
            "outputs_count": 0,
            "columns": {},
            "dirty_from": -1,
            "rows_per_block": 256,
        },
        "data": [[], []],
    }


def test_wide_integer_paths_wrap_like_godot() -> None:
    dataset = {
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
    }

    result = compression.compress_blocks(dataset)

    assert result["data"][0][0]["blocks"] == ["00ffff1170"]
    assert result["data"][0][1]["blocks"] == ["010004ff000400"]


def test_rows_per_block_matches_frontend_thresholds() -> None:
    def dataset_with_rows(count: int) -> dict:
        return {
            "arr": [[{"type": "num", "num": index % 2}] for index in range(count)],
            "col_names": ["Value:num"],
            "outputs_from": 1,
            "col_args": [{"min": 0, "max": 1}],
        }

    assert compression.compress_blocks(dataset_with_rows(100_000))["header"]["rows_per_block"] == 256
    assert compression.compress_blocks(dataset_with_rows(100_001))["header"]["rows_per_block"] == 512
    assert compression.compress_blocks(dataset_with_rows(300_001))["header"]["rows_per_block"] == 1024


def test_block_hashes_are_sha256_of_encoded_block_bytes() -> None:
    dataset = {
        "arr": [[{"type": "text", "text": "same"}], [{"type": "text", "text": "same"}]],
        "col_names": ["Text:text"],
        "outputs_from": 1,
    }

    result = compression.compress_blocks(dataset)
    block_hex = result["data"][0][0]["blocks"][0]

    assert result["data"][0][0]["hashes"] == [
        hashlib.sha256(bytes.fromhex(block_hex)).hexdigest()
    ]


def test_compressed_packet_can_be_decoded_back_to_training_rows() -> None:
    compressed = compression.compress_blocks(
        {
            "arr": [
                [{"type": "num", "num": 0}, {"type": "num", "num": 0}, {"type": "num", "num": 0}],
                [{"type": "num", "num": 0}, {"type": "num", "num": 1}, {"type": "num", "num": 1}],
                [{"type": "num", "num": 1}, {"type": "num", "num": 0}, {"type": "num", "num": 1}],
                [{"type": "num", "num": 1}, {"type": "num", "num": 1}, {"type": "num", "num": 1}],
            ],
            "col_names": ["X0:num", "X1:num", "Class:num"],
            "outputs_from": 2,
            "col_args": [
                {"min": 0, "max": 1},
                {"min": 0, "max": 1},
                {"min": 0, "max": 1},
            ],
        }
    )
    packet = {
        "header": compressed["header"],
        "data": [
            [[bytes.fromhex(block) for block in column["blocks"]] for column in compressed["data"][0]],
            [[bytes.fromhex(block) for block in column["blocks"]] for column in compressed["data"][1]],
        ],
    }

    rows = compression.decompress_dataset_packet(packet)

    assert rows == [
        ([0.0, 0.0], 0),
        ([0.0, 1.0], 1),
        ([1.0, 0.0], 1),
        ([1.0, 1.0], 1),
    ]
