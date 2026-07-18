# ===== nns/fuse_op.py =====
from __future__ import annotations
from typing import List

import torch
import torch.nn as nn

# opcodes (TorchScript-friendly)
OP_UNARY = 0
OP_CAT   = 1
OP_SOFTMAX = 2
OP_FLATTEN = 3
OP_IDENTITY = 4
OP_VIEW2D = 5
OP_INPUT_PREP = 6
OP_SHAPE_ADAPTER = 7

# activations
ACT_NONE = 0
ACT_RELU = 1
ACT_SIGMOID = 2
ACT_TANH = 3

def _act_id(act) -> int:
	if not act or act == "none":
		return ACT_NONE
	a = str(act).lower()
	if a == "relu":
		return ACT_RELU
	if a == "sigmoid":
		return ACT_SIGMOID
	if a == "tanh":
		return ACT_TANH
	return ACT_NONE

class FuseOp(nn.Module):
	"""
	ONE class for everything.
	Forward signature: forward(List[Tensor]) -> Tensor
	"""
	def __init__(
		self,
		op: int,
		*,
		mod: nn.Module | None = None,
		act: int = ACT_NONE,
		dim: int = 1,
		r: int = -1,
		c: int = -1,
		batch_already: bool = False,
		have_rc: bool = False,
	):
		super().__init__()
		self.op = int(op)
		self.act = int(act)
		self.dim = int(dim)
		self.r = int(r)
		self.c = int(c)
		self.batch_already = bool(batch_already)
		self.have_rc = bool(have_rc)

		self.mod = mod if mod is not None else nn.Identity()

	def forward(self, xs: List[torch.Tensor]) -> torch.Tensor:
		op = int(self.op)

		if op == 0:  # OP_UNARY
			y = self.mod(xs[0])
			a = int(self.act)
			if a == 1:  # ACT_RELU
				return torch.relu(y)
			if a == 2:  # ACT_SIGMOID
				return torch.sigmoid(y)
			if a == 3:  # ACT_TANH
				return torch.tanh(y)
			return y

		if op == 1:  # OP_CAT
			return torch.cat(xs, dim=int(self.dim)).to(torch.float32)

		if op == 2:  # OP_SOFTMAX
			return torch.softmax(xs[0], dim=int(self.dim))

		if op == 3:  # OP_FLATTEN
			x = xs[0]
			if x.dim() == 1:
				x = x.unsqueeze(0)
			return x.view(x.shape[0], -1)

		if op == 4:  # OP_IDENTITY
			return xs[0]

		if op == 5:  # OP_VIEW2D
			x = xs[0]
			r = int(self.r)
			c = int(self.c)
			if r <= 0 or c <= 0:
				return x
			if x.dim() == 0:
				x = x.view(1, 1)
			elif x.dim() == 1:
				x = x.unsqueeze(0)
			if x.dim() == 2:
				return x.contiguous().view(x.shape[0], r, c)
			return x

		if op == 6: # OP_INPUT_PREP
			x = xs[0]
			r = int(self.r)
			c = int(self.c)

			# ---- batch normalization ----
			if self.batch_already:
				if x.dim() == 0:
					x = x.view(1, 1)
				elif x.dim() == 1:
					x = x.view(-1, 1)
			else:
				if x.dim() == 0:
					x = x.view(1, 1)
				elif x.dim() == 1:
					x = x.unsqueeze(0)
				elif x.dim() == 2:
					x = x.unsqueeze(0)

			# ---- spatial reshape ----
			if self.have_rc and r > 0 and c > 0:
				if x.dim() == 2:
					x = x.contiguous().view(x.shape[0], r, c)

			# ---- CANONICALIZE: no rank-3 allowed ----
			if x.dim() == 3:
				x = x.unsqueeze(1)  # [N,1,H,W]

			return x

		if op == 7: # OP_SHAPE_ADAPTER
			x = xs[0]
			# policy: ensure [N,C,H,W]
			if x.dim() == 3:
				x = x.unsqueeze(1)  # [N,1,H,W]
			elif x.dim() == 4:
				pass
			else:
				raise RuntimeError(f"Expected 3D or 4D tensor, got {x.shape}")
			return x

		return xs[0]


# tiny factories => node code stays 1 line
def op_unary(mod: nn.Module, act=None) -> nn.Module:
	return FuseOp(OP_UNARY, mod=mod, act=_act_id(act))

def op_cat(dim: int = 1) -> nn.Module:
	return FuseOp(OP_CAT, dim=dim)

def op_softmax(dim: int = 1) -> nn.Module:
	return FuseOp(OP_SOFTMAX, dim=dim)

def op_flatten() -> nn.Module:
	return FuseOp(OP_FLATTEN)

def op_identity() -> nn.Module:
	return FuseOp(OP_IDENTITY)

def op_view2d(r: int, c: int) -> nn.Module:
	return FuseOp(OP_VIEW2D, r=r, c=c)

def op_input(batch_already: bool, have_rc: bool, r: int, c: int) -> nn.Module:
	return FuseOp(OP_INPUT_PREP, batch_already=batch_already, have_rc=have_rc, r=r, c=c)

def op_shape_adapter() -> nn.Module:
	return FuseOp(OP_SHAPE_ADAPTER)