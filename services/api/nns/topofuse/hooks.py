from __future__ import annotations
from typing import Any, Dict, Optional, Tuple
import torch

from .manager import TopoFuseManager

# global singleton
_MANAGER = TopoFuseManager()

def enabled() -> bool:
	return True


def unregister_session(*, session_id: str) -> None:
	"""
	Explicit lifecycle call. Should be invoked when a training session ends
	(e.g., WS close / stop-train).
	This is safe to call even if the session was never registered.
	"""
	if not isinstance(session_id, str) or not session_id:
		return
	_MANAGER.unregister_session(session_id=session_id)

def maybe_run_fused_step(*, pack: Dict[str, Any], ctx, x, y, do_update: bool, session_id: str) -> Optional[Tuple[float, float]]:
	"""
	Return (loss, acc) if TopoFuse handled it; else None to indicate fallback.

	IMPORTANT:
	- session_id is REQUIRED and must be stable for the duration of a training session.
	- session_id is NOT the same as ctx.
	"""
	if not enabled():
		return None
	if not isinstance(session_id, str) or not session_id:
		return None
	if not torch.cuda.is_available():
		return None

	# must be on cuda for kernel-sharing value
	dev = x.device if isinstance(x, torch.Tensor) else None
	if dev is None or dev.type != "cuda":
		return None

	return _MANAGER.submit_step(pack=pack, ctx=ctx, x=x, y=y, do_update=do_update, session_id=session_id)
