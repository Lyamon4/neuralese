from __future__ import annotations

from dataclasses import dataclass
import json
import shutil
from pathlib import Path
from typing import Any

from .godot_static import LANGS, NodeInfo, godot_to_fs


SCHEMA_VERSION = 1


@dataclass
class ValidationIssue:
    level: str
    node_id: str
    message: str

    def format(self) -> str:
        prefix = self.level.upper()
        node = self.node_id or "-"
        return f"[{prefix}] {node}: {self.message}"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict[str, Any], dry_run: bool = False) -> None:
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def empty_langs(seed: dict[str, str] | None = None) -> dict[str, str]:
    seed = seed or {}
    return {lang: seed.get(lang, "") or "" for lang in LANGS}


def docs_shell(node: NodeInfo, existing: dict[str, Any] | None = None) -> dict[str, Any]:
    existing = existing or {}
    docs = existing.copy()
    docs.setdefault("title", empty_langs(node.title_candidates))
    docs.setdefault("summary", empty_langs())
    docs.setdefault("operation", empty_langs())
    docs.setdefault("compact", {})
    docs["compact"].setdefault("body", empty_langs())
    docs.setdefault("ports", {})
    docs.setdefault("settings", {})
    docs.setdefault("connects_to", [])
    docs.setdefault("examples", [])

    for port in node.ports:
        port_doc = docs["ports"].setdefault(port.id, {})
        port_doc.setdefault("label", empty_langs({"en": port.server_name or port.scene_node}))
        port_doc.setdefault("description", empty_langs())

    for setting in node.settings:
        setting_doc = docs["settings"].setdefault(setting.id, {})
        setting_doc.setdefault("label", empty_langs({"en": setting.id}))
        setting_doc.setdefault("description", empty_langs())

    return docs


def node_document(node: NodeInfo, existing: dict[str, Any] | None = None) -> dict[str, Any]:
    existing = existing or {}
    return {
        "schema_version": SCHEMA_VERSION,
        "node_id": node.node_id,
        "status": existing.get("status", "stable"),
        "generated": node.to_generated(),
        "docs": docs_shell(node, existing.get("docs", {})),
    }


def node_path(docs_root: Path, node_id: str) -> Path:
    return docs_root / node_id / "node.json"


def load_existing_node(docs_root: Path, node_id: str) -> dict[str, Any] | None:
    path = node_path(docs_root, node_id)
    if not path.exists():
        return None
    return load_json(path)


def sync_jasondocs(
    repo_root: Path,
    docs_root: Path,
    nodes: list[NodeInfo],
    schema_source: Path,
    dry_run: bool = False,
) -> list[str]:
    messages: list[str] = []
    if not dry_run:
        docs_root.mkdir(parents=True, exist_ok=True)
        (docs_root / ".gdignore").write_text("Generated docs data; keep out of Godot import scanning.\n", encoding="utf-8")
        (docs_root / "schema").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(schema_source, docs_root / "schema" / "node.schema.json")
    messages.append(f"sync .gdignore -> {docs_root / '.gdignore'}")
    messages.append(f"sync schema -> {docs_root / 'schema' / 'node.schema.json'}")

    for node in nodes:
        existing = load_existing_node(docs_root, node.node_id)
        document = node_document(node, existing)
        target = node_path(docs_root, node.node_id)
        write_json(target, document, dry_run=dry_run)
        messages.append(f"sync {node.node_id} -> {target}")

        if node.icon_source:
            source = godot_to_fs(repo_root, node.icon_source)
            icon_target = docs_root / node.node_id / "icon.png"
            if not dry_run:
                icon_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, icon_target)
            messages.append(f"sync {node.node_id} icon -> {icon_target}")
    return messages


def generated_equal(left: Any, right: Any) -> bool:
    return json.dumps(left, ensure_ascii=False, sort_keys=True) == json.dumps(
        right, ensure_ascii=False, sort_keys=True
    )


def lang_missing(value: Any) -> list[str]:
    if not isinstance(value, dict):
        return list(LANGS)
    return [lang for lang in LANGS if not str(value.get(lang, "")).strip()]


