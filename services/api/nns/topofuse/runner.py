# ===== FILE: topofuse/runner.py =====
from __future__ import annotations
from typing import Any, Dict, List

import torch
import torch.nn as nn
import torch.nn.functional as F

import nns.model_core as nodes
from nns.fuse_op import FuseMeta, FuseOp
from .plan import build_nid_to_exec

from common.logger import get_logger

topo = get_logger("topo")
topo_log = get_logger("toporun")

# AOT + banks
from .aot import compile_aot_runner, build_aot_cache_key, AOTCompiled
from .bucket_optim import get_optim_sig, PerUserBankOptim  # <-- NEW import

_DEBUG_EVERY = 512

_DBG = {
	"calls": 0,
	"fused": 0,
	"plain": 0,
	"no_cap": 0,
	"partial_ops": 0,
	"missing_op": 0,
}

def _dbg_tick(kind: str):
	return


def _normalize_ce_targets(y_true: torch.Tensor, y_pred: torch.Tensor) -> torch.Tensor:
	if y_pred.dim() == 1:
		y_pred = y_pred.unsqueeze(0)
	if y_pred.dim() != 2:
		raise ValueError("ce expects logits [N,C]")
	N, C = y_pred.shape
	if y_true.dim() == 0:
		return y_true.view(1).long()
	if y_true.dim() == 1:
		if y_true.numel() == N:
			return y_true.long()
		if N == 1 and y_true.numel() == C:
			return y_true.argmax(dim=0, keepdim=True).long()
		raise ValueError("ce 1d target mismatch")
	if y_true.dim() == 2 and y_true.shape == (N, C):
		return y_true.argmax(dim=1).long()
	raise ValueError("unsupported ce target shape")


def fused_train_step(*, plan, reqs, aot_cache: Dict[str, Any], plan_sig: str) -> None:
	U = len(reqs)

	# ---- batch invariant ----
	B = int(reqs[0].x.shape[0])
	for r in reqs[1:]:
		if int(r.x.shape[0]) != B:
			raise RuntimeError("TopoFuse: batch size mismatch")

	device = plan.device

	# ---- ensure exec maps (unchanged, rare path) ----
	graph = reqs[0].pack["graph"]
	for r in reqs:
		if "_topofuse_exec_map" not in r.ctx.extra:
			nid_to_exec = build_nid_to_exec(graph)
			if not nid_to_exec:
				raise RuntimeError("TopoFuse: canonicalization ambiguous")
			r.ctx.extra["_topofuse_exec_map"] = nid_to_exec
			nodes.get_or_build_fused_main(
				graph,
				r.ctx,
				x_warmup=r.x,
				output_nid=str(r.output_nid),
			)

	# =====================================================
	# AOT lookup / compile
	# =====================================================
	key = build_aot_cache_key(plan_sig=str(plan_sig), output_exec=int(plan.output_exec), reqs=reqs)
	compiled = aot_cache.get(key)

	if compiled is None:
		compiled = compile_aot_runner(plan=plan, reqs=reqs, plan_sig=str(plan_sig))
		compiled.mod = compiled.mod.to(device)
		compiled.banks = compiled.banks.to(device)

		# Build per-user optimizer sigs (must exist for ALL users)
		sigs = []
		for r in reqs:
			s = get_optim_sig(r.ctx)
			if s is None:
				X_dbg = torch.cat([rr.x.to(device) for rr in reqs], dim=0)
				return _fused_train_step_python(plan=plan, reqs=reqs, X=X_dbg)
			sigs.append(s)

		compiled._per_user_optim = PerUserBankOptim(sigs=sigs, device=device)
		compiled._bank_safe = True
		aot_cache[key] = compiled

	# =====================================================
	# Input packing — FAST PATH
	# =====================================================
	X = torch.cat([r.x.to(device) for r in reqs], dim=0)

	# =====================================================
	# Forward (TorchScript)
	# =====================================================
	Y = compiled.mod(X)
	if isinstance(Y, dict):
		Y = Y["tensor"]
	if Y.dim() == 1:
		Y = Y.unsqueeze(1)
	elif Y.dim() > 2:
		Y = Y.view(Y.shape[0], Y.shape[1])

	# =====================================================
	# Loss / backward / optimizer
	# CRITICAL FIX:
	# - match python runner semantics: total_loss = sum_u mean_b CE(u,b)
	# - NOT mean over U*B which scales gradients by 1/U
	# =====================================================
	do_update_mask = [bool(r.do_update) for r in reqs]
	any_update = any(do_update_mask)

	total_loss_t: torch.Tensor | None = None
	loss_u_t: torch.Tensor | None = None

	if any_update:
		y_all = torch.cat([r.y.to(device) for r in reqs], dim=0)
		y_true = _normalize_ce_targets(nodes.to_tensor(y_all, device), Y)  # [U*B]

		# per-sample CE then reshape by user
		# loss_vec: [U*B]
		loss_vec = F.cross_entropy(Y, y_true, reduction="none")
		# loss_u: [U]
		loss_u = loss_vec.view(U, B).mean(dim=1)

		# sum only users that update (supports mixed eval/update)
		mask = torch.tensor(do_update_mask, device=device, dtype=torch.bool)
		total_loss_t = loss_u[mask].sum()
		loss_u_t = loss_u

		# Backward once over fused graph
		params = compiled.banks.all_bank_parameters()
		compiled._per_user_optim.zero_grad_(params)
		total_loss_t.backward()
		compiled._per_user_optim.step_(params=params, do_update_mask=do_update_mask)

	# =====================================================
	# Publish metrics
	# =====================================================
	with torch.no_grad():
		for i, r in enumerate(reqs):
			y_pred = Y[i * B : (i + 1) * B]
			y_true_i = r.y.to(device)

			# loss per user (mean over its batch), matches python runner meaning
			if loss_u_t is not None:
				r.loss = float(loss_u_t[i].detach().item())
			else:
				r.loss = 0.0

			# accuracy
			# NOTE: assumes y_true_i is already class indices [B]
			r.acc = float((y_pred.argmax(dim=1) == y_true_i).float().mean())


