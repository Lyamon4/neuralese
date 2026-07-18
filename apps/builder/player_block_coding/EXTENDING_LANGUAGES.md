# Adding Python / C++ / Rust / Other Languages

The language layer is intentionally thin.

## 1. Create an emitter

```gdscript
extends BlockLanguageEmitter
class_name PythonEmitter

func _init() -> void:
	language_id = &"python"
	indent_text = "\t"
	statement_separator = "\n"

func get_pass_statement() -> String:
	return "pass"

func get_null_literal() -> String:
	return "None"

func get_bool_literal(value: bool) -> String:
	return "True" if value else "False"
```

## 2. Add templates to blocks

Every `BlockDefinition` has `templates`, for example:

```gdscript
{
	&"lua": "if {condition} then\n{body}\nend",
	&"python": "if {condition}:\n{body}",
	&"cpp": "if ({condition}) {\n{body}\n}",
}
```

## 3. Register the emitter

```gdscript
block_panel.register_emitter(PythonEmitter.new())
```

## Rule of thumb

Do not subclass blocks for every language. Keep blocks semantic and put syntax in templates/emitter classes. This is the maintainable part.
