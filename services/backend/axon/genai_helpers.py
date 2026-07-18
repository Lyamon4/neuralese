from __future__ import annotations

import threading
import time
import traceback
from typing import Any, Callable

from sanic.log import logger

from .model_providers import ModelProvider


Emit = Callable[[dict[str, Any]], None]

FLOOD_MAX_CALLS = 5
FLOOD_MIN_INTERVAL = 1.0
FLOOD_RETRY_DELAY = 10.0

_call_lock = threading.Lock()
_last_call_time = 0.0


def _pace_call() -> None:
    global _last_call_time
    with _call_lock:
        delta = time.time() - _last_call_time
        if delta < FLOOD_MIN_INTERVAL:
            time.sleep(FLOOD_MIN_INTERVAL - delta)
        _last_call_time = time.time()


def run_with_tools(
    *,
    provider: ModelProvider,
    history: list[Any],
    tool_registry: dict[str, Callable],
    emit: Emit,
    should_stop: Callable[[], bool] = lambda: False,
    thinking_budget: int = 0,
    system_text: str = "",
    max_tool_rounds: int = 1,
) -> dict[str, Any]:
    final_text = ""
    rounds = 0
    api_calls = 0
    active_tool_registry = dict(tool_registry)

    try:
        while not should_stop():
            if api_calls >= FLOOD_MAX_CALLS:
                logger.warning(
                    "axon llm flood_guard provider=%s model=%s calls=%d max=%d",
                    provider.provider_name,
                    provider.model_name,
                    api_calls,
                    FLOOD_MAX_CALLS,
                )
                emit({
                    "phase": "error",
                    "error": {
                        "type": "flood_guard",
                        "message": f"Aborted: {FLOOD_MAX_CALLS} LLM calls exceeded",
                    },
                })
                break

            tools_enabled = bool(active_tool_registry)
            _pace_call()
            api_calls += 1
            logger.info(
                "axon llm call provider=%s model=%s call=%d tools_enabled=%s active_tools=%s history_items=%d system_chars=%d",
                provider.provider_name,
                provider.model_name,
                api_calls,
                tools_enabled,
                ",".join(active_tool_registry.keys()),
                len(history),
                len(system_text),
            )

            try:
                round_result = provider.stream_progress(
                    history=history,
                    tool_registry=active_tool_registry,
                    emit=emit,
                    system_text=system_text,
                    thinking_budget=thinking_budget,
                    tools_enabled=tools_enabled,
                    should_stop=should_stop,
                )
            except Exception as exc:
                if "429" in str(exc):
                    logger.warning(
                        "axon llm quota_hit provider=%s model=%s call=%d error=%s",
                        provider.provider_name,
                        provider.model_name,
                        api_calls,
                        str(exc),
                    )
                    emit({"phase": "error", "error": {"type": "quota_hit", "message": str(exc)}})
                    time.sleep(FLOOD_RETRY_DELAY)
                    break
                raise

            final_text += round_result.text
            logger.info(
                "axon llm round_done provider=%s model=%s call=%d text_chars=%d executed_tool=%s",
                provider.provider_name,
                provider.model_name,
                api_calls,
                len(round_result.text),
                round_result.executed_tool,
            )

            if round_result.executed_tool:
                rounds += 1
                if rounds >= max_tool_rounds:
                    logger.info(
                        "axon llm disabling_tools rounds=%d max_tool_rounds=%d",
                        rounds,
                        max_tool_rounds,
                    )
                    active_tool_registry = {}
                continue

            break

    except Exception as exc:
        traceback.print_exc()
        logger.exception(
            "axon llm stream_abort provider=%s model=%s calls=%d",
            provider.provider_name,
            provider.model_name,
            api_calls,
        )
        emit({"phase": "error", "error": {"type": "stream_abort", "message": str(exc)}})
        return {"status": "error", "text": final_text}

    logger.info(
        "axon llm complete provider=%s model=%s calls=%d text_chars=%d stopped=%s",
        provider.provider_name,
        provider.model_name,
        api_calls,
        len(final_text),
        should_stop(),
    )
    return {"status": "ok", "text": final_text}
