from __future__ import annotations

import json
from typing import Any


def summarize_graph(scene: dict[str, Any] | None) -> str:
    if not isinstance(scene, dict):
        return "Graph is empty."

    nodes = scene.get("nodes") or {}
    edges = scene.get("edges") or []
    if not isinstance(nodes, dict) or not nodes:
        return "Graph is empty."

    outgoing, incoming = _build_edge_indexes(nodes, edges)
    activation_by_layer, activation_source_by_layer = _activation_inputs(nodes, incoming)

    seen: set[str] = set()
    parts: list[str] = []

    inference_roots = [tag for tag, node in nodes.items() if _node_type(node) in {"input_image_small", "input_1d"}]
    inference_chains = []
    for root in sorted(inference_roots):
        chain = _render_flow(root, nodes, outgoing, activation_by_layer, activation_source_by_layer, seen)
        if chain:
            inference_chains.append(chain)
    if inference_chains:
        parts.append("Inference: " + " | ".join(inference_chains) + ".")

    training_roots = [tag for tag, node in nodes.items() if _node_type(node) == "load_dataset"]
    training_chains = []
    for root in sorted(training_roots):
        chain = _render_flow(root, nodes, outgoing, activation_by_layer, activation_source_by_layer, seen)
        if chain:
            training_chains.append(chain)
    if training_chains:
        parts.append("Training: " + " | ".join(training_chains) + ".")

    disconnected = [
        f"{tag}:{_format_node(tag, node, activation_by_layer)}"
        for tag, node in sorted(nodes.items())
        if tag not in seen
    ]
    if disconnected:
        parts.append("Other nodes: " + "; ".join(disconnected[:20]) + ".")

    if parts:
        return " ".join(parts)

    return _compact_fallback(nodes, edges)


def _build_edge_indexes(nodes: dict[str, Any], edges: Any) -> tuple[dict[str, list[dict[str, Any]]], dict[str, list[dict[str, Any]]]]:
    outgoing: dict[str, list[dict[str, Any]]] = {str(tag): [] for tag in nodes.keys()}
    incoming: dict[str, list[dict[str, Any]]] = {str(tag): [] for tag in nodes.keys()}

    if isinstance(edges, list):
        for edge in edges:
            if not isinstance(edge, dict):
                continue
            from_info = edge.get("from") or {}
            to_info = edge.get("to") or {}
            if not isinstance(from_info, dict) or not isinstance(to_info, dict):
                continue
            src = str(from_info.get("tag", ""))
            dst = str(to_info.get("tag", ""))
            if not src or not dst:
                continue
            packed = {
                "from": src,
                "to": dst,
                "from_port": int(from_info.get("port", 0) or 0),
                "to_port": int(to_info.get("port", 0) or 0),
            }
            outgoing.setdefault(src, []).append(packed)
            incoming.setdefault(dst, []).append(packed)

    if not any(outgoing.values()):
        for src, node in nodes.items():
            outputs = node.get("outputs", {}) if isinstance(node, dict) else {}
            if not isinstance(outputs, dict):
                continue
            for from_port, fanouts in outputs.items():
                if not isinstance(fanouts, list):
                    continue
                for item in fanouts:
                    if not isinstance(item, dict):
                        continue
                    dst = str(item.get("to", ""))
                    if not dst:
                        continue
                    packed = {
                        "from": str(src),
                        "to": dst,
                        "from_port": int(from_port),
                        "to_port": int(item.get("port", 0) or 0),
                    }
                    outgoing.setdefault(str(src), []).append(packed)
                    incoming.setdefault(dst, []).append(packed)

    for edge_list in outgoing.values():
        edge_list.sort(key=lambda e: (e["from_port"], e["to"], e["to_port"]))
    for edge_list in incoming.values():
        edge_list.sort(key=lambda e: (e["to_port"], e["from"], e["from_port"]))
    return outgoing, incoming


