# ===== nns/grad_gating.py =====
from __future__ import annotations
from typing import Any, Dict, List
import math
import torch
import torch.nn as nn
from .utils import pick_device
def _policy_state(ctx, n: int) -> Dict[str, Any]:
	"""
	period[i]: update every 'period' steps (1 => always).
	ema[i]: EMA of grad norm for params in op i.
	"""
	st = ctx.extra.setdefault("_grad_gate_policy", {})
	if st.get("n") != n:
		st.clear()
		st["n"] = n
		st["period"] = [1] * n
		st["ema"] = [0.0] * n
		st["ones"] = torch.ones(n, device=pick_device(ctx))

		# knobs (safe defaults)
		st["beta"] = 0.90
		st["max_period"] = 16
		st["low_ratio"] = 0.30
		st["high_ratio"] = 1.50
		st["head_keep"] = 2  # last K trainable ops always update each step
	return st

def build_grad_gates(ctx, entry: Dict[str, Any], *, device: torch.device) -> torch.Tensor:
	"""
	Compute gates for this step based on current periods.
	Stores 'entry' pointer in ctx for later policy update after backward.
	"""
	n = int(entry["order_len"])
	st = _policy_state(ctx, n)
	if ctx.extra.get("_sections_last_acc", 0.0) < 0.7:
		return ctx.extra["_grad_gate_policy"]["ones"]

	step = int(ctx.extra.get("_train_step", 0))
	period: List[int] = st["period"]
	trainable: List[bool] = entry["trainable_mask"]

	# keep last K trainable ops always open
	trainable_idx = [i for i, t in enumerate(trainable) if t]
	if trainable_idx:
		k = int(st["head_keep"])
		if k > 0:
			for i in trainable_idx[-k:]:
				period[i] = 1

	gates = torch.ones((n,), device=device, dtype=torch.float32)
	for i in range(n):
		if not trainable[i]:
			continue
		p = int(period[i])
		if p > 1 and (step % p) != 0:
			gates[i] = 0.0

	# stash for update after backward
	ctx.extra["_grad_gate_last_entry"] = entry
	ctx.extra["_grad_gate_last_gates"] = gates
	return gates

def update_policy_after_backward(ctx) -> None:
	"""
	Update EMA + periods using current gradients.
	Call AFTER total_loss.backward().
	"""
	if ctx.extra.get("_sections_last_acc", 0.0) < 0.7:

		return
	entry = ctx.extra.get("_grad_gate_last_entry")

	n = int(entry["order_len"])
	st = _policy_state(ctx, n)

	param_groups: List[List[nn.Parameter]] = entry["param_groups"]
	trainable: List[bool] = entry["trainable_mask"]

	# per-op grad L2 norm
	norms: List[float] = [0.0] * n
	for i in range(n):
		if not trainable[i]:
			continue
		ss = 0.0
		for p in param_groups[i]:
			g = p.grad
			if g is None:
				continue
			ss += float(g.detach().pow(2).sum().item())
		norms[i] = math.sqrt(ss) if ss > 0.0 else 0.0

	active = sorted([v for i, v in enumerate(norms) if trainable[i] and v > 0.0])
	if not active:
		return

	med = active[len(active) // 2]
	eps = 1e-12

	beta = float(st["beta"])
	ema: List[float] = st["ema"]
	period: List[int] = st["period"]

	low = float(st["low_ratio"])
	high = float(st["high_ratio"])
	maxp = int(st["max_period"])

	for i in range(n):
		if not trainable[i]:
			continue
		ema[i] = beta * float(ema[i]) + (1.0 - beta) * float(norms[i])

		ratio = float(ema[i]) / (float(med) + eps)
		if ratio < low:
			period[i] = min(int(period[i]) * 2, maxp)
		elif ratio > high:
			period[i] = max(int(period[i]) // 2, 1)

	# re-enforce head_keep
	trainable_idx = [i for i, t in enumerate(trainable) if t]
	if trainable_idx:
		k = int(st["head_keep"])
		if k > 0:
			for i in trainable_idx[-k:]:
				period[i] = 1
