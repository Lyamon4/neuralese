from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "Neuralese_Godot_Frontend_Documentation.md"


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def fence_json(text: str) -> str:
    return "```json\n" + text.strip() + "\n```"


PURPOSE = {
    "scripts/project.gd": "Main scene controller. Registers `glob.base_node`, anchors project-level state, and validates graph type load ordering.",
    "scripts/glob.gd": "Global app state/service locator: login, project save/load, local datasets/RLE cache, undo/redo, tabs, localization, AI chat, and backend root selection.",
    "scripts/graph_manager.gd": "Autoload graph registry/serializer/traverser. Owns graph scene type map, graph ids, connection ids, load/save, reachability, shape propagation, and backend syntax tree generation.",
    "scripts/base_graph.gd": "Base class for visual graph nodes. Handles config, ports, serialization, propagation, validation, connection lifecycle, subgraphs/contexts, selection, dragging, delete/copy, and undo integration.",
    "scripts/connection.gd": "Graph port class. Handles datatype compatibility, spline lifecycle, hover/drag connection UX, connection ids, and attach/detach side effects.",
    "scripts/spline.gd": "Visual curve/edge between Connection ports.",
    "scripts/block_component.gd": "Core custom UI primitive for buttons, menus, dynamic children, scrolling, hover/press/release signals, and block-style text rendering.",
    "scripts/ui_manager.gd": "Global splash/dialog and UI effects manager: errors, hourglass, lock, confetti, arrows, focus, graph screenshots, and Markdown rendering.",
    "scripts/web.gd": "Threaded HTTP/SSE client returning RequestHandle signals.",
    "scripts/sockets.gd": "WebSocket connection registry/poller autoload.",
    "scripts/socket_connection.gd": "WebSocketPeer wrapper with connected/closed/packet/kill/ack signals and JSON/binary send helpers.",
    "scripts/run_manager.gd": "Training/inference backend bridge. Validates graph topology, serializes syntax trees, opens ws/train and ws/infer, streams local dataset blocks, and dispatches progress/results.",
    "scripts/train_begin.gd": "Train button graph node. Holds dataset/epoch state, propagates dataset metadata, starts/stops training, and handles progress UI.",
    "scripts/train_input.gd": "Optimizer/training config graph node. Stores optimizer/lr/momentum/weight decay and active training-head state.",
    "scripts/train_rl.gd": "Experimental RL training graph node, present but skipped in the default add menu.",
    "scripts/run_m.gd": "RunModel graph node. Selects named model input, maps branch losses/output maps, and emits runtime config.",
    "scripts/input_graph.gd": "2D drawing input node for inference. Captures canvas pixels and streams data to ws/infer.",
    "scripts/input_1d.gd": "1D/tabular input node. Builds dynamic controls from dataset metadata and streams tensor data to inference.",
    "scripts/dataset_node.gd": "DatasetName graph node. Opens selector, stores dataset name, loads preview metadata, and propagates to TrainBegin.",
    "scripts/dataset_tab.gd": "Local dataset editor window coordinating dataset list, VirtualTable, CLI, preview validation, dirty state, and RLE cache updates.",
    "scripts/virtualt.gd": "Virtualized typed table widget for dataset editing, row/column caching, cell pooling, preview generation, and dirty signals.",
    "scripts/ds_obj_serialize.gd": "Dataset preview validation and compressed block/RLE serialization for local dataset upload.",
    "scripts/dataset_helpers.gd": "CSV import helper: encoding/delimiter detection and conversion into Neuralese dataset objects.",
    "scripts/cli.gd": "Dataset command-line editor for table transforms, filters, column conversion, output boundary, and row operations.",
    "scripts/cmdparse.gd": "Dataset CLI command grammar/parser.",
    "scripts/graph_script_parser.gd": "AI action tag parser and graph mutation applier: create/delete/connect/configure/layout graph nodes from streamed chat actions.",
    "scripts/ai_help.gd": "AI chat splash; streams assistant text and hands graph actions to parser on socket close.",
    "scripts/model_export.gd": "Model export splash; serializes selected graph and requests backend export formats/quantization.",
    "scripts/top_panel.gd": "Top navigation/foreground controller for login, AI, export, graph/dataset tabs, project list, and other windows.",
    "scripts/cmenu.gd": "Add-node context menu. Filters node list and instantiates selected graph scenes through `graphs.get_graph`.",
    "scripts/menus.gd": "Workspace menu layer bootstrap.",
    "scripts/edit_graph.gd": "Graph node context menu actions.",
    "scripts/detatch_menu.gd": "Spline detach/delete context menu.",
    "scripts/gview.gd": "GraphStorage registration script.",
    "scripts/win_graph.gd": "Tab window wrapper for graph/dataset/environment views.",
    "scripts/camera_2d.gd": "Workspace camera pan/zoom controller.",
    "scripts/selector_box.gd": "Drag selection rectangle and camera pan requester.",
    "scripts/netname.gd": "ModelName graph node and model update propagation.",
    "scripts/classifier.gd": "Classifier/output graph node; manages labels and displays inference outputs.",
    "scripts/branches.gd": "OutputMap graph node for mapping dataset outputs to model output branches/losses.",
    "scripts/base_layer.gd": "Base class for trainable layer graph nodes.",
    "scripts/neuron_layer.gd": "Dense layer graph node.",
    "scripts/conv_2d.gd": "Conv2D layer graph node with filter/kernel/stride visualization and 2D shape propagation.",
    "scripts/maxpool.gd": "MaxPool layer graph node.",
    "scripts/flatten.gd": "Flatten layer graph node.",
    "scripts/reshape.gd": "Reshape2D graph node.",
    "scripts/softmax_node.gd": "Softmax graph node.",
    "scripts/dropout.gd": "Dropout graph node.",
    "scripts/layer_concat.gd": "Dynamic concatenation graph node.",
    "scripts/learner.gd": "Lesson/tutorial runtime manager and graph invariant watcher.",
    "scripts/lesson_code.gd": "Lesson DSL/state machine.",
    "scripts/lua_envs.gd": "Global Lua environment/process registry.",
    "scripts/lua_process.gd": "Lua process/interpreter bridge.",
    "scripts/env_tab.gd": "Environment editor tab.",
    "scripts/env_tag.gd": "Lua environment tag graph node.",
    "scripts/update_state.gd": "Desktop update checker/downloader.",
    "scripts/transcriber.gd": "Audio recording/transcription helper.",
    "scripts/yaml_comp.gd": "YAML helper using the YAML addon.",
}