# =========================================================
# Old Python runner preserved for debugging / fail-closed
# =========================================================
def _fused_train_step_python(*, plan, reqs, X: torch.Tensor) -> None:
	ctxs = [r.ctx for r in reqs]
	users = len(reqs)
	B = int(reqs[0].x.shape[0])
	device = plan.device

	values: Dict[int, torch.Tensor] = {}
	meta = FuseMeta(users=users, batch=B, device=device)

	for ex in plan.exec_order:
		ops: List[FuseOp | None] = []
		for c in ctxs:
			ops_map = c.extra.get("_torch_ops_exec") or {}
			ops.append(ops_map.get(int(ex)))

		op0 = next((o for o in ops if o is not None), None)

		if op0 is None:
			if plan.pass_through.get(int(ex), False):
				srcs = plan.in_edges.get(int(ex)) or []
				if srcs:
					values[int(ex)] = values[int(srcs[0][0])]
				continue
			raise RuntimeError(f"TopoFuse: missing exec op ex={ex}")

		# gather inputs (same behavior as current runner)
		if int(ex) not in plan.in_edges:
			xs = [X]
		else:
			srcs = plan.in_edges[int(ex)]
			if not srcs:
				xs = [X]
			else:
				xs = [values[int(srcs[0][0])]]

		in_ports = ctxs[0].extra.get("_fuse_in_ports_exec", {}).get(int(ex))
		if in_ports:
			src_map = plan.in_by_port.get(int(ex), {})
			xs = [values[int(src_map[p])] for p in in_ports]

		# execution
		if users == 1:
			y = op0.forward(xs)
		else:
			y = op0.fused_forward(ops, xs, meta)

		values[int(ex)] = y

	Y = values.get(int(plan.output_exec))
	if Y is None:
		raise RuntimeError(f"TopoFuse: output exec not produced: {plan.output_exec}")

	if isinstance(Y, dict) and "tensor" in Y:
		Y = Y["tensor"]
	if Y.dim() == 1:
		Y = Y.unsqueeze(0)
	Y = Y.view(Y.shape[0], -1)

	# loss/back/optim identical to above: reuse by calling the AOT version’s tail if desired
	losses = []
	accs = []

	for i, r in enumerate(reqs):
		y_pred = Y[i * B : (i + 1) * B]
		y_true = r.y.to(device)

		branch_losses = r.ctx.extra.get("branch_losses") or {}
		loss_name = (branch_losses.get(str(r.output_nid)) or "cross_entropy").lower()

		if "ce" in loss_name or "cross" in loss_name:
			y_true_t = _normalize_ce_targets(nodes.to_tensor(y_true, device), y_pred)
			l = nn.CrossEntropyLoss()(y_pred, y_true_t)
			with torch.no_grad():
				a = (y_pred.argmax(dim=1) == y_true_t).float().mean()
		else:
			y_true_t = nodes.to_tensor(y_true, device).to(torch.float32)
			if y_true_t.dim() == 1:
				y_true_t = y_true_t.unsqueeze(0)
			err = y_pred - y_true_t
			l = err.pow(2).mean()
			with torch.no_grad():
				mse = err.pow(2).mean()
				var_y = torch.var(y_true_t, dim=0, unbiased=False).mean().clamp_min(1e-6)
				a = torch.clamp(1.0 - mse / var_y, 0.0, 1.0)

		losses.append(l)
		accs.append(a)

	total_loss = torch.stack(losses).sum()

	for r in reqs:
		cfg = r.ctx.extra.get("_train_step_cfg") or {}
		opt = nodes.get_or_make_optim(r.ctx, cfg)
		if opt is not None and bool(cfg.get("zero_grad", True)):
			opt.zero_grad(set_to_none=True)

	if any(r.do_update for r in reqs):
		total_loss.backward()

	for i, r in enumerate(reqs):
		cfg = r.ctx.extra.get("_train_step_cfg") or {}
		opt = nodes.get_or_make_optim(r.ctx, cfg)
		if not r.do_update or opt is None:
			continue
		max_grad = cfg.get("max_grad_norm")
		if max_grad is not None:
			nn.utils.clip_grad_norm_(nodes.all_params(r.ctx), float(max_grad))
		opt.step()

	for i, r in enumerate(reqs):
		r.loss = float(losses[i].detach().item())
		r.acc = float(accs[i].detach().item())
