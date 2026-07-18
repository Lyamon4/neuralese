from __future__ import annotations

import hashlib

import pytest

from onprem_runtime.core.dataset_sync import (
    DatasetSyncCache,
    DatasetSyncError,
    build_dataset_frame,
)


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _header() -> dict:
    return {
        "rows": 2,
        "inputs_count": 1,
        "outputs_count": 1,
        "columns": {
            "0": {"dtype": "num", "min": 0, "max": 255, "bits": 8},
            "1": {"dtype": "num", "min": 0, "max": 10, "bits": 8},
        },
        "rows_per_block": 256,
        "dirty_from": -1,
    }


def test_prepare_sync_requests_all_blocks_when_cache_is_empty() -> None:
    cache = DatasetSyncCache()
    hashes = {
        "inputs": [[_hash(b"input-0"), _hash(b"input-1")]],
        "outputs": [[_hash(b"output-0")]],
    }

    need = cache.prepare_sync(
        user_id="teacher",
        dataset_id="local-digits",
        header=_header(),
        block_hashes=hashes,
        hash_algo="sha256",
    )

    assert need == {"inputs": {"0": [0, 1]}, "outputs": {"0": [0]}}


def test_apply_frames_updates_cache_and_repeated_sync_needs_nothing() -> None:
    cache = DatasetSyncCache()
    input_payload = b"\x00\x01\x02"
    output_payload = b"\x00\x00"
    hashes = {
        "inputs": [[_hash(input_payload)]],
        "outputs": [[_hash(output_payload)]],
    }
    header = _header()
    cache.prepare_sync("teacher", "local-digits", header, hashes, hash_algo="sha256")

    synced = cache.apply_frames(
        "teacher",
        "local-digits",
        [
            build_dataset_frame("inputs", 0, 0, input_payload),
            build_dataset_frame("outputs", 0, 0, output_payload),
        ],
    )
    need_after = cache.prepare_sync("teacher", "local-digits", header, hashes, hash_algo="sha256")

    assert synced.user_id == "teacher"
    assert synced.dataset_id == "local-digits"
    assert synced.rows == 2
    assert synced.fingerprint.startswith("sha256:")
    assert synced.packet == {"header": header, "data": [[[input_payload]], [[output_payload]]]}
    assert need_after == {"inputs": {"0": []}, "outputs": {"0": []}}
    assert cache.get_synced_dataset("teacher", "local-digits").fingerprint == synced.fingerprint


def test_prepare_sync_requests_only_changed_blocks() -> None:
    cache = DatasetSyncCache()
    header = _header()
    old_a = b"a"
    old_b = b"b"
    old_y = b"y"
    old_hashes = {"inputs": [[_hash(old_a), _hash(old_b)]], "outputs": [[_hash(old_y)]]}
    cache.prepare_sync("teacher", "local-digits", header, old_hashes, hash_algo="sha256")
    cache.apply_frames(
        "teacher",
        "local-digits",
        [
            build_dataset_frame("inputs", 0, 0, old_a),
            build_dataset_frame("inputs", 0, 1, old_b),
            build_dataset_frame("outputs", 0, 0, old_y),
        ],
    )

    new_hashes = {"inputs": [[_hash(old_a), _hash(b"new-b")]], "outputs": [[_hash(old_y)]]}
    need = cache.prepare_sync(
        "teacher",
        "local-digits",
        header,
        new_hashes,
        hash_algo="sha256",
    )

    assert need == {"inputs": {"0": [1]}, "outputs": {"0": []}}


def test_persistent_cache_restores_synced_dataset_after_restart(tmp_path) -> None:
    storage_dir = tmp_path / "dataset-sync"
    cache = DatasetSyncCache(storage_dir=storage_dir)
    header = _header()
    input_payload = b"\x00\x01"
    output_payload = b"\x00\x00"
    hashes = {"inputs": [[_hash(input_payload)]], "outputs": [[_hash(output_payload)]]}
    cache.prepare_sync("teacher", "local-digits", header, hashes, hash_algo="sha256")
    synced = cache.apply_frames(
        "teacher",
        "local-digits",
        [
            build_dataset_frame("inputs", 0, 0, input_payload),
            build_dataset_frame("outputs", 0, 0, output_payload),
        ],
    )

    restored = DatasetSyncCache(storage_dir=storage_dir)
    restored_synced = restored.get_synced_dataset("teacher", "local-digits")
    need_after_restart = restored.prepare_sync(
        "teacher",
        "local-digits",
        header,
        hashes,
        hash_algo="sha256",
    )

    assert restored_synced.fingerprint == synced.fingerprint
    assert restored_synced.packet == synced.packet
    assert restored.cached_fingerprints() == [synced.fingerprint]
    assert need_after_restart == {"inputs": {"0": []}, "outputs": {"0": []}}


def test_apply_frames_rejects_payload_that_does_not_match_sha256_hash() -> None:
    cache = DatasetSyncCache()
    hashes = {"inputs": [["not-the-real-hash"]], "outputs": []}
    cache.prepare_sync("teacher", "local-digits", _header(), hashes, hash_algo="sha256")

    with pytest.raises(DatasetSyncError, match="hash mismatch"):
        cache.apply_frames(
            "teacher",
            "local-digits",
            [build_dataset_frame("inputs", 0, 0, b"payload")],
        )


def test_apply_frames_rejects_invalid_frame_side() -> None:
    cache = DatasetSyncCache()
    hashes = {"inputs": [[_hash(b"payload")]], "outputs": []}
    cache.prepare_sync("teacher", "local-digits", _header(), hashes, hash_algo="sha256")

    with pytest.raises(DatasetSyncError, match="invalid side"):
        cache.apply_frames(
            "teacher",
            "local-digits",
            [build_dataset_frame("wrong", 0, 0, b"payload")],
        )
