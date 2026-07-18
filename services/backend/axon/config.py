from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sanic.log import logger


AXON_CONFIG_PATH = Path(__file__).resolve().parents[1] / "axon_config.json"


@dataclass(frozen=True)
class AxonLimitsConfig:
    enabled: bool = True
    per_user_requests_per_day: int = 40
    per_user_requests_per_hour: int = 20
    per_user_requests_per_5_minutes: int = 6
    global_requests_per_day: int = 1500
    graph_builds_per_user_per_day: int = 8
    graph_builds_per_user_per_hour: int = 4
    graph_build_min_interval_seconds: float = 30.0
    global_graph_builds_per_day: int = 250
    soft_global_tokens_per_day: int = 10_000_000
    hard_global_tokens_per_day: int = 20_000_000
    max_user_message_chars: int = 4000
    max_retained_chat_messages: int = 12
    estimated_tokens_per_char: float = 0.25


@dataclass(frozen=True)
class AxonLoggingConfig:
    retrieval_debug: bool = True


@dataclass(frozen=True)
class AxonConfig:
    model_provider: str = "deepseek"
    limits: AxonLimitsConfig = AxonLimitsConfig()
    logging: AxonLoggingConfig = AxonLoggingConfig()


def load_axon_config(path: Path = AXON_CONFIG_PATH) -> AxonConfig:
    if not path.exists():
        logger.warning("axon config missing path=%s; using defaults", path)
        return AxonConfig()

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.warning("axon config invalid path=%s error=%s; using defaults", path, exc)
        return AxonConfig()

    if not isinstance(raw, dict):
        logger.warning("axon config root is not an object path=%s; using defaults", path)
        return AxonConfig()

    limits_raw = raw.get("limits") if isinstance(raw.get("limits"), dict) else {}
    logging_raw = raw.get("logging") if isinstance(raw.get("logging"), dict) else {}

    config = AxonConfig(
        model_provider=str(raw.get("model_provider") or "deepseek").strip().lower(),
        limits=_limits_from_dict(limits_raw),
        logging=AxonLoggingConfig(
            retrieval_debug=_bool(logging_raw.get("retrieval_debug"), True),
        ),
    )
    logger.info(
        "axon config loaded path=%s provider=%s limits_enabled=%s",
        path,
        config.model_provider,
        config.limits.enabled,
    )
    return config


def _limits_from_dict(raw: dict[str, Any]) -> AxonLimitsConfig:
    return AxonLimitsConfig(
        enabled=_bool(raw.get("enabled"), True),
        per_user_requests_per_day=_int(raw.get("per_user_requests_per_day"), 40),
        per_user_requests_per_hour=_int(raw.get("per_user_requests_per_hour"), 20),
        per_user_requests_per_5_minutes=_int(raw.get("per_user_requests_per_5_minutes"), 6),
        global_requests_per_day=_int(raw.get("global_requests_per_day"), 1500),
        graph_builds_per_user_per_day=_int(raw.get("graph_builds_per_user_per_day"), 8),
        graph_builds_per_user_per_hour=_int(raw.get("graph_builds_per_user_per_hour"), 4),
        graph_build_min_interval_seconds=_float(raw.get("graph_build_min_interval_seconds"), 30.0),
        global_graph_builds_per_day=_int(raw.get("global_graph_builds_per_day"), 250),
        soft_global_tokens_per_day=_int(raw.get("soft_global_tokens_per_day"), 10_000_000),
        hard_global_tokens_per_day=_int(raw.get("hard_global_tokens_per_day"), 20_000_000),
        max_user_message_chars=_int(raw.get("max_user_message_chars"), 4000),
        max_retained_chat_messages=_int(raw.get("max_retained_chat_messages"), 12),
        estimated_tokens_per_char=_float(raw.get("estimated_tokens_per_char"), 0.25),
    )


def _bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _int(value: Any, default: int) -> int:
    try:
        return max(0, int(value))
    except Exception:
        return default


def _float(value: Any, default: float) -> float:
    try:
        return max(0.0, float(value))
    except Exception:
        return default
