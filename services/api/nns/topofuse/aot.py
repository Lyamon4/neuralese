# ===== FILE: topofuse/aot.py =====
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import hashlib
import json

import torch
import torch.nn as nn
import torch.nn.functional as F

from .banks import BankRegistry, LinearWeightBank, ConvGroupedWeightBank

from nns.fuse_op import (
	FuseOp,
	OP_UNARY, OP_CAT, OP_SOFTMAX, OP_FLATTEN, OP_IDENTITY, OP_VIEW2D, OP_INPUT_PREP, OP_SHAPE_ADAPTER,
	ACT_NONE, ACT_RELU, ACT_SIGMOID, ACT_TANH,
)

# ============================================================
# AOT TopoFuse:
# - compile-time decides per-step fuse mode
# - runtime executes a fixed kernel list (TorchScript)
# - no per-step Python logic
# - banked weights: NO stack/cat in hot linear/conv kernels
# ============================================================

# Fuse modes (compile-time only)
FUSE_SHARED         = 0  # single shared op for all users (safe)
FUSE_LINEAR_BATCHED = 1  # linear banked bmm path
FUSE_CONV_GROUPED   = 2  # conv banked grouped conv path
FUSE_FALLBACK       = 3  # per-user forward inside scripted kernel
FUSE_PASSTHRU       = 4  # pass-through alias

_DEFAULT_CONV_GROUP_THRESHOLD = 4  # keep identical to your current policy


@dataclass
class AOTCompiled:
	mod: torch.jit.ScriptModule
	banks: BankRegistry
	U: int


def _stable_hash(obj: Any, n: int = 16) -> str:
	s = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
	return hashlib.sha1(s.encode("utf-8")).hexdigest()[:n]


def _module_section_id(mod: nn.Module) -> str:
	return str(getattr(mod, "_section_id", ""))


def _all_same_nonempty(xs: List[str]) -> bool:
	if not xs or any(not x for x in xs):
		return False
	return all(x == xs[0] for x in xs)


def build_aot_cache_key(
	*,
	plan_sig: str,
	output_exec: int,
	reqs: List[Any],  # manager._Req
) -> str:
	"""
	Cache key must change whenever per-step compatibility changes.
	We hash:
	- plan signature (topology bucket key already computed upstream)
	- users count
	- per-user input shape/dtype
	- per-step per-user op signatures (cfg_hash)
	- output_exec
	"""
	ctxs = [r.ctx for r in reqs]
	users = len(reqs)

	x_sigs: List[Dict[str, Any]] = []
	for r in reqs:
		x = r.x
		x_sigs.append({
			"shape": tuple(int(i) for i in x.shape),
			"dtype": str(x.dtype),
		})

	ops_sigs: List[List[Dict[str, Any]]] = []
	for c in ctxs:
		ops_map = c.extra.get("_torch_ops_exec") or {}
		if not isinstance(ops_map, dict):
			ops_map = {}
		ops_sigs.append([
			{
				"ex": int(ex),
				"cfg": getattr(ops_map.get(int(ex)), "cfg_hash", ""),
			}
			for ex in sorted(ops_map.keys())
		])

	obj = {
		"plan_sig": str(plan_sig),
		"users": int(users),
		"x": x_sigs,
		"ops": ops_sigs,
		"out": int(output_exec),
	}
	return _stable_hash(obj, 20)


# ============================================================
# Kernels (TorchScript-friendly)
# ============================================================

class _AOTKernel(nn.Module):
	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		raise NotImplementedError


class PassthroughKernel(_AOTKernel):
	"""
	Pass-through: returns xs[0] as-is.
	Kept minimal: upstream already ensures X is [U*B,...] for fused runs.
	"""
	def __init__(self):
		super().__init__()

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		return xs[0]


