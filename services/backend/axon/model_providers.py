from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any, Callable, Protocol

from sanic.log import logger

from . import model_api


Emit = Callable[[dict[str, Any]], None]


@dataclass(frozen=True)
class StreamRoundResult:
    text: str = ""
    executed_tool: bool = False


class ModelProvider(Protocol):
    provider_name: str
    model_name: str

    def build_content(self, messages: list[dict[str, Any]]) -> list[Any]: ...

    def user_content(self, text: str) -> Any: ...

    def stream_progress(
        self,
        *,
        history: list[Any],
        tool_registry: dict[str, Callable],
        emit: Emit,
        system_text: str,
        thinking_budget: int,
        tools_enabled: bool,
        should_stop: Callable[[], bool],
    ) -> StreamRoundResult: ...


class GoogleGenAIProvider:
    provider_name = "google-genai"
    DEFAULT_MODEL = "gemini-2.5-flash"
    SETTINGS_API_KEY = "axon_api_key"
    SETTINGS_MODEL = "axon_google_model"
    ENV_API_KEY = "AXON_API_KEY"
    ENV_MODEL = "AXON_GOOGLE_MODEL"

    def __init__(self, settings: Any | None = None, *, api_key: str | None = None, model: str | None = None):
        self.api_key = self._resolve_value(settings, self.SETTINGS_API_KEY, self.ENV_API_KEY, api_key, allow_missing=True)
        self.model_name = self._resolve_value(settings, self.SETTINGS_MODEL, self.ENV_MODEL, model, self.DEFAULT_MODEL)
        self._client: Any | None = None

    @staticmethod
    def _resolve_value(
        settings: Any | None,
        setting_name: str,
        env_name: str,
        override: str | None,
        default: str | None = None,
        allow_missing: bool = False,
    ) -> str:
        value = override
        if value is None and settings is not None:
            value = getattr(settings, setting_name, None)
        if value is None:
            value = os.environ.get(env_name)
        if value is None:
            value = default
        if not value:
            if allow_missing:
                return ""
            raise RuntimeError(f"missing {setting_name}; configure it in {self_name(GoogleGenAIProvider)}")
        return str(value)

    @property
    def client(self) -> Any:
        if not self.api_key:
            raise RuntimeError(f"missing {self.SETTINGS_API_KEY}; configure it in {self_name(GoogleGenAIProvider)}")
        if self._client is None:
            self._client = model_api.create_google_genai_client(api_key=self.api_key)
        return self._client

    def build_content(self, messages: list[dict[str, Any]]) -> list[Any]:
        content: list[Any] = []
        for message in messages:
            text = str(message.get("text", ""))
            if not text.strip():
                continue
            role = str(message.get("role", "user"))
            if role == "assistant":
                role = "model"
            content.append(model_api.google_text_content(role=role, text=text))
        return content

    def user_content(self, text: str) -> Any:
        return model_api.google_user_content(text)

    def stream_progress(
        self,
        *,
        history: list[Any],
        tool_registry: dict[str, Callable],
        emit: Emit,
        system_text: str,
        thinking_budget: int,
        tools_enabled: bool,
        should_stop: Callable[[], bool],
    ) -> StreamRoundResult:
        tools = model_api.google_function_tools(client=self.client, funcs=tool_registry.values())
        active_tools = tools_enabled and bool(tool_registry) and bool(tools)
        stream = model_api.google_generate_content_stream(
            client=self.client,
            model=self.model_name,
            history=history,
            tools=tools,
            tools_enabled=active_tools,
            system_text=system_text,
            thinking_budget=thinking_budget,
        )

        text = ""
        for chunk in stream:
            if should_stop():
                break

            chunk_text = getattr(chunk, "text", None)
            if chunk_text:
                emit({"phase": "text", "text": chunk_text})
                text += chunk_text
                continue

            executed, response_parts = self._handle_tool_calls(chunk, tool_registry, emit, execute=active_tools)
            if executed:
                candidates = getattr(chunk, "candidates", [])
                if candidates:
                    content = getattr(candidates[0], "content", None)
                    if content and getattr(content, "parts", None):
                        history.append(content)
                        history.append(model_api.google_tool_content(response_parts))
                return StreamRoundResult(text=text, executed_tool=True)

        return StreamRoundResult(text=text, executed_tool=False)

    def _handle_tool_calls(
        self,
        chunk: Any,
        tool_registry: dict[str, Callable],
        emit: Emit,
        *,
        execute: bool,
    ) -> tuple[bool, list[Any]]:
        executed = False
        response_parts: list[Any] = []

        candidates = getattr(chunk, "candidates", [])
        if not candidates:
            return executed, response_parts

        content = getattr(candidates[0], "content", None)
        if not content or not getattr(content, "parts", None):
            return executed, response_parts

        for part in content.parts:
            function_call = getattr(part, "function_call", None)
            if not function_call:
                continue

            name = function_call.name
            args = dict(function_call.args or {})
            func = tool_registry.get(name)

            if not execute or not func:
                emit({
                    "phase": "tool_ignored",
                    "tool": name,
                    "reason": "disabled" if not execute else "not_registered",
                })
                continue

            try:
                emit({"phase": "tool_call", "tool": name, "args": args})
                logger.info(
                    "axon provider tool_call provider=%s tool=%s arg_keys=%s",
                    self.provider_name,
                    name,
                    ",".join(sorted(args.keys())),
                )
                result = func(**args)
                logger.info(
                    "axon provider tool_result provider=%s tool=%s result_chars=%d",
                    self.provider_name,
                    name,
                    len(str(result)),
                )
                emit({"phase": "tool_result", "tool": name, "result": result})
                response_parts.append(model_api.google_function_response_part(name=name, response={"result": result}))
                executed = True
            except Exception as exc:
                message = str(exc)
                emit({"phase": "error", "error": {"type": "tool_exec_error", "message": message, "tool": name}})
                response_parts.append(model_api.google_function_response_part(name=name, response={"error": message}))
                executed = True

        return executed, response_parts
