from typing import Any, Callable, Dict, List
from google.genai import types
import google.genai

Emit = Callable[[Dict[str, Any]], None]

from typing import Tuple
def make_tools(client: google.genai.Client, *funcs: Callable) -> List[types.Tool]:
	fdecls = [types.FunctionDeclaration.from_callable(callable=f, client=client) for f in funcs]
	return [types.Tool(function_declarations=fdecls)]
def handle_tool_calls(
    chunk: Any,
    tool_registry: Dict[str, Callable],
    emit: Emit,
    *,
    execute: bool  # << NEW: caller controls whether tools may run
) -> Tuple[bool, List[types.Part]]:
    """Returns (executed, response_parts). executed=True only if we actually ran a tool."""
    executed = False
    response_parts: List[types.Part] = []

    cands = getattr(chunk, "candidates", [])
    if not cands:
        return executed, response_parts

    content = getattr(cands[0], "content", None)
    if not content or not getattr(content, "parts", None):
        return executed, response_parts

    for part in content.parts:
        fn_call = getattr(part, "function_call", None)
        if not fn_call:
            continue

        name = fn_call.name
        args = fn_call.args or {}
        fn = tool_registry.get(name)

        if not execute or not fn:
            # Tools disabled or not registered → do NOT fabricate a function_response.
            # Just log and continue streaming tokens.
            emit({"phase": "tool_ignored",
                  "tool": name,
                  "reason": "disabled" if not execute else "not_registered"})
            continue

        try:
            emit({"phase": "tool_call", "tool": name, "args": args})
            result = fn(**args)
            emit({"phase": "tool_result", "tool": name, "result": result})
            response_parts.append(types.Part.from_function_response(
                name=name,
                response={"result": result}
            ))
            executed = True
        except Exception as e:
            msg = str(e)
            emit({"phase": "error",
                  "error": {"type": "tool_exec_error", "message": msg, "tool": name}})
            response_parts.append(types.Part.from_function_response(
                name=name,
                response={"error": msg}
            ))
            executed = True  # we *did* try to execute

    return executed, response_parts


# ------------------------------
# Streaming runner
# ------------------------------

FLOOD_MAX_CALLS = 3
FLOOD_MIN_INTERVAL = 1.0
FLOOD_RETRY_DELAY = 10.0

_last_call_time = 0.0
_active_calls = 0

def run_with_tools(
    client,
    model: str,
    history: list,
    tool_registry: Dict[str, Callable],
    emit: Emit,
    should_stop: Callable[[], bool] = lambda: False,
    thinking_budget: int = 0,
    system_text: str = "",
    max_tool_rounds: int = 1,
) -> Dict[str, Any]:
    global _last_call_time, _active_calls

    tools_all = make_tools(client, *tool_registry.values())
    final_text = ""
    rounds = 0
    tools_enabled = bool(tool_registry) and bool(tools_all)  # true only if we actually have tools
    api_calls = 0

    try:
        while not should_stop():
            # simple pacing (doesn’t change your current working behavior)
            if api_calls >= FLOOD_MAX_CALLS:
                emit({"phase": "error",
                      "error": {"type": "flood_guard",
                                "message": f"Aborted: {FLOOD_MAX_CALLS} LLM calls exceeded"}})
                break

            delta = time.time() - _last_call_time
            if delta < FLOOD_MIN_INTERVAL:
                time.sleep(FLOOD_MIN_INTERVAL - delta)

            _active_calls += 1
            _last_call_time = time.time()
            api_calls += 1
            print(f"[LLM] Call {api_calls} — model={model}")

            config = types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(thinking_budget=thinking_budget),
                tools=tools_all if tools_enabled else [],
                automatic_function_calling=types.AutomaticFunctionCallingConfig(
                    disable=not tools_enabled
                ),
                system_instruction=system_text,
            )

            try:
                print("HISTORY SNAPSHOT", [getattr(c, "role", None) for c in history])

                stream = client.models.generate_content_stream(
                    model=model,
                    contents=history,
                    config=config,
                )
            except Exception as e:
                if "429" in str(e):
                    emit({"phase": "error",
                          "error": {"type": "quota_hit", "message": str(e)}})
                    time.sleep(FLOOD_RETRY_DELAY)
                    break
                raise

            has_executed_tool = False

            for chunk in stream:
                if getattr(chunk, "text", None):
                    emit({"phase": "text", "text": chunk.text})
                    final_text += chunk.text
                    continue

                # Only *try* tools when enabled; otherwise ignore function_calls.
                executed, response_parts = handle_tool_calls(
                    chunk, tool_registry, emit, execute=tools_enabled
                )
                if executed:
                    has_executed_tool = True
                    rounds += 1

                    # append the model’s function_call turn + our tool result
                    cands = getattr(chunk, "candidates", [])
                    if cands:
                        content = getattr(cands[0], "content", None)
                        if content and getattr(content, "parts", None):
                            history.append(content)
                            history.append(types.Content(role="tool", parts=response_parts))

                    # break to re-enter once; otherwise continue streaming
                    break

                # If we didn’t execute (tools disabled / not found), **do not break**.
                if should_stop():
                    break

            _active_calls -= 1

            if has_executed_tool:
                # Cap tool rounds
                if rounds >= max_tool_rounds:
                    tools_enabled = False
                    tools_all = []          # defensively clear
                    tool_registry = {}      # defensively clear
                # Re-enter once to let the model “close the turn”
                continue

            # No executed tool this pass → we’re done.
            break

    except Exception as e:
        traceback.print_exc()
        emit({"phase": "error",
              "error": {"type": "stream_abort", "message": str(e)}})
        return {"status": "error", "text": final_text}
    finally:
        _active_calls = max(0, _active_calls - 1)

    return {"status": "ok", "text": final_text}

import traceback
import time