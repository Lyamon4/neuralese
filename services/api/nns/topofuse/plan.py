from __future__ import annotations
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple, DefaultDict, Optional
from collections import defaultdict, deque
import hashlib, json

import torch

import nns.model_core as nodes  # get_or_build_fused_main, pick_device, etc.
from nns.graph_core import NODE_REGISTRY


# ============================================================
# === Canonicalization (NID-INDEPENDENT) ======================
# ============================================================

_Edge = Tuple[str, str, str, str]  # (src_nid, out_port, tgt_nid, tgt_port)
from common.logger import get_logger

topo = get_logger("topo")
def _stable_hash(obj: Any, n: int = 16) -> str:
	s = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
	return hashlib.sha1(s.encode("utf-8")).hexdigest()[:n]


def _extract_nodes_edges(graph: Dict[str, Any]) -> Tuple[Dict[str, str], List[_Edge]]:
	"""
	Returns:
	- node_type_by_nid: nid -> type
	- edges: (src_nid, out_port, tgt_nid, tgt_port)
	"""
	pages = (graph.get("graph") or graph).get("pages") or {}
	node_type_by_nid: Dict[str, str] = {}
	edges: List[_Edge] = []

	for _pk, page in pages.items():
		if not isinstance(page, dict):
			continue
		for nid, blob in page.items():
			if not isinstance(blob, dict):
				continue
			nid_s = str(nid)
			nt = str(blob.get("type") or "")
			node_type_by_nid[nid_s] = nt

			emit = blob.get("emit") or {}
			for out_port, fanouts in emit.items():
				for tgt_id, tgt_ports in (fanouts or {}).items():
					tgt_s = str(tgt_id)
					if isinstance(tgt_ports, list) and tgt_ports:
						for tp in tgt_ports:
							edges.append((nid_s, str(out_port), tgt_s, str(tp)))
					else:
						edges.append((nid_s, str(out_port), tgt_s, ""))

	return node_type_by_nid, edges


def _build_in_out(edges: List[_Edge]) -> Tuple[
	DefaultDict[str, List[Tuple[str, str, str]]],
	DefaultDict[str, List[Tuple[str, str, str]]],
	DefaultDict[str, List[str]],
	DefaultDict[str, List[str]],
	DefaultDict[str, int],
]:
	"""
	in_desc[tgt]  = [(src, out_port, tgt_port)]
	out_desc[src] = [(tgt, out_port, tgt_port)]
	out_adj[src]  = [tgt...]
	in_adj[tgt]   = [src...]
	indeg[tgt]    = count
	"""
	in_desc: DefaultDict[str, List[Tuple[str, str, str]]] = defaultdict(list)
	out_desc: DefaultDict[str, List[Tuple[str, str, str]]] = defaultdict(list)
	out_adj: DefaultDict[str, List[str]] = defaultdict(list)
	in_adj: DefaultDict[str, List[str]] = defaultdict(list)
	indeg: DefaultDict[str, int] = defaultdict(int)

	for u, outp, v, tgp in edges:
		in_desc[v].append((u, outp, tgp))
		out_desc[u].append((v, outp, tgp))
		out_adj[u].append(v)
		in_adj[v].append(u)
		indeg[v] += 1

	return in_desc, out_desc, out_adj, in_adj, indeg


def _wl_refine_labels(
	nids: List[str],
	nt: Dict[str, str],
	in_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	out_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	iters: int = 5,
) -> Dict[str, str]:
	"""
	Weisfeiler–Lehman-ish refinement with port labels.
	Initial label = node type.
	Refine using neighbor labels + ports to become NID-independent.
	"""
	labels: Dict[str, str] = {nid: str(nt.get(nid, "")) for nid in nids}

	for _ in range(int(iters)):
		new_labels: Dict[str, str] = {}
		for nid in nids:
			in_sig = []
			for src, outp, tgp in in_desc.get(nid, []):
				in_sig.append((outp, tgp, labels.get(src, "")))
			in_sig.sort()

			out_sig = []
			for tgt, outp, tgp in out_desc.get(nid, []):
				out_sig.append((outp, tgp, labels.get(tgt, "")))
			out_sig.sort()

			obj = {
				"t": labels.get(nid, ""),
				"in": in_sig,
				"out": out_sig,
			}
			new_labels[nid] = _stable_hash(obj, 20)

		labels = new_labels

	return labels