def _activation_inputs(nodes: dict[str, Any], incoming: dict[str, list[dict[str, Any]]]) -> tuple[dict[str, str], dict[str, str]]:
    out: dict[str, str] = {}
    source: dict[str, str] = {}
    for tag, edges in incoming.items():
        for edge in edges:
            if edge["to_port"] != 0:
                continue
            src_node = nodes.get(edge["from"])
            if _node_type(src_node) == "activation":
                activ = _config(src_node).get("activ", "")
                if activ:
                    out[tag] = str(activ)
                    source[tag] = edge["from"]
    return out, source


def _render_flow(
    root: str,
    nodes: dict[str, Any],
    outgoing: dict[str, list[dict[str, Any]]],
    activation_by_layer: dict[str, str],
    activation_source_by_layer: dict[str, str],
    seen: set[str],
) -> str:
    return _render_flow_until(
        root,
        None,
        nodes,
        outgoing,
        activation_by_layer,
        activation_source_by_layer,
        seen,
        set(),
    )


def _render_flow_until(
    current: str,
    stop_before: str | None,
    nodes: dict[str, Any],
    outgoing: dict[str, list[dict[str, Any]]],
    activation_by_layer: dict[str, str],
    activation_source_by_layer: dict[str, str],
    seen: set[str],
    active: set[str],
) -> str:
    if not current or current == stop_before or current not in nodes:
        return ""
    if current in active:
        return f"{_format_node(current, nodes[current], activation_by_layer)}(cycle)"

    active = set(active)
    active.add(current)
    seen.add(current)
    node = nodes[current]
    base = _format_node(current, node, activation_by_layer)
    activation_src = activation_source_by_layer.get(current)
    if activation_src:
        seen.add(activation_src)

    candidates = _model_outputs(current, nodes, outgoing)
    if not candidates:
        return base

    if len(candidates) == 1:
        tail = _render_flow_until(
            candidates[0]["to"],
            stop_before,
            nodes,
            outgoing,
            activation_by_layer,
            activation_source_by_layer,
            seen,
            active,
        )
        return f"{base} -> {tail}" if tail else base

    join = _first_common_join([edge["to"] for edge in candidates], nodes, outgoing)
    if join:
        branches = []
        for edge in candidates:
            branch = _render_flow_until(
                edge["to"],
                join,
                nodes,
                outgoing,
                activation_by_layer,
                activation_source_by_layer,
                seen,
                active,
            )
            branches.append(branch or "(direct)")
        join_tail = _render_flow_until(
            join,
            stop_before,
            nodes,
            outgoing,
            activation_by_layer,
            activation_source_by_layer,
            seen,
            active,
        )
        return f"{base} -> split[{'; '.join(branches)}] -> {join_tail}" if join_tail else f"{base} -> split[{'; '.join(branches)}]"

    branches = []
    for edge in candidates:
        branch = _render_flow_until(
            edge["to"],
            stop_before,
            nodes,
            outgoing,
            activation_by_layer,
            activation_source_by_layer,
            seen,
            active,
        )
        branches.append(branch or "(direct)")
    return f"{base} -> split[{'; '.join(branches)}]"