def validate_docs(docs_root: Path, nodes: list[NodeInfo], strict_generated: bool = True) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    by_id = {node.node_id: node for node in nodes}

    if not docs_root.exists():
        return [ValidationIssue("error", "", f"JasonDocs root does not exist: {docs_root}")]

    for node in nodes:
        path = node_path(docs_root, node.node_id)
        if not path.exists():
            issues.append(ValidationIssue("error", node.node_id, "missing node.json; run sync"))
            continue
        try:
            document = load_json(path)
        except Exception as exc:
            issues.append(ValidationIssue("error", node.node_id, f"invalid JSON: {exc}"))
            continue

        generated = document.get("generated")
        if strict_generated and not generated_equal(generated, node.to_generated()):
            issues.append(ValidationIssue("error", node.node_id, "generated metadata is stale; run sync"))

        if not (docs_root / node.node_id / "icon.png").exists():
            issues.append(ValidationIssue("error", node.node_id, "missing icon.png"))

        docs = document.get("docs", {})
        for field in ("title", "summary", "operation"):
            missing = lang_missing(docs.get(field))
            if missing:
                issues.append(ValidationIssue("error", node.node_id, f"docs.{field} missing: {', '.join(missing)}"))

        compact = docs.get("compact", {})
        missing = lang_missing(compact.get("body"))
        if missing:
            issues.append(ValidationIssue("error", node.node_id, f"docs.compact.body missing: {', '.join(missing)}"))

        port_docs = docs.get("ports", {})
        for port in node.ports:
            port_doc = port_docs.get(port.id)
            if not isinstance(port_doc, dict):
                issues.append(ValidationIssue("error", node.node_id, f"missing docs for port {port.id}"))
                continue
            missing = lang_missing(port_doc.get("description"))
            if missing:
                issues.append(
                    ValidationIssue(
                        "error",
                        node.node_id,
                        f"port {port.id} description missing: {', '.join(missing)}",
                    )
                )
        for port_id in port_docs.keys():
            if port_id not in {port.id for port in node.ports}:
                issues.append(ValidationIssue("error", node.node_id, f"stale port docs: {port_id}"))

        setting_docs = docs.get("settings", {})
        for setting in node.settings:
            setting_doc = setting_docs.get(setting.id)
            if not isinstance(setting_doc, dict):
                issues.append(ValidationIssue("error", node.node_id, f"missing docs for setting {setting.id}"))
                continue
            missing = lang_missing(setting_doc.get("description"))
            if missing:
                issues.append(
                    ValidationIssue(
                        "error",
                        node.node_id,
                        f"setting {setting.id} description missing: {', '.join(missing)}",
                    )
                )
        for setting_id in setting_docs.keys():
            if setting_id not in {setting.id for setting in node.settings}:
                issues.append(ValidationIssue("error", node.node_id, f"stale setting docs: {setting_id}"))

        for link in docs.get("connects_to", []):
            if not isinstance(link, dict):
                issues.append(ValidationIssue("error", node.node_id, "connects_to entries must be objects"))
                continue
            target = link.get("node_id")
            if target not in by_id:
                issues.append(ValidationIssue("error", node.node_id, f"unknown connects_to node_id: {target}"))

    for child in docs_root.iterdir():
        if child.is_dir() and child.name != "schema" and child.name not in by_id:
            path = child / "node.json"
            if not path.exists():
                continue
            try:
                status = load_json(path).get("status")
            except Exception:
                status = None
            if status != "deprecated":
                issues.append(ValidationIssue("error", child.name, "docs folder is not in active graph_types"))

    return issues


def report_todos(docs_root: Path, nodes: list[NodeInfo]) -> list[str]:
    lines: list[str] = []
    issues = validate_docs(docs_root, nodes, strict_generated=False)
    by_node: dict[str, list[str]] = {}
    for issue in issues:
        by_node.setdefault(issue.node_id or "-", []).append(issue.message)
    for issue in by_node.get("-", []):
        lines.append("global:")
        lines.append(f"  - {issue}")
    for node in nodes:
        node_issues = by_node.get(node.node_id, [])
        if not node_issues:
            continue
        lines.append(f"{node.node_id}:")
        for issue in node_issues:
            lines.append(f"  - {issue}")
    return lines