SCENE_PURPOSE = {
    "scenes/project.tscn": "Main runtime scene: top UI, graph workspace, GraphStorage, menus, camera, background, and AI loader.",
    "scenes/fg.tscn": "Foreground/top navigation panel.",
    "scenes/menus.tscn": "Workspace add/context/detach menu layer.",
    "scenes/base_graph.tscn": "Base graph node visual template.",
    "scenes/Connection.tscn": "Reusable graph port scene.",
    "scenes/default_spline.tscn": "Reusable graph edge/spline scene.",
    "scenes/BaseBComponent.tscn": "Reusable BlockComponent button/menu template.",
    "scenes/train_begin.tscn": "TrainBegin graph node and Train/Clear UI.",
    "scenes/train_input.tscn": "Optimizer/training configuration graph node.",
    "scenes/run_model.tscn": "RunModel graph node.",
    "scenes/input_graph.tscn": "2D drawing input graph node.",
    "scenes/input_1d.tscn": "1D/tabular input graph node.",
    "scenes/dataset.tscn": "DatasetName graph node.",
    "scenes/netname.tscn": "ModelName graph node.",
    "scenes/classifier_graph.tscn": "Classifier/output graph node.",
    "scenes/branch_mapping.tscn": "OutputMap branch/loss mapping graph node.",
    "scenes/layer.tscn": "Dense layer graph node.",
    "scenes/conv2d.tscn": "Conv2D graph node.",
    "scenes/maxpool.tscn": "MaxPool graph node.",
    "scenes/flatten.tscn": "Flatten graph node.",
    "scenes/reshape.tscn": "Reshape2D graph node.",
    "scenes/softmax.tscn": "Softmax graph node.",
    "scenes/dropout.tscn": "Dropout graph node.",
    "scenes/layer_concat.tscn": "Concat graph node.",
    "scenes/activation_node.tscn": "Activation selector graph/menu component.",
    "scenes/dataset_tab.tscn": "Local dataset editor tab/window.",
    "scenes/select_dataset.tscn": "Dataset selection splash.",
    "scenes/dataset_create.tscn": "Dataset create/import splash.",
    "scenes/model_export.tscn": "Model export splash.",
    "scenes/path_open.tscn": "Filesystem picker dialog.",
    "scenes/ai_help.tscn": "AI assistant/chat splash.",
    "scenes/splash.tscn": "Login splash.",
    "scenes/signup.tscn": "Signup splash.",
    "scenes/settings.tscn": "Settings/account/language/classroom splash.",
    "scenes/workslist.tscn": "Project/work list splash.",
    "scenes/works.tscn": "Project/work list variant.",
    "scenes/lessonlist.tscn": "Lesson selector splash.",
    "scenes/project_create.tscn": "New project dialog.",
    "scenes/scene_create.tscn": "New scene/classroom-style dialog.",
    "scenes/classroom_create.tscn": "Classroom creation dialog.",
    "scenes/env_tab.tscn": "Lua/environment editor tab.",
    "scenes/bg.tscn": "Workspace background layer.",
    "scenes/aiload.tscn": "AI/loading overlay.",
    "scenes/confetti.tscn": "Confetti particle effect.",
    "scenes/quest.tscn": "Lesson/question UI.",
    "scenes/quest_legacy.tscn": "Legacy lesson/question UI.",
}


def parse_script(path: Path) -> dict:
    text = read(path)
    lines = text.splitlines()
    info = {
        "path": rel(path),
        "lines": len(lines),
        "extends": "",
        "class": "",
        "signals": [],
        "exports": [],
        "funcs": [],
        "todos": [],
        "connects": [],
        "emits": [],
    }
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("extends "):
            info["extends"] = s
        if s.startswith("class_name "):
            info["class"] = s
        if s.startswith("signal "):
            info["signals"].append((i, s))
        if s.startswith("@export") or s.startswith("export "):
            info["exports"].append((i, s[:180]))
        if s.startswith("func "):
            info["funcs"].append((i, s[:220]))
        if ".connect(" in s:
            info["connects"].append((i, s[:220]))
        if ".emit(" in s or "emit_signal(" in s:
            info["emits"].append((i, s[:220]))
        if "TODO" in s or "FIXME" in s or "deprecated" in s.lower():
            info["todos"].append((i, s[:220]))
    return info


def parse_scene(path: Path) -> dict:
    text = read(path)
    lines = text.splitlines()
    info = {
        "path": rel(path),
        "uid": "",
        "root": "",
        "nodes": 0,
        "scripts": [],
        "connections": [],
        "key_props": [],
    }
    for i, line in enumerate(lines, 1):
        if i == 1:
            m = re.search(r'uid="([^"]+)"', line)
            if m:
                info["uid"] = m.group(1)
        if line.startswith("[node "):
            info["nodes"] += 1
            if not info["root"]:
                info["root"] = line.strip()
        if line.startswith("[ext_resource"):
            m = re.search(r'path="([^"]+)"', line)
            if m and m.group(1).endswith(".gd"):
                info["scripts"].append(m.group(1))
        if line.startswith("[connection "):
            info["connections"].append(line.strip())
        if any(k in line for k in [
            "server_typename =",
            "base_config =",
            "window_name =",
            "accepted_datatypes",
            "connection_type =",
            "hint =",
            "skip =",
        ]):
            info["key_props"].append((i, line.strip()[:220]))
    info["scripts"] = sorted(set(info["scripts"]))
    return info


