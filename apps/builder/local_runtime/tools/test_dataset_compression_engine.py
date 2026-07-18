from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dataset_compression_engine import compress_blocks


class DatasetCompressionEngineTests(unittest.TestCase):
    def test_mixed_columns_exact_bytes(self) -> None:
        dataset = {
            "arr": [
                [
                    {"type": "num", "num": 5},
                    {"type": "float", "val": 0.0},
                    {"type": "text", "text": "a"},
                    {"type": "num", "num": 10},
                ],
                [
                    {"type": "num", "num": 5},
                    {"type": "float", "val": 0.5},
                    {"type": "text", "text": "б"},
                    {"type": "num", "num": 11},
                ],
                [
                    {"type": "num", "num": 5},
                    {"type": "float", "val": 1.0},
                    {"type": "text", "text": ""},
                    {"type": "num", "num": 12},
                ],
            ],
            "col_names": ["Count:num", "Ratio:float", "Text:text", "Output:num"],
            "outputs_from": 3,
            "col_args": [
                {"min": 0, "max": 255},
                {},
                {},
                {"min": 10, "max": 20},
            ],
        }
        result = compress_blocks(dataset)
        self.assertEqual(result["header"]["rows_per_block"], 256)
        self.assertEqual(result["data"][0][0]["blocks"], ["00050505"])
        self.assertEqual(result["data"][0][1]["blocks"], ["00007fff"])
        self.assertEqual(result["data"][0][2]["blocks"], ["006100d0b10000"])
        self.assertEqual(result["data"][1][0]["blocks"], ["00000102"])

    def test_rle_is_selected_only_when_strictly_smaller(self) -> None:
        dataset = {
            "arr": [[{"type": "num", "num": 0}] for _ in range(8)],
            "col_names": ["Value:num"],
            "outputs_from": 1,
            "col_args": [{"min": 0, "max": 1}],
        }
        result = compress_blocks(dataset)
        self.assertEqual(result["data"][0][0]["blocks"], ["01000800"])

    def test_empty_dataset_contract(self) -> None:
        result = compress_blocks({"arr": []})
        self.assertEqual(result["header"]["rows_per_block"], 256)
        self.assertEqual(result["data"], [[], []])

    def test_wide_integer_paths_wrap_like_godot(self) -> None:
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
        result = compress_blocks(dataset)
        self.assertEqual(result["data"][0][0]["blocks"], ["00ffff1170"])
        self.assertEqual(result["data"][0][1]["blocks"], ["010004ff000400"])


if __name__ == "__main__":
    unittest.main()
