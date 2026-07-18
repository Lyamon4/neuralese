from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class DatasetSyncError(ValueError):
    pass


@dataclass(frozen=True)
class SyncedDataset:
    user_id: str
    dataset_id: str
    header: dict[str, Any]
    hash_algo: str
    fingerprint: str
    packet: dict[str, Any]

    @property
    def rows(self) -> int:
        return int(self.header.get("rows", 0))


@dataclass
class _DatasetEntry:
    header: dict[str, Any] = field(default_factory=dict)
    hash_algo: str = "sha256"
    inputs: list[list[bytes]] = field(default_factory=list)
    outputs: list[list[bytes]] = field(default_factory=list)
    hashes: dict[str, list[list[str]]] = field(
        default_factory=lambda: {"inputs": [], "outputs": []}
    )
    pending_hashes: dict[str, list[list[str]]] = field(
        default_factory=lambda: {"inputs": [], "outputs": []}
    )
    fingerprint: str = ""


class DatasetSyncCache:
    def __init__(self, storage_dir: str | Path | None = None) -> None:
        self._entries: dict[tuple[str, str], _DatasetEntry] = {}
        self._storage_dir = Path(storage_dir) if storage_dir is not None else None
        if self._storage_dir is not None:
            self._storage_dir.mkdir(parents=True, exist_ok=True)
            self._load_persisted_entries()

    def prepare_sync(
        self,
        user_id: str,
        dataset_id: str,
        header: dict[str, Any],
        block_hashes: dict[str, list[list[str]]],
        hash_algo: str = "sha256",
    ) -> dict[str, dict[str, list[int]]]:
        key = (str(user_id), str(dataset_id))
        hash_algo = str(hash_algo or "sha256")
        entry = self._entries.get(key)
        if entry is None or entry.hash_algo != hash_algo:
            entry = _DatasetEntry(hash_algo=hash_algo)
            self._entries[key] = entry

        entry.header = copy.deepcopy(header)
        entry.hash_algo = hash_algo
        entry.pending_hashes = _normalize_hashes(block_hashes)

        need: dict[str, dict[str, list[int]]] = {"inputs": {}, "outputs": {}}
        for side in ("inputs", "outputs"):
            client_columns = entry.pending_hashes[side]
            cached_hashes = entry.hashes[side]
            cached_blocks = getattr(entry, side)
            _resize_side(cached_hashes, cached_blocks, client_columns)

            for col_index, column_hashes in enumerate(client_columns):
                missing: list[int] = []
                for block_index, expected_hash in enumerate(column_hashes):
                    if cached_hashes[col_index][block_index] != expected_hash:
                        missing.append(block_index)
                need[side][str(col_index)] = missing

        return need

    def apply_frames(
        self,
        user_id: str,
        dataset_id: str,
        frames: list[bytes],
    ) -> SyncedDataset:
        entry = self._entries.get((str(user_id), str(dataset_id)))
        if entry is None:
            raise DatasetSyncError("dataset sync was not prepared")

        for frame in frames:
            meta, payload = parse_dataset_frame(frame)
            side = str(meta.get("side", ""))
            if side not in ("inputs", "outputs"):
                raise DatasetSyncError(f"invalid side: {side}")
            col = _non_negative_int(meta.get("col"), "col")
            blk = _non_negative_int(meta.get("blk"), "blk")

            expected_hash = _expected_hash(entry, side, col, blk)
            if entry.hash_algo == "sha256":
                actual_hash = hashlib.sha256(payload).hexdigest()
                if actual_hash != expected_hash:
                    raise DatasetSyncError(
                        f"hash mismatch for {side}[{col}][{blk}]: "
                        f"{actual_hash} != {expected_hash}"
                    )

            blocks = getattr(entry, side)
            _ensure_index(blocks, col, [])
            _ensure_index(blocks[col], blk, b"")
            _ensure_index(entry.hashes[side], col, [])
            _ensure_index(entry.hashes[side][col], blk, "")
            blocks[col][blk] = bytes(payload)
            entry.hashes[side][col][blk] = expected_hash

        entry.fingerprint = _fingerprint(entry)
        self._persist_entry(str(user_id), str(dataset_id), entry)
        return _to_synced_dataset(str(user_id), str(dataset_id), entry)

    def get_synced_dataset(self, user_id: str, dataset_id: str) -> SyncedDataset:
        entry = self._entries.get((str(user_id), str(dataset_id)))
        if entry is None or not entry.fingerprint:
            raise DatasetSyncError("dataset is not synced")
        return _to_synced_dataset(str(user_id), str(dataset_id), entry)

    def cached_fingerprints(self) -> list[str]:
        return sorted(entry.fingerprint for entry in self._entries.values() if entry.fingerprint)

    def _load_persisted_entries(self) -> None:
        if self._storage_dir is None:
            return
        for path in sorted(self._storage_dir.glob("*.json")):
            try:
                user_id, dataset_id, entry = _entry_from_record(
                    json.loads(path.read_text(encoding="utf-8"))
                )
            except Exception:
                continue
            self._entries[(user_id, dataset_id)] = entry

    def _persist_entry(self, user_id: str, dataset_id: str, entry: _DatasetEntry) -> None:
        if self._storage_dir is None or not entry.fingerprint:
            return
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        path = self._entry_path(user_id, dataset_id)
        tmp_path = path.with_suffix(".tmp")
        tmp_path.write_text(
            json.dumps(
                _entry_to_record(user_id, dataset_id, entry),
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        tmp_path.replace(path)

    def _entry_path(self, user_id: str, dataset_id: str) -> Path:
        assert self._storage_dir is not None
        digest = hashlib.sha256(
            json.dumps([user_id, dataset_id], separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        return self._storage_dir / f"{digest}.json"


def build_dataset_frame(side: str, col: int, blk: int, payload: bytes) -> bytes:
    header = json.dumps(
        {"side": side, "col": int(col), "blk": int(blk)},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    if len(header) > 65_535:
        raise DatasetSyncError("frame header is too large")
    return len(header).to_bytes(2, "big") + header + bytes(payload)


def parse_dataset_frame(frame: bytes) -> tuple[dict[str, Any], bytes]:
    if len(frame) < 2:
        raise DatasetSyncError("frame is missing header length")
    header_len = int.from_bytes(frame[:2], "big")
    header_start = 2
    header_end = header_start + header_len
    if header_end > len(frame):
        raise DatasetSyncError("frame header is truncated")
    try:
        meta = json.loads(frame[header_start:header_end].decode("utf-8"))
    except Exception as exc:
        raise DatasetSyncError(f"invalid frame header: {exc}") from exc
    if not isinstance(meta, dict):
        raise DatasetSyncError("frame header must be a JSON object")
    return meta, frame[header_end:]


def _normalize_hashes(block_hashes: dict[str, list[list[str]]]) -> dict[str, list[list[str]]]:
    normalized: dict[str, list[list[str]]] = {"inputs": [], "outputs": []}
    for side in ("inputs", "outputs"):
        columns = block_hashes.get(side, [])
        if not isinstance(columns, list):
            raise DatasetSyncError(f"{side} hashes must be a list")
        normalized[side] = [[str(item) for item in column] for column in columns]
    return normalized


def _entry_to_record(user_id: str, dataset_id: str, entry: _DatasetEntry) -> dict[str, Any]:
    return {
        "version": 1,
        "user_id": user_id,
        "dataset_id": dataset_id,
        "header": entry.header,
        "hash_algo": entry.hash_algo,
        "hashes": entry.hashes,
        "fingerprint": entry.fingerprint,
        "inputs": _encode_block_side(entry.inputs),
        "outputs": _encode_block_side(entry.outputs),
    }


def _entry_from_record(record: dict[str, Any]) -> tuple[str, str, _DatasetEntry]:
    if not isinstance(record, dict) or int(record.get("version", 0)) != 1:
        raise DatasetSyncError("unsupported persisted dataset sync record")
    user_id = str(record.get("user_id") or "")
    dataset_id = str(record.get("dataset_id") or "")
    if not user_id or not dataset_id:
        raise DatasetSyncError("persisted dataset sync record is missing ids")
    hashes = _normalize_hashes(record.get("hashes") or {"inputs": [], "outputs": []})
    entry = _DatasetEntry(
        header=copy.deepcopy(record.get("header") or {}),
        hash_algo=str(record.get("hash_algo") or "sha256"),
        inputs=_decode_block_side(record.get("inputs") or []),
        outputs=_decode_block_side(record.get("outputs") or []),
        hashes=hashes,
        pending_hashes=copy.deepcopy(hashes),
        fingerprint=str(record.get("fingerprint") or ""),
    )
    if not entry.fingerprint:
        raise DatasetSyncError("persisted dataset sync record is missing fingerprint")
    return user_id, dataset_id, entry


def _encode_block_side(blocks: list[list[bytes]]) -> list[list[str]]:
    return [[bytes(block).hex() for block in column] for column in blocks]


def _decode_block_side(blocks: Any) -> list[list[bytes]]:
    if not isinstance(blocks, list):
        raise DatasetSyncError("persisted dataset sync blocks must be a list")
    decoded: list[list[bytes]] = []
    for column in blocks:
        if not isinstance(column, list):
            raise DatasetSyncError("persisted dataset sync column must be a list")
        decoded.append([bytes.fromhex(str(block)) for block in column])
    return decoded


def _resize_side(
    cached_hashes: list[list[str]],
    cached_blocks: list[list[bytes]],
    client_columns: list[list[str]],
) -> None:
    del cached_hashes[len(client_columns) :]
    del cached_blocks[len(client_columns) :]
    while len(cached_hashes) < len(client_columns):
        cached_hashes.append([])
    while len(cached_blocks) < len(client_columns):
        cached_blocks.append([])

    for col_index, column_hashes in enumerate(client_columns):
        del cached_hashes[col_index][len(column_hashes) :]
        del cached_blocks[col_index][len(column_hashes) :]
        while len(cached_hashes[col_index]) < len(column_hashes):
            cached_hashes[col_index].append("")
        while len(cached_blocks[col_index]) < len(column_hashes):
            cached_blocks[col_index].append(b"")


def _expected_hash(entry: _DatasetEntry, side: str, col: int, blk: int) -> str:
    try:
        return entry.pending_hashes[side][col][blk]
    except IndexError as exc:
        raise DatasetSyncError(f"unexpected block: {side}[{col}][{blk}]") from exc


def _non_negative_int(value: Any, name: str) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise DatasetSyncError(f"{name} must be an integer") from exc
    if number < 0:
        raise DatasetSyncError(f"{name} must be >= 0")
    return number


def _ensure_index(items: list, index: int, fill: Any) -> None:
    while len(items) <= index:
        items.append(copy.deepcopy(fill))


def _fingerprint(entry: _DatasetEntry) -> str:
    payload = {
        "header": entry.header,
        "hash_algo": entry.hash_algo,
        "hashes": entry.hashes,
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _to_synced_dataset(user_id: str, dataset_id: str, entry: _DatasetEntry) -> SyncedDataset:
    packet = {
        "header": copy.deepcopy(entry.header),
        "data": [
            [[bytes(block) for block in column] for column in entry.inputs],
            [[bytes(block) for block in column] for column in entry.outputs],
        ],
    }
    return SyncedDataset(
        user_id=user_id,
        dataset_id=dataset_id,
        header=copy.deepcopy(entry.header),
        hash_algo=entry.hash_algo,
        fingerprint=entry.fingerprint,
        packet=packet,
    )
