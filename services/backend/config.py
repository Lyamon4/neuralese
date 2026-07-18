from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    db_path: Path
    auth_public_base_url: str
    clerk_publishable_key: str
    clerk_secret_key: str
    clerk_handoff_secret: str
    jwt_secret: str
    jwt_issuer: str
    jwt_audience: str
    access_token_ttl_seconds: int
    refresh_token_ttl_seconds: int
    gumroad_product_permalink: str
    gumroad_product_id: str
    gumroad_product_url: str
    gumroad_ping_secret: str
    dev_shared_secret: str
    datasets_dir: Path
    axon_api_key: str

    @classmethod
    def from_env(cls) -> "Settings":
        root = Path(__file__).resolve().parent
        data_dir = Path(env("NEURALESE_DATA_DIR", str(root / "data"))).resolve()
        return cls(
            data_dir=data_dir,
            db_path=Path(env("NEURALESE_DB_PATH", str(data_dir / "userdata.db"))).resolve(),
            auth_public_base_url=env("AUTH_PUBLIC_BASE_URL", "http://127.0.0.1:8081/auth"),
            clerk_publishable_key=env("NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY", env("CLERK_PUBLISHABLE_KEY")),
            clerk_secret_key=env("CLERK_SECRET_KEY"),
            clerk_handoff_secret=env("CLERK_HANDOFF_SECRET", "dev_clerk_handoff_secret_change_me"),
            jwt_secret=env("NEURALESE_JWT_SECRET", env("DEV_SHARED_SECRET", "dev_local_neuralese_jwt_secret_change_me_64_bytes_minimum_for_hs256")),
            jwt_issuer=env("NEURALESE_JWT_ISSUER", "neuralese-auth"),
            jwt_audience=env("NEURALESE_JWT_AUDIENCE", "neuralese-client"),
            access_token_ttl_seconds=int(env("NEURALESE_ACCESS_TOKEN_TTL_SECONDS", "28800")),
            refresh_token_ttl_seconds=int(env("NEURALESE_REFRESH_TOKEN_TTL_SECONDS", "2592000")),
            gumroad_product_permalink=env("GUMROAD_PRODUCT_PERMALINK"),
            gumroad_product_id=env("GUMROAD_PRODUCT_ID"),
            gumroad_product_url=env("GUMROAD_PRODUCT_URL"),
            gumroad_ping_secret=env("GUMROAD_PING_SECRET"),
            dev_shared_secret=env("DEV_SHARED_SECRET", "dev_neuralese_secret_change_me"),
            datasets_dir=Path(env("NEURALESE_DATASETS_DIR", str(root / "data" / "datasets"))).resolve(),
            axon_api_key=env("API_KEY", env("GOOGLE_API_KEY")),
        )