def _model_outputs(current: str, nodes: dict[str, Any], outgoing: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    return [
        edge for edge in outgoing.get(current, [])
        if _node_type(nodes.get(edge["to"])) != "activation"
    ]


def _first_common_join(starts: list[str], nodes: dict[str, Any], outgoing: dict[str, list[dict[str, Any]]]) -> str | None:
    if len(starts) < 2:
        return None

    reachable_by_start = [_reachable_distances(start, nodes, outgoing) for start in starts]
    if not reachable_by_start:
        return None

    common = set(reachable_by_start[0].keys())
    for reachable in reachable_by_start[1:]:
        common &= set(reachable.keys())
    if not common:
        return None

    def score(tag: str) -> tuple[int, int, str]:
        distances = [reachable[tag] for reachable in reachable_by_start]
        return (sum(distances), max(distances), tag)

    return min(common, key=score)


def _reachable_distances(start: str, nodes: dict[str, Any], outgoing: dict[str, list[dict[str, Any]]]) -> dict[str, int]:
    distances: dict[str, int] = {}
    queue: list[tuple[str, int]] = [(start, 0)]
    while queue:
        current, distance = queue.pop(0)
        if current in distances or current not in nodes:
            continue
        distances[current] = distance
        for edge in _model_outputs(current, nodes, outgoing):
            queue.append((edge["to"], distance + 1))
    return distances


def _format_node(tag: str, node: Any, activation_by_layer: dict[str, str]) -> str:
    typ = _node_type(node)
    cfg = _config(node)

    if typ == "input_1d":
        features = cfg.get("input_features") or []
        count = len(features) if isinstance(features, list) else "?"
        return f"input_1d(features={count})"
    if typ == "input_image_small":
        return "input_image_small"
    if typ == "load_dataset":
        name = cfg.get("name", cfg.get("dataset_name", ""))
        meta = cfg.get("meta") if isinstance(cfg.get("meta"), dict) else {}
        label = name or meta.get("name", "")
        return f"load_dataset(name={label})" if label else "load_dataset"
    if typ == "activation":
        return f"activation({cfg.get('activ', 'none')})"
    if typ == "dense_layer":
        units = cfg.get("neuron_count", cfg.get("neuron_amount", "?"))
        return _with_activation(tag, f"dense(neurons={units})", activation_by_layer)
    if typ == "conv2d_layer":
        base = "conv2d(filters={filters}, window={window}, stride={stride})".format(
            filters=cfg.get("filters", "?"),
            window=cfg.get("window", "?"),
            stride=cfg.get("stride", 1),
        )
        return _with_activation(tag, base, activation_by_layer)
    if typ == "maxpool_layer":
        return f"maxpool(group={cfg.get('group', '?')})"
    if typ == "dropout":
        return f"dropout(p={cfg.get('p', 0.5)})"
    if typ == "flatten":
        return "flatten"
    if typ == "reshape2d":
        return f"reshape2d(x={cfg.get('x', cfg.get('rows', '?'))}, y={cfg.get('y', cfg.get('columns', '?'))})"
    if typ == "softmax":
        return "softmax"
    if typ == "out_labels":
        labels = cfg.get("label_names") or []
        title = cfg.get("title", "")
        if isinstance(labels, list) and len(labels) <= 10:
            labels_text = ",".join(str(x) for x in labels)
        elif isinstance(labels, list):
            labels_text = f"{len(labels)} labels"
        else:
            labels_text = "labels=?"
        return f"out_labels(title={title}, labels={labels_text})"
    if typ == "train_begin":
        return "train_begin"
    if typ == "run_model":
        branches = cfg.get("branches", cfg.get("branch_res", {}))
        mapped = cfg.get("mapped", {})
        bits = []
        if branches:
            bits.append("branches=" + _compact_json(branches))
        if mapped:
            bits.append("mapped=" + _compact_json(mapped))
        return "run_model(" + ", ".join(bits) + ")" if bits else "run_model"
    if typ == "output_map":
        return "output_map"
    if typ == "train_step":
        return f"train_step(optimizer={cfg.get('optimizer', 'adam')}, lr={cfg.get('lr', '?')})"
    return typ or str(tag)


def _with_activation(tag: str, base: str, activation_by_layer: dict[str, str]) -> str:
    activation = activation_by_layer.get(tag)
    if not activation:
        return base
    return base[:-1] + f", activation={activation})" if base.endswith(")") else f"{base}(activation={activation})"


def _node_type(node: Any) -> str:
    return str(node.get("type", "")) if isinstance(node, dict) else ""


def _config(node: Any) -> dict[str, Any]:
    cfg = node.get("config", {}) if isinstance(node, dict) else {}
    return cfg if isinstance(cfg, dict) else {}


def _compact_json(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    except Exception:
        return str(value)


def _compact_fallback(nodes: dict[str, Any], edges: Any) -> str:
    node_list = ", ".join(f"{tag}:{_node_type(node)}" for tag, node in sorted(nodes.items()))
    edge_count = len(edges) if isinstance(edges, list) else 0
    return f"Graph nodes: {node_list}. Edges: {edge_count}."
