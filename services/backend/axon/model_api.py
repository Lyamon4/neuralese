from __future__ import annotations

import inspect
import json
from typing import Any, Callable, Iterable


def create_google_genai_client(*, api_key: str):
    from google import genai

    return genai.Client(api_key=api_key)


def google_text_content(*, role: str, text: str):
    from google.genai import types

    return types.Content(role=role, parts=[types.Part(text=text)])


def google_user_content(text: str):
    return google_text_content(role="user", text=text)


def google_function_response_part(*, name: str, response: dict[str, Any]):
    from google.genai import types

    return types.Part.from_function_response(name=name, response=response)


def google_tool_content(response_parts: list[Any]):
    from google.genai import types

    return types.Content(role="tool", parts=response_parts)


def google_function_tools(*, client: Any, funcs: Iterable[Callable]) -> list[Any]:
    from google.genai import types

    declarations = [types.FunctionDeclaration.from_callable(callable=func, client=client) for func in funcs]
    return [types.Tool(function_declarations=declarations)] if declarations else []


def google_generate_content_stream(
    *,
    client: Any,
    model: str,
    history: list[Any],
    tools: list[Any],
    tools_enabled: bool,
    system_text: str,
    thinking_budget: int,
):
    from google.genai import types

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=thinking_budget),
        tools=tools if tools_enabled else [],
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=not tools_enabled),
        system_instruction=system_text,
    )
    return client.models.generate_content_stream(model=model, contents=history, config=config)


def create_deepseek_client(*, api_key: str, base_url: str):
    from openai import OpenAI

    return OpenAI(api_key=api_key, base_url=base_url)


def deepseek_generate_chat_stream(
    *,
    client: Any,
    model: str,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]],
    tools_enabled: bool,
    system_text: str,
    thinking_enabled: bool,
    reasoning_effort: str,
):
    api_messages: list[dict[str, Any]] = []
    if system_text:
        api_messages.append({"role": "system", "content": system_text})
    api_messages.extend(messages)

    kwargs: dict[str, Any] = {
        "model": model,
        "messages": api_messages,
        "stream": True,
        "extra_body": {"thinking": {"type": "enabled" if thinking_enabled else "disabled"}},
    }
    if thinking_enabled:
        kwargs["reasoning_effort"] = reasoning_effort
    if tools_enabled and tools:
        kwargs["tools"] = tools

        # DeepSeek V4 thinking mode can reject tool_choice.
        # Let the model auto-select tools implicitly when thinking is enabled.
        if not thinking_enabled:
            kwargs["tool_choice"] = "auto"

    return client.chat.completions.create(**kwargs)


def deepseek_tool_message(*, tool_call_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "role": "tool",
        "tool_call_id": tool_call_id,
        "content": json.dumps(payload, ensure_ascii=False),
    }


def callable_to_deepseek_tool(func: Callable) -> dict[str, Any]:
    signature = inspect.signature(func)
    properties: dict[str, Any] = {}
    required: list[str] = []

    for name, parameter in signature.parameters.items():
        if parameter.kind in (parameter.VAR_POSITIONAL, parameter.VAR_KEYWORD):
            continue

        properties[name] = _annotation_to_json_schema(parameter.annotation)
        if parameter.default is inspect.Parameter.empty:
            required.append(name)

    parameters: dict[str, Any] = {
        "type": "object",
        "properties": properties,
        "additionalProperties": False,
    }
    if required:
        parameters["required"] = required

    return {
        "type": "function",
        "function": {
            "name": func.__name__,
            "description": inspect.getdoc(func) or f"Call {func.__name__}.",
            "parameters": parameters,
        },
    }


def _annotation_to_json_schema(annotation: Any) -> dict[str, Any]:
    if annotation is inspect.Parameter.empty or annotation is Any:
        return {"type": "string"}

    origin = getattr(annotation, "__origin__", None)
    if origin is list:
        return {"type": "array", "items": {"type": "string"}}
    if origin is dict:
        return {"type": "object"}

    mapping = {
        str: "string",
        int: "integer",
        float: "number",
        bool: "boolean",
        list: "array",
        dict: "object",
    }
    return {"type": mapping.get(annotation, "string")}
