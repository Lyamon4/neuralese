# ===== FILE: topofuse/bucket_optim.py =====
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import torch
import torch.nn as nn


@dataclass(frozen=True)
class OptimSig:
	name: str           # "sgd" | "adam" | "adamw"
	lr: float
	beta1: float
	beta2: float
	eps: float
	weight_decay: float
	momentum: float
	nesterov: bool


def get_optim_sig(ctx) -> Optional[OptimSig]:
	"""
	Safe: only supports a minimal stable subset.
	Read from ctx.extra["train_config"].
	If missing/unknown => return None (caller must fall back).
	"""
	tc = ctx.extra.get("train_config") or {}
	if not isinstance(tc, dict):
		return None

	name = str(tc.get("optimizer", tc.get("optim", "adam"))).lower()
	lr = float(tc.get("lr", 1e-3))
	wd = float(tc.get("weight_decay", 0.0))

	if name in ("sgd", "momentum"):
		mom = float(tc.get("momentum", 0.0))
		nes = bool(tc.get("nesterov", False))
		return OptimSig(
			name="sgd", lr=lr,
			beta1=0.0, beta2=0.0, eps=0.0,
			weight_decay=wd, momentum=mom, nesterov=nes
		)

	# adam / adamw
	betas = tc.get("betas", (0.9, 0.999))
	try:
		b1 = float(betas[0])
		b2 = float(betas[1])
	except Exception:
		b1, b2 = 0.9, 0.999
	eps = float(tc.get("eps", 1e-8))
	if name not in ("adam", "adamw"):
		return None

	return OptimSig(
		name=name, lr=lr,
		beta1=b1, beta2=b2, eps=eps,
		weight_decay=wd, momentum=0.0, nesterov=False
	)


# -----------------------------------------------------------------------------
# NEW: Per-user optimizer state applied to *banked parameters* by slicing.
# This avoids Adam state sharing across users while keeping a single backward pass.
# -----------------------------------------------------------------------------
class PerUserBankOptim:
	"""
	Per-user optimizer state over banked parameters.

	Assumptions about bank params:
	- Each banked parameter encodes user dimension in dim0, either:
	  A) shape[0] == U              (direct user dimension), or
	  B) shape[0] % U == 0          (concatenated blocks along dim0)

	We update ONLY the slice belonging to each user, with that user's optimizer state.
	"""

	def __init__(self, *, sigs: List[OptimSig], device: torch.device):
		self.device = device
		self.sigs = list(sigs)
		self.U = int(len(sigs))

		# per-user step counters
		self._step: List[int] = [0 for _ in range(self.U)]

		# state keyed by (id(param), user_index)
		self._m: Dict[Tuple[int, int], torch.Tensor] = {}
		self._v: Dict[Tuple[int, int], torch.Tensor] = {}
		self._mom: Dict[Tuple[int, int], torch.Tensor] = {}

	def zero_grad_(self, params: List[nn.Parameter]) -> None:
		for p in params:
			p.grad = None

	def _slice_for_user(self, p: torch.Tensor, ui: int) -> slice:
		"""
	Returns slice along dim0 that corresponds to user ui.
	"""
		n0 = int(p.shape[0])
		U = self.U
		if n0 == U:
			return slice(ui, ui + 1)
		if n0 % U == 0:
			block = n0 // U
			start = ui * block
			return slice(start, start + block)
		raise RuntimeError(f"TopoFuse bank param not sliceable by user: shape0={n0} U={U}")

	def step_(self, *, params: List[nn.Parameter], do_update_mask: List[bool]) -> None:
		if len(do_update_mask) != self.U:
			raise RuntimeError("TopoFuse: do_update_mask length mismatch with U")

		# increment step only for users who update this call
		for ui, do_up in enumerate(do_update_mask):
			if do_up:
				self._step[ui] += 1

		with torch.no_grad():
			for p in params:
				g_full = p.grad
				if g_full is None:
					continue

				# Always detach once; slicing keeps view semantics
				g_full = g_full.detach()

				for ui, do_up in enumerate(do_update_mask):
					if not do_up:
						continue

					sig = self.sigs[ui]
					sl = self._slice_for_user(p, ui)

					# slice views (keep dims consistent)
					p_sl = p.data[sl]
					g_sl = g_full[sl]

					# If we used n0==U, we returned slice(ui,ui+1) which keeps dim0=1.
					# That's fine; state tensors match that shape.

					if sig.name == "sgd":
						self._step_sgd_slice_(p_sl, g_sl, key=(id(p), ui), sig=sig)
					else:
						self._step_adam_slice_(
							p_sl, g_sl,
							key=(id(p), ui),
							sig=sig,
							step=float(self._step[ui]),
							decoupled=(sig.name == "adamw"),
						)

			# clear grads after update to avoid accumulation
			for p in params:
				p.grad = None

	def _step_sgd_slice_(self, p_sl: torch.Tensor, g_sl: torch.Tensor, *, key: Tuple[int, int], sig: OptimSig) -> None:
		lr = float(sig.lr)
		wd = float(sig.weight_decay)
		mom = float(sig.momentum)
		nes = bool(sig.nesterov)

		# weight decay as L2 on grad
		if wd != 0.0:
			g_sl = g_sl.add(p_sl, alpha=wd)

		if mom != 0.0:
			buf = self._mom.get(key)
			if buf is None or buf.shape != g_sl.shape:
				buf = torch.zeros_like(g_sl)
				self._mom[key] = buf
			buf.mul_(mom).add_(g_sl)
			if nes:
				g_use = g_sl.add(buf, alpha=mom)
			else:
				g_use = buf
		else:
			g_use = g_sl

		p_sl.add_(g_use, alpha=-lr)

	def _step_adam_slice_(
		self,
		p_sl: torch.Tensor,
		g_sl: torch.Tensor,
		*,
		key: Tuple[int, int],
		sig: OptimSig,
		step: float,
		decoupled: bool,
	) -> None:
		lr = float(sig.lr)
		b1 = float(sig.beta1)
		b2 = float(sig.beta2)
		eps = float(sig.eps)
		wd = float(sig.weight_decay)

		m = self._m.get(key)
		v = self._v.get(key)
		if m is None or m.shape != g_sl.shape:
			m = torch.zeros_like(g_sl)
			self._m[key] = m
		if v is None or v.shape != g_sl.shape:
			v = torch.zeros_like(g_sl)
			self._v[key] = v

		# AdamW decoupled decay: p -= lr * wd * p
		if decoupled and wd != 0.0:
			p_sl.add_(p_sl, alpha=-lr * wd)
		elif (not decoupled) and wd != 0.0:
			g_sl = g_sl.add(p_sl, alpha=wd)

		m.mul_(b1).add_(g_sl, alpha=1.0 - b1)
		v.mul_(b2).addcmul_(g_sl, g_sl, value=1.0 - b2)

		bc1 = 1.0 - (b1 ** step)
		bc2 = 1.0 - (b2 ** step)

		den = (v.sqrt() / (bc2 ** 0.5)).add_(eps)
		upd = (m / bc1) / den

		p_sl.add_(upd, alpha=-lr)


