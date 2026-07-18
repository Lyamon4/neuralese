from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Iterable

from .jason_docs import load_json


@dataclass(frozen=True)
class CompatEdge:
    from_node: str
    from_port: str
    to_node: str
    to_port: str
    datatypes: tuple[str, ...]

    def to_json(self) -> dict[str, Any]:
        return {
            "from_node": self.from_node,
            "from_port": self.from_port,
            "to_node": self.to_node,
            "to_port": self.to_port,
            "datatypes": list(self.datatypes),
        }


@dataclass(frozen=True)
class NodeSpec:
    node_id: str
    title: str
    generated: dict[str, Any]
    compat: tuple[CompatEdge, ...]


def load_node_specs(docs_root: Path) -> list[NodeSpec]:
    node_dirs = sorted(
        child for child in docs_root.iterdir() if child.is_dir() and child.name != "schema" and (child / "node.json").exists()
    )
    specs: list[NodeSpec] = []
    for node_dir in node_dirs:
        document = load_json(node_dir / "node.json")
        if document.get("status") == "deprecated":
            continue
        node_id = str(document["node_id"])
        docs = document.get("docs", {})
        title = str(docs.get("title", {}).get("en") or node_id)
        generated = document.get("generated", {})
        compat = []
        for item in generated.get("static_compatible_nodes", []):
            compat.append(
                CompatEdge(
                    from_node=node_id,
                    from_port=str(item.get("from_port", "")),
                    to_node=str(item.get("to_node", "")),
                    to_port=str(item.get("to_port", "")),
                    datatypes=tuple(str(value) for value in item.get("datatypes", [])),
                )
            )
        specs.append(NodeSpec(node_id=node_id, title=title, generated=generated, compat=tuple(compat)))
    known = {spec.node_id for spec in specs}
    return [
        NodeSpec(
            node_id=spec.node_id,
            title=spec.title,
            generated=spec.generated,
            compat=tuple(edge for edge in spec.compat if edge.to_node in known),
        )
        for spec in specs
    ]


def selected_node_ids(specs: list[NodeSpec], requested: Iterable[str] | None) -> set[str]:
    if not requested:
        return {spec.node_id for spec in specs}
    known = {spec.node_id for spec in specs}
    selected = {node_id for node_id in requested if node_id}
    unknown = sorted(selected.difference(known))
    if unknown:
        raise ValueError(f"unknown node id(s): {', '.join(unknown)}")
    return selected


def compatibility_matrix(specs: list[NodeSpec]) -> tuple[list[str], list[list[int]], dict[str, list[CompatEdge]]]:
    node_ids = [spec.node_id for spec in specs]
    index = {node_id: pos for pos, node_id in enumerate(node_ids)}
    matrix = [[0 for _ in node_ids] for _ in node_ids]
    adjacency: dict[str, list[CompatEdge]] = {node_id: [] for node_id in node_ids}
    for spec in specs:
        from_index = index[spec.node_id]
        for edge in spec.compat:
            if edge.to_node not in index:
                continue
            matrix[from_index][index[edge.to_node]] += 1
            adjacency[spec.node_id].append(edge)
    for edges in adjacency.values():
        edges.sort(key=lambda edge: (edge.to_node, edge.from_port, edge.to_port, edge.datatypes))
    return node_ids, matrix, adjacency


def exact_chain_counts(
    node_ids: list[str],
    matrix: list[list[int]],
    min_nodes: int,
    max_nodes: int,
    starts: set[str],
    ends: set[str],
) -> dict[int, int]:
    if min_nodes < 1:
        raise ValueError("min_nodes must be at least 1")
    if max_nodes < min_nodes:
        raise ValueError("max_nodes must be greater than or equal to min_nodes")

    start_vector = [1 if node_id in starts else 0 for node_id in node_ids]
    end_mask = [1 if node_id in ends else 0 for node_id in node_ids]
    counts: dict[int, int] = {}
    current = start_vector[:]
    for length in range(1, max_nodes + 1):
        if length >= min_nodes:
            counts[length] = sum(value for value, allowed in zip(current, end_mask) if allowed)
        current = vector_times_matrix(current, matrix)
    return counts


def vector_times_matrix(vector: list[int], matrix: list[list[int]]) -> list[int]:
    size = len(vector)
    result = [0 for _ in range(size)]
    for row, value in enumerate(vector):
        if value == 0:
            continue
        matrix_row = matrix[row]
        for col, weight in enumerate(matrix_row):
            if weight:
                result[col] += value * weight
    return result


def reachable_nodes(node_ids: list[str], matrix: list[list[int]], roots: set[str], reverse: bool = False) -> set[str]:
    index = {node_id: pos for pos, node_id in enumerate(node_ids)}
    seen = {node_id for node_id in roots if node_id in index}
    stack = list(seen)
    while stack:
        node_id = stack.pop()
        pos = index[node_id]
        if reverse:
            neighbors = [node_ids[row] for row in range(len(node_ids)) if matrix[row][pos]]
        else:
            neighbors = [node_ids[col] for col, weight in enumerate(matrix[pos]) if weight]
        for neighbor in neighbors:
            if neighbor not in seen:
                seen.add(neighbor)
                stack.append(neighbor)
    return seen


