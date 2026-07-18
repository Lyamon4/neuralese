extends Resource
class_name BlockDefinition

## Language-agnostic block definition.
## Inspired by Godot-Block-Coding's BlockDefinition resource, but designed for
## player-facing generation to any text language.

enum BlockKind {
	ENTRY,
	STATEMENT,
	VALUE,
	CONTROL
}

@export var id: StringName = &""
@export var label: String = ""
@export var category: String = "General"
@export var kind: BlockKind = BlockKind.STATEMENT
@export var output_type: StringName = &"any"
@export var input_schema: Array[Dictionary] = []
@export var defaults: Dictionary = {}
@export var templates: Dictionary = {}
@export var color: Color = Color(0.25, 0.25, 0.25)
@export_multiline var description: String = ""

func _init(
	p_id: StringName = &"",
	p_label: String = "",
	p_category: String = "General",
	p_kind: BlockKind = BlockKind.STATEMENT,
	p_output_type: StringName = &"any",
	p_input_schema: Array[Dictionary] = [],
	p_defaults: Dictionary = {},
	p_templates: Dictionary = {},
	p_description: String = ""
) -> void:
	id = p_id
	label = p_label
	category = p_category
	kind = p_kind
	output_type = p_output_type
	input_schema = p_input_schema
	defaults = p_defaults
	templates = p_templates
	description = p_description

func get_template(language_id: StringName) -> String:
	if templates.has(language_id):
		return str(templates[language_id])
	if templates.has(&"generic"):
		return str(templates[&"generic"])
	if templates.has("generic"):
		return str(templates["generic"])
	return ""

func duplicate_definition() -> BlockDefinition:
	var result: BlockDefinition = BlockDefinition.new()
	result.id = id
	result.label = label
	result.category = category
	result.kind = kind
	result.output_type = output_type
	result.input_schema = input_schema.duplicate(true)
	result.defaults = defaults.duplicate(true)
	result.templates = templates.duplicate(true)
	result.color = color
	result.description = description
	return result
