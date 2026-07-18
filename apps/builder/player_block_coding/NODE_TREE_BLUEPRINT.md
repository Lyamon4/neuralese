# Godot Player-Facing Block Coding — Node Tree Blueprint

This package is script-only. Create this scene manually and attach the scripts.

## Recommended scene: `BlockCodingPanel.tscn`

```text
BlockCodingPanel : Control
├── HSplitContainer : HSplitContainer
│   ├── PalettePanel : PanelContainer
│   │   └── PaletteScroll : ScrollContainer
│   │       └── PaletteList : VBoxContainer
│   └── WorkspacePanel : PanelContainer
│       └── WorkspaceVBox : VBoxContainer
│           ├── Toolbar : HBoxContainer
│           │   ├── LanguageLabel : Label
│           │   ├── LanguageOption : OptionButton
│           │   ├── ExportButton : Button
│           │   ├── ClearButton : Button
│           │   └── StatusLabel : Label
│           ├── WorkspaceScroll : ScrollContainer
│           │   └── BlockList : VBoxContainer
│           └── CodePreview : TextEdit
```

## Attach scripts

| Node | Script |
|---|---|
| `BlockCodingPanel` | `res://scripts/player_block_coding/ui/block_coding_panel.gd` |

The root script creates palette buttons and simple block rows at runtime. You do not need to attach scripts to children.

## Required root-node exported NodePaths

After attaching `block_coding_panel.gd`, assign these paths in the Inspector:

```text
palette_list_path = HSplitContainer/PalettePanel/PaletteScroll/PaletteList
block_list_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/WorkspaceScroll/BlockList
language_option_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/LanguageOption
export_button_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/ExportButton
clear_button_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/ClearButton
status_label_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/StatusLabel
code_preview_path = HSplitContainer/WorkspacePanel/WorkspaceVBox/CodePreview
```

## Minimal usage from another script

```gdscript
@onready var block_panel: BlockCodingPanel = $BlockCodingPanel

func _ready() -> void:
	block_panel.code_exported.connect(_on_code_exported)

func _on_code_exported(language: StringName, code: String) -> void:
	print("Generated ", language, ":\n", code)
```

## Design intent

This implementation is based on the Godot-Block-Coding repository architecture:

1. Blocks are data definitions.
2. Player-created blocks become a serializable block tree.
3. The tree is converted to text through code templates.
4. Language differences live in a small emitter child class.

The key difference: this package is player-facing and language-agnostic. The base `BlockLanguageEmitter` contains the shared block-to-code pipeline. `LuaEmitter` only defines Lua syntax differences.
