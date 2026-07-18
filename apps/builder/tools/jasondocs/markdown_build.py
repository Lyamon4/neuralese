from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from .godot_static import LANGS
from .jason_docs import load_json


def lang_text(value: dict[str, Any] | None, lang: str) -> str:
    if not isinstance(value, dict):
        return ""
    return str(value.get(lang, "")).strip()


def escape_cell(value: Any) -> str:
    text = str(value if value is not None else "")
    return text.replace("|", "\\|").replace("\n", "<br>")


def generated_ports(document: dict[str, Any], direction: str) -> list[dict[str, Any]]:
    ports = document.get("generated", {}).get("ports", [])
    return [port for port in ports if port.get("direction") == direction]


def generated_settings(document: dict[str, Any]) -> list[dict[str, Any]]:
    return document.get("generated", {}).get("settings", [])


def full_markdown(document: dict[str, Any], lang: str) -> str:
    node_id = document["node_id"]
    docs = document.get("docs", {})
    generated = document.get("generated", {})
    title = lang_text(docs.get("title"), lang) or node_id
    summary = lang_text(docs.get("summary"), lang)
    operation = lang_text(docs.get("operation"), lang)
    port_docs = docs.get("ports", {})
    setting_docs = docs.get("settings", {})

    lines: list[str] = [
        f"# {title}",
        "",
        f"![{title}](../../assets/nodes/{node_id}/icon.png)",
        "",
    ]
    if summary:
        lines.extend([summary, ""])

    lines.extend(["## Operation", "", operation, ""])

    for direction, heading in (("input", "Inputs"), ("output", "Outputs")):
        ports = generated_ports(document, direction)
        if not ports:
            continue
        lines.extend([f"## {heading}", "", "| Port | Server name | Data types | Description |", "|---|---|---|---|"])
        for port in ports:
            port_doc = port_docs.get(port.get("id"), {})
            label = lang_text(port_doc.get("label"), lang) or port.get("id", "")
            description = lang_text(port_doc.get("description"), lang)
            lines.append(
                "| "
                + " | ".join(
                    [
                        escape_cell(label),
                        escape_cell(port.get("server_name") or ""),
                        escape_cell(", ".join(port.get("datatypes", []))),
                        escape_cell(description),
                    ]
                )
                + " |"
            )
        lines.append("")

    settings = generated_settings(document)
    if settings:
        lines.extend(["## Settings", "", "| Setting | Default | UI | Description |", "|---|---:|---|---|"])
        for setting in settings:
            setting_doc = setting_docs.get(setting.get("id"), {})
            label = lang_text(setting_doc.get("label"), lang) or setting.get("id", "")
            description = lang_text(setting_doc.get("description"), lang)
            lines.append(
                "| "
                + " | ".join(
                    [
                        escape_cell(label),
                        escape_cell(setting.get("default", "")),
                        escape_cell(setting.get("ui_kind") or setting.get("source") or ""),
                        escape_cell(description),
                    ]
                )
                + " |"
            )
        lines.append("")

    compatible = generated.get("static_compatible_nodes", [])
    if compatible:
        lines.extend(["## Static Compatibility", "", "| Output | Target node | Target input | Data types |", "|---|---|---|---|"])
        for item in compatible:
            lines.append(
                "| "
                + " | ".join(
                    [
                        escape_cell(item.get("from_port", "")),
                        escape_cell(item.get("to_node", "")),
                        escape_cell(item.get("to_port", "")),
                        escape_cell(", ".join(item.get("datatypes", []))),
                    ]
                )
                + " |"
            )
        lines.append("")

    examples = docs.get("examples", [])
    rendered_examples = []
    for example in examples:
        if isinstance(example, dict):
            body = lang_text(example.get("body"), lang)
            if body:
                rendered_examples.append(body)
    if rendered_examples:
        lines.extend(["## Examples", ""])
        for body in rendered_examples:
            lines.extend([body, ""])

    return "\n".join(lines).rstrip() + "\n"


def compact_markdown(document: dict[str, Any], lang: str) -> str:
    node_id = document["node_id"]
    docs = document.get("docs", {})
    title = lang_text(docs.get("title"), lang) or node_id
    body = lang_text(docs.get("compact", {}).get("body"), lang)
    lines = [
        f"# {title}",
        "",
        f"![{title}](../../assets/nodes/{node_id}/icon.png)",
        "",
        body,
        "",
    ]
    return "\n".join(lines).rstrip() + "\n"


def build_markdown(docs_root: Path, out_root: Path) -> list[str]:
    messages: list[str] = []
    node_dirs = sorted(
        child for child in docs_root.iterdir() if child.is_dir() and child.name != "schema" and (child / "node.json").exists()
    )
    documents = [load_json(child / "node.json") for child in node_dirs]

    for document in documents:
        node_id = document["node_id"]
        icon_source = docs_root / node_id / "icon.png"
        icon_target = out_root / "assets" / "nodes" / node_id / "icon.png"
        icon_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(icon_source, icon_target)
        messages.append(f"asset {node_id} -> {icon_target}")

        for lang in LANGS:
            full_target = out_root / lang / "nodes" / f"{node_id}.md"
            full_target.parent.mkdir(parents=True, exist_ok=True)
            full_target.write_text(full_markdown(document, lang), encoding="utf-8")
            messages.append(f"full {lang}/{node_id}")

            compact_target = out_root / "compact" / lang / f"{node_id}.md"
            compact_target.parent.mkdir(parents=True, exist_ok=True)
            compact_target.write_text(compact_markdown(document, lang), encoding="utf-8")
            messages.append(f"compact {lang}/{node_id}")

    index = []
    compact_manifest: dict[str, dict[str, str]] = {lang: {} for lang in LANGS}
    for document in documents:
        node_id = document["node_id"]
        docs = document.get("docs", {})
        index.append(
            {
                "node_id": node_id,
                "status": document.get("status", "stable"),
                "titles": docs.get("title", {}),
                "summary": docs.get("summary", {}),
                "icon": f"assets/nodes/{node_id}/icon.png",
                "full": {lang: f"{lang}/nodes/{node_id}.md" for lang in LANGS},
                "compact": {lang: f"compact/{lang}/{node_id}.md" for lang in LANGS},
            }
        )
        for lang in LANGS:
            compact_manifest[lang][node_id] = f"compact/{lang}/{node_id}.md"

    out_root.mkdir(parents=True, exist_ok=True)
    (out_root / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out_root / "compact_manifest.json").write_text(
        json.dumps(compact_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    messages.append(f"index -> {out_root / 'index.json'}")
    messages.append(f"compact manifest -> {out_root / 'compact_manifest.json'}")
    return messages

