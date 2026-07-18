from __future__ import annotations
from typing import Any, Dict, Tuple, Optional, Set, List
import threading
import torch

from .plan import compile_plan, topo_signature
from .runner import fused_train_step

from common.logger import get_logger

topo = get_logger("topo")
class _Req:
	__slots__ = ("pack", "ctx", "x", "y", "do_update", "done", "loss", "acc", "err", "output_nid", "session_id")
	def __init__(self, pack, ctx, x, y, do_update: bool, output_nid: str, session_id: str):
		self.pack = pack
		self.ctx = ctx
		self.x = x
		self.y = y
		self.do_update = bool(do_update)
		self.output_nid = str(output_nid)
		self.session_id = str(session_id)
		self.done = threading.Event()
		self.loss = 0.0
		self.acc = 0.0
		self.err: Optional[BaseException] = None


class _Bucket:
	def __init__(self, key: str):
		self.key = key
		self.lock = threading.Lock()
		self.cv = threading.Condition(self.lock)

		self.waiting: List[_Req] = []

		# session state (SESSION != CONTEXT)
		self.leader_session: Optional[str] = None
		self.sessions: Set[str] = set()
		self.session_fused = False  # sticky

		self._plan = None
		self._plan_sig = None
		self.active: Dict[str, _Req] = {}  # NEW: last req per session

		topo.info(f"[TOPOFUSE][BUCKET][INIT] key={key}")

		self._aot_cache: Dict[str, AOTCompiled] = {}

	def is_empty(self) -> bool:
		return not self.waiting and not self.sessions and self.leader_session is None

	def _reset_bucket(self, reason: str):
		topo.info(f"[TOPOFUSE][SESSION][RESET] bucket={self.key} reason={reason}")
		err = RuntimeError(f"TopoFuse: leader lost ({reason})")
		for r in self.waiting:
			r.err = err
			r.done.set()
		self.waiting.clear()
		self.leader_session = None
		self.sessions.clear()
		self.session_fused = False
		self._aot_cache.clear()
		self.cv.notify_all()

	def unregister_session(self, session_id: str):
		with self.cv:
			if self._aot_cache:
				for compiled in self._aot_cache.values():
					try:
						compiled.banks.export_all_to_ops_()
					except Exception as e:
						topo.error(f"[TOPOFUSE][EXPORT_FAIL] {e}")

			if self.leader_session == session_id:
				self._reset_bucket("unregister")
			else:
				self.sessions.discard(session_id)

			for r in list(self.waiting):
				if r.session_id == session_id:
					r.err = RuntimeError("TopoFuse: session unregistered")
					r.done.set()
					self.waiting.remove(r)

	def _active_batch_size(self) -> Optional[int]:
		sizes = {int(r.x.shape[0]) for r in self.active.values()}
		if len(sizes) == 1:
			return sizes.pop()
		return None

	def _get_plan(self, graph: Dict[str, Any], ctx, x: torch.Tensor, output_nid: str):
		sig = topo_signature(graph, output_nid)
		if self._plan is None or self._plan_sig != sig:
			#topo.info(f"[TOPOFUSE][PLAN][COMPILE] bucket={self.key} sig={sig}")
			self._plan = compile_plan(graph, ctx, x, output_nid)
			self._plan_sig = sig
		else:
			pass
			#topo.info(f"[TOPOFUSE][PLAN][CACHE_HIT] bucket={self.key} sig={sig}")
		return self._plan

	def submit(self, req: _Req, *, max_group: int = 4) -> Tuple[float, float]:
		sid = req.session_id

		# -------------------------
		# Enqueue
		# -------------------------
		with self.cv:
			if self.leader_session is None:
				self.leader_session = sid

			self.sessions.add(sid)

			# Record latest req per session (still useful for state), but DO NOT rely on it for waking.
			self.active[sid] = req

			is_leader = (sid == self.leader_session)
			if not is_leader:
				self.session_fused = True

			self.waiting.append(req)

			# -------------------------
			# Follower waits on *its* req.done
			# -------------------------
			if not is_leader:
				while not req.done.is_set():
					if self.leader_session is None:
						req.err = RuntimeError("TopoFuse: leader lost")
						req.done.set()
						break
					self.cv.wait(timeout=0.5)

				if req.err:
					raise req.err
				return req.loss, req.acc

		# -------------------------
		# LEADER PATH
		# -------------------------
		# Snapshot all pending requests for this step.
		with self.cv:
			if self.leader_session != sid:
				raise RuntimeError("TopoFuse: lost leadership")

			# Take everything that is currently waiting (THIS is what followers are blocked on)
			pending = list(self.waiting)
			self.waiting.clear()

			# Nothing pending? Shouldn’t happen, but be safe.
			if not pending:
				req.done.set()
				self.cv.notify_all()
				return req.loss, req.acc

			# Pick the latest req per session from *pending*.
			latest_by_sid: Dict[str, _Req] = {}
			for r in pending:
				latest_by_sid[r.session_id] = r

			batch = list(latest_by_sid.values())

			# Any older reqs from same session are superseded; wake them immediately.
			for r in pending:
				if latest_by_sid.get(r.session_id) is not r:
					r.err = RuntimeError("TopoFuse: superseded by a newer step")
					r.done.set()

			# If only one active session in THIS step, just run solo for that one and wake everyone else.
			if len(batch) <= 1:
				# Ensure the leader req (or whoever is in batch[0]) runs, and everyone is released.
				mode = "solo"
			else:
				# Fusion eligibility: all batch sizes equal
				sizes = {int(r.x.shape[0]) for r in batch}
				mode = "fused" if (len(sizes) == 1 and self.session_fused) else "solo"

			# Mark active flag for all requests that will be executed in this leader cycle (fused or solo)
			for r in batch:
				r.ctx.extra["_topofuse_active"] = True

		# -------------------------
		# Execute
		# -------------------------
		try:
			graph0 = batch[0].pack["graph"]
			plan = self._get_plan(graph0, batch[0].ctx, batch[0].x, batch[0].output_nid)

			if mode == "fused":
				# Run one fused step for all reqs in batch
				fused_train_step(plan=plan, reqs=batch, aot_cache=self._aot_cache, plan_sig=self._plan_sig or "")
			else:
				with self.cv:
					for r in batch:
						r.done.set()
						r.ctx.extra.pop("_topofuse_active", None)
					self.cv.notify_all()
				return None

		except BaseException as e:
			# Wake everybody (including any pending we didn’t execute — but we already superseded older ones above)
			with self.cv:
				if self.leader_session == sid:
					self._reset_bucket("exec_error")
				for r in batch:
					r.err = e
					r.done.set()
				for r in batch:
					r.ctx.extra.pop("_topofuse_active", None)
				self.cv.notify_all()
			raise

		else:
			# Normal completion: wake everyone we executed
			with self.cv:
				for r in batch:
					r.done.set()
				for r in batch:
					r.ctx.extra.pop("_topofuse_active", None)
				self.cv.notify_all()

		# Leader returns its own req result (the req passed in).
		# If leader’s req was superseded (rare), it’ll have err set, but then it wouldn’t be leader realistically.
		if req.err:
			raise req.err
		return req.loss, req.acc


	def has_other_sessions(self, sid: str) -> bool:
		# True if at least one *other* session exists
		return any(s != sid for s in self.sessions)
