from __future__ import annotations

import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Any

from sanic.log import logger

from .config import AxonLimitsConfig


DAY_SECONDS = 24 * 60 * 60
HOUR_SECONDS = 60 * 60
FIVE_MINUTES_SECONDS = 5 * 60


@dataclass(frozen=True)
class LimitDecision:
    allowed: bool
    reason: str = ""
    retry_after_seconds: float = 0.0
    detail: dict[str, Any] | None = None


class AxonLimiter:
    def __init__(self, config: AxonLimitsConfig):
        self.config = config
        self._lock = threading.Lock()
        self._user_requests: dict[str, deque[float]] = defaultdict(deque)
        self._global_requests: deque[float] = deque()
        self._user_builds: dict[str, deque[float]] = defaultdict(deque)
        self._global_builds: deque[float] = deque()
        self._global_token_estimates: deque[tuple[float, int]] = deque()

    def check_request(self, account_id: str) -> LimitDecision:
        if not self.config.enabled:
            return LimitDecision(True)
        now = time.time()
        with self._lock:
            self._prune(now)
            if self.config.hard_global_tokens_per_day > 0 and self._tokens_today_locked() >= self.config.hard_global_tokens_per_day:
                return self._deny("global_token_hard_cap", now)
            if len(self._global_requests) >= self.config.global_requests_per_day:
                return self._deny("global_requests_per_day", now, self._global_requests)

            user_requests = self._user_requests[account_id]
            if self._count_since(user_requests, now - DAY_SECONDS) >= self.config.per_user_requests_per_day:
                return self._deny("per_user_requests_per_day", now, user_requests)
            if self._count_since(user_requests, now - HOUR_SECONDS) >= self.config.per_user_requests_per_hour:
                return self._deny("per_user_requests_per_hour", now, user_requests)
            if self._count_since(user_requests, now - FIVE_MINUTES_SECONDS) >= self.config.per_user_requests_per_5_minutes:
                return self._deny("per_user_requests_per_5_minutes", now, user_requests)
            return LimitDecision(True)

    def record_request(self, account_id: str) -> None:
        if not self.config.enabled:
            return
        now = time.time()
        with self._lock:
            self._prune(now)
            self._global_requests.append(now)
            self._user_requests[account_id].append(now)
            logger.info(
                "axon limit record_request account=%s user_day=%d global_day=%d",
                account_id,
                self._count_since(self._user_requests[account_id], now - DAY_SECONDS),
                len(self._global_requests),
            )

    def check_graph_build(self, account_id: str) -> LimitDecision:
        if not self.config.enabled:
            return LimitDecision(True)
        now = time.time()
        with self._lock:
            self._prune(now)
            tokens_today = self._tokens_today_locked()
            if self.config.hard_global_tokens_per_day > 0 and tokens_today >= self.config.hard_global_tokens_per_day:
                return self._deny("global_token_hard_cap", now)
            if self.config.soft_global_tokens_per_day > 0 and tokens_today >= self.config.soft_global_tokens_per_day:
                return self._deny("global_token_soft_cap_builds_paused", now)
            if len(self._global_builds) >= self.config.global_graph_builds_per_day:
                return self._deny("global_graph_builds_per_day", now, self._global_builds)

            user_builds = self._user_builds[account_id]
            if user_builds:
                since_last = now - user_builds[-1]
                if since_last < self.config.graph_build_min_interval_seconds:
                    return LimitDecision(
                        False,
                        "graph_build_min_interval_seconds",
                        self.config.graph_build_min_interval_seconds - since_last,
                        {"since_last": since_last},
                    )
            if self._count_since(user_builds, now - DAY_SECONDS) >= self.config.graph_builds_per_user_per_day:
                return self._deny("graph_builds_per_user_per_day", now, user_builds)
            if self._count_since(user_builds, now - HOUR_SECONDS) >= self.config.graph_builds_per_user_per_hour:
                return self._deny("graph_builds_per_user_per_hour", now, user_builds)
            return LimitDecision(True)

    def record_graph_build(self, account_id: str) -> None:
        if not self.config.enabled:
            return
        now = time.time()
        with self._lock:
            self._prune(now)
            self._global_builds.append(now)
            self._user_builds[account_id].append(now)
            logger.info(
                "axon limit record_graph_build account=%s user_day=%d global_day=%d",
                account_id,
                self._count_since(self._user_builds[account_id], now - DAY_SECONDS),
                len(self._global_builds),
            )

    def record_estimated_tokens(self, account_id: str, tokens: int, *, graph_build_used: bool) -> int:
        if not self.config.enabled:
            return 0
        now = time.time()
        tokens = max(0, int(tokens))
        with self._lock:
            self._prune(now)
            self._global_token_estimates.append((now, tokens))
            total = self._tokens_today_locked()
            logger.info(
                "axon limit record_tokens account=%s estimated=%d total_day=%d graph_build=%s",
                account_id,
                tokens,
                total,
                graph_build_used,
            )
            return total

    def snapshot(self, account_id: str) -> dict[str, Any]:
        now = time.time()
        with self._lock:
            self._prune(now)
            return {
                "enabled": self.config.enabled,
                "account_id": account_id,
                "user_requests_day": self._count_since(self._user_requests[account_id], now - DAY_SECONDS),
                "user_requests_hour": self._count_since(self._user_requests[account_id], now - HOUR_SECONDS),
                "user_requests_5m": self._count_since(self._user_requests[account_id], now - FIVE_MINUTES_SECONDS),
                "global_requests_day": len(self._global_requests),
                "user_builds_day": self._count_since(self._user_builds[account_id], now - DAY_SECONDS),
                "user_builds_hour": self._count_since(self._user_builds[account_id], now - HOUR_SECONDS),
                "global_builds_day": len(self._global_builds),
                "global_estimated_tokens_day": self._tokens_today_locked(),
            }

    def estimate_tokens_from_chars(self, chars: int) -> int:
        return int(max(0, chars) * self.config.estimated_tokens_per_char)

    def _prune(self, now: float) -> None:
        cutoff = now - DAY_SECONDS
        self._prune_deque(self._global_requests, cutoff)
        self._prune_deque(self._global_builds, cutoff)
        self._prune_token_deque(cutoff)
        for requests in list(self._user_requests.values()):
            self._prune_deque(requests, cutoff)
        for builds in list(self._user_builds.values()):
            self._prune_deque(builds, cutoff)

    @staticmethod
    def _prune_deque(values: deque[float], cutoff: float) -> None:
        while values and values[0] < cutoff:
            values.popleft()

    def _prune_token_deque(self, cutoff: float) -> None:
        while self._global_token_estimates and self._global_token_estimates[0][0] < cutoff:
            self._global_token_estimates.popleft()

    @staticmethod
    def _count_since(values: deque[float], cutoff: float) -> int:
        return sum(1 for value in values if value >= cutoff)

    def _tokens_today_locked(self) -> int:
        return sum(tokens for _ts, tokens in self._global_token_estimates)

    def _deny(self, reason: str, now: float, values: deque[float] | None = None) -> LimitDecision:
        retry_after = 0.0
        if values:
            retry_after = max(0.0, DAY_SECONDS - (now - values[0]))
        logger.warning("axon limit denied reason=%s retry_after=%.1f", reason, retry_after)
        return LimitDecision(False, reason, retry_after)
