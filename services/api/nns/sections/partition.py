from __future__ import annotations
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple, Set, DefaultDict
from collections import defaultdict
import hashlib
import json


# --------- types ---------

@dataclass(frozen=True)
class SectionPlan:
	"""
	A plan is purely structural: which param-node NIDs belong to a section,
	and what the rough key (no params) is.
	"""
	rough_layers: Tuple[str, ...]     # e.g. ("conv2d","dense","dense")
	param_nids: Tuple[str, ...]       # NIDs in forward order along chain
	plan_id: str                      # stable-ish hash (no whole-graph hash)


# --------- helpers ---------

def _norm_layer_kind(node_type: str, blob: Dict[str, Any]) -> str | None:
	"""
	Return param-layer kind ("dense"/"conv2d") or None if not a reusable param node.
	We only treat NeuronLayer nodes with cfg.type in {dense,linear,conv2d,convolution2d}.
	"""
	if node_type != "NeuronLayer":
		return None
	cfg = (blob.get("config") or blob.get("props", {}).get("config") or {}) or {}
	lt = str(cfg.get("type", "dense")).lower()

	if lt in ("dense", "linear"):
		return "dense"
	if lt in ("conv2d", "convolution2d"):
		return "conv2d"

	# no reuse for maxpool/dropout/etc in this version
	return None


def _graph_nodes_edges(graph: Dict[str, Any]) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, str], List[Tuple[str, str]]]:
	"""
	Extract nodes and edges from your graph pack (graph['pages'][...]).
	Returns:
	- node_blob_by_nid (raw blob)
	- node_type_by_nid
	- edges (nid -> tgt_nid)
	"""
	pages = (graph.get("graph") or graph).get("pages") or {}
	node_blob_by_nid: Dict[str, Dict[str, Any]] = {}
	node_type_by_nid: Dict[str, str] = {}
	edges: List[Tuple[str, str]] = []

	for _pk, page in pages.items():
		if not isinstance(page, dict):
			continue
		for nid, blob in page.items():
			if not isinstance(blob, dict):
				continue
			node_blob_by_nid[str(nid)] = blob
			node_type_by_nid[str(nid)] = str(blob.get("type") or "")
			emit = blob.get("emit") or {}
			for _out_port, fanouts in emit.items():
				for tgt_id, _tgt_ports in (fanouts or {}).items():
					edges.append((str(nid), str(tgt_id)))

	return node_blob_by_nid, node_type_by_nid, edges


def _adjacency(edges: List[Tuple[str, str]]) -> Tuple[DefaultDict[str, List[str]], DefaultDict[str, List[str]]]:
	out_adj: DefaultDict[str, List[str]] = defaultdict(list)
	in_adj: DefaultDict[str, List[str]] = defaultdict(list)
	for u, v in edges:
		out_adj[u].append(v)
		in_adj[v].append(u)
	return out_adj, in_adj


def _stable_hash(obj: Any) -> str:
	s = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
	return hashlib.sha1(s.encode("utf-8")).hexdigest()[:16]


def _plan_id_for_chain(kinds: List[str], nids: List[str]) -> str:
	# not whole graph: only this chain signature
	return _stable_hash({"k": kinds, "n": len(nids)})


# --------- main ---------

def partition_graph_into_section_plans(graph: Dict[str, Any]) -> List[SectionPlan]:
	print("\n[SECTIONS][PARTITION] ===== partition_graph_into_section_plans =====")

	node_blob, node_type, edges = _graph_nodes_edges(graph)
	out_adj, in_adj = _adjacency(edges)

	param_kind: Dict[str, str] = {}
	for nid, blob in node_blob.items():
		kind = _norm_layer_kind(node_type.get(nid, ""), blob)
		if kind:
			param_kind[nid] = kind
			print(f"[SECTIONS][PARTITION] param node: nid={nid} kind={kind}")

	param_nodes: Set[str] = set(param_kind.keys())
	if not param_nodes:
		print("[SECTIONS][PARTITION] no param nodes found")
		return []

	param_succ: Dict[str, List[str]] = {}
	param_pred: Dict[str, List[str]] = {}
	for nid in param_nodes:
		param_succ[nid] = [v for v in out_adj.get(nid, []) if v in param_nodes]
		param_pred[nid] = [u for u in in_adj.get(nid, []) if u in param_nodes]

	starts: List[str] = []
	for nid in param_nodes:
		preds = param_pred.get(nid, [])
		if len(preds) != 1:
			starts.append(nid)
			print(f"[SECTIONS][PARTITION] chain start (pred count): {nid}")
			continue
		p = preds[0]
		if len(param_succ.get(p, [])) != 1:
			starts.append(nid)
			print(f"[SECTIONS][PARTITION] chain start (pred split): {nid}")

	starts.sort(key=lambda n: (param_kind[n], n))

	visited: Set[str] = set()
	plans: List[SectionPlan] = []

	for s in starts:
		if s in visited:
			continue

		chain_nids: List[str] = []
		cur = s

		while True:
			if cur in visited:
				break
			visited.add(cur)
			chain_nids.append(cur)

			succs = param_succ.get(cur, [])
			if len(succs) != 1:
				break
			nxt = succs[0]

			preds = param_pred.get(nxt, [])
			if len(preds) != 1 or preds[0] != cur:
				break

			cur = nxt

		if chain_nids:
			kinds = [param_kind[n] for n in chain_nids]
			pid = _plan_id_for_chain(kinds, chain_nids)
			print(
				f"[SECTIONS][PARTITION] plan: "
				f"nids={chain_nids} kinds={kinds} plan_id={pid}"
			)
			plans.append(SectionPlan(
				rough_layers=tuple(kinds),
				param_nids=tuple(chain_nids),
				plan_id=pid,
			))

	for nid in sorted(param_nodes):
		if nid in visited:
			continue
		k = param_kind[nid]
		pid = _plan_id_for_chain([k], [nid])
		print(f"[SECTIONS][PARTITION] orphan plan: nid={nid} kind={k}")
		plans.append(SectionPlan(
			rough_layers=(k,),
			param_nids=(nid,),
			plan_id=pid,
		))

	print(f"[SECTIONS][PARTITION] total plans: {len(plans)}")
	return plans