def bullets(items, limit=None):
    out = []
    data = items[:limit] if limit else items
    for item in data:
        if isinstance(item, tuple):
            out.append(f"  - L{item[0]}: `{item[1]}`")
        else:
            out.append(f"  - `{item}`")
    if limit and len(items) > limit:
        out.append(f"  - ... {len(items) - limit} more")
    return "\n".join(out)


def main():
    scripts = [parse_script(p) for p in sorted((ROOT / "scripts").glob("*.gd"))]
    scripts += [parse_script(p) for p in sorted((ROOT / "scenes").glob("*.gd"))]
    scenes = [parse_scene(p) for p in sorted((ROOT / "scenes").glob("*.tscn"))]
    resources = sorted([p for p in (ROOT / "resources").glob("*") if p.is_file()])
    configs = [p for p in [ROOT / "project.godot", ROOT / "export_presets.cfg", ROOT / "default_bus_layout.tres", ROOT / "ports.tres"] if p.exists()]
    addons = sorted([p for p in (ROOT / "addons").glob("**/*") if p.is_file()]) if (ROOT / "addons").exists() else []

    project = read(ROOT / "project.godot")
    autoloads, inputs, app = [], [], []
    section = None
    for line in project.splitlines():
        if line.startswith("["):
            section = line.strip()
            continue
        if not line.strip() or line.strip().startswith(";"):
            continue
        if section == "[autoload]":
            autoloads.append(line.strip())
        elif section == "[input]" and "=" in line and not line.startswith("events"):
            inputs.append(line.strip())
        elif section == "[application]":
            app.append(line.strip())

    graph_manager = read(ROOT / "scripts" / "graph_manager.gd")
    graph_types = re.findall(r'"([^"]+)"\s*:\s*preload\("([^"]+)"\)', graph_manager)
    declared_signals = [(s["path"], sig) for s in scripts for sig in s["signals"]]
    scene_connections = [(sc["path"], c) for sc in scenes for c in sc["connections"]]

    md = []
    add = md.append
    add("# Neuralese Godot Frontend Documentation")
    add("")
    add("Generated from static repository inspection on 2026-05-25. Scope: first-party Godot scripts/scenes/resources/configuration plus vendor/addon inventory. Backend behavior is documented only where visible from frontend call sites; uncertain server-side details are explicitly marked.")
    add("")
    add("## 1. Executive Summary")
    add("")
    add("Neuralese is a Godot-based visual neural-network frontend. It provides a graph canvas for building model/training/inference pipelines, a typed local dataset editor, project save/load/import/export flows, lesson/AI assistance, and HTTP/WebSocket clients for backend training, inference, export, project persistence, datasets, and chat.")
    add("")
    add(f"This pass scanned **{len(scripts)}** first-party GDScript files, **{len(scenes)}** scenes, **{len(resources) + len(configs)}** resource/config files, **{len(declared_signals)}** declared script signals, and **{len(scene_connections)}** editor scene connections.")
    add("")
    add("The highest-leverage files are `project.godot`, `scenes/project.tscn`, `scripts/project.gd`, `scripts/glob.gd`, `scripts/graph_manager.gd`, `scripts/base_graph.gd`, `scripts/connection.gd`, `scripts/block_component.gd`, `scripts/run_manager.gd`, `scripts/train_begin.gd`, `scripts/train_input.gd`, `scripts/dataset_tab.gd`, `scripts/virtualt.gd`, `scripts/ds_obj_serialize.gd`, and `scripts/graph_script_parser.gd`.")
    add("")
    add("The biggest engineering risks are global mutable state in `glob.gd`, multi-responsibility graph logic in `base_graph.gd`, implicit backend packet contracts in `run_manager.gd`, dynamic signal chains through `BlockComponent`, and dataset compression/upload race conditions around `VirtualTable`, `glob`, and `DsObjRLE`.")
    add("")
    add("## 2. Architecture Overview")
    add("")
    add("Runtime layers:")
    add("- Godot starts `scenes/project.tscn` from `project.godot` and initializes autoload singletons.")
    add("- `project.tscn` hosts top UI (`fg.tscn`), graph workspace (`WIN_GRAPH/GraphStorage`), menus, camera, background, and loading overlays.")
    add("- `graphs` creates graph-node scenes from type keys and owns active graph/id/connection maps.")
    add("- `Graph`, `Connection`, and `Spline` implement node, port, and edge behavior.")
    add("- `BlockComponent` and `SplashMenu` implement the custom UI interaction framework.")
    add("- `glob` owns app/project/dataset/AI/login state and is the central service locator.")
    add("- `nn`, `web`, `sockets`, and `socket_connection` implement the backend boundary.")
    add("- Dataset editing flows through `dataset_tab`, `VirtualTable`, `DsObjRLE`, `dataset_helpers`, and `cli`.")
    add("- AI and guided lessons flow through `ai_help`, `glob.update_message_stream`, `graph_script_parser`, `learner`, `lesson_code`, DSL, and Lua scripts.")
    add("")
    add("```mermaid")
    add("flowchart TD")
    add("  Project[\"project.godot / project.tscn\"] --> Auto[\"autoloads\"]")
    add("  Project --> FG[\"fg.tscn top UI\"]")
    add("  Project --> WS[\"GraphStorage workspace\"]")
    add("  WS --> G[\"Graph nodes\"]")
    add("  G --> C[\"Connection ports\"]")
    add("  C --> S[\"Spline edges\"]")
    add("  Auto --> Glob[\"glob.gd\"]")
    add("  Auto --> Graphs[\"graph_manager.gd\"]")
    add("  Auto --> NN[\"run_manager.gd\"]")
    add("  Auto --> UI[\"ui_manager.gd\"]")
    add("  Auto --> Web[\"web.gd\"]")
    add("  Auto --> Sock[\"sockets.gd\"]")
    add("  FG --> Splash[\"SplashMenu dialogs\"]")
    add("  Dataset[\"Dataset editor/cache\"] --> Glob")
    add("  Dataset --> RLE[\"DsObjRLE compressed blocks\"]")
    add("  Graphs --> Syntax[\"get_syntax_tree payloads\"]")
    add("  NN --> Backend[\"Backend HTTP/WebSocket\"]")
    add("  Web --> Backend")
    add("  Sock --> Backend")
    add("  AI[\"AI chat/parser\"] --> Graphs")
    add("```")
    add("")
    add("## 3. Repository Map")
    add("")
    add("- `project.godot`: application settings, main scene, autoloads, input actions, rendering/audio config.")
    add("- `scenes/`: main scene, graph node scenes, dialogs/splashes, dataset/editor windows, reusable UI scenes, particles/loading effects, legacy/experimental scenes.")
    add("- `scripts/`: first-party GDScript, including autoloads, graph framework, node implementations, UI framework, dataset editor, backend clients, lessons, DSL, Lua, and utilities.")
    add("- `resources/`: shader materials, themes, syntax highlighters, button configs, graph/port UI materials.")
    add("- `addons/yaml/`: third-party YAML plugin used by YAML helper paths.")
    add("- `.godot/`: generated editor/import/export cache; inventoried but not treated as source architecture.")
    add("- `export_presets.cfg`: Android export preset.")
    add("")
    add("## 4. Godot Configuration")
    add("")
    add("Application settings:")
    add("\n".join(f"- `{x}`" for x in app))
    add("")
    add("Autoloads in initialization order:")
    add("\n".join(f"- `{x}`" for x in autoloads))
    add("")
    add("Input actions:")
    add("\n".join(f"- `{x}`" for x in inputs))
    add("")
    add("Important notes: `run/main_scene` resolves to `scenes/project.tscn`; `config/features` includes `4.6`; audio input is enabled at 16000 Hz for transcription; rendering uses mobile renderer settings and transparent clear color.")
    add("")
    add("## 5. Autoloads / Singletons")
    add("")
    add("### `glob` -> `scripts/glob.gd`")
    add("Owns project/session/login/dataset/AI/undo/window/localization state. Public workflow groups include project `open_last_project`, `request_projects`, `load_scene`, `save`, `save_empty`, project import/export; dataset `load_datasets`, `save_datasets`, `cache_rle_compress`, `join_ds_processing`, `create_dataset`, `dirtify_dataset`, `change_local_ds`, `invalidate_local_ds`; backend roots `get_root_ws`, `get_root_http`; auth `try_auto_login`, `login_req`, `splash_login`; AI `update_message_stream`, `message_chunk_received`, `sock_end_life`.")
    add("")
    add("### `graphs` -> `scripts/graph_manager.gd`")
    add("Owns graph type registration, active graph registry, graph ids, connection ids, graph load/save, reachability, shape propagation, connection hover arbitration, and `get_syntax_tree` backend serialization.")
    add("")
    add("Registered graph type map:")
    add("\n".join(f"- `{k}` -> `{v}`" for k, v in graph_types))
    add("")
    add("Signals: `model_updated(who)`, `spline_connected(from_conn,to_conn)`, `spline_disconnected(from_conn,to_conn)`, `node_added(who)`.")
    add("")
    add("### Other singletons")
    add("- `cookies`: storage/auth header manager used by login, project, HTTP, and WebSocket calls.")
    add("- `ui`: splash/dialog/effects/focus manager.")
    add("- `web`: HTTP/SSE client with RequestHandle signals.")
    add("- `sockets`: WebSocket connection registry/poller.")
    add("- `nn`: training/inference/export bridge.")
    add("- `luas`: Lua environment registry.")
    add("- `parser`: AI graph action parser.")
    add("- `dsl_reg`: DSL registry.")
    add("- `dsreader`: CSV/dataset helper.")
    add("- `learner`: lesson/tutorial runtime.")
    add("")
    add("## 6. Scene-by-Scene Documentation")
    add("")
    add("`scenes/project.tscn` is the main scene. It contains `fg`, `WIN_GRAPH`, `GraphStorage`, menus, camera, follow menus, background, and AI loader. `scripts/project.gd._enter_tree` sets `glob.base_node`; `_ready` validates that all `graphs.graph_types` keys have an entry in the `importance_chain` used by graph load ordering.")
    add("")
    add("Graph node scenes define `server_typename`, `base_config`, `Connection` children, accepted datatypes, UI controls, and attached scripts. Script subclasses implement backend properties, validation, shape propagation, and runtime behavior.")
    add("")
    for sc in scenes:
        add(f"### `{sc['path']}`")
        add(f"- Purpose: {SCENE_PURPOSE.get(sc['path'], 'Scene scanned. Purpose is inferred from attached scripts, root node, and key properties; likely reusable UI, dialog variant, visual effect, legacy scene, or specialized utility scene.')}")
        add(f"- UID: `{sc['uid'] or '(none parsed)'}`")
        add(f"- Root: `{sc['root'] or '(not parsed)'}`")
        add(f"- Node count: {sc['nodes']}")
        add(f"- Attached/extern scripts: {', '.join(f'`{x}`' for x in sc['scripts']) if sc['scripts'] else 'none parsed'}")
        if sc["key_props"]:
            add("- Key properties:")
            add(bullets(sc["key_props"], 20))
        if sc["connections"]:
            add("- Editor signal connections:")
            add(bullets(sc["connections"], 30))
        add("")
    add("## 7. Script-by-Script Documentation")
    add("")
    add("### Workflow-Critical Script Details")
    add("")
    add("`scripts/base_graph.gd` (`Graph`) is the node contract. Important methods: `update_config`, `update_config_subfield`, `_config_field`, `get_info`, `map_properties`, `llm_map`, `useful_properties`, `propagate`, `gather`, `just_connected`, `just_disconnected`, `check_valid`, `is_valid`, `delete`, `copy`, drag/group-drag helpers, `mark_new_subgraph`, `propagate_subgraph`, `_merge_subgraphs`, and `_recompute_context_for_subgraph`. Side effects include undo recording, config mutation, validation visuals, port/spline updates, graph context assignment, and global signal emission.")
    add("")
    add("`scripts/graph_manager.gd` (`graphs`) is the registry/serializer. `get_graph` instantiates scenes from type keys; `load_graph` restores project graph state and reconnects saved edges; `reach`/`simple_reach`/`_reach_input` trace topology; `get_syntax_tree` builds backend payloads; `reg_gather` asks nodes for `useful_properties`; `_process` maintains active/hovered connection candidates.")
    add("")
    add("`scripts/run_manager.gd` (`nn`) validates and runs backend workflows. `start_train` validates train and execution graphs, resolves TrainBegin/RunModel/input origins, requests graph saves, builds compressed train payloads, opens `ws/train`, optionally streams local dataset blocks, and routes progress packets. `open_infer_channel`, `send_inference_data`, and `close_infer_channel` manage `ws/infer`.")
    add("")
    add("`scripts/dataset_tab.gd`, `scripts/virtualt.gd`, and `scripts/ds_obj_serialize.gd` form the dataset system: UI edits -> dirty signals -> preview validation -> global dataset change signals -> RLE/block cache recompression -> local save or train upload.")
    add("")
    add("`scripts/graph_script_parser.gd` is a second graph mutation surface besides manual UI. It parses streamed AI tags (`change_nodes`, `connect_ports`, `delete_nodes`, `disconnect_ports`, `thinking`) and applies batched graph edits, node creation, config mapping, connection restoration, layout, and camera focus.")
    add("")
    add("### Complete Script Inventory and Function Catalogue")
    for s in scripts:
        add(f"#### `{s['path']}`")
        add(f"- Purpose: {PURPOSE.get(s['path'], 'Inspected first-party script. Purpose should be confirmed from scene attachment/function names; likely utility, visual control, dialog helper, legacy/experimental code, or specialized UI component.')}")
        add(f"- Lines: {s['lines']}")
        add(f"- Extends: `{s['extends'] or '(none parsed)'}`")
        add(f"- Class: `{s['class'] or '(none)'}`")
        if s["signals"]:
            add("- Signals:")
            add(bullets(s["signals"]))
        if s["exports"]:
            add("- Exported variables/properties:")
            add(bullets(s["exports"], 35))
        if s["funcs"]:
            add("- Functions:")
            add(bullets(s["funcs"]))
        if s["connects"]:
            add("- Code signal connections:")
            add(bullets(s["connects"], 20))
        if s["emits"]:
            add("- Signal emissions:")
            add(bullets(s["emits"], 20))
        if s["todos"]:
            add("- TODO/FIXME/deprecated markers:")
            add(bullets(s["todos"]))
        add("")
    add("## 8. Core Data Models")
    add("")
    add("### Graph Save Model")
    add("Produced by `Graph.get_info()` and consumed by `graphs.load_graph`. It stores position, config, scene/type key, LLM tag, subgraph/context ids, and connection/port ids. Approximate shape:")
    add(fence_json('''{
  "pos": {"x": 120, "y": 240},
  "inputs": [{"id": 12, "from": 34, "from_port": 0, "to_port": 1}],
  "outputs": [{"id": 34, "to": 56, "from_port": 0, "to_port": 0}],
  "config": {"name": "model", "neurons": 32},
  "created_with": "layer",
  "llm_tag": "dense_1",
  "subgraph_id": 10,
  "context_id": 42
}'''))
    add("")
    add("### Backend Syntax Tree")
    add("Produced by `graphs.get_syntax_tree(input)` and sent by train/infer/export flows. It contains graph pages, expected outputs, train flag, and abstract node entries from each node's `useful_properties()`.")
    add(fence_json('''{
  "pages": [
    {
      "nodes": {
        "17": {"type": "Conv2D", "props": {"kernel": 3}, "emit": {}}
      },
      "outputs": []
    }
  ],
  "expect": {},
  "train": 1
}'''))
    add("")
    add("### Dataset Object")
    add("Default local dataset shape from `glob.default_dataset`:")
    add(fence_json('''{
  "arr": [[{"type": "text", "text": "Hello"}, {"type": "num", "num": 0}]],
  "col_names": ["Input:text", "Output:num"],
  "outputs_from": 1,
  "col_args": [],
  "cache": {}
}'''))
    add("")
    add("### Dataset Preview")
    add("Produced by `DsObjRLE.get_preview` and propagated to DatasetName, TrainBegin, OutputMap, and Input1D.")
    add(fence_json('''{
  "name": "dataset name",
  "size": 1234,
  "inputs": [{"name": "Input", "type": "num"}],
  "outputs": [{"name": "Output", "type": "class", "classes": ["a", "b"]}],
  "input_hints": [],
  "no_outputs": false,
  "bad_img": false
}'''))
    add("")
    add("### Training Payload")
    add("Built in `run_manager.gd:start_train` and compressed with ZSTD before sending to `ws/train`.")
    add(fence_json('''{
  "session": "neriqward",
  "graph": {"pages": [], "expect": {}, "train": 1},
  "train_graph": {"pages": [], "expect": {}, "train": 1},
  "scene_id": "<project_id>",
  "context": "<context_id>",
  "epochs": 10,
  "dataset": "dataset name",
  "test_dataset": "",
  "batch_size": 0,
  "local": true
}'''))
    add("")
    add("### Local Dataset Block Upload")
    add("`ws_ds_frames` sends a compressed header/hash payload, waits for backend `need` JSON, then streams binary frames: first two bytes metadata length, metadata JSON, then compressed block bytes. The final marker is `__end__`. Exact server-side schema is uncertain.")
    add("")
    add("## 9. Signal Map")
    add("")
    add("| Signal | Declared in | Main emit/connect points | Purpose |")
    add("|---|---|---|---|")
    add("| `graphs.spline_connected(from_conn,to_conn)` | `graph_manager.gd` | emitted by `Graph.just_connected`; listened by TrainBegin, NetName, undo hooks | graph edge created |")
    add("| `graphs.spline_disconnected(from_conn,to_conn)` | `graph_manager.gd` | emitted by `Graph.just_disconnected` | graph edge removed |")
    add("| `graphs.model_updated(who)` | `graph_manager.gd` | input/classifier/model scripts | refresh model-dependent nodes |")
    add("| `graphs.node_added(who)` | `graph_manager.gd` | `graphs.get_graph` for new nodes; learner listens | add-node/lesson invariant tracking |")
    add("| `BlockComponent.released` | `block_component.gd` | many `_on_*_released` scene handlers | button activation |")
    add("| `BlockComponent.child_button_release(button)` | `block_component.gd` | add menu, lists, option menus | menu selection |")
    add("| `VirtualTable.dirtified` | `virtualt.gd` | `dataset_tab._on_code_edit_dirtified` | dataset changed |")
    add("| `VirtualTable.preview_refreshed` | `virtualt.gd` | `dataset_tab._on_code_edit_preview_refreshed` | dataset preview changed |")
    add("| `SocketConnection.packet` | `socket_connection.gd` | train/infer/chat callbacks | backend packet arrived |")
    add("| `RequestHandle.completed` | `web.gd` | project/auth/settings/export callers | HTTP complete |")
    add("")
    add("Declared script signal inventory:")
    for path, sig in declared_signals:
        add(f"- `{path}` L{sig[0]}: `{sig[1]}`")
    add("")
    add("Editor scene connections:")
    for path, conn in scene_connections:
        add(f"- `{path}`: `{conn}`")
    add("")
    add("## 10. Full Workflow Traces")
    add("")
    add("### App Startup")
    add("1. Godot reads `project.godot` and creates autoloads in order.")
    add("2. Godot instantiates `scenes/project.tscn`.")
    add("3. `project.gd._enter_tree` sets `glob.base_node`.")
    add("4. `top_panel.gd` registers foreground UI in `glob.fg`.")
    add("5. `gview.gd` registers `graphs.storage`.")
    add("6. `project.gd._ready` validates graph type importance ordering.")
    add("7. UI can now open project/dataset/AI/graph workflows.")
    add("")
    add("```mermaid")
    add("sequenceDiagram")
    add("  participant Godot")
    add("  participant Auto as Autoloads")
    add("  participant Project as project.gd")
    add("  participant FG as top_panel.gd")
    add("  participant Graphs as graph_manager.gd")
    add("  Godot->>Auto: initialize singletons")
    add("  Godot->>Project: instantiate project.tscn")
    add("  Project->>Auto: glob.base_node = self")
    add("  FG->>Auto: glob.fg = self")
    add("  Graphs->>Graphs: storage registered by GraphStorage")
    add("  Project->>Graphs: validate graph_types vs importance_chain")
    add("```")
    add("")
    add("### Opening / Loading a Project")
    add("Top panel opens works/project list or startup calls `glob.open_last_project`. `glob.request_projects` POSTs `project_list`. User selection calls `glob.load_scene`, which POSTs `project`, decodes serialized scene bytes, calls `graphs.load_graph`, restores graph nodes/connections/config/camera/env/chat/context, and updates project id/name/last id.")
    add("")
    add("### Adding a Node")
    add("User selects add-menu item -> `BlockComponent.child_button_release` -> `cmenu._menu_handle_release` -> `graphs.get_graph(button.hint, Graph.Flags.NEW)` -> scene instance added under GraphStorage -> `Graph._ready` registers ports/config -> `graphs.node_added.emit(new)` -> optional lesson invariant observer.")
    add("")
    add("### Connecting Nodes")
    add("User drags a `Connection` -> `Connection.start_spline`/hover state -> `graphs._process` chooses compatible candidate -> `Connection.connect_to(target)` -> parent `Graph.connecting`/`just_connected` hooks -> dictionaries and spline attached -> `graphs.spline_connected` emitted -> TrainBegin/NetName/undo/model listeners react.")
    add("")
    add("### Editing Node Parameters")
    add("User edits a ValidInput/slider/menu -> scene `_on_*` handler -> `Graph.update_config` or `update_config_subfield` -> subclass `_config_field` updates UI/shape/state -> `check_valid` -> optional `graphs.model_updated` -> saved project and syntax tree use new config.")
    add("")
    add("### Dataset Selection")
    add("DatasetName Run/select button -> `dataset_node._on_run_released` -> `ui.splash_and_get_result('select_dataset')` -> selected dataset name stored in config -> `glob.load_dataset`/`DsObjRLE.get_preview` -> metadata propagated to TrainBegin -> OutputMap/Input1D update expected outputs/features.")
    add("")
    add("### Training")
    add("Train button -> `TrainBegin._on_train_released` -> `TrainBegin.train_start` -> `TrainInput.train_start` -> `nn.start_train` -> validation -> login -> resolve TrainBegin and RunModel execution input -> `nn.request_save` -> `graphs.get_syntax_tree` for execution and training graphs -> open `ws/train` -> send compressed payload -> optional local dataset block transfer -> progress packets -> `nn.train_state_received` -> `TrainBegin.additional_call` and `TrainInput.push_acceptance` -> stop/completion UI.")
    add("")
    add("```mermaid")
    add("sequenceDiagram")
    add("  participant User")
    add("  participant TB as TrainBegin")
    add("  participant TI as TrainInput")
    add("  participant NN as run_manager")
    add("  participant Graphs as graph_manager")
    add("  participant WS as ws/train")
    add("  User->>TB: click Train")
    add("  TB->>TI: train_start()")
    add("  TB->>NN: start_train(TI, additional_call, button)")
    add("  NN->>NN: check_valid train/execution graphs")
    add("  NN->>Graphs: get_syntax_tree(execution input)")
    add("  NN->>Graphs: get_syntax_tree(TrainBegin)")
    add("  NN->>WS: compressed train init payload")
    add("  NN->>WS: local dataset frames if needed")
    add("  WS->>NN: progress/result packets")
    add("  NN->>TB: additional_call(dict)")
    add("  NN->>TI: push_acceptance(acc,time)")
    add("```")
    add("")
    add("### Inference")
    add("Input node Run button -> `nn.open_infer_channel` -> login/save/validation -> send init payload to `ws/infer` -> input changes call `nn.send_inference_data` -> backend returns `ack`/`result` -> `_infer_state_received` maps result into classifier/output nodes.")
    add("")
    add("### Saving / Exporting")
    add("Save -> `glob.save` -> `save_datasets` -> `nn.request_save` -> serialize `get_project_data` -> local cache write -> POST `save`. Export -> `top_panel._on_export_released` -> `model_export` -> selected input graph -> `graphs.get_syntax_tree` -> backend export request. Exact export endpoint schema is uncertain.")
    add("")
    add("### Deleting Nodes / Connections")
    add("Node context/delete -> `Graph.delete_call`/`delete` -> disconnect ports -> lifecycle hooks -> unregister/free. Connection detach menu -> `Connection.disconnect_from`/`end_spline` -> `Graph.just_disconnected` -> `graphs.spline_disconnected`.")
    add("")
    add("### AI-Assisted Graph Editing")
    add("Top AI button -> `AIHelpMenu` -> `glob.update_message_stream` opens `ws/talk` -> text chunks render -> `parser.parse_stream_tags` accumulates graph actions -> socket close calls `parser.model_changes_apply` -> graph nodes created/deleted/configured/connected/layouted inside undo batch.")
    add("")
    add("## 11. Training Pipeline Deep Dive")
    add("")
    add("Training uses two graph roots: an execution/model input resolved from `RunModel.name_graph`, and a training root found by `_reach_input(train_input, 'TrainBegin')`. Required reachable nodes include RunModel, OutputMap, ModelName, DatasetName, and valid execution input; inference also requires ClassifierNode. Every reachable graph's `is_valid()` must pass.")
    add("")
    add("Local dataset upload is demand-driven and block-hash based. The frontend sends dataset header and block hashes, receives backend need lists, sends requested compressed blocks as framed binary, and terminates with `__end__`. Malformed phase packets or missing `data.data.val_acc` can lead to partial UI updates because packet parsing is defensive but not strongly typed.")
    add("")
    add("## 12. Frontend-Backend Communication")
    add("")
    add("Base roots: `glob.get_root_ws` chooses localhost `ws://127.0.0.1:8000/`, remote `wss://neriqward.360hub.ru/api/`, or LAN `ws://{base_lan_ip}:8000/`; `glob.get_root_http` mirrors this for HTTP/HTTPS.")
    add("")
    add("Observed HTTP endpoints: `login`, `project_list`, `project`, `save`, `datasets`, `delete_ctx`, plus export/update/settings/lesson endpoints in their scripts. Observed WebSocket routes: `ws/train`, `ws/infer`, `ws/talk`, and referenced/uncertain `ws/ds_load`.")
    add("")
    add("Error handling is mostly caller-driven: HTTP completion payload checks, `ui.error`, WebSocket `kill` cleanup, and user retry. There is little explicit retry/backoff. Auth appears to mix cookie headers and user/pass fields; this should be clarified with backend ownership.")
    add("")
    add("## 13. State Management")
    add("")
    add("- Local scene state: visible controls, graph `cfg`, labels, active splines, table cells, scroll offsets.")
    add("- Global runtime state: `glob`, `graphs`, `nn`, `ui`, `sockets`, `luas`.")
    add("- Persisted state: project graph/env/camera/chat/context data, local datasets, local project cache, cookies/memory credentials.")
    add("- Derived state: syntax trees, dataset previews, RLE block cache, input feature controls, validation visuals.")
    add("")
    add("Race/stale risks: async dataset compression vs edits; syntax tree generation before node `request_save`; socket lifecycle during node deletion; AI parser graph mutations concurrent with user edits; global backend root/auth changes mid-session.")
    add("")
    add("## 14. Dependency Graphs")
    add("")
    add("```mermaid")
    add("flowchart LR")
    add("  glob --> cookies")
    add("  glob --> web")
    add("  glob --> sockets")
    add("  glob --> graphs")
    add("  graphs --> Graph")
    add("  nn --> graphs")
    add("  nn --> glob")
    add("  nn --> sockets")
    add("  nn --> cookies")
    add("  parser --> graphs")
    add("  learner --> graphs")
    add("  ui --> glob")
    add("```")
    add("")
    add("## 15. Diagrams")
    add("")
    add("### Data Flow")
    add("```mermaid")
    add("flowchart TD")
    add("  User[\"User edits graph/dataset\"] --> GraphCfg[\"Graph cfg/topology\"]")
    add("  User --> DatasetObj[\"Dataset object\"]")
    add("  DatasetObj --> Preview[\"DsObjRLE.get_preview\"]")
    add("  Preview --> DatasetName")
    add("  DatasetName --> TrainBegin")
    add("  TrainBegin --> OutputMap")
    add("  TrainBegin --> Input1D")
    add("  GraphCfg --> Syntax[\"graphs.get_syntax_tree\"]")
    add("  DatasetObj --> RLE[\"RLE cache\"]")
    add("  Syntax --> NN")
    add("  RLE --> NN")
    add("  NN --> Backend")
    add("  Backend --> UIUpdates[\"progress/results\"]")
    add("```")
    add("")
    add("### Signal Flow")
    add("```mermaid")
    add("flowchart TD")
    add("  Button[\"BlockComponent.released\"] --> Handler[\"_on_* handler\"]")
    add("  Handler --> Config[\"Graph.update_config/workflow\"]")
    add("  Conn[\"Connection.connect_to\"] --> GraphLC[\"Graph.just_connected\"]")
    add("  GraphLC --> Sig[\"graphs.spline_connected\"]")
    add("  Sig --> Listeners[\"TrainBegin/NetName/undo\"]")
    add("  Table[\"VirtualTable.dirtified\"] --> DSTab[\"dataset_tab\"]")
    add("  DSTab --> GlobDS[\"glob dataset cache/signals\"]")
    add("  Packet[\"SocketConnection.packet\"] --> Runtime[\"train/infer/chat handlers\"]")
    add("```")
    add("")
    add("## 16. CTO Onboarding Guide")
    add("")
    add("Run in Godot 4.6 or the team-pinned Godot 4.x build. Open `C:\\godotprojs\\nnets\\teachneurons`, run `scenes/project.tscn`, and start the backend for login/project/training/inference/export/AI. Check `glob.get_root_http` and `glob.get_root_ws` when switching localhost/LAN/remote.")
    add("")
    add("Recommended reading order: `project.godot`; `scenes/project.tscn`; `project.gd`; `top_panel.gd`; `ui_manager.gd`; `glob.gd`; `graph_manager.gd`; `base_graph.gd`; `connection.gd`; `run_manager.gd`; graph node scripts; dataset scripts; AI/lesson scripts.")
    add("")
    add("To add a visual node: create scene/script extending `Graph`, define ports/config/server typename, register in `graphs.graph_types`, add key to `project.gd.importance_chain`, add add-menu/localization entry, implement `_useful_properties`, `_config_field`, `_is_valid`, shape propagation, and optional LLM mapping.")
    add("")
    add("To add a trainable layer: follow node steps, add datatype compatibility and shape propagation, expose backend layer props, update backend schema, and add validation for dimensions/parameters.")
    add("")
    add("To add a dialog/workflow: use `BlockComponent` signals and `SplashMenu` result patterns, keep domain mutations inside `glob` or the appropriate service, and trace editor `[connection]` entries after renames.")
    add("")
    add("## 17. Debugging Guide")
    add("")
    add("- Graph missing after load: check `created_with`, `graphs.graph_types`, and `importance_chain`.")
    add("- Connections not restored: check dynamic port creation before `graphs.load_graph` reconnects edge ids.")
    add("- Train button fails: check `TrainBegin.get_training_head`, `nn.check_valid`, login, dataset meta, and `ws/train` connection.")
    add("- Dataset upload stalls: check `glob.rle_cache`, `join_ds_processing`, backend need packet, and `ws_ds_frames` framing.")
    add("- Inference result missing: check reachable ClassifierNode and `_infer_state_received` result mapping.")
    add("- AI graph edit wrong: check LLM tags, parser action JSON, and `model_changes_apply` matching.")
    add("- UI button not firing: inspect scene `[connection]`, blocked/frozen `BlockComponent`, and `_on_*` handler name.")
    add("")
    add("## 18. Refactor Risks and Recommendations")
    add("")
    add("Refactor risks: `glob.gd`, `base_graph.gd`, `graph_manager.gd`, `block_component.gd`, `virtualt.gd`, `ds_obj_serialize.gd`, `run_manager.gd`, and `lua_process.gd` are high-risk due to size, global state, and workflow breadth.")
    add("")
    add("Recommended roadmap: document backend protocols; extract project/dataset services from `glob`; centralize graph node definitions; add syntax-tree snapshot tests; add dataset compression round-trip tests; add explicit WebSocket state enums/logging; define a typed graph-node interface for config/validation/serialization/AI mapping.")
    add("")
    add("## 19. Glossary")
    add("")
    add("- Graph: visual node object extending `scripts/base_graph.gd`.")
    add("- Connection: graph input/output port.")
    add("- Spline: visual edge between ports.")
    add("- Graph type key: frontend key such as `layer`, `train_begin`, or `run_model`.")
    add("- Server typename: backend node type such as `TrainBegin`, `InputNode`, or `ClassifierNode`.")
    add("- Syntax tree: backend payload from `graphs.get_syntax_tree`.")
    add("- Dataset object: editable local table data with `arr`, `col_names`, `outputs_from`, `col_args`, and `cache`.")
    add("- RLE/block cache: compressed dataset representation for local training upload.")
    add("- Context id: graph/model execution context sent to backend.")
    add("- LLM tag: stable node label used by AI graph action payloads.")
    add("")
    add("## 20. Appendix: File Index")
    add("")
    add("### First-Party Scripts")
    for s in scripts:
        add(f"- `{s['path']}` — {s['lines']} lines; {s['extends'] or 'no extends'}; {s['class'] or 'no class'}")
    add("")
    add("### Scenes")
    for sc in scenes:
        add(f"- `{sc['path']}` — {sc['nodes']} nodes; root `{sc['root'] or '?'}`; scripts {', '.join(sc['scripts']) if sc['scripts'] else 'none parsed'}")
    add("")
    add("### Resources / Config")
    for path in configs + resources:
        first = read(path).splitlines()[0] if read(path).splitlines() else ""
        add(f"- `{rel(path)}` — {path.stat().st_size} bytes; `{first[:160]}`")
    add("")
    add("### Addon / Vendor Files")
    for path in addons[:300]:
        add(f"- `{rel(path)}` — {path.stat().st_size} bytes")
    if len(addons) > 300:
        add(f"- ... {len(addons) - 300} more addon files")
    add("")
    add("### Generated Godot Files")
    add("`.godot/editor`, `.godot/imported`, and `.godot/exported` are generated/editor cache. They were inventoried but intentionally not treated as source architecture.")
    add("")
    add("## Clarifying Questions for Next Documentation Iteration")
    add("")
    add("1. What is the authoritative backend schema for `ws/train` init payloads, progress packets, stop packets, and local dataset `need` messages?")
    add("2. What exact packet/result shape does `ws/infer` return for multi-output models?")
    add("3. Which endpoints power model export in production, and what are the accepted format/quantization combinations?")
    add("4. Is `train_rl` active, planned, or intentionally hidden?")
    add("5. Are Lua/environment workflows production features, lesson-only tooling, or experimental?")
    add("6. Should generated `.godot` cache files be excluded from source control and future docs?")
    add("7. What exact Godot version should contributors use?")
    add("8. Is auth intended to be cookie-header based, user/pass payload based, or both during migration?")
    add("9. Which graph node types are deprecated or lesson-only, and which must remain supported?")

    OUT.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(OUT)
    print(f"scripts={len(scripts)} scenes={len(scenes)} signals={len(declared_signals)} scene_connections={len(scene_connections)} markdown_lines={len(md)}")


if __name__ == "__main__":
    main()
