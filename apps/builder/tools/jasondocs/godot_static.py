from __future__ import annotations

from dataclasses import dataclass, field
import json
import re
from pathlib import Path
from typing import Any


LANGS = ("en", "ru", "kz")


def strip_gd_comments(text: str) -> str:
    """Remove whole-line comments before simple GDScript pattern matching."""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def to_repo_path(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


def godot_to_fs(root: Path, godot_path: str) -> Path:
    if godot_path.startswith("res://"):
        return root / godot_path.removeprefix("res://")
    return root / godot_path


def fs_to_godot(root: Path, path: Path) -> str:
    return "res://" + to_repo_path(path, root)


def normalize_id(value: str) -> str:
    value = value.replace("res://", "")
    value = re.sub(r"[^A-Za-z0-9_]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_").lower()
    return value or "unnamed"


def pascal_graph_id(graph_id: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in graph_id.split("_") if part)


def clean_godot_value(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip().rstrip(",")
    if value.startswith("&"):
        value = value[1:]
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_scalar(value: str) -> Any:
    value = clean_godot_value(value) or ""
    if value in ("true", "false"):
        return value == "true"
    if value in ("null", "nil"):
        return None
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?\d+\.\d+", value):
        return float(value)
    return value


def parse_header_attrs(header: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    for key, value in re.findall(r"(\w+)=\"([^\"]*)\"", header):
        attrs[key] = value
    for key, value in re.findall(r"(\w+)=ExtResource\(\"([^\"]+)\"\)", header):
        attrs[key] = f"ExtResource({value})"
    for key, value in re.findall(r"(\w+)=SubResource\(\"([^\"]+)\"\)", header):
        attrs[key] = f"SubResource({value})"
    return attrs


@dataclass
class ExtResource:
    id: str
    type: str | None
    path: str
    uid: str | None = None


@dataclass
class SceneNode:
    name: str
    parent: str
    header: str
    attrs: dict[str, str]
    block: str

    def prop(self, name: str) -> str | None:
        match = re.search(r"^" + re.escape(name) + r"\s*=\s*(.+)$", self.block, re.MULTILINE)
        return clean_godot_value(match.group(1)) if match else None

    def raw_prop(self, name: str) -> str | None:
        match = re.search(r"^" + re.escape(name) + r"\s*=\s*(.+)$", self.block, re.MULTILINE)
        return match.group(1).strip() if match else None


@dataclass
class SceneInfo:
    path: str
    uid: str | None
    ext_resources: dict[str, ExtResource]
    nodes: list[SceneNode]

    @property
    def root(self) -> SceneNode | None:
        return self.nodes[0] if self.nodes else None


@dataclass
class ScriptInfo:
    path: str
    extends: str | None
    class_name: str | None
    has_useful_properties: bool
    has_config_field: bool
    has_is_valid: bool
    update_config_keys: list[str] = field(default_factory=list)
    cfg_keys: list[str] = field(default_factory=list)
    config_field_cases: list[str] = field(default_factory=list)


@dataclass
class PortInfo:
    id: str
    scene_node: str
    scene_path: str
    hint: int
    server_name: str | None
    direction: str
    datatypes: list[str]
    multiple: bool
    config_conn: bool
    keyword: str | None
    conn_count_keyword: str | None


@dataclass
class SettingInfo:
    id: str
    source: str
    default: Any = None
    ui_kind: str | None = None
    ui_path: str | None = None
    options: list[dict[str, str | None]] = field(default_factory=list)


@dataclass
class NodeInfo:
    node_id: str
    created_with: str
    scene_path: str
    scene_uid: str | None
    root_instance_path: str | None
    script_path: str | None
    inheritance_chain: list[str]
    inherits_graph: bool
    server_typename: str | None
    layer_name: str | None
    title_candidates: dict[str, str]
    base_config: dict[str, Any]
    ports: list[PortInfo]
    settings: list[SettingInfo]
    icon_source: str | None
    static_compatible_nodes: list[dict[str, Any]] = field(default_factory=list)

    def to_generated(self) -> dict[str, Any]:
        return {
            "node_id": self.node_id,
            "created_with": self.created_with,
            "scene_path": self.scene_path,
            "scene_uid": self.scene_uid,
            "root_instance_path": self.root_instance_path,
            "script_path": self.script_path,
            "inheritance_chain": self.inheritance_chain,
            "inherits_graph": self.inherits_graph,
            "server_typename": self.server_typename,
            "layer_name": self.layer_name,
            "title_candidates": self.title_candidates,
            "base_config": self.base_config,
            "ports": [port.__dict__ for port in self.ports],
            "settings": [setting.__dict__ for setting in self.settings],
            "icon_source": self.icon_source,
            "static_compatible_nodes": self.static_compatible_nodes,
        }


class GodotStaticAnalyzer:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.scripts = self._load_scripts()
        self.class_to_script = {
            info.class_name: path for path, info in self.scripts.items() if info.class_name
        }

    def scan(self) -> list[NodeInfo]:
        graph_types = self.graph_types()
        nodes: list[NodeInfo] = []
        for node_id, scene_path in graph_types.items():
            scene = self.parse_scene(godot_to_fs(self.root, scene_path))
            nodes.append(self._node_from_scene(node_id, scene))
        self._attach_static_compatibility(nodes)
        return nodes

    def graph_types(self) -> dict[str, str]:
        graph_manager = self.root / "scripts" / "graph_manager.gd"
        text = strip_gd_comments(graph_manager.read_text(encoding="utf-8", errors="replace"))
        match = re.search(r"var\s+graph_types\s*=\s*\{(?P<body>.*?)^\}", text, re.MULTILINE | re.DOTALL)
        if not match:
            return {}
        body = match.group("body")
        found = re.findall(r'"([^"]+)"\s*:\s*gload\("([^"]+)"\)', body)
        return {key: path for key, path in found}

    def parse_scene(self, path: Path) -> SceneInfo:
        text = path.read_text(encoding="utf-8", errors="replace")
        uid_match = re.search(r"^\[gd_scene[^\]]*uid=\"([^\"]+)\"", text, re.MULTILINE)
        ext_resources: dict[str, ExtResource] = {}
        for match in re.finditer(r"^\[ext_resource(?P<body>[^\]]+)\]", text, re.MULTILINE):
            attrs = parse_header_attrs("[ext_resource" + match.group("body") + "]")
            resource_id = attrs.get("id")
            resource_path = attrs.get("path")
            if resource_id and resource_path:
                ext_resources[resource_id] = ExtResource(
                    id=resource_id,
                    type=attrs.get("type"),
                    path=resource_path,
                    uid=attrs.get("uid"),
                )

        starts = [m.start() for m in re.finditer(r"^\[node ", text, re.MULTILINE)]
        scene_nodes: list[SceneNode] = []
        for index, start in enumerate(starts):
            end = starts[index + 1] if index + 1 < len(starts) else len(text)
            block = text[start:end]
            header = block.splitlines()[0]
            attrs = parse_header_attrs(header)
            scene_nodes.append(
                SceneNode(
                    name=attrs.get("name", ""),
                    parent=attrs.get("parent", "."),
                    header=header,
                    attrs=attrs,
                    block=block,
                )
            )
        return SceneInfo(
            path=fs_to_godot(self.root, path),
            uid=uid_match.group(1) if uid_match else None,
            ext_resources=ext_resources,
            nodes=scene_nodes,
        )

    def _load_scripts(self) -> dict[str, ScriptInfo]:
        result: dict[str, ScriptInfo] = {}
        scripts_dir = self.root / "scripts"
        for path in scripts_dir.glob("*.gd"):
            text = path.read_text(encoding="utf-8", errors="replace")
            godot_path = fs_to_godot(self.root, path)
            extends = self._first_match(text, r"^extends\s+([^\s#]+)")
            class_name = self._first_match(text, r"^class_name\s+([^\s#]+)")
            result[godot_path] = ScriptInfo(
                path=godot_path,
                extends=extends.strip('"') if extends else None,
                class_name=class_name,
                has_useful_properties=bool(re.search(r"^func\s+_useful_properties\s*\(", text, re.MULTILINE)),
                has_config_field=bool(re.search(r"^func\s+_config_field\s*\(", text, re.MULTILINE)),
                has_is_valid=bool(re.search(r"^func\s+_is_valid\s*\(", text, re.MULTILINE)),
                update_config_keys=sorted(set(re.findall(r'(?<!\.)\bupdate_config(?:_subfield)?\s*\(\s*\{[^}]*"([^"]+)"\s*:', text))),
                cfg_keys=sorted(set(re.findall(r'cfg\s*\[\s*"([^"]+)"\s*\]', text))),
                config_field_cases=self._config_field_cases(text),
            )
        return result

    @staticmethod
    def _config_field_cases(text: str) -> list[str]:
        match = re.search(
            r"^func\s+_config_field\s*\([^)]*\):(?P<body>.*?)(?=^func\s|\Z)",
            text,
            re.MULTILINE | re.DOTALL,
        )
        if not match:
            return []
        body = match.group("body")
        return sorted(set(re.findall(r"^\s*\"([^\"]+)\"\s*:\s*$", body, re.MULTILINE)))

    @staticmethod
    def _first_match(text: str, pattern: str) -> str | None:
        match = re.search(pattern, text, re.MULTILINE)
        return match.group(1) if match else None

    def _node_from_scene(self, node_id: str, scene: SceneInfo) -> NodeInfo:
        root = scene.root
        script_path = self._resolve_script(root, scene.ext_resources) if root else None
        root_instance_path = self._resolve_instance(root, scene.ext_resources) if root else None
        inheritance_chain = self._inheritance_chain(script_path)
        base_config = self._parse_base_config(root.block if root else "")
        ports = self._parse_ports(scene)
        controls = self._parse_controls(scene)
        settings = self._settings(base_config, controls, script_path)
        return NodeInfo(
            node_id=node_id,
            created_with=node_id,
            scene_path=scene.path,
            scene_uid=scene.uid,
            root_instance_path=root_instance_path,
            script_path=script_path,
            inheritance_chain=inheritance_chain,
            inherits_graph=self._inherits_graph(inheritance_chain, root_instance_path),
            server_typename=root.prop("server_typename") if root else None,
            layer_name=root.prop("layer_name") if root else None,
            title_candidates=self._title_candidates(scene),
            base_config=base_config,
            ports=ports,
            settings=settings,
            icon_source=self._icon_source(node_id),
        )

    def _resolve_script(self, node: SceneNode | None, resources: dict[str, ExtResource]) -> str | None:
        if not node:
            return None
        raw = node.raw_prop("script")
        if not raw:
            return None
        match = re.search(r'ExtResource\("([^"]+)"\)', raw)
        if not match:
            return None
        resource = resources.get(match.group(1))
        return resource.path if resource else None

    def _resolve_instance(self, node: SceneNode | None, resources: dict[str, ExtResource]) -> str | None:
        if not node:
            return None
        raw = node.attrs.get("instance")
        if not raw:
            return None
        match = re.search(r"ExtResource\(([^)]+)\)", raw)
        if not match:
            return None
        resource = resources.get(match.group(1))
        return resource.path if resource else None

    def _inheritance_chain(self, script_path: str | None) -> list[str]:
        chain: list[str] = []
        current = script_path
        seen: set[str] = set()
        while current and current not in seen:
            seen.add(current)
            chain.append(current)
            info = self.scripts.get(current)
            if not info or not info.extends:
                break
            current = self.class_to_script.get(info.extends)
            if current is None and info.extends.startswith("res://"):
                current = info.extends
        return chain

    @staticmethod
    def _inherits_graph(chain: list[str], root_instance_path: str | None) -> bool:
        return (
            "res://scripts/base_graph.gd" in chain
            or "res://scripts/io_graph.gd" in chain
            or root_instance_path == "res://scenes/base_graph.tscn"
        )

    def _parse_base_config(self, block: str) -> dict[str, Any]:
        match = re.search(
            r"^base_config\s*=\s*Dictionary[^{]*\(\{(?P<body>.*?)^\}\)",
            block,
            re.MULTILINE | re.DOTALL,
        )
        if not match:
            return {}
        body = match.group("body")
        result: dict[str, Any] = {}
        for line in body.splitlines():
            item = re.match(r'\s*&?"([^"]+)"\s*:\s*(.+?)\s*,?\s*$', line)
            if item:
                result[item.group(1)] = parse_scalar(item.group(2))
        return result

    def _parse_ports(self, scene: SceneInfo) -> list[PortInfo]:
        ports: list[PortInfo] = []
        used_ids: dict[str, int] = {}
        for node in scene.nodes:
            instance_path = self._resolve_instance(node, scene.ext_resources)
            looks_like_connection = (
                instance_path == "res://scenes/Connection.tscn"
                or node.raw_prop("_accepted_datatypes") is not None
                or node.raw_prop("connection_type") is not None
                or node.raw_prop("server_name") is not None
            )
            if not looks_like_connection:
                continue
            direction = "output" if node.prop("connection_type") == "1" else "input"
            hint_raw = node.prop("hint")
            try:
                hint = int(hint_raw) if hint_raw is not None else 0
            except ValueError:
                hint = 0
            server_name = node.prop("server_name")
            datatypes = (node.prop("_accepted_datatypes") or "").split()
            base_id_parts = [direction]
            if node.parent not in ("", "."):
                base_id_parts.append(node.parent)
            base_id_parts.extend([node.name, server_name or f"hint_{hint}"])
            base_id = normalize_id("_".join(base_id_parts))
            count = used_ids.get(base_id, 0) + 1
            used_ids[base_id] = count
            port_id = base_id if count == 1 else f"{base_id}_{count}"
            ports.append(
                PortInfo(
                    id=port_id,
                    scene_node=node.name,
                    scene_path=node.parent,
                    hint=hint,
                    server_name=server_name,
                    direction=direction,
                    datatypes=datatypes,
                    multiple=node.prop("multiple_splines") == "true",
                    config_conn=node.prop("config_conn") == "true",
                    keyword=node.prop("keyword"),
                    conn_count_keyword=node.prop("conn_count_keyword"),
                )
            )
        return ports

    def _parse_controls(self, scene: SceneInfo) -> list[dict[str, Any]]:
        controls: list[dict[str, Any]] = []
        for node in scene.nodes:
            node_type = node.attrs.get("type")
            text = node.prop("text")
            hint = node.prop("hint")
            placeholder = node.prop("placeholder_text")
            is_control = (
                node_type in {"HSlider", "LineEdit", "TextEdit", "CheckBox", "OptionButton"}
                or hint is not None
                or placeholder is not None
            )
            if not is_control:
                continue
            controls.append(
                {
                    "name": node.name,
                    "path": node.parent if node.parent != "." else node.name,
                    "type": node_type or "instance",
                    "text": text,
                    "hint": hint,
                    "placeholder": placeholder,
                }
            )
        return controls

    def _settings(
        self,
        base_config: dict[str, Any],
        controls: list[dict[str, Any]],
        script_path: str | None,
    ) -> list[SettingInfo]:
        script = self.scripts.get(script_path or "")
        ids: dict[str, SettingInfo] = {}
        for key, default in base_config.items():
            ids[key] = SettingInfo(id=key, source="base_config", default=default)
        if script:
            for key in script.update_config_keys + script.config_field_cases:
                ids.setdefault(key, SettingInfo(id=key, source="script"))
        for setting in ids.values():
            lower_id = setting.id.lower()
            for control in controls:
                path = str(control["path"]).lower()
                placeholder = str(control.get("placeholder") or "").lower()
                if lower_id in path or lower_id in placeholder:
                    setting.ui_kind = control["type"]
                    setting.ui_path = control["path"]
        menu_groups: dict[str, list[dict[str, str | None]]] = {}
        for control in controls:
            if control.get("hint") and control.get("text"):
                parent = str(control["path"]).split("/")[0]
                menu_groups.setdefault(parent, []).append(
                    {"hint": control.get("hint"), "text": control.get("text")}
                )
        for setting_id, options in menu_groups.items():
            if setting_id in ids:
                ids[setting_id].options = options
                ids[setting_id].ui_kind = ids[setting_id].ui_kind or "menu"
        return list(ids.values())

    def _title_candidates(self, scene: SceneInfo) -> dict[str, str]:
        english = ""
        ru = ""
        kz = ""
        for node in scene.nodes:
            if node.name in {"Label", "Label2"} and "ColorRect/root" in node.parent:
                english = node.prop("text") or english
                break
        if not english:
            for node in scene.nodes:
                text = node.prop("text")
                if text:
                    english = text
                    break
        for node in scene.nodes:
            if not ru and "localizations_ru" in node.block:
                values = self._dict_string_values(node.block, "localizations_ru")
                ru = values[0] if values else ""
            if not kz and "localizations_kz" in node.block:
                values = self._dict_string_values(node.block, "localizations_kz")
                kz = values[0] if values else ""
        return {"en": english, "ru": ru, "kz": kz}

    @staticmethod
    def _dict_string_values(block: str, prop: str) -> list[str]:
        match = re.search(
            r"^" + re.escape(prop) + r"\s*=\s*Dictionary[^{]*\(\{(?P<body>.*?)^\}\)",
            block,
            re.MULTILINE | re.DOTALL,
        )
        if not match:
            return []
        return re.findall(r'"[^"]*"\s*:\s*"([^"]*)"', match.group("body"))

    def _icon_source(self, node_id: str) -> str | None:
        candidates = [
            self.root / "node_icons" / f"Icon{pascal_graph_id(node_id)}.png",
            self.root / "node_icons" / f"Icon{node_id}.png",
        ]
        for path in candidates:
            if path.exists():
                return fs_to_godot(self.root, path)
        return None

    def _attach_static_compatibility(self, nodes: list[NodeInfo]) -> None:
        for source in nodes:
            out_ports = [port for port in source.ports if port.direction == "output" and port.datatypes]
            compatible: list[dict[str, Any]] = []
            for out_port in out_ports:
                out_types = set(out_port.datatypes)
                for target in nodes:
                    for in_port in target.ports:
                        if in_port.direction != "input" or not in_port.datatypes:
                            continue
                        shared = sorted(out_types.intersection(in_port.datatypes))
                        if not shared:
                            continue
                        compatible.append(
                            {
                                "from_port": out_port.id,
                                "to_node": target.node_id,
                                "to_port": in_port.id,
                                "datatypes": shared,
                                "confidence": "static_datatype_intersection",
                            }
                        )
            source.static_compatible_nodes = compatible


class EnhancedJsonEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if hasattr(obj, "__dict__"):
            return obj.__dict__
        return super().default(obj)