def _node_sort_key(
	nid: str,
	nt: Dict[str, str],
	labels: Dict[str, str],
	in_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	out_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	indeg0: int,
	outdeg0: int,
) -> Tuple[Any, ...]:
	# Only NID-independent data here.
	# Ports + neighbor WL labels are included to break symmetry.
	in_sig = []
	for src, outp, tgp in in_desc.get(nid, []):
		in_sig.append((outp, tgp, labels.get(src, "")))
	in_sig.sort()

	out_sig = []
	for tgt, outp, tgp in out_desc.get(nid, []):
		out_sig.append((outp, tgp, labels.get(tgt, "")))
	out_sig.sort()

	return (
		labels.get(nid, ""),
		str(nt.get(nid, "")),
		int(indeg0),
		int(outdeg0),
		tuple(in_sig),
		tuple(out_sig),
	)


def _canonical_toposort(
	nids: List[str],
	nt: Dict[str, str],
	out_adj: DefaultDict[str, List[str]],
	indeg: DefaultDict[str, int],
	in_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	out_desc: DefaultDict[str, List[Tuple[str, str, str]]],
	labels: Dict[str, str],
) -> Optional[List[str]]:
	"""
	Deterministic, NID-independent Kahn topo sort.
	CRITICAL SAFETY: if tie for minimal key occurs, we treat as ambiguous and return None.
	"""
	remaining = set(nids)
	indeg_m = {k: int(v) for k, v in indeg.items()}
	for nid in nids:
		indeg_m.setdefault(nid, 0)

	order: List[str] = []

	while remaining:
		cands = [n for n in remaining if indeg_m.get(n, 0) == 0]
		if not cands:
			return None  # cycle or broken graph

		# compute minimal key among candidates
		keys = []
		for n in cands:
			k = _node_sort_key(
				n,
				nt=nt,
				labels=labels,
				in_desc=in_desc,
				out_desc=out_desc,
				indeg0=indeg_m.get(n, 0),
				outdeg0=len(out_adj.get(n, [])),
			)
			keys.append((k, n))

		keys.sort(key=lambda x: x[0])
		min_key = keys[0][0]
		mins = [n for (k, n) in keys if k == min_key]

		# If multiple indistinguishable nodes can be chosen, mapping is ambiguous -> skip TopoFuse.
		if len(mins) != 1:
			return None

		u = mins[0]
		order.append(u)
		remaining.remove(u)

		for v in out_adj.get(u, []):
			if v in remaining:
				indeg_m[v] = int(indeg_m.get(v, 0)) - 1

	return order


def build_nid_to_exec(graph: Dict[str, Any]) -> Optional[Dict[str, int]]:
	nt, edges = _extract_nodes_edges(graph)
	if not nt:
		return None

	nids = list(nt.keys())
	in_desc, out_desc, out_adj, _in_adj, indeg = _build_in_out(edges)
	labels = _wl_refine_labels(nids, nt, in_desc, out_desc, iters=5)

	order = _canonical_toposort(
		nids=nids,
		nt=nt,
		out_adj=out_adj,
		indeg=indeg,
		in_desc=in_desc,
		out_desc=out_desc,
		labels=labels,
	)
	if order is None:
		return None

	return {nid: i for i, nid in enumerate(order)}


