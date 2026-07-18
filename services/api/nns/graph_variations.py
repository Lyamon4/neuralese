from collections import defaultdict, deque
from typing import Dict, Callable, Any, List, Tuple, Set
import torch, torch.nn as nn
from .graph_core import NODE_REGISTRY, Context, ExecutionResult, sh_context, NodeFn, _ensure_dict, _sorted_page_keys




class GraphModule(nn.Module):
	def __init__(self, node_defs: Dict[str, Tuple[str, Dict[str, Any]]],
	             node_types: Dict[str, str],
	             edges: List[Tuple[str, str]],
	             order: List[str],
	             ctx: Context):
		super().__init__()
		self.node_defs = node_defs         # {nid: (page_k, blob)}
		self.node_types = node_types       # {nid: type_name}
		self.adj = {u: [v for u2, v in edges if u2 == u] for u in node_types}
		self.order = order
		self.ctx = ctx

	def forward(self, inputs):
		ctx = self.ctx
		global_inbox: Dict[str, Dict[str, List[Any]]] = {}
		vals: Dict[str, Any] = {}
		vals["input"] = inputs

		for nid in self.order:
			page_k, blob = self.node_defs[nid]
			type_name = self.node_types[nid]
			fn = NODE_REGISTRY.get(type_name)
			if fn is None:
				continue

			props = _ensure_dict(blob.get("props")).copy()
			props["nid"] = nid

			# prepare inputs (we don't simulate expect here)
			inbox = global_inbox.get(nid, {})
			inp = {}
			for port, val_list in inbox.items():
				if not isinstance(val_list, list):
					val_list = [val_list]
				inp[port] = val_list

			try:
				outputs = fn(inp, props, ctx)
			except Exception as e:
				raise RuntimeError(f"Error in node {nid} ({type_name}): {e}") from e

			emit = blob.get("emit", {}) or {}
			if not emit:
				continue

			# deliver outputs to connected nodes
			for out_port, fanouts in emit.items():
				val = outputs.get(out_port)
				if val is None:
					continue
				for tgt_id, tgt_ports in fanouts.items():
					for tgt_port in (tgt_ports or []):
						slot = global_inbox.setdefault(tgt_id, {}).setdefault(tgt_port, [])
						slot.append(val)

		# return output of last node or fallback
		last = self.order[-1]
		last_outputs = global_inbox.get(last)
		if last_outputs:
			first_port = next(iter(last_outputs))
			val = last_outputs[first_port]
			if isinstance(val, list):
				val = val[-1]
			return _unpack_tensor(val)

		# fallback to input (also unpack just in case)
		return _unpack_tensor(vals.get("input"))




def topo_sort(nodes, edges):
    indeg = defaultdict(int)
    adj = defaultdict(list)
    for u, v in edges:
        adj[u].append(v)
        indeg[v] += 1
    q = deque([n for n in nodes if indeg[n] == 0])
    order = []
    while q:
        n = q.popleft()
        order.append(n)
        for nxt in adj[n]:
            indeg[nxt] -= 1
            if indeg[nxt] == 0:
                q.append(nxt)
    return order




class CompiledGraph:
	def __init__(self, pack: Dict[str, Any]):
		graph = pack.get("graph") or pack
		pages = graph["pages"]
		expect = graph["expect"]

		self.pages = pages
		self.expect = expect
		self.page_keys = _sorted_page_keys(pages)
		self.node_defs: Dict[str, Tuple[str, Dict[str, Any]]] = {}
		self.node_types: Dict[str, str] = {}
		self.edges: List[Tuple[str, str]] = []

		for page_k in self.page_keys:
			for nid, blob in pages[page_k].items():
				self.node_defs[nid] = (page_k, blob)
				self.node_types[nid] = blob["type"]
				for out_port, fanouts in (blob.get("emit") or {}).items():
					for tgt_id, tgt_ports in fanouts.items():
						self.edges.append((nid, tgt_id))

		self.nodes = list(self.node_types.keys())
		self.order = topo_sort(self.nodes, self.edges)
		self.fn_map: Dict[str, NodeFn] = {}
		for nid, t in self.node_types.items():
			if t not in NODE_REGISTRY:
				raise KeyError(f"unknown node type {t}")
			self.fn_map[nid] = NODE_REGISTRY[t]

	def run(self, context: Context | None = None) -> ExecutionResult:
		context = context or sh_context
		global_inbox: Dict[str, Dict[str, List[Any]]] = {}
		inbox_by_page: Dict[str, Dict[str, Dict[str, Any]]] = {}
		trace: Dict[Tuple[str, str], Dict[str, Any]] = {}
		branch_heads, endings = {}, {}
		executed: Set[str] = set()

		def _is_ready(nid: str) -> bool:
			exp_ports = self.expect.get(nid, {})
			for port, need in exp_ports.items():
				have = len(global_inbox.get(nid, {}).get(port, []))
				if have < need:
					return False
			return True

		def _prepare_inputs(nid: str) -> Dict[str, Any]:
			res = {}
			exp_ports = self.expect.get(nid, {})
			for port, need in exp_ports.items():
				vals = global_inbox.get(nid, {}).get(port, [])
				# Always keep a list, even for single-input ports
				if not isinstance(vals, list):
					vals = [vals] if vals is not None else []
				res[port] = vals
			return res

		# Simple direct delivery (in-page)
		for nid in self.order:
			if nid in executed:
				continue
			if not _is_ready(nid):
				continue

			page_k, blob = self.node_defs[nid]
			props = blob["props"]
			props["nid"] = nid
			fn = self.fn_map[nid]

			inputs = _prepare_inputs(nid)
			outputs = fn(inputs, props, context)
			trace[(page_k, nid)] = outputs

			emit = blob["emit"]
			if not emit:
				endings[nid] = inputs.copy()

			is_branch = getattr(fn, "__branch_head__", False) or bool(props.get("branch_head"))
			if is_branch:
				branch_heads[nid] = outputs.copy()

			# Deliver
			for out_port, fanouts in emit.items():
				val = outputs.get(out_port)
				if val is None:
					continue
				for tgt_id, tgt_ports in fanouts.items():
					for tgt_port in (tgt_ports or []):
						slot = global_inbox.setdefault(tgt_id, {}).setdefault(tgt_port, [])
						slot.append(val)

			executed.add(nid)

		last_page_k = self.page_keys[-1] if self.page_keys else "0"
		last_inbox = inbox_by_page.get(last_page_k, {})
		return ExecutionResult(
			last_inbox=last_inbox,
			endings=endings,
			trace=trace,
			inbox_by_page=inbox_by_page,
			branch_heads=branch_heads
		)




def extract_graph_structure(pack):
    pages = pack["pages"]
    edges = []
    nodes = {}
    for page_k, page in pages.items():
        for nid, blob in page.items():
            nodes[nid] = blob["type"]
            for out_port, fanouts in (blob.get("emit") or {}).items():
                for tgt_id, tgt_ports in fanouts.items():
                    edges.append((nid, tgt_id))
    return nodes, edges


def _unpack_tensor(v):
    # pack_tensor(...) returns {"tensor": torch.Tensor, ...}
    if isinstance(v, dict) and "tensor" in v:
        return v["tensor"]
    return v




