from __future__ import annotations

import time
import traceback
from typing import Any, Callable
from sanic.log import logger

from .config import load_axon_config
from .genai_helpers import run_with_tools
from .graph_summary import summarize_graph
from .limits import AxonLimiter
from .model_providers import ModelProvider, create_model_provider
from .prompts import get_builder_prompt, get_digit_2_conv_graph, get_filtered_node_docs, get_start_prompt


Emit = Callable[[dict[str, Any]], None]


def world_state(what: Any) -> str:
    return f"### WORLD STATE\nWhat follows is **current, live** world state:\n```{what}```\n\n"


def _safe_json(value: Any) -> str:
    import json

    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    except Exception:
        return str(value)


def _graph_is_empty(summary: dict[str, Any] | None) -> bool:
    if not isinstance(summary, dict):
        return True
    nodes = summary.get("nodes") or {}
    return not isinstance(nodes, dict) or len(nodes) == 0


def _node_count(summary: dict[str, Any] | None) -> int:
    if not isinstance(summary, dict):
        return 0
    nodes = summary.get("nodes") or {}
    return len(nodes) if isinstance(nodes, dict) else 0


def _edge_count(summary: dict[str, Any] | None) -> int:
    if not isinstance(summary, dict):
        return 0
    edges = summary.get("edges") or []
    return len(edges) if isinstance(edges, list) else 0


def _safe_label(value: Any, max_len: int = 120) -> str:
    text = str(value or "").replace("\n", " ").replace("\r", " ").strip()
    if len(text) > max_len:
        return text[:max_len] + "..."
    return text


def _content_chars(content: list[Any]) -> int:
    total = 0
    for item in content:
        if isinstance(item, dict):
            total += len(str(item.get("content", "")))
        else:
            total += len(str(item))
    return total


