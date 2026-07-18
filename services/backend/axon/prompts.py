from __future__ import annotations

import re
from functools import lru_cache
from pathlib import Path
from typing import Iterable


AXON_DIR = Path(__file__).resolve().parent


def _read_text(name: str) -> str:
    return (AXON_DIR / name).read_text(encoding="utf-8")


def _read_block(name: str) -> str:
    return _read_text(f"prompt_blocks/{name}.txt")


@lru_cache(maxsize=1)
def get_node_docs() -> str:
    return _read_text("node_docs.txt")


@lru_cache(maxsize=1)
def get_legacy_start_prompt() -> str:
    return _read_text("prompt.txt").replace("{node_docs}", get_node_docs())


@lru_cache(maxsize=1)
def get_compact_start_prompt() -> str:
    prompt = _read_text("prompt_compact.txt")
    blocks = {
        "STYLE_RULES": _read_block("style_rules"),
        "DECISION_RULES": _read_block("decision_rules"),
        "CONTEXT_TOOLS": _read_block("context_tools"),
        "NODE_LIST": _read_block("node_list"),
        "DATASETS": _read_block("datasets"),
        "BUILD_REFERENCES": _read_block("build_references"),
        "RESPONSE_RULES": _read_block("response_rules"),
    }
    for key, value in blocks.items():
        prompt = prompt.replace("{{" + key + "}}", value.strip())
    return prompt.strip() + "\n"


def get_start_prompt() -> str:
    return get_compact_start_prompt()


@lru_cache(maxsize=1)
def get_builder_prompt() -> str:
    return _read_text("builder.txt").replace("{node_docs}", get_node_docs())


@lru_cache(maxsize=1)
def get_digit_2_conv_graph() -> str:
    return _read_text("digit_2_conv")


VALID_NODE_TYPES = {
    "activation",
    "dense_layer",
    "conv2d_layer",
    "maxpool_layer",
    "dropout",
    "softmax",
    "flatten",
    "reshape2d",
    "concat",
    "input_1d",
    "out_labels",
    "input_image_small",
    "load_dataset",
    "train_begin",
    "run_model",
    "output_map",
    "train_step",
}


def _normalize_node_type_request(node_types: str | Iterable[str] | None) -> list[str]:
    if node_types is None:
        return []
    if isinstance(node_types, str):
        raw = node_types.strip()
        if not raw:
            return []
        raw = raw.strip("[]")
        parts = re.split(r"[\s,]+", raw)
    else:
        parts = [str(x) for x in node_types]
    out: list[str] = []
    for part in parts:
        name = str(part).strip().strip("\"'")
        if name and name not in out:
            out.append(name)
    return out


def _extract_node_doc(name: str, docs: str) -> str:
    marker = f'"{name}"'
    start = docs.find(marker)
    if start == -1:
        return ""
    brace_start = docs.find("{", start)
    if brace_start == -1:
        return ""

    depth = 0
    in_string = False
    escaped = False
    for idx in range(brace_start, len(docs)):
        ch = docs[idx]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return f'{marker}: {docs[brace_start:idx + 1]}'
    return ""


def get_filtered_node_docs(node_types: str | Iterable[str] | None = None) -> str:
    docs = get_node_docs()
    requested = _normalize_node_type_request(node_types)
    if not requested:
        return docs

    unknown = [name for name in requested if name not in VALID_NODE_TYPES]
    known = [name for name in requested if name in VALID_NODE_TYPES]
    sections = [_extract_node_doc(name, docs) for name in known]
    sections = [section for section in sections if section]

    lines: list[str] = []
    if sections:
        lines.append("Requested Neuralese node docs:")
        lines.append("```json")
        lines.append("{")
        lines.append(",\n".join(sections))
        lines.append("}")
        lines.append("```")
    if unknown:
        lines.append("Unknown requested node types ignored: " + ", ".join(unknown))
    if not sections and not unknown:
        return docs
    return "\n".join(lines).strip()


def remove_tag_blocks(text: str, tags: list[str]) -> str:
    tag_pattern = "|".join(re.escape(tag) for tag in tags)
    full = re.compile(rf"\s*<(?P<tag>{tag_pattern})>.*?</(?P=tag)>\s*", re.DOTALL)
    open_only = re.compile(rf"\s*<(?P<tag>{tag_pattern})>.*?(?=\Z|\n|$)", re.DOTALL)
    close_only = re.compile(rf"</(?P<tag>{tag_pattern})>\s*", re.DOTALL)

    while True:
        new_text, n1 = full.subn(" ", text)
        new_text, n2 = open_only.subn(" ", new_text)
        new_text, n3 = close_only.subn(" ", new_text)
        if n1 + n2 + n3 == 0:
            break
        text = new_text

    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s*\n\s*", "\n", text)
    text = re.sub(r"\n{2,}", "\n", text)
    return text.strip()

