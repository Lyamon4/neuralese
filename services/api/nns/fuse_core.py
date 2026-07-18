# ===== nns/fuse_core.py =====
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

import torch
import torch.nn as nn

from .graph_core import _ensure_dict
from .fuse_op import op_identity

TorchOp = nn.Module

@torch.jit.script
def _grad_gate(y: torch.Tensor, g: torch.Tensor) -> torch.Tensor:
	"""
	TorchScript-friendly gradient gate.
	g: scalar float tensor in {0,1}.
	Forward stays == y, but autograd path is cut when g==0.
	"""
	return y * g + y.detach() * (1.0 - g)

def _build_incoming(node_defs: Dict[str, Tuple[str, Dict[str, Any]]]) -> Dict[str, Dict[str, List[str]]]:
	"""
	incoming[tgt_nid][tgt_port] = [src_nid, ...] in deterministic order
	(node_defs values are (page_k, blob); blob["emit"] drives wiring)
	"""
	incoming: Dict[str, Dict[str, List[str]]] = {}
	for src_nid, (_page_k, blob) in node_defs.items():
		emit = _ensure_dict(blob.get("emit"))
		for _out_port, fanouts in emit.items():
			for tgt_id, tgt_ports in _ensure_dict(fanouts).items():
				for tgt_port in (tgt_ports or []):
					incoming.setdefault(str(tgt_id), {}).setdefault(str(tgt_port), []).append(str(src_nid))
	return incoming


class FusedForward(nn.Module):
	"""
	Tracing-friendly fused forward:
	- ops[i] corresponds to order[i]
	- in_srcs[i] is list of source node ids (or "__INPUT__")
	"""
	def __init__(
		self,
		*,
		order: List[str],
		in_srcs: List[List[str]],
		ops: nn.ModuleList,
		output_nid: str,
	):
		super().__init__()
		self.order = list(order)
		self.in_srcs = in_srcs
		self.ops = ops
		self.output_nid = str(output_nid)

		n2i: Dict[str, int] = {}
		for i, nid in enumerate(self.order):
			n2i[str(nid)] = i
		self._nid_to_i = n2i

	def forward(self, x: torch.Tensor, grad_gates: torch.Tensor) -> torch.Tensor:
		"""
		grad_gates: 1D float tensor [len(order)] with values in {0,1}.
		- 1: normal
		- 0: detach at this node output (cuts grads for this op + all ancestors)
		"""
		vals: List[torch.Tensor] = []

		for i in range(len(self.order)):

			src_ids = self.in_srcs[i]

			if not src_ids:
				xs = [x]
			else:
				xs = []
				for sid in src_ids:
					j = self._nid_to_i[sid]
					xs.append(vals[j])

			y = self.ops[i](xs)

			# grad gate per node (must be inside traced forward to save backward FLOPs)
			y = _grad_gate(y, grad_gates[i])

			vals.append(y)

		return vals[self._nid_to_i[self.output_nid]]





def build_fused_forward(compiled, ctx, *, output_nid: str) -> nn.Module:
	order: List[str] = [str(n) for n in getattr(compiled, "order", [])]
	if not order:
		raise ValueError("build_fused_forward: compiled.order is empty")

	node_defs = getattr(compiled, "node_defs", None)
	if not isinstance(node_defs, dict) or not node_defs:
		raise ValueError("build_fused_forward: compiled.node_defs is missing/empty")

	# map output_nid (may be props['nid']) -> actual node key in order
	out_id = str(output_nid)
	if out_id not in set(order):
		found = None
		for nid in order:
			v = node_defs.get(nid)
			if isinstance(v, tuple) and len(v) == 2:
				_blob = v[1]
				props = _ensure_dict(_blob.get("props"))
				if str(props.get("nid", "")) == out_id:
					found = nid
					break
		if found is None:
			raise ValueError(f"build_fused_forward: output_nid={out_id} not found in compiled.order nor props.nid")
		out_id = found

	# real wiring source: node_defs[*].emit
	incoming_by_port: Dict[str, Dict[str, List[str]]] = {}
	for src_nid, (_page_k, blob) in node_defs.items():
		emit = _ensure_dict(blob.get("emit"))
		for _out_port, fanouts in emit.items():
			for tgt_id, tgt_ports in _ensure_dict(fanouts).items():
				for tgt_port in (tgt_ports or []):
					incoming_by_port.setdefault(str(tgt_id), {}).setdefault(str(tgt_port), []).append(str(src_nid))

	# optional per-node port ordering (Concat etc)
	fuse_in_ports: Dict[str, List[str]] = ctx.extra.get("_fuse_in_ports", {}) or {}

	# IMPORTANT FIX:
	# Do NOT special-case i==0. Any node with no incoming is a root and receives "__INPUT__".
	in_srcs: List[List[str]] = []
	for nid in order:
		ports_map = incoming_by_port.get(nid, {}) or {}
		if not ports_map:
			# root node must consume previous node, not raw input
			in_srcs.append([])
			continue

		port_order = fuse_in_ports.get(nid)
		if port_order:
			srcs: List[str] = []
			for p in port_order:
				srcs.extend(sorted(ports_map.get(p, [])))
			seen = set(port_order)
			for p in sorted(ports_map.keys()):
				if p in seen:
					continue
				srcs.extend(sorted(ports_map[p]))
			in_srcs.append(srcs if srcs else ["__INPUT__"])
		else:
			srcs: List[str] = []
			for p in sorted(ports_map.keys()):
				srcs.extend(sorted(ports_map[p]))
			in_srcs.append(srcs if srcs else ["__INPUT__"])

	# ops registered during warmup
	torch_ops: Dict[str, TorchOp] = ctx.extra.get("_torch_ops", {}) or {}

	ops_list: List[nn.Module] = []
	for nid in order:
		op = torch_ops.get(nid)
		if op is None:
			v = node_defs.get(nid)
			if isinstance(v, tuple) and len(v) == 2:
				blob = v[1]
				props = _ensure_dict(blob.get("props"))
				alt = props.get("nid")
				if alt is not None:
					op = torch_ops.get(str(alt))
		if op is None:
			op = op_identity()
		ops_list.append(op)

	return FusedForward(
		order=order,
		in_srcs=in_srcs,
		ops=nn.ModuleList(ops_list),
		output_nid=out_id,
	)