class AxonService:
    def __init__(self, settings):
        self.settings = settings
        self.config = load_axon_config()
        self.limiter = AxonLimiter(self.config.limits)
        self.provider: ModelProvider = create_model_provider(settings, provider_name=self.config.model_provider)
        logger.info(
            "axon service initialized provider=%s model=%s",
            self.provider.provider_name,
            self.provider.model_name,
        )

    def build_content(self, messages: list[dict[str, Any]]) -> list[Any]:
        return self.provider.build_content(messages)

    def run_talk(
        self,
        *,
        content: list,
        summary: dict[str, Any] | None,
        emit: Emit,
        should_stop: Callable[[], bool],
        account_id: str = "",
        system: str | None = None,
        builder: str | None = None,
    ) -> dict[str, Any]:
        result = {
            "status": "error",
            "text": "",
            "func_called": False,
            "graph_build_used": False,
            "estimated_tokens": 0,
        }
        summary = summary or {"nodes": {}, "edges": {}}

        try:
            system_text = system or get_start_prompt()
            builder_text = (builder or get_builder_prompt()) + world_state(summary)
            context_flags = {
                "graph_summary_loaded": False,
                "full_graph_scene_loaded": False,
                "node_docs_loaded": False,
            }
            retrieval_stats = {
                "graph_summary_chars": 0,
                "full_graph_scene_chars": 0,
                "node_docs_chars": 0,
                "builder_prompt_chars": 0,
            }

            def emit_wrapper(payload: dict[str, Any]) -> None:
                if should_stop():
                    return
                if payload.get("phase") == "text":
                    result["text"] += str(payload.get("text", ""))
                emit(payload)

            builder_debounce = {"pending_plan": None}
            auto_debounce = {"pending": ""}

            def get_current_graph_summary() -> str:
                """Read-only. Return a concise summary of the current Neuralese graph. Use for questions about the current graph/model/canvas/topology/layers/connections before answering."""
                context_flags["graph_summary_loaded"] = True
                text = summarize_graph(summary)
                retrieval_stats["graph_summary_chars"] += len(text)
                logger.info(
                    "axon retrieval graph_summary account=%s chars=%d nodes=%d edges=%d",
                    account_id,
                    len(text),
                    _node_count(summary),
                    _edge_count(summary),
                )
                return text

            def get_current_graph_scene() -> str:
                """Read-only. Return the exact serialized current graph scene as JSON. Use only when summary is insufficient for precise topology, ambiguous placement, or modification planning."""
                context_flags["full_graph_scene_loaded"] = True
                text = _safe_json(summary)
                retrieval_stats["full_graph_scene_chars"] += len(text)
                logger.info(
                    "axon retrieval full_graph_scene account=%s chars=%d nodes=%d edges=%d",
                    account_id,
                    len(text),
                    _node_count(summary),
                    _edge_count(summary),
                )
                return text

            def full_node_docs(node_types: str = "") -> str:
                """Read-only. Return detailed Neuralese node docs for requested node types such as 'dropout,dense_layer'. Use for node behavior, ports, config, valid connections, or graph validity questions. Empty returns all docs, but prefer specific node types."""
                context_flags["node_docs_loaded"] = True
                text = get_filtered_node_docs(node_types)
                retrieval_stats["node_docs_chars"] += len(text)
                logger.info(
                    "axon retrieval node_docs account=%s requested=%s chars=%d",
                    account_id,
                    _safe_label(node_types),
                    len(text),
                )
                return text

            def build_graph(plan: str):
                """Mutation tool. Delegate graph construction or graph edits to Builder. Use only for explicit user commands to modify/build now. The plan must be semantic, concise, and specific, not raw JSON."""
                if should_stop():
                    return {"status": "aborted"}
                if result["func_called"]:
                    return {"status": "already_called"}
                decision = self.limiter.check_graph_build(account_id or "anonymous")
                if not decision.allowed:
                    logger.warning(
                        "axon build denied account=%s reason=%s retry_after=%.1f",
                        account_id,
                        decision.reason,
                        decision.retry_after_seconds,
                    )
                    return {
                        "status": "rate_limited",
                        "reason": decision.reason,
                        "retry_after_seconds": decision.retry_after_seconds,
                    }
                self.limiter.record_graph_build(account_id or "anonymous")
                result["func_called"] = True
                result["graph_build_used"] = True
                builder_debounce["pending_plan"] = plan
                logger.info("axon build accepted account=%s plan_chars=%d", account_id, len(str(plan)))
                return {"status": "Build complete!"}

            def build_graph_digit_2_conv():
                """Mutation tool. Build the complete two-conv MNIST-style classifier from scratch. Use only for an explicit matching build command and only when the current canvas is empty."""
                if should_stop():
                    return {"status": "aborted"}
                if not _graph_is_empty(summary):
                    return {"status": "not_empty", "message": "Specialized builders only run on an empty canvas; use build_graph(plan) for incremental edits."}
                if result["func_called"]:
                    return {"status": "already_called"}
                decision = self.limiter.check_graph_build(account_id or "anonymous")
                if not decision.allowed:
                    logger.warning(
                        "axon specialized build denied account=%s reason=%s retry_after=%.1f",
                        account_id,
                        decision.reason,
                        decision.retry_after_seconds,
                    )
                    return {
                        "status": "rate_limited",
                        "reason": decision.reason,
                        "retry_after_seconds": decision.retry_after_seconds,
                    }
                self.limiter.record_graph_build(account_id or "anonymous")
                result["func_called"] = True
                result["graph_build_used"] = True
                auto_debounce["pending"] = get_digit_2_conv_graph()
                logger.info("axon specialized build accepted account=%s tool=build_graph_digit_2_conv", account_id)
                return {"status": "Build complete!"}

            tool_registry = {
                "get_current_graph_summary": get_current_graph_summary,
                "get_current_graph_scene": get_current_graph_scene,
                "full_node_docs": full_node_docs,
                "build_graph": build_graph,
                "build_graph_digit_2_conv": build_graph_digit_2_conv,
            }

            logger.info(
                "axon prompt compact_chars=%d provider=%s model=%s tools=%s account=%s",
                len(system_text),
                self.provider.provider_name,
                self.provider.model_name,
                ",".join(tool_registry.keys()),
                account_id,
            )

            run_with_tools(
                provider=self.provider,
                history=content,
                tool_registry=tool_registry,
                emit=emit_wrapper,
                system_text=system_text,
                max_tool_rounds=5,
                should_stop=should_stop,
            )

            if builder_debounce["pending_plan"] and not should_stop():
                plan = builder_debounce["pending_plan"]
                retrieval_stats["builder_prompt_chars"] = len(builder_text)
                logger.info(
                    "axon builder start account=%s builder_prompt_chars=%d plan_chars=%d",
                    account_id,
                    len(builder_text),
                    len(str(plan)),
                )
                run_with_tools(
                    provider=self.provider,
                    history=[
                        self.provider.user_content(f"PLAN: {plan}"),
                        self.provider.user_content("BUILDER:"),
                    ],
                    tool_registry={},
                    emit=emit_wrapper,
                    system_text=builder_text,
                    should_stop=should_stop,
                )

            if auto_debounce["pending"] and not should_stop():
                emit_wrapper({"phase": "text", "text": auto_debounce["pending"]})
                time.sleep(0.1)

            result["status"] = "stopped" if should_stop() else "ok"
            result.update(context_flags)
            estimated_chars = (
                len(system_text)
                + _content_chars(content)
                + len(result["text"])
                + retrieval_stats["graph_summary_chars"]
                + retrieval_stats["full_graph_scene_chars"]
                + retrieval_stats["node_docs_chars"]
                + retrieval_stats["builder_prompt_chars"]
            )
            result["estimated_tokens"] = self.limiter.estimate_tokens_from_chars(estimated_chars)
            logger.info(
                "axon context account=%s graph_summary=%s full_scene=%s node_docs=%s graph_build=%s estimated_chars=%d estimated_tokens=%d retrieval=%s",
                account_id,
                context_flags["graph_summary_loaded"],
                context_flags["full_graph_scene_loaded"],
                context_flags["node_docs_loaded"],
                result.get("graph_build_used", False),
                estimated_chars,
                result["estimated_tokens"],
                retrieval_stats,
            )

        except Exception as exc:
            traceback.print_exc()
            emit({"phase": "error", "error": {"type": "AxonError", "message": str(exc)}})
            result["status"] = "error"
        finally:
            if result["text"].count("</thinking>") != result["text"].count("<thinking>"):
                emit({"phase": "text", "text": "</thinking>"})
                result["text"] += "</thinking>"
            emit({"phase": "end", "text": ""})

        return result

    def run_once(
        self,
        *,
        text: str,
        emit: Emit,
        should_stop: Callable[[], bool],
    ) -> dict[str, Any]:
        result = {"status": "error", "text": ""}

        def emit_wrapper(payload: dict[str, Any]) -> None:
            if should_stop():
                return
            if payload.get("phase") == "text":
                result["text"] += str(payload.get("text", ""))
            emit(payload)

        try:
            content = [self.provider.user_content(text)]
            run_with_tools(
                provider=self.provider,
                history=content,
                tool_registry={},
                emit=emit_wrapper,
                system_text="You are a concise AI assistant.",
                should_stop=should_stop,
            )
            result["status"] = "stopped" if should_stop() else "ok"
        except Exception as exc:
            traceback.print_exc()
            emit({"phase": "error", "error": {"type": "AxonError", "message": str(exc)}})
            result["status"] = "error"
        return result
