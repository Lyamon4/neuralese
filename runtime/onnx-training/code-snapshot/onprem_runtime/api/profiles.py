from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RuntimeProfile:
    mode: str
    storage_dir: Path
    enable_dashboard: bool
    enable_direct_upload: bool
    enable_cloud_registration: bool
    max_parallel_jobs: int
    auth_token: str | None = None

    @classmethod
    def local_school(
        cls,
        *,
        storage_dir: str | Path = ".neuralese_onprem",
        enable_dashboard: bool = True,
        enable_direct_upload: bool = True,
        max_parallel_jobs: int = 1,
        auth_token: str | None = None,
    ) -> "RuntimeProfile":
        return cls(
            mode="local_school",
            storage_dir=Path(storage_dir),
            enable_dashboard=enable_dashboard,
            enable_direct_upload=enable_direct_upload,
            enable_cloud_registration=False,
            max_parallel_jobs=max(1, int(max_parallel_jobs)),
            auth_token=_normalize_auth_token(auth_token),
        )

    @classmethod
    def cloud_node(
        cls,
        *,
        storage_dir: str | Path = ".neuralese_onprem",
        enable_dashboard: bool = False,
        enable_direct_upload: bool = False,
        enable_cloud_registration: bool = True,
        max_parallel_jobs: int = 1,
        auth_token: str | None = None,
    ) -> "RuntimeProfile":
        return cls(
            mode="cloud_node",
            storage_dir=Path(storage_dir),
            enable_dashboard=enable_dashboard,
            enable_direct_upload=enable_direct_upload,
            enable_cloud_registration=enable_cloud_registration,
            max_parallel_jobs=max(1, int(max_parallel_jobs)),
            auth_token=_normalize_auth_token(auth_token),
        )

    @classmethod
    def from_env(cls) -> "RuntimeProfile":
        mode = os.environ.get("NEURALESE_RUNTIME_MODE", "local_school")
        max_parallel_jobs = int(os.environ.get("NEURALESE_MAX_PARALLEL_JOBS", "1"))
        storage_dir = os.environ.get("NEURALESE_STORAGE_DIR", ".neuralese_onprem")
        auth_token = _normalize_auth_token(os.environ.get("NEURALESE_AUTH_TOKEN"))
        if mode == "cloud_node":
            return cls.cloud_node(
                storage_dir=storage_dir,
                max_parallel_jobs=max_parallel_jobs,
                auth_token=auth_token,
            )
        return cls.local_school(
            storage_dir=storage_dir,
            max_parallel_jobs=max_parallel_jobs,
            auth_token=auth_token,
        )


def _normalize_auth_token(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None
