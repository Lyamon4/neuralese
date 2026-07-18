# Player-Facing Block Coding for Godot

Script-only, maintainable Scratch-like block coding layer for Godot 4.x.

## What is included

- `core/block_definition.gd` — block metadata and language templates.
- `core/block_instance.gd` — player-created block instance / tree node.
- `core/block_program.gd` — serializable program container.
- `languages/block_language_emitter.gd` — base backend for any text language.
- `languages/lua_emitter.gd` — first backend: Lua.
- `library/default_block_library.gd` — starter blocks: events, movement, loops, logic, math, variables, functions.
- `ui/block_coding_panel.gd` — simple player-facing palette/workspace/export UI.
- `NODE_TREE_BLUEPRINT.md` — exact node tree to create.

## How to extend to another language

Create a new child class of `BlockLanguageEmitter`, override only what changes:

```gdscript
extends BlockLanguageEmitter
class_name PythonEmitter

func _init() -> void:
	language_id = &"python"
	indent_text = "\t"
	statement_separator = "\n"

func get_pass_statement() -> String:
	return "pass"

func literal_to_code(value: Variant) -> String:
	# Override booleans/null/strings if needed.
	return super.literal_to_code(value)
```

Then add per-block templates under `templates["python"]` in `default_block_library.gd` or your custom library.

## Why this structure

The original Godot-Block-Coding add-on uses `BlockDefinition`, serialized block trees, AST nodes, and template-based code generation. This package keeps those core ideas but moves code emission into language-specific classes so Lua, Python, C++, Rust, etc. can be added with minimal code.
