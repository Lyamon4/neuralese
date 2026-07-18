from __future__ import annotations

import asyncio
import hashlib
import json
import threading
from typing import Any

from sanic import Blueprint, Request
from sanic.response import json as sanic_json

from auth.dependencies import AuthError, require_account
from projects.service import validate_scene_id

from .prompts import remove_tag_blocks


bp_axon = Blueprint("axon", url_prefix="")


def _stable_json(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _json_dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False)


async def _graceful_close(ws, payload: dict[str, Any] | None = None) -> None:
    try:
        if payload:
            await ws.send(_json_dumps(payload))
        await ws.send(_json_dumps({"_close_request": ""}))
        try:
            await asyncio.wait_for(ws.recv(), timeout=0.5)
        except Exception:
            pass
    finally:
        try:
            await ws.close()
        except Exception:
            pass


async def _stream_axon_call(ws, func):
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
    stop_event = threading.Event()

    def emit(payload: dict[str, Any]) -> None:
        loop.call_soon_threadsafe(queue.put_nowait, payload)

    task = asyncio.create_task(asyncio.to_thread(func, emit, stop_event))
    result = None

    try:
        while True:
            if task.done() and queue.empty():
                result = task.result()
                break
            try:
                payload = await asyncio.wait_for(queue.get(), timeout=0.1)
            except asyncio.TimeoutError:
                continue
            await ws.send(_json_dumps(payload))
    except Exception:
        stop_event.set()
        raise
    finally:
        if not task.done():
            stop_event.set()
            try:
                await asyncio.wait_for(task, timeout=2.0)
            except Exception:
                pass

    return result or {"status": "error", "text": ""}

from sanic.log import logger

@bp_axon.websocket("/ws/axon/talk", name="ws_talk_api")
@bp_axon.websocket("/ws/talk", name="ws_talk_legacy")
async def ws_talk(request: Request, ws):
    try:
        await _ws_talk_impl(request, ws)
    except Exception as exc:
        print(exc)
        logger.exception("ws/talk crashed")
        try:
            await _graceful_close(ws, {"error": "ws_talk_crashed", "detail": str(exc)})
        except Exception:
            pass


async def _ws_talk_impl(request: Request, ws):
    logger.info("ws/talk entered")
    try:
        account = require_account(request)
    except AuthError as exc:
        logger.warning("ws/talk auth failed: %s", exc)
        await _graceful_close(ws, {"status": "wrong", "error": str(exc)})
        return

    try:
        first = json.loads(await ws.recv())
    except Exception as exc:
        logger.warning("ws/talk invalid first packet: %s", exc)
        await _graceful_close(ws, {"error": "invalid_first_packet", "detail": str(exc)})
        return

    scene_id = str(first.get("scene", ""))
    if not validate_scene_id(scene_id):
        logger.warning("ws/talk invalid scene: %s", scene_id)
        await _graceful_close(ws, {"error": "invalid_scene"})
        return

    chat_id = str(first.get("chat_id", ""))
    account_id = account.profile.account_id or account.principal.user_id
    text = str(first.get("text", ""))
    limits = request.app.ctx.axon_service.config.limits
    if limits.enabled and len(text) > limits.max_user_message_chars:
        logger.warning(
            "ws/talk message too long account=%s scene=%s chat=%s chars=%d max=%d",
            account_id,
            scene_id,
            chat_id,
            len(text),
            limits.max_user_message_chars,
        )
        await _graceful_close(ws, {
            "error": "axon_message_too_long",
            "max_chars": limits.max_user_message_chars,
        })
        return

    decision = request.app.ctx.axon_service.limiter.check_request(account_id)
    if not decision.allowed:
        logger.warning(
            "ws/talk rate limited account=%s scene=%s chat=%s reason=%s retry_after=%.1f",
            account_id,
            scene_id,
            chat_id,
            decision.reason,
            decision.retry_after_seconds,
        )
        await _graceful_close(ws, {
            "error": "axon_rate_limited",
            "reason": decision.reason,
            "retry_after_seconds": decision.retry_after_seconds,
        })
        return
    request.app.ctx.axon_service.limiter.record_request(account_id)

    logger.info(
        "ws/talk accepted scene=%s chat=%s account=%s username=%s text_chars=%d",
        scene_id,
        chat_id,
        account_id,
        account.profile.username,
        len(text),
    )
    chats = account.root.child(f"projects/{scene_id}/chats")
    data = chats.read_rel(chat_id + ".doc") or {
        "messages": [],
        "graph_state": {"nodes": {}, "edges": {}},
        "graph_state_hash": "",
        "last_id": 0,
    }

    if first.get("_clear"):
        data["messages"] = []

    stored_hash = str(data.get("graph_state_hash", ""))
    client_hash = str(first.get("summary_hash", ""))
    await ws.send(_json_dumps({"server_hash": stored_hash}))

    summary = data.setdefault("graph_state", {"nodes": {}, "edges": {}})
    if client_hash != stored_hash and "summary" not in first:
        await ws.send(_json_dumps({"need_summary": True}))
        try:
            second = json.loads(await asyncio.wait_for(ws.recv(), timeout=5.0))
        except asyncio.TimeoutError:
            logger.warning("ws/talk summary timeout scene=%s chat=%s", scene_id, chat_id)
            await _graceful_close(ws, {"error": "summary_timeout"})
            return
        except Exception as exc:
            logger.warning("ws/talk invalid summary packet: %s", exc)
            await _graceful_close(ws, {"error": "invalid_summary_packet", "detail": str(exc)})
            return
        summary = second.get("summary", summary)
        data["graph_state_hash"] = second.get("summary_hash", client_hash or _sha256_text(_stable_json(summary)))
    elif "summary" in first:
        summary = first["summary"]
        data["graph_state_hash"] = client_hash or _sha256_text(_stable_json(summary))

    data["graph_state"] = summary
    logger.info(
        "ws/talk graph_state scene=%s chat=%s account=%s hash_match=%s nodes=%d edges=%d",
        scene_id,
        chat_id,
        account_id,
        client_hash == stored_hash,
        len(summary.get("nodes", {})) if isinstance(summary, dict) and isinstance(summary.get("nodes"), dict) else 0,
        len(summary.get("edges", [])) if isinstance(summary, dict) and isinstance(summary.get("edges"), list) else 0,
    )
    chats.update_doc_rel(chat_id + ".doc", data)
    await ws.send(_json_dumps({"updated": True}))

    data.setdefault("messages", []).append({
        "role": "user",
        "text": text,
        "id": first.get("user_id", 0),
    })
    if limits.enabled and limits.max_retained_chat_messages > 0:
        original_len = len(data["messages"])
        data["messages"] = data["messages"][-limits.max_retained_chat_messages:]
        if len(data["messages"]) != original_len:
            logger.info(
                "ws/talk trimmed chat history account=%s scene=%s chat=%s before=%d after=%d",
                account_id,
                scene_id,
                chat_id,
                original_len,
                len(data["messages"]),
            )
    chats.update_doc_rel(chat_id + ".doc", data)

    content = request.app.ctx.axon_service.build_content(data["messages"])

    def run_llm(emit, stop_event):
        return request.app.ctx.axon_service.run_talk(
            content=content,
            summary=summary,
            emit=emit,
            should_stop=stop_event.is_set,
            account_id=account_id,
        )

    try:
        result = await _stream_axon_call(ws, run_llm)
    except Exception as exc:
        logger.exception("ws/talk stream failed")
        await _graceful_close(ws, {
	        "error": "stream_failed",
	        "detail": str(exc),
        })
        return

    if result and result.get("text"):
        text = remove_tag_blocks(
            str(result.get("text", "")),
            ["change_nodes", "connect_ports", "disconnect_ports", "delete_nodes", "thinking"],
        )
        data.setdefault("messages", []).append({
            "role": "model",
            "text": text,
            "func_called": bool(result.get("func_called", False)),
            "id": first.get("ai_id", 0),
        })
        if limits.enabled and limits.max_retained_chat_messages > 0:
            data["messages"] = data["messages"][-limits.max_retained_chat_messages:]
        chats.update_doc_rel(chat_id + ".doc", data)

    estimated_tokens = int(result.get("estimated_tokens") or 0) if result else 0
    total_tokens = request.app.ctx.axon_service.limiter.record_estimated_tokens(
        account_id,
        estimated_tokens,
        graph_build_used=bool(result.get("graph_build_used", False)) if result else False,
    )
    logger.info(
        "ws/talk complete account=%s scene=%s chat=%s status=%s estimated_tokens=%d global_tokens_day=%d graph_build=%s",
        account_id,
        scene_id,
        chat_id,
        result.get("status", "") if result else "",
        estimated_tokens,
        total_tokens,
        bool(result.get("graph_build_used", False)) if result else False,
    )

    if bool(result.get("graph_build_used", False)):
        await asyncio.sleep(3.0)
    await _graceful_close(ws, {})


