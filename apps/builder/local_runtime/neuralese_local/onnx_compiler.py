from __future__ import annotations

from collections import deque
from types import SimpleNamespace
from typing import Any, Dict, List, Set, Tuple

from onnx import TensorProto, helper

from .onnx_node_handlers import get_handler


def _as_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _as_str(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _is_cross_entropy(loss_name: str) -> bool:
    return str(loss_name).lower() in {"cross_entropy", "crossentropyloss", "ce"}


def _output_softmax_nodes(pages: Dict[str, Any]) -> Set[str]:
    result: Set[str] = set()
    for page in pages.values():
        for raw_nid, node_blob in page.items():
            ntype = _as_str(node_blob.get("type"))
            props = node_blob.get("props", {}) or {}
            config = props.get("config", {}) or {}
            if ntype in ("SoftmaxNode", "softmax") and _as_str(config.get("role", "")).lower() == "output":
                result.add(str(raw_nid))
    return result


def normalize_flat_graph_to_syntax_tree(flat_graph: Dict[str, Any]) -> Dict[str, Any]:
    graph_nodes = flat_graph.get("nodes", {})
    connections = flat_graph.get("connections", [])

    adj = {str(nid): [] for nid in graph_nodes}
    indeg = {str(nid): 0 for nid in graph_nodes}
    expect: Dict[str, Dict[str, int]] = {}
    node_types = {str(nid): graph_nodes[nid].get("type", "") for nid in graph_nodes}
    emit_mapping: Dict[str, Dict[str, Dict[str, List[str]]]] = {}

    for conn in connections:
        u = str(conn.get("from_node"))
        v = str(conn.get("to_node"))
        if u not in adj or v not in indeg:
            continue

        adj[u].append(v)
        indeg[v] += 1

        from_port = conn.get("from_port", "input_out" if node_types[u] == "InputNode" else "layer_out")
        to_port = conn.get("to_port", "model_in" if node_types[v] in ("SoftmaxNode", "softmax") else "layer_in")

        emit_mapping.setdefault(u, {}).setdefault(str(from_port), {}).setdefault(v, []).append(str(to_port))
        expect.setdefault(v, {}).setdefault(str(to_port), 0)
        expect[v][str(to_port)] += 1

    q = deque([nid for nid in indeg if indeg[nid] == 0])
    order: List[str] = []
    while q:
        nid = q.popleft()
        order.append(nid)
        for nxt in adj[nid]:
            indeg[nxt] -= 1
            if indeg[nxt] == 0:
                q.append(nxt)

    depth = {nid: 0 for nid in graph_nodes}
    for u in order:
        for v in adj[u]:
            depth[v] = max(depth[v], depth[u] + 1)

    pages: Dict[str, Dict[str, Any]] = {}
    for nid in order:
        original_node = graph_nodes[nid]
        config = original_node.get("data", {})
        abstract_node = {
            "type": original_node.get("type"),
            "props": {
                "config": config,
                "shape": config.get("shape", 784),
                "neuron_count": config.get("neuron_count", config.get("units", 64)),
            },
            "emit": emit_mapping.get(nid, {}),
        }
        pages.setdefault(str(depth[nid]), {})[nid] = abstract_node

    return {"pages": pages, "expect": expect, "train": 1}


def build_onnx_model_from_graph(graph: Dict[str, Any], loss_name: str = "cross_entropy") -> Tuple[Any, List[str]]:
    if "nodes" in graph:
        graph = normalize_flat_graph_to_syntax_tree(graph)

    pages = graph.get("pages", {})
    if not pages:
        raise ValueError("Invalid graph structure: empty pages")

    page_keys = sorted(pages.keys(), key=lambda k: int(k) if str(k).isdigit() else str(k))
    disabled_softmax_nodes = _output_softmax_nodes(pages) if _is_cross_entropy(loss_name) else set()

    onnx_nodes = []
    initializers = []
    inputs = []
    outputs = []
    trainable_params: List[str] = []
    tensor_routing: Dict[str, Dict[str, str]] = {}
    input_deliveries: Dict[str, Dict[str, List[str]]] = {}
    tensor_shapes: Dict[str, List[Any]] = {}

    def inputs_for(nid: str, port_name: str) -> List[str]:
        return input_deliveries.get(str(nid), {}).get(str(port_name), [])

    def first_input(nid: str, *ports: str) -> str:
        for port_name in ports:
            tensors = inputs_for(nid, port_name)
            if tensors:
                return tensors[0]
        return "input"

    def add_activation(nid: str, source_name: str, shape: List[Any], activation: str) -> str:
        activation = _as_str(activation, "none").lower()
        if activation in ("", "none", "linear"):
            return source_name
        op_type = {"relu": "Relu", "sigmoid": "Sigmoid", "tanh": "Tanh", "softmax": "Softmax"}.get(activation)
        if op_type is None:
            raise ValueError(f"Unsupported activation '{activation}' on node {nid}")
        activated_name = f"tensor_{nid}_layer_out_activated"
        attrs = {"axis": 1} if op_type == "Softmax" else {}
        onnx_nodes.append(helper.make_node(op_type, inputs=[source_name], outputs=[activated_name], name=f"{op_type}_{nid}", **attrs))
        tensor_shapes[activated_name] = shape
        return activated_name

    def deliver_outputs(nid: str, emit: Dict[str, Any]) -> None:
        for out_port, fanouts in emit.items():
            tensor_name = tensor_routing.get(str(nid), {}).get(str(out_port))
            if tensor_name is None:
                continue
            for tgt_id, tgt_ports in (fanouts or {}).items():
                for tgt_port in (tgt_ports or []):
                    input_deliveries.setdefault(str(tgt_id), {}).setdefault(str(tgt_port), []).append(tensor_name)

    ctx = SimpleNamespace(
        onnx_nodes=onnx_nodes,
        initializers=initializers,
        inputs=inputs,
        outputs=outputs,
        trainable_params=trainable_params,
        tensor_routing=tensor_routing,
        input_deliveries=input_deliveries,
        tensor_shapes=tensor_shapes,
        disabled_softmax_nodes=disabled_softmax_nodes,
        inputs_for=inputs_for,
        first_input=first_input,
        add_activation=add_activation,
    )

    for page_k in page_keys:
        for raw_nid, node_blob in pages[page_k].items():
            nid = str(raw_nid)
            ntype = _as_str(node_blob.get("type"))
            props = node_blob.get("props", {}) or {}
            config = props.get("config", {}) or {}
            emit = node_blob.get("emit", {}) or {}

            handler = get_handler(ntype)
            if handler is None:
                raise ValueError(f"Unsupported graph node type '{ntype}' on node {nid}")
            handler(ctx, nid, ntype, props, config, emit)
            deliver_outputs(nid, emit)

    last_nid = _find_final_node_id(pages, page_keys)
    last_ports = tensor_routing.get(last_nid, {})
    last_output_name = next((last_ports[p] for p in ("layer_out", "soft_out", "model_out", "input_out") if p in last_ports), "input")
    final_shape = tensor_shapes.get(last_output_name, ["batch_size", 64])
    outputs.append(helper.make_tensor_value_info(last_output_name, TensorProto.FLOAT, final_shape))

    graph_proto = helper.make_graph(
        onnx_nodes if onnx_nodes else [helper.make_node("Identity", inputs=["input"], outputs=["input"])],
        "neuralese_onnx_model",
        inputs,
        outputs,
        initializer=initializers,
    )
    model_proto = helper.make_model(graph_proto, ir_version=7, producer_name="neuralese_fullylocal")
    model_proto.opset_import[0].version = 14
    return model_proto, trainable_params


def _find_final_node_id(pages: Dict[str, Any], page_keys: List[str]) -> str:
    ignored = {"TrainInput", "TrainBegin", "RunModel", "DatasetName", "ModelName"}
    for page_k in reversed(page_keys):
        page_nodes = pages.get(page_k, {})
        for nid in reversed(list(page_nodes.keys())):
            if page_nodes[nid].get("type") not in ignored:
                return str(nid)
    return str(next(iter(pages[page_keys[-1]].keys())))