def topo_signature(graph: Dict[str, Any], output_nid: str) -> str:
	"""
	NID-INDEPENDENT signature.
	If canonicalization is ambiguous, returns "" (causes safe fallback).
	"""
	nt, edges = _extract_nodes_edges(graph)
	if not nt:
		return ""

	nid_to_exec = build_nid_to_exec(graph)
	if not nid_to_exec:
		return ""

	out_exec = nid_to_exec.get(str(output_nid))
	if out_exec is None:
		return ""

	# nodes list in canonical exec order
	order_nids = sorted(nid_to_exec.items(), key=lambda kv: kv[1])
	nodes_types = [str(nt.get(nid, "")) for nid, _i in order_nids]

	# edges in exec space
	exec_edges = []
	for u, outp, v, tgp in edges:
		ue = nid_to_exec.get(u)
		ve = nid_to_exec.get(v)
		if ue is None or ve is None:
			return ""
		exec_edges.append((int(ue), str(outp), int(ve), str(tgp)))
	exec_edges.sort()

	obj = {"nodes": nodes_types, "edges": exec_edges, "out": int(out_exec)}
	return _stable_hash(obj, 16)


# ============================================================
# === Plan ====================================================
# ============================================================

@dataclass
class Plan:
	exec_order: List[int]                                # 0..N-1
	in_edges: Dict[int, List[Tuple[int, str]]]            # exec -> [(src_exec, src_port)]
	in_by_port: Dict[int, Dict[str, int]]                 # exec -> {tgt_port: src_exec}
	pass_through: Dict[int, bool]                         # exec -> bool
	device: torch.device
	output_exec: int                                      # exec id of output node


def compile_plan(graph: Dict[str, Any], ctx, x_warmup: torch.Tensor, output_nid: str) -> Plan:
	"""
	Build a canonical (NID-independent) plan.
	Still calls get_or_build_fused_main to ensure ops are registered into ctx.
	"""
	# Per-user exec mapping: required so node code can register _torch_ops_exec.
	nid_to_exec = build_nid_to_exec(graph)
	if not nid_to_exec:
		raise RuntimeError("TopoFuse: canonicalization ambiguous; cannot compile plan")

	out_exec = nid_to_exec.get(str(output_nid))
	if out_exec is None:
		raise RuntimeError("TopoFuse: output nid not found in exec map")

	# ensure ops are registered in ctx for this graph shape
	# IMPORTANT: set mapping BEFORE execute_graph happens inside get_or_build_fused_main
	ctx.extra["_topofuse_exec_map"] = nid_to_exec
	nodes.get_or_build_fused_main(graph, ctx, x_warmup=x_warmup, output_nid=str(output_nid))

	device = nodes.pick_device(ctx)

	# build pass_through flags in exec space (from NODE_REGISTRY)
	pages = (graph.get("graph") or graph).get("pages") or {}
	nid_to_type: Dict[str, str] = {}
	for _pk, page in pages.items():
		if not isinstance(page, dict):
			continue
		for nid, blob in page.items():
			if not isinstance(blob, dict):
				continue
			nid_to_type[str(nid)] = str(blob.get("type") or "")

	pass_through: Dict[int, bool] = {}
	for nid, ex in nid_to_exec.items():
		nt = nid_to_type.get(str(nid), "")
		fn = NODE_REGISTRY.get(nt)
		pass_through[int(ex)] = bool(getattr(fn, "__pass_through__", False)) if fn else False

	# edges in exec space, plus port-level input mapping
	nt2, edges = _extract_nodes_edges(graph)

	in_edges: DefaultDict[int, List[Tuple[int, str]]] = defaultdict(list)
	in_by_port: DefaultDict[int, Dict[str, int]] = defaultdict(dict)

	for u, outp, v, tgp in edges:
		ue = nid_to_exec.get(u)
		ve = nid_to_exec.get(v)
		if ue is None or ve is None:
			raise RuntimeError("TopoFuse: exec map missing edge endpoint")
		in_edges[int(ve)].append((int(ue), str(outp)))
		if tgp != "":
			in_by_port[int(ve)][str(tgp)] = int(ue)

	# canonical exec order is 0..N-1
	N = len(nid_to_exec)
	exec_order = list(range(N))

	topo.info(f"[TOPOFUSE][PLAN] order_len={len(exec_order)} device={device} out_exec={out_exec}")

	return Plan(
		exec_order=exec_order,
		in_edges={k: list(v) for k, v in in_edges.items()},
		in_by_port={k: dict(v) for k, v in in_by_port.items()},
		pass_through=pass_through,
		device=device,
		output_exec=int(out_exec),
	)