class SharedFuseOpKernel(_AOTKernel):
	def __init__(self, op: FuseOp, *, U: int):
		super().__init__()
		self.op = op
		self.U = int(U)

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		X = xs[0]
		if self.U == 1:
			return self.op.forward(xs)

		# CRITICAL: only take leader slice and repeat
		B = int(X.shape[0] // self.U)
		xs0 = [t[:B] for t in xs]
		y0 = self.op.forward(xs0)
		return y0.repeat(self.U, *([1] * (y0.dim() - 1)))


# ------------------------------------------------------------
# Old kernels (kept for debugging / fallback)
# NOTE: these do stack/cat at runtime => NOT used in banked modes
# ------------------------------------------------------------

class LinearBatchedKernel(_AOTKernel):
	def __init__(self, ops: List[FuseOp]):
		super().__init__()
		self.ops = nn.ModuleList(ops)
		self.U = int(len(ops))

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		X = xs[0]  # [U*B, F]
		U = self.U
		B = int(X.shape[0] // U)

		xu = X.view(U, B, -1)  # [U,B,F]

		ws = torch.jit.annotate(List[torch.Tensor], [])
		for i in range(U):
			ws.append(self.ops[i].mod.weight)
		w = torch.stack(ws, dim=0)  # [U,O,F]

		y = torch.bmm(xu, w.transpose(1, 2))  # [U,B,O]

		all_bias = True
		for i in range(U):
			if self.ops[i].mod.bias is None:
				all_bias = False
				break

		if all_bias:
			bs = torch.jit.annotate(List[torch.Tensor], [])
			for i in range(U):
				bs.append(self.ops[i].mod.bias)
			b = torch.stack(bs, dim=0).unsqueeze(1)  # [U,1,O]
			y = y + b

		return y.reshape(U * B, -1)


class ConvGroupedKernel(_AOTKernel):
	def __init__(self, ops: List[FuseOp], *, act: int):
		super().__init__()
		self.ops = nn.ModuleList(ops)
		self.U = int(len(ops))
		self.act = int(act)

		m0: nn.Conv2d = ops[0].mod
		self.stride = m0.stride
		self.padding = m0.padding
		self.dilation = m0.dilation

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		X = xs[0]  # [U*B,C,H,W]
		U = self.U
		B = int(X.shape[0] // U)
		C = int(X.shape[1])

		xg = (
			X.view(U, B, C, *X.shape[2:])
			 .transpose(0, 1)
			 .reshape(B, U * C, *X.shape[2:])
		)

		ws = torch.jit.annotate(List[torch.Tensor], [])
		for i in range(U):
			ws.append(self.ops[i].mod.weight)
		w = torch.cat(ws, dim=0)

		all_bias = True
		for i in range(U):
			if self.ops[i].mod.bias is None:
				all_bias = False
				break

		bias = None
		if all_bias:
			bs = torch.jit.annotate(List[torch.Tensor], [])
			for i in range(U):
				bs.append(self.ops[i].mod.bias)
			bias = torch.cat(bs, dim=0)

		yg = F.conv2d(
			xg, w, bias=bias,
			stride=self.stride,
			padding=self.padding,
			dilation=self.dilation,
			groups=U,
		)

		OC = int(yg.shape[1] // U)
		y = (
			yg.view(B, U, OC, *yg.shape[2:])
			  .transpose(0, 1)
			  .reshape(U * B, OC, *yg.shape[2:])
		)

		a = self.act
		if a == ACT_RELU:
			return torch.relu(y)
		if a == ACT_SIGMOID:
			return torch.sigmoid(y)
		if a == ACT_TANH:
			return torch.tanh(y)
		return y


# ------------------------------------------------------------
# Bank-backed kernels (NO stack/cat in hot path)
# ------------------------------------------------------------

class LinearBankedKernel(_AOTKernel):
	def __init__(self, bank: LinearWeightBank):
		super().__init__()
		self.bank = bank
		self.U = int(bank.U)

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		X = xs[0]  # [U*B, F]
		U = self.U
		B = int(X.shape[0] // U)

		xu = X.view(U, B, -1)  # [U,B,F]
		y = torch.bmm(xu, self.bank.W.transpose(1, 2))  # [U,B,O]

		if self.bank.use_bias:
			y = y + self.bank.B.unsqueeze(1)  # [U,1,O]

		return y.reshape(U * B, -1)


class ConvGroupedBankedKernel(_AOTKernel):
	def __init__(self, bank: ConvGroupedWeightBank, *, act: int, stride, padding, dilation):
		super().__init__()
		self.bank = bank
		self.U = int(bank.U)
		self.act = int(act)
		self.stride = stride
		self.padding = padding
		self.dilation = dilation

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		X = xs[0]  # [U*B,C,H,W]
		U = self.U
		B = int(X.shape[0] // U)
		C = int(X.shape[1])

		xg = (
			X.view(U, B, C, *X.shape[2:])
			 .transpose(0, 1)
			 .reshape(B, U * C, *X.shape[2:])
		)

		bias = self.bank.B if self.bank.use_bias else None
		yg = F.conv2d(
			xg, self.bank.W, bias=bias,
			stride=self.stride,
			padding=self.padding,
			dilation=self.dilation,
			groups=U,
		)

		OC = int(yg.shape[1] // U)
		y = (
			yg.view(B, U, OC, *yg.shape[2:])
			  .transpose(0, 1)
			  .reshape(U * B, OC, *yg.shape[2:])
		)

		a = self.act
		if a == ACT_RELU:
			return torch.relu(y)
		if a == ACT_SIGMOID:
			return torch.sigmoid(y)
		if a == ACT_TANH:
			return torch.tanh(y)
		return y


class FallbackKernel(_AOTKernel):
	"""
	Per-user forward inside TorchScript (no Python loop).
	WARNING: this still uses torch.cat at the end (not hot in banked cases).
	"""
	def __init__(self, ops: List[FuseOp]):
		super().__init__()
		self.ops = nn.ModuleList(ops)
		self.U = int(len(ops))

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		U = self.U
		X0 = xs[0]
		B = int(X0.shape[0] // U)

		ys = torch.jit.annotate(List[torch.Tensor], [])
		for ui in range(U):
			xu = torch.jit.annotate(List[torch.Tensor], [])
			start = ui * B
			end = (ui + 1) * B
			for t in xs:
				xu.append(t[start:end])
			ys.append(self.ops[ui].forward(xu))

		return torch.cat(ys, dim=0)


# ============================================================
# AOT Runner (fixed kernel list, fixed input wiring)
# ============================================================

class AOTRunner(nn.Module):
	"""
	- kernels[i] executes exec node i (aligned with plan.exec_order iteration order)
	- src_index[i, j] indexes into `vals` list (vals[0] == X, vals[ex+1] == output of exec ex)
	- src_len[i] is number of inputs for node i
	"""
	def __init__(
		self,
		*,
		kernels: List[nn.Module],
		src_index: torch.Tensor,
		src_len: torch.Tensor,
		output_index: int,
	):
		super().__init__()
		self.kernels = nn.ModuleList(kernels)
		self.src_index = src_index.to(torch.int64)
		self.src_len = src_len.to(torch.int64)
		self.output_index = int(output_index)

	def forward(self, X: torch.Tensor) -> torch.Tensor:
		vals = torch.jit.annotate(List[torch.Tensor], [])
		vals.append(X)

		N = int(self.src_len.numel())
		for i in range(N):
			K = int(self.src_len[i])

			xs = torch.jit.annotate(List[torch.Tensor], [])
			for j in range(K):
				idx = int(self.src_index[i, j])
				xs.append(vals[idx])

			y = self.kernels[i](xs)
			vals.append(y)

		return vals[int(self.output_index)]


# ============================================================
# Compile-time decision logic
# ============================================================

def _same_static_config(a: FuseOp, b: FuseOp) -> bool:
	# semantic equality = exact node.config equality
	# (cfg_hash must be derived from props.cfg upstream)
	return (a.cfg_hash and a.cfg_hash == b.cfg_hash)


def _can_shared_unary(ops: List[FuseOp]) -> bool:
	section_ids = [_module_section_id(op.mod) for op in ops]
	if _all_same_nonempty(section_ids):
		return True
	if all(isinstance(op.mod, nn.Identity) for op in ops):
		return True
	return False


def _can_linear_batched(ops: List[FuseOp]) -> bool:
	if not ops:
		return False
	if not all(isinstance(op.mod, nn.Linear) for op in ops):
		return False
	m0: nn.Linear = ops[0].mod
	in_f = int(m0.in_features)
	out_f = int(m0.out_features)
	bias0 = (m0.bias is not None)
	for op in ops[1:]:
		m: nn.Linear = op.mod
		if int(m.in_features) != in_f or int(m.out_features) != out_f:
			return False
		if (m.bias is not None) != bias0:
			return False
	return True


def _can_conv_grouped(ops: List[FuseOp], *, U: int) -> bool:
	if not ops:
		return False
	if not all(isinstance(op.mod, nn.Conv2d) for op in ops):
		return False

	m0: nn.Conv2d = ops[0].mod
	for op in ops[1:]:
		m: nn.Conv2d = op.mod
		if int(m.in_channels) != int(m0.in_channels): return False
		if int(m.out_channels) != int(m0.out_channels): return False
		if tuple(m.kernel_size) != tuple(m0.kernel_size): return False
		if tuple(m.stride) != tuple(m0.stride): return False
		if tuple(m.padding) != tuple(m0.padding): return False
		if tuple(m.dilation) != tuple(m0.dilation): return False
		if int(m.groups) != int(m0.groups): return False
		if (m.bias is not None) != (m0.bias is not None): return False

	return True


def compile_aot_runner(
	*,
	plan: Any,           # topofuse.plan.Plan
	reqs: List[Any],     # manager._Req list
	plan_sig: str,
) -> AOTCompiled:
	"""
	Compile and trace an AOTRunner for THIS EXACT group composition + per-user op signatures.

	Returns AOTCompiled:
	- mod: traced ScriptModule (fast forward path)
	- banks: packed weight banks (Parameters) used by banked kernels
	- U: user count for this compiled group
	"""
	ctxs = [r.ctx for r in reqs]
	U = int(len(reqs))

	# Per-user exec ops
	ops_maps: List[Dict[int, FuseOp]] = []
	for c in ctxs:
		ops_map = c.extra.get("_torch_ops_exec") or {}
		if not isinstance(ops_map, dict):
			ops_map = {}
		ops_maps.append(ops_map)

	# Ports ordering (for Cat / multi-input nodes), use leader ctx only
	leader_ports = ctxs[0].extra.get("_fuse_in_ports_exec") or {}
	if not isinstance(leader_ports, dict):
		leader_ports = {}

	N = len(plan.exec_order)

	# Input wiring tensors
	src_lists: List[List[int]] = []
	kernels: List[nn.Module] = []

	# Bank registry for this compiled module
	banks = BankRegistry()

	for ex in plan.exec_order:
		exi = int(ex)

		# ----------------------------
		# Determine input sources
		# ----------------------------
		in_ports = leader_ports.get(exi)
		if in_ports:
			src_map = plan.in_by_port.get(exi, {})
			src_execs = [int(src_map[p]) for p in in_ports]
		else:
			srcs = plan.in_edges.get(exi) or []
			if srcs:
				src_execs = [int(srcs[0][0])]
			else:
				src_execs = []

		if not src_execs:
			src_idx = [0]  # read initial X
		else:
			src_idx = [s + 1 for s in src_execs]  # vals[0] is X

		src_lists.append(src_idx)

		# ----------------------------
		# Collect per-user ops
		# ----------------------------
		ops: List[Optional[FuseOp]] = []
		for m in ops_maps:
			ops.append(m.get(exi))

		op0 = next((o for o in ops if o is not None), None)

		# Pass-through nodes may legally have no op
		if op0 is None:
			if bool(plan.pass_through.get(exi, False)):
				kernels.append(PassthroughKernel())
				continue
			raise RuntimeError(f"TopoFuse AOT: missing op for exec={exi} and not pass-through")

		# If not pass-through, require all users have an op
		if any(o is None for o in ops):
			raise RuntimeError(f"TopoFuse AOT: partial missing ops at exec={exi}")

		ops_nn: List[FuseOp] = [o for o in ops if o is not None]  # type: ignore

		# ----------------------------
		# Decide fuse mode ONCE
		# ----------------------------
		mode = FUSE_FALLBACK

		# Shared stateless ops (must match static config)
		if int(op0.op) in (OP_CAT, OP_SOFTMAX, OP_FLATTEN, OP_IDENTITY, OP_VIEW2D, OP_INPUT_PREP, OP_SHAPE_ADAPTER):
			if all(_same_static_config(op0, o) for o in ops_nn[1:]):
				mode = FUSE_SHARED

		# Unary ops
		if int(op0.op) == OP_UNARY:
			if _can_shared_unary(ops_nn) and all(_same_static_config(op0, o) for o in ops_nn[1:]):
				mode = FUSE_SHARED
			elif _can_linear_batched(ops_nn):
				mode = FUSE_LINEAR_BATCHED
			elif (_can_conv_grouped(ops_nn, U=U) and U >= _DEFAULT_CONV_GROUP_THRESHOLD):
				mode = FUSE_CONV_GROUPED
			else:
				mode = FUSE_FALLBACK

		# ----------------------------
		# Build kernel module
		# ----------------------------
		if mode == FUSE_SHARED:
			kernels.append(SharedFuseOpKernel(op0, U=U))

		elif mode == FUSE_LINEAR_BATCHED:
			# allocate packed parameter ONCE (no stack per forward)
			m0: nn.Linear = ops_nn[0].mod
			Uu = len(ops_nn)
			O = int(m0.out_features)
			Ff = int(m0.in_features)
			use_bias = (m0.bias is not None)

			bank = LinearWeightBank(U=Uu, O=O, F=Ff, use_bias=use_bias, device=plan.device, dtype=m0.weight.dtype)
			bank.load_from_ops_(ops_nn)

			banks.register_linear(exec_id=exi, bank=bank, ops=ops_nn)
			kernels.append(LinearBankedKernel(bank))

		elif mode == FUSE_CONV_GROUPED:
			m0: nn.Conv2d = ops_nn[0].mod
			Uu = len(ops_nn)
			O = int(m0.out_channels)
			C = int(m0.in_channels)
			kH = int(m0.kernel_size[0])
			kW = int(m0.kernel_size[1])
			use_bias = (m0.bias is not None)

			bank = ConvGroupedWeightBank(U=Uu, O=O, C=C, kH=kH, kW=kW, use_bias=use_bias, device=plan.device, dtype=m0.weight.dtype)
			bank.load_from_ops_(ops_nn)

			banks.register_conv_grouped(exec_id=exi, bank=bank, ops=ops_nn)
			kernels.append(
				ConvGroupedBankedKernel(
					bank,
					act=int(getattr(op0, "act", 0)),
					stride=m0.stride,
					padding=m0.padding,
					dilation=m0.dilation,
				)
			)

		elif bool(plan.pass_through.get(exi, False)):
			kernels.append(PassthroughKernel())

		else:
			kernels.append(FallbackKernel(ops_nn))

	# Pack src_lists into fixed tensors
	max_in = 1
	for s in src_lists:
		if len(s) > max_in:
			max_in = len(s)

	src_index = torch.full((N, max_in), 0, dtype=torch.int64)  # default to X
	src_len = torch.zeros((N,), dtype=torch.int64)
	for i, s in enumerate(src_lists):
		src_len[i] = int(len(s))
		for j, idx in enumerate(s):
			src_index[i, j] = int(idx)

	out_idx = int(plan.output_exec) + 1  # exec id -> vals index

	mod = AOTRunner(
		kernels=kernels,
		src_index=src_index,
		src_len=src_len,
		output_index=out_idx,
	)

	# Trace: avoids TorchScript class redefinition issues
	device = plan.device
	example_x = torch.cat([r.x.to(device) for r in reqs], dim=0)  # [U*B, ...] (compile-time only)

	scripted = torch.jit.trace(
		mod,
		(example_x,),
		check_trace=False,
		strict=False,
	)

	return AOTCompiled(mod=scripted, banks=banks, U=U)