# -----------------------------------------------------------------------------
# Keep the old BucketOptim if you still want it for SGD-only experiments,
# but DO NOT use it for Adam with banked params (it couples users).
# -----------------------------------------------------------------------------
class BucketOptim:
	"""
	Single shared optimizer for all fused users (leader-based).
	Gradients are already summed by autograd.
	WARNING: unsafe for Adam-style optimizers with banked per-user parameters.
	"""
	def __init__(self, *, sig: OptimSig, device: torch.device):
		self.sig = sig
		self.device = device

		self._step = 0
		self._m: Dict[int, torch.Tensor] = {}
		self._v: Dict[int, torch.Tensor] = {}
		self._mom: Dict[int, torch.Tensor] = {}

	def zero_grad_(self, params: List[nn.Parameter]) -> None:
		for p in params:
			p.grad = None

	def step_(self, *, params: List[nn.Parameter]) -> None:
		sig = self.sig
		if sig.name == "sgd":
			self._step_sgd_(params)
		else:
			self._step_adam_(params, decoupled=(sig.name == "adamw"))

	def _step_sgd_(self, params: List[nn.Parameter]) -> None:
		lr = float(self.sig.lr)
		wd = float(self.sig.weight_decay)
		mom = float(self.sig.momentum)
		nes = bool(self.sig.nesterov)

		with torch.no_grad():
			for p in params:
				g = p.grad
				if g is None:
					continue
				g = g.detach()

				if wd != 0.0:
					g = g.add(p, alpha=wd)

				if mom != 0.0:
					key = id(p)
					buf = self._mom.get(key)
					if buf is None or buf.shape != g.shape:
						buf = torch.zeros_like(g)
						self._mom[key] = buf
					buf.mul_(mom).add_(g)
					g = g.add(buf, alpha=mom) if nes else buf

				p.add_(g, alpha=-lr)

	def _step_adam_(self, params: List[nn.Parameter], decoupled: bool) -> None:
		sig = self.sig
		lr = float(sig.lr)
		b1 = float(sig.beta1)
		b2 = float(sig.beta2)
		eps = float(sig.eps)
		wd = float(sig.weight_decay)

		self._step += 1
		step = float(self._step)

		with torch.no_grad():
			for p in params:
				g = p.grad
				if g is None:
					continue
				g = g.detach()

				key = id(p)
				m = self._m.get(key)
				v = self._v.get(key)

				if m is None or m.shape != g.shape:
					m = torch.zeros_like(g)
					self._m[key] = m
				if v is None or v.shape != g.shape:
					v = torch.zeros_like(g)
					self._v[key] = v

				if decoupled and wd != 0.0:
					p.add_(p, alpha=-lr * wd)
				elif (not decoupled) and wd != 0.0:
					g = g.add(p, alpha=wd)

				m.mul_(b1).add_(g, alpha=1 - b1)
				v.mul_(b2).addcmul_(g, g, value=1 - b2)

				bc1 = 1.0 - b1 ** step
				bc2 = 1.0 - b2 ** step
				den = (v.sqrt() / (bc2 ** 0.5)).add_(eps)
				upd = (m / bc1) / den

				p.add_(upd, alpha=-lr)
