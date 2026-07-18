# ===== FILE: topofuse/banks.py =====
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import torch
import torch.nn as nn


@dataclass(frozen=True)
class BankSpec:
	exec_id: int
	kind: str          # "linear" | "conv_grouped"
	U: int
	cfg_hash: str      # from FuseOp.cfg_hash (derived from props.cfg)


class LinearWeightBank(nn.Module):
	def __init__(self, *, U: int, O: int, F: int, use_bias: bool, device: torch.device, dtype: torch.dtype):
		super().__init__()
		self.U = int(U)
		self.O = int(O)
		self.F = int(F)
		self.use_bias = bool(use_bias)

		self.W = nn.Parameter(torch.empty((U, O, F), device=device, dtype=dtype))
		# Always allocate B to keep scripting simple; gate with use_bias.
		self.B = nn.Parameter(torch.empty((U, O), device=device, dtype=dtype))

	def load_from_ops_(self, ops: List[nn.Module]) -> None:
		# ops are FuseOp; we only access .mod.weight/.bias data tensors here
		with torch.no_grad():
			for u, op in enumerate(ops):
				m = op.mod
				self.W[u].copy_(m.weight)
				if self.use_bias:
					self.B[u].copy_(m.bias)

	def export_to_ops_(self, ops: List[nn.Module]) -> None:
		with torch.no_grad():
			for u, op in enumerate(ops):
				m = op.mod
				m.weight.copy_(self.W[u])
				if self.use_bias:
					m.bias.copy_(self.B[u])


class ConvGroupedWeightBank(nn.Module):

	def __init__(
		self,
		*,
		U: int,
		O: int,
		C: int,
		kH: int,
		kW: int,
		use_bias: bool,
		device: torch.device,
		dtype: torch.dtype,
	):
		super().__init__()
		self.U = int(U)
		self.O = int(O)
		self.C = int(C)
		self.kH = int(kH)
		self.kW = int(kW)
		self.use_bias = bool(use_bias)

		self.W = nn.Parameter(torch.empty((U * O, C, kH, kW), device=device, dtype=dtype))
		self.B = nn.Parameter(torch.empty((U * O,), device=device, dtype=dtype))

	def load_from_ops_(self, ops: List[nn.Module]) -> None:
		with torch.no_grad():
			for u, op in enumerate(ops):
				m = op.mod
				start = u * self.O
				end = (u + 1) * self.O
				self.W[start:end].copy_(m.weight)
				if self.use_bias:
					self.B[start:end].copy_(m.bias)

	def export_to_ops_(self, ops: List[nn.Module]) -> None:
		with torch.no_grad():
			for u, op in enumerate(ops):
				m = op.mod
				start = u * self.O
				end = (u + 1) * self.O
				m.weight.copy_(self.W[start:end])
				if self.use_bias:
					m.bias.copy_(self.B[start:end])


class BankRegistry(nn.Module):
	"""
	Holds banks keyed by exec_id so AOT kernels can reference them.
	Also provides export of packed weights back to per-user modules.
	"""
	def __init__(self):
		super().__init__()
		self.linear: nn.ModuleDict = nn.ModuleDict()
		self.conv_grouped: nn.ModuleDict = nn.ModuleDict()

		# exec_id -> list[FuseOp] used for export (Python-side only)
		self._ops_by_exec: Dict[int, List[nn.Module]] = {}

	def register_linear(self, *, exec_id: int, bank: LinearWeightBank, ops: List[nn.Module]) -> None:
		self.linear[str(int(exec_id))] = bank
		self._ops_by_exec[int(exec_id)] = ops

	def register_conv_grouped(self, *, exec_id: int, bank: ConvGroupedWeightBank, ops: List[nn.Module]) -> None:
		self.conv_grouped[str(int(exec_id))] = bank
		self._ops_by_exec[int(exec_id)] = ops

	def load_all_from_ops_(self) -> None:
		for k, bank in self.linear.items():
			ex = int(k)
			bank.load_from_ops_(self._ops_by_exec[ex])
		for k, bank in self.conv_grouped.items():
			ex = int(k)
			bank.load_from_ops_(self._ops_by_exec[ex])

	def export_all_to_ops_(self) -> None:
		for k, bank in self.linear.items():
			ex = int(k)
			bank.export_to_ops_(self._ops_by_exec[ex])
		for k, bank in self.conv_grouped.items():
			ex = int(k)
			bank.export_to_ops_(self._ops_by_exec[ex])

	def all_bank_parameters(self) -> List[nn.Parameter]:
		params: List[nn.Parameter] = []
		for bank in self.linear.values():
			params.extend(list(bank.parameters()))
		for bank in self.conv_grouped.values():
			params.extend(list(bank.parameters()))
		return params