import time
class TextBatcher:
    def __init__(
        self,
        emit: Emit,
        *,
        phase: str = "text",
        min_chars: int = 80,
        max_delay: float = 0.06,
    ):
        self.emit = emit
        self.phase = phase
        self.min_chars = min_chars
        self.max_delay = max_delay
        self.buffer = ""
        self.last_flush = time.time()

    def push(self, text: str) -> None:
        if not text:
            return

        self.buffer += text
        now = time.time()

        if (
            len(self.buffer) >= self.min_chars
            or "\n" in self.buffer
            or now - self.last_flush >= self.max_delay
        ):
            self.flush()

    def flush(self) -> None:
        if not self.buffer:
            return

        self.emit({"phase": self.phase, "text": self.buffer})
        self.buffer = ""
        self.last_flush = time.time()

class DeepSeekProvider:
    provider_name = "deepseek"
    DEFAULT_MODEL = "deepseek-v4-flash"
    DEFAULT_BASE_URL = "https://api.deepseek.com"
    DEFAULT_REASONING_EFFORT = "medium"
    DEFAULT_THINKING_ENABLED = True
    SETTINGS_API_KEY = "deepseek_api_key"
    SETTINGS_MODEL = "axon_deepseek_model"
    SETTINGS_BASE_URL = "deepseek_base_url"
    ENV_API_KEY = "DEEPSEEK_API_KEY"
    ENV_MODEL = "AXON_DEEPSEEK_MODEL"
    ENV_BASE_URL = "DEEPSEEK_BASE_URL"

    def __init__(
        self,
        settings: Any | None = None,
        *,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str | None = None,
        thinking_enabled: bool | None = None,
        reasoning_effort: str | None = None,
    ):
        self.api_key = self._resolve_value(settings, self.SETTINGS_API_KEY, self.ENV_API_KEY, api_key, allow_missing=True)
        self.model_name = self._resolve_value(settings, self.SETTINGS_MODEL, self.ENV_MODEL, model, self.DEFAULT_MODEL)
        self.base_url = self._resolve_value(settings, self.SETTINGS_BASE_URL, self.ENV_BASE_URL, base_url, self.DEFAULT_BASE_URL)
        self.thinking_enabled = self.DEFAULT_THINKING_ENABLED if thinking_enabled is None else bool(thinking_enabled)
        self.reasoning_effort = reasoning_effort or self.DEFAULT_REASONING_EFFORT
        self._client: Any | None = None

    @staticmethod
    def _resolve_value(
        settings: Any | None,
        setting_name: str,
        env_name: str,
        override: str | None,
        default: str | None = None,
        allow_missing: bool = False,
    ) -> str:
        value = override
        if value is None and settings is not None:
            value = getattr(settings, setting_name, None)
        if value is None:
            value = os.environ.get(env_name)
        if value is None:
            value = default
        if not value:
            if allow_missing:
                return ""
            raise RuntimeError(f"missing {setting_name}; configure it in {self_name(DeepSeekProvider)}")
        return str(value)

    @property
    def client(self) -> Any:
        if not self.api_key:
            raise RuntimeError(f"missing {self.SETTINGS_API_KEY}; configure it in {self_name(DeepSeekProvider)}")
        if self._client is None:
            self._client = model_api.create_deepseek_client(api_key=self.api_key, base_url=self.base_url)
        return self._client

    def build_content(self, messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        content: list[dict[str, Any]] = []
        for message in messages:
            text = str(message.get("text", ""))
            if not text.strip():
                continue
            role = str(message.get("role", "user"))
            if role == "model":
                role = "assistant"
            content.append({"role": role, "content": text})
        return content

    def user_content(self, text: str) -> dict[str, Any]:
        return {"role": "user", "content": text}

    def stream_progress(
            self,
            *,
            history: list[dict[str, Any]],
            tool_registry: dict[str, Callable],
            emit: Emit,
            system_text: str,
            thinking_budget: int,
            tools_enabled: bool,
            should_stop: Callable[[], bool],
    ) -> StreamRoundResult:
        del thinking_budget

        tools = [model_api.callable_to_deepseek_tool(func) for func in tool_registry.values()]
        active_tools = tools_enabled and bool(tool_registry) and bool(tools)

        stream = model_api.deepseek_generate_chat_stream(
            client=self.client,
            model=self.model_name,
            messages=history,
            tools=tools,
            tools_enabled=active_tools,
            system_text=system_text,
            thinking_enabled=self.thinking_enabled,
            reasoning_effort=self.reasoning_effort,
        )

        text = ""
        assistant_text = ""
        reasoning_text = ""
        tool_calls_by_index: dict[int, dict[str, Any]] = {}

        text_batcher = TextBatcher(emit, phase="text", min_chars=96, max_delay=0.08)

        for chunk in stream:
            if should_stop():
                break

            choices = getattr(chunk, "choices", None) or []
            if not choices:
                continue

            choice = choices[0]
            delta = getattr(choice, "delta", None)
            if delta is None:
                continue

            reasoning_delta = getattr(delta, "reasoning_content", None)
            if reasoning_delta:
                reasoning_text += reasoning_delta
                continue

            delta_text = getattr(delta, "content", None)
            if delta_text:
                text_batcher.push(delta_text)
                text += delta_text
                assistant_text += delta_text

            for tool_call_delta in getattr(delta, "tool_calls", None) or []:
                index = int(getattr(tool_call_delta, "index", 0) or 0)
                stored = tool_calls_by_index.setdefault(
                    index,
                    {"id": "", "type": "function", "function": {"name": "", "arguments": ""}},
                )

                call_id = getattr(tool_call_delta, "id", None)
                if call_id:
                    stored["id"] = call_id

                function_delta = getattr(tool_call_delta, "function", None)
                if function_delta:
                    name_delta = getattr(function_delta, "name", None)
                    args_delta = getattr(function_delta, "arguments", None)

                    if name_delta:
                        stored["function"]["name"] += name_delta
                    if args_delta:
                        stored["function"]["arguments"] += args_delta

        text_batcher.flush()

        if tool_calls_by_index:
            tool_calls = [tool_calls_by_index[index] for index in sorted(tool_calls_by_index)]
            uses_build_tool = any(
                str((call.get("function") or {}).get("name", "")).startswith("build_graph")
                for call in tool_calls
            )
            # Only expose <thinking> for build_graph-style mutation planning.
            # Read-only retrieval tools should not surface verbose thinking.
            if reasoning_text.strip():
                if uses_build_tool:
                    emit({
                        "phase": "text",
                        "text": f"<thinking>\n{reasoning_text.strip()}\n</thinking>\n",
                    })

            assistant_message: dict[str, Any] = {
                "role": "assistant",
                "content": assistant_text or "",
                "tool_calls": tool_calls,
            }

            if reasoning_text:
                assistant_message["reasoning_content"] = reasoning_text

            history.append(assistant_message)

            executed = self._execute_tool_calls(
                tool_calls,
                tool_registry,
                emit,
                execute=active_tools,
                history=history,
            )

            return StreamRoundResult(text=text, executed_tool=executed)

        return StreamRoundResult(text=text, executed_tool=False)

    def _execute_tool_calls(
        self,
        tool_calls: list[dict[str, Any]],
        tool_registry: dict[str, Callable],
        emit: Emit,
        *,
        execute: bool,
        history: list[dict[str, Any]],
    ) -> bool:
        executed = False

        for tool_call in tool_calls:
            function = tool_call.get("function") or {}
            name = str(function.get("name") or "")
            args_text = str(function.get("arguments") or "{}")
            func = tool_registry.get(name)

            try:
                args = json.loads(args_text)
                if not isinstance(args, dict):
                    raise ValueError("tool arguments must decode to a JSON object")
            except Exception as exc:
                args = {}
                message = f"invalid tool arguments: {exc}"
                logger.warning("axon provider tool_args_error provider=%s tool=%s error=%s", self.provider_name, name, message)
                emit({"phase": "error", "error": {"type": "tool_args_error", "message": message, "tool": name}})
                history.append(model_api.deepseek_tool_message(tool_call_id=tool_call.get("id", ""), payload={"error": message}))
                executed = True
                continue

            if not execute or not func:
                logger.info(
                    "axon provider tool_ignored provider=%s tool=%s reason=%s",
                    self.provider_name,
                    name,
                    "disabled" if not execute else "not_registered",
                )
                emit({
                    "phase": "tool_ignored",
                    "tool": name,
                    "reason": "disabled" if not execute else "not_registered",
                })
                continue

            try:
                emit({"phase": "tool_call", "tool": name, "args": args})
                logger.info(
                    "axon provider tool_call provider=%s tool=%s arg_keys=%s",
                    self.provider_name,
                    name,
                    ",".join(sorted(args.keys())),
                )
                result = func(**args)
                logger.info(
                    "axon provider tool_result provider=%s tool=%s result_chars=%d",
                    self.provider_name,
                    name,
                    len(str(result)),
                )
                emit({"phase": "tool_result", "tool": name, "result": result})
                history.append(model_api.deepseek_tool_message(tool_call_id=tool_call.get("id", ""), payload={"result": result}))
                executed = True
            except Exception as exc:
                message = str(exc)
                logger.warning("axon provider tool_exec_error provider=%s tool=%s error=%s", self.provider_name, name, message)
                emit({"phase": "error", "error": {"type": "tool_exec_error", "message": message, "tool": name}})
                history.append(model_api.deepseek_tool_message(tool_call_id=tool_call.get("id", ""), payload={"error": message}))
                executed = True

        return executed


def create_model_provider(settings: Any | None = None, *, provider_name: str | None = None) -> ModelProvider:
    raw_name = provider_name

    if raw_name is None:
        raw_name = os.environ.get("AXON_MODEL_PROVIDER")

    if raw_name is None and settings is not None:
        raw_name = getattr(settings, "axon_model_provider", None)

    name = str(raw_name or "google").strip().lower().replace("_", "-")

    if name in {"google", "google-genai", "gemini"}:
        return GoogleGenAIProvider(settings)
    if name in {"deepseek", "deep-seek"}:
        return DeepSeekProvider(settings)

    raise RuntimeError(f"unknown Axon model provider: {raw_name}")


def self_name(cls: type) -> str:
    return cls.__name__
