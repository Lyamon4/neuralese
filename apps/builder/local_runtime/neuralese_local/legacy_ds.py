from __future__ import annotations

import io
import json
import os
import struct
import sys
from pathlib import Path
from typing import Iterator, Tuple

import lmdb
import numpy as np


def _bytes_to_nd(blob: bytes) -> np.ndarray:
    return np.load(io.BytesIO(blob), allow_pickle=False)


def unpack_pair(blob: bytes) -> Tuple[np.ndarray, np.ndarray]:
    offset = 0
    x_len = struct.unpack(">I", blob[offset:offset + 4])[0]
    offset += 4
    x_blob = blob[offset:offset + x_len]
    offset += x_len
    y_len = struct.unpack(">I", blob[offset:offset + 4])[0]
    offset += 4
    y_blob = blob[offset:offset + y_len]
    return _bytes_to_nd(x_blob), _bytes_to_nd(y_blob)


class LegacyDsIterable:
    """Reader for the old single-file LMDB `.ds` dataset format."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.env = lmdb.open(
            str(self.path),
            readonly=True,
            lock=False,
            subdir=False,
            readahead=True,
            max_readers=512,
            map_size=os.path.getsize(self.path),
        )

        with self.env.begin(write=False) as txn:
            raw = txn.get(b"__len__")
            self._len = 0 if raw is None else struct.unpack(">Q", raw)[0]

    def __len__(self) -> int:
        return int(self._len)

    def __iter__(self) -> Iterator[Tuple[np.ndarray, np.ndarray]]:
        with self.env.begin(write=False) as txn:
            for i in range(self._len):
                key = f"{i:016d}".encode("ascii")
                value = txn.get(key)
                if value is None:
                    raise RuntimeError(f"Dataset corrupted at index {i}: {self.path}")
                yield unpack_pair(value)

    def close(self) -> None:
        self.env.close()


def load_legacy_ds(path: str | Path) -> Tuple[np.ndarray, np.ndarray]:
    ds = LegacyDsIterable(path)
    try:
        if len(ds) <= 0:
            raise RuntimeError(f"Dataset empty: {path}")
        xs = []
        ys = []
        for x, y in ds:
            xs.append(np.asarray(x))
            ys.append(np.asarray(y))
        return np.stack(xs).astype(np.float32), np.stack(ys)
    finally:
        ds.close()


def convert_dataset(src_dir: str | Path, dst_dir: str | Path) -> None:
    src = Path(src_dir)
    dst = Path(dst_dir)
    dst.mkdir(parents=True, exist_ok=True)

    train_x, train_y = load_legacy_ds(src / "train.ds")
    test_x = test_y = None
    if (src / "test.ds").exists():
        test_x, test_y = load_legacy_ds(src / "test.ds")

    npz_path = dst / "train.npz"
    if test_x is not None and test_y is not None:
        np.savez_compressed(npz_path, x=train_x, y=train_y, val_x=test_x, val_y=test_y)
    else:
        np.savez_compressed(npz_path, x=train_x, y=train_y)

    pub_path = src / ".pub"
    meta = {}
    if pub_path.exists():
        with pub_path.open("r", encoding="utf-8") as f:
            meta = json.load(f)

    meta.setdefault("name", src.name)
    meta["size"] = int(train_x.shape[0])
    meta["fully_local"] = True
    meta["storage"] = "numpy"
    meta["source_format"] = "legacy_lmdb_ds"

    with (dst / "meta.json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")

    print(
        json.dumps(
            {
                "dst": str(dst),
                "train_x": list(train_x.shape),
                "train_y": list(train_y.shape),
                "val_x": None if test_x is None else list(test_x.shape),
                "val_y": None if test_y is None else list(test_y.shape),
                "npz": str(npz_path),
            },
            indent=2,
        )
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: legacy_ds.py <source_dataset_dir> <destination_dataset_dir>", file=sys.stderr)
        return 2
    convert_dataset(argv[1], argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