def _choose_branch_nid(ctx) -> str:
	branch_losses = ctx.extra.get("branch_losses") or {}
	branch_id = next(iter(branch_losses.keys()), "default")
	return str(branch_id)


class TopoFuseManager:
	def __init__(self):
		self._lock = threading.Lock()
		self._buckets: Dict[str, _Bucket] = {}
		topo.info("[TOPOFUSE][MANAGER][INIT]")

	def _get_or_create_bucket(self, sig: str) -> _Bucket:
		with self._lock:
			b = self._buckets.get(sig)
			if b is None:
				#topo.info(f"[TOPOFUSE][BUCKET][CREATE] sig={sig}")
				b = _Bucket(sig)
				self._buckets[sig] = b
			else:
				pass
				#topo.info(f"[TOPOFUSE][BUCKET][REUSE] sig={sig}")
			return b


	def unregister_session(self, *, session_id: str) -> None:
		sid = str(session_id)
		# scan buckets (simple + safe; #buckets is typically small)
		with self._lock:
			buckets = list(self._buckets.items())

		for sig, b in buckets:
			b.unregister_session(sid)

		# opportunistic GC of empty buckets
		with self._lock:
			to_del = []
			for sig, b in self._buckets.items():
				if b.is_empty():
					to_del.append(sig)
			for sig in to_del:
				#topo.info(f"[TOPOFUSE][BUCKET][GC] sig={sig}")
				del self._buckets[sig]

	def submit_step(self, *, pack, ctx, x, y, do_update: bool, session_id: str) -> Optional[Tuple[float, float]]:
		tid = threading.get_ident()
		graph = pack.get("graph") or {}
		output_nid = _choose_branch_nid(ctx)
		sig = topo_signature(graph, output_nid)

		if not sig:
			topo.info("[TOPOFUSE][SUBMIT][SKIP] empty/ambiguous signature")
			return None

		req = _Req(pack, ctx, x, y, do_update, output_nid=output_nid, session_id=str(session_id))
		b = self._get_or_create_bucket(sig)

		#topo.info(f"[TOPOFUSE][SUBMIT][REQ] sig={sig} tid={tid} session={session_id}")
		try:
			return b.submit(req)
		except Exception as e:
			#topo.info(f"[TOPOFUSE][FALLBACK] sig={sig} err={e}")
			import traceback
			traceback.print_exc()
			return None
