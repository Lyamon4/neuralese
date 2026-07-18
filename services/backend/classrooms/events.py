from __future__ import annotations

import asyncio
import json


class ClassroomEventHub:
    def __init__(self) -> None:
        self.subs: dict[str, set[asyncio.Queue]] = {}

    def subscribe(self, classroom_id: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self.subs.setdefault(classroom_id, set()).add(q)
        return q

    def unsubscribe(self, classroom_id: str, q: asyncio.Queue) -> None:
        subs = self.subs.get(classroom_id)
        if not subs:
            return
        subs.discard(q)
        if not subs:
            self.subs.pop(classroom_id, None)

    def emit(self, classroom_id: str, event_type: str = "snapshot", data=None) -> None:
        for q in list(self.subs.get(classroom_id, set())):
            q.put_nowait({"type": event_type, "data": data or {}})


def sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"
