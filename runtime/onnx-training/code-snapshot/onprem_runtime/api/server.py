from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI

from onprem_runtime.api.app import create_app
from onprem_runtime.api.profiles import RuntimeProfile
from onprem_runtime.core.dataset_compression import decompress_dataset_packet
from onprem_runtime.core.dataset_sync import DatasetSyncCache
from onprem_runtime.core.datasets import (
    DatasetResolver,
    IncrementalLocalDatasetProvider,
    NeuralesePublicDatasetProvider,
    NpzPublicDatasetEngine,
    UploadedDatasetProvider,
)
from onprem_runtime.core.engine import TrainingEngine
from onprem_runtime.core.ort_trainer import OrtBundleTrainer


def build_runtime_app(
    *,
    profile: RuntimeProfile | None = None,
    trainer: Any | None = None,
    dataset_sync: DatasetSyncCache | None = None,
    public_datasets: dict[str, Any] | None = None,
    public_dataset_dir: str | Path | None = None,
) -> FastAPI:
    runtime_profile = profile or RuntimeProfile.from_env()
    runtime_profile.storage_dir.mkdir(parents=True, exist_ok=True)
    dataset_sync_cache = dataset_sync or DatasetSyncCache(runtime_profile.storage_dir / "dataset_sync")
    public_engine = NpzPublicDatasetEngine(_public_dataset_dir(public_dataset_dir))
    runtime_trainer = trainer or OrtBundleTrainer(
        dataset_resolver=DatasetResolver(
            uploaded=UploadedDatasetProvider(),
            public=NeuralesePublicDatasetProvider(public_engine),
            local=IncrementalLocalDatasetProvider(
                dataset_sync_cache,
                decompress_dataset=decompress_dataset_packet,
            ),
        )
    )
    engine = TrainingEngine(runtime_profile.storage_dir, runtime_trainer)
    return create_app(
        engine,
        profile=runtime_profile,
        dataset_sync=dataset_sync_cache,
        public_datasets=public_datasets if public_datasets is not None else public_engine.catalog(),
    )


def _public_dataset_dir(value: str | Path | None) -> Path:
    if value is not None:
        return Path(value)
    env_value = os.environ.get("NEURALESE_PUBLIC_DATASET_DIR")
    if env_value:
        return Path(env_value)
    return Path("local_runtime/datasets")


app = build_runtime_app()