@bp_axon.post("/api/axon/ask-once", name="ask_once_api")
@bp_axon.post("/ask_once", name="ask_once_legacy")
async def ask_once(request: Request):
    try:
        account = require_account(request)
    except AuthError:
        return sanic_json({"answer": "wrong"}, status=403)

    body = request.json or {}
    text = str(body.get("text", ""))
    account_id = account.profile.account_id or account.principal.user_id
    limits = request.app.ctx.axon_service.config.limits
    if limits.enabled and len(text) > limits.max_user_message_chars:
        logger.warning("ask_once message too long account=%s chars=%d", account_id, len(text))
        return sanic_json({"answer": "error", "error": "axon_message_too_long", "max_chars": limits.max_user_message_chars}, status=413)
    decision = request.app.ctx.axon_service.limiter.check_request(account_id)
    if not decision.allowed:
        logger.warning("ask_once rate limited account=%s reason=%s", account_id, decision.reason)
        return sanic_json({
            "answer": "error",
            "error": "axon_rate_limited",
            "reason": decision.reason,
            "retry_after_seconds": decision.retry_after_seconds,
        }, status=429)
    request.app.ctx.axon_service.limiter.record_request(account_id)

    chunks: list[str] = []
    stop_event = threading.Event()

    def emit(payload: dict[str, Any]) -> None:
        if payload.get("phase") == "text":
            chunks.append(str(payload.get("text", "")))

    result = await asyncio.to_thread(
        request.app.ctx.axon_service.run_once,
        text=text,
        emit=emit,
        should_stop=stop_event.is_set,
    )
    final_text = str(result.get("text") or "".join(chunks))
    estimated_tokens = request.app.ctx.axon_service.limiter.estimate_tokens_from_chars(len(text) + len(final_text))
    total_tokens = request.app.ctx.axon_service.limiter.record_estimated_tokens(
        account_id,
        estimated_tokens,
        graph_build_used=False,
    )
    logger.info(
        "ask_once complete account=%s status=%s estimated_tokens=%d global_tokens_day=%d",
        account_id,
        result.get("status", ""),
        estimated_tokens,
        total_tokens,
    )
    return sanic_json({"answer": "ok" if result.get("status") == "ok" else "error", "text": final_text})
