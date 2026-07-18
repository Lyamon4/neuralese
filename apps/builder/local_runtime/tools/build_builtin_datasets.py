from __future__ import annotations

import csv
import gzip
import struct
import urllib.request
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1] / "datasets"


def _download(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def _read_mnist_images(blob: bytes) -> np.ndarray:
    raw = gzip.decompress(blob)
    magic, count, rows, cols = struct.unpack(">IIII", raw[:16])
    if magic != 2051:
        raise ValueError(f"Unexpected MNIST image magic: {magic}")
    arr = np.frombuffer(raw, dtype=np.uint8, offset=16)
    arr = arr.reshape(count, 1, rows, cols).astype(np.float32) / 255.0
    return arr


def _read_mnist_labels(blob: bytes) -> np.ndarray:
    raw = gzip.decompress(blob)
    magic, count = struct.unpack(">II", raw[:8])
    if magic != 2049:
        raise ValueError(f"Unexpected MNIST label magic: {magic}")
    return np.frombuffer(raw, dtype=np.uint8, offset=8).astype(np.int64)


def build_mnist() -> None:
    base = ROOT / "mnist"
    base.mkdir(parents=True, exist_ok=True)
    host = "https://storage.googleapis.com/cvdf-datasets/mnist"
    train_x = _read_mnist_images(_download(f"{host}/train-images-idx3-ubyte.gz"))
    train_y = _read_mnist_labels(_download(f"{host}/train-labels-idx1-ubyte.gz"))
    test_x = _read_mnist_images(_download(f"{host}/t10k-images-idx3-ubyte.gz"))
    test_y = _read_mnist_labels(_download(f"{host}/t10k-labels-idx1-ubyte.gz"))
    np.savez_compressed(base / "train.npz", x=train_x, y=train_y, val_x=test_x, val_y=test_y)


def build_iris() -> None:
    base = ROOT / "iris"
    base.mkdir(parents=True, exist_ok=True)
    url = "https://archive.ics.uci.edu/ml/machine-learning-databases/iris/iris.data"
    rows = []
    labels = []
    label_map = {"Iris-setosa": 0, "Iris-versicolor": 1, "Iris-virginica": 2}
    for row in csv.reader(_download(url).decode("utf-8").splitlines()):
        if len(row) != 5:
            continue
        rows.append([float(v) for v in row[:4]])
        labels.append(label_map[row[4]])
    x = np.asarray(rows, dtype=np.float32)
    y = np.asarray(labels, dtype=np.int64)
    rng = np.random.default_rng(42)
    order = rng.permutation(len(x))
    split = int(len(x) * 0.8)
    train_idx, val_idx = order[:split], order[split:]
    np.savez_compressed(base / "train.npz", x=x[train_idx], y=y[train_idx], val_x=x[val_idx], val_y=y[val_idx])


def build_titanic() -> None:
    base = ROOT / "titanic"
    base.mkdir(parents=True, exist_ok=True)
    url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/titanic.csv"
    reader = csv.DictReader(_download(url).decode("utf-8").splitlines())
    rows = []
    labels = []
    for row in reader:
        try:
            sex = 1.0 if row["sex"] == "male" else 0.0
            embarked = {"C": 0.0, "Q": 1.0, "S": 2.0}.get(row.get("embarked", ""), 0.0)
            age = float(row["age"]) if row["age"] else 29.7
            fare = float(row["fare"]) if row["fare"] else 0.0
            rows.append([
                float(row["pclass"]),
                sex,
                age / 80.0,
                float(row["sibsp"]),
                float(row["parch"]),
                fare / 512.0,
                embarked,
                1.0 if row.get("alone") == "True" else 0.0,
            ])
            labels.append(int(row["survived"]))
        except Exception:
            continue
    x = np.asarray(rows, dtype=np.float32)
    y = np.asarray(labels, dtype=np.int64)
    rng = np.random.default_rng(42)
    order = rng.permutation(len(x))
    split = int(len(x) * 0.8)
    train_idx, val_idx = order[:split], order[split:]
    np.savez_compressed(base / "train.npz", x=x[train_idx], y=y[train_idx], val_x=x[val_idx], val_y=y[val_idx])


def main() -> None:
    build_mnist()
    build_iris()
    build_titanic()
    print(f"Datasets written under {ROOT}")


if __name__ == "__main__":
    main()