def find_cycle_nodes(node_ids: list[str], matrix: list[list[int]], allowed: set[str] | None = None) -> list[list[str]]:
    allowed = set(node_ids) if allowed is None else allowed
    graph = {
        node_ids[row]: [node_ids[col] for col, weight in enumerate(matrix[row]) if weight and node_ids[col] in allowed]
        for row in range(len(node_ids))
        if node_ids[row] in allowed
    }
    node_index = {node_id: pos for pos, node_id in enumerate(node_ids)}
    index = 0
    stack: list[str] = []
    on_stack: set[str] = set()
    indices: dict[str, int] = {}
    lowlinks: dict[str, int] = {}
    components: list[list[str]] = []

    def strongconnect(node_id: str) -> None:
        nonlocal index
        indices[node_id] = index
        lowlinks[node_id] = index
        index += 1
        stack.append(node_id)
        on_stack.add(node_id)

        for target in graph[node_id]:
            if target not in indices:
                strongconnect(target)
                lowlinks[node_id] = min(lowlinks[node_id], lowlinks[target])
            elif target in on_stack:
                lowlinks[node_id] = min(lowlinks[node_id], indices[target])

        if lowlinks[node_id] == indices[node_id]:
            component: list[str] = []
            while True:
                member = stack.pop()
                on_stack.remove(member)
                component.append(member)
                if member == node_id:
                    break
            component.sort()
            if len(component) > 1:
                components.append(component)
            else:
                only = component[0]
                row = node_index[only]
                if matrix[row][row]:
                    components.append(component)

    for node_id in node_ids:
        if node_id in allowed and node_id not in indices:
            strongconnect(node_id)
    components.sort(key=lambda component: (len(component), component))
    return components



def enumerate_chains(
    adjacency: dict[str, list[CompatEdge]],
    min_nodes: int,
    max_nodes: int,
    starts: set[str],
    ends: set[str],
    limit: int,
) -> list[dict[str, Any]]:
    if limit < 1:
        return []
    results: list[dict[str, Any]] = []
    path_nodes: list[str] = []
    path_edges: list[CompatEdge] = []

    def visit(node_id: str) -> None:
        if len(results) >= limit:
            return
        path_nodes.append(node_id)
        if len(path_nodes) >= min_nodes and node_id in ends:
            results.append(
                {
                    "nodes": path_nodes[:],
                    "connections": [edge.to_json() for edge in path_edges],
                }
            )
            if len(results) >= limit:
                path_nodes.pop()
                return
        if len(path_nodes) < max_nodes:
            for edge in adjacency.get(node_id, []):
                path_edges.append(edge)
                visit(edge.to_node)
                path_edges.pop()
                if len(results) >= limit:
                    break
        path_nodes.pop()

    for start in sorted(starts):
        if start not in adjacency:
            continue
        visit(start)
        if len(results) >= limit:
            break
    return results


def chain_summary(
    docs_root: Path,
    min_nodes: int,
    max_nodes: int,
    starts_requested: Iterable[str] | None = None,
    ends_requested: Iterable[str] | None = None,
) -> dict[str, Any]:
    specs = load_node_specs(docs_root)
    node_ids, matrix, adjacency = compatibility_matrix(specs)
    starts = selected_node_ids(specs, starts_requested)
    ends = selected_node_ids(specs, ends_requested)
    counts = exact_chain_counts(node_ids, matrix, min_nodes, max_nodes, starts, ends)
    reachable_from_starts = reachable_nodes(node_ids, matrix, starts)
    reachable_to_ends = reachable_nodes(node_ids, matrix, ends, reverse=True)
    cycle_scope = reachable_from_starts.intersection(reachable_to_ends)
    cycle_components = find_cycle_nodes(node_ids, matrix, cycle_scope)
    edge_count = sum(sum(row) for row in matrix)
    return {
        "docs_root": str(docs_root),
        "node_count": len(specs),
        "port_level_compatibility_edges": edge_count,
        "unbounded_chain_count": "infinite" if cycle_components else "finite",
        "cycle_components": cycle_components,
        "min_nodes": min_nodes,
        "max_nodes": max_nodes,
        "starts": sorted(starts),
        "ends": sorted(ends),
        "chain_counts_by_nodes": {str(length): count for length, count in counts.items()},
        "total_chains": sum(counts.values()),
    }


def write_chain_jsonl(
    docs_root: Path,
    target: Path,
    min_nodes: int,
    max_nodes: int,
    starts_requested: Iterable[str] | None,
    ends_requested: Iterable[str] | None,
    limit: int,
) -> int:
    specs = load_node_specs(docs_root)
    _, _, adjacency = compatibility_matrix(specs)
    starts = selected_node_ids(specs, starts_requested)
    ends = selected_node_ids(specs, ends_requested)
    chains = enumerate_chains(adjacency, min_nodes, max_nodes, starts, ends, limit)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8") as handle:
        for chain in chains:
            handle.write(json.dumps(chain, ensure_ascii=False, sort_keys=True) + "\n")
    return len(chains)
