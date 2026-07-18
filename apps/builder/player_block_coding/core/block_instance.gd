extends RefCounted
class_name BlockInstance

const BlockDefinitionClass = preload("res://player_block_coding/core/block_definition.gd")

var uid: StringName = &""
var definition: BlockDefinition
var arguments: Dictionary = {}
var children: Array[BlockInstance] = []
var else_children: Array[BlockInstance] = []

func _init(p_definition: BlockDefinition = null) -> void:
	definition = p_definition
	uid = StringName("block_%d" % Time.get_ticks_usec())
	if definition != null:
		arguments = definition.defaults.duplicate(true)

func add_child_block(block: BlockInstance) -> void:
	if block == null:
		return
	children.append(block)

func add_else_child_block(block: BlockInstance) -> void:
	if block == null:
		return
	else_children.append(block)

func set_argument(name: StringName, value: Variant) -> void:
	arguments[name] = value

func get_argument(name: StringName, fallback: Variant = null) -> Variant:
	if arguments.has(name):
		return arguments[name]
	return fallback

func to_dictionary() -> Dictionary:
	var child_data: Array = []
	for child in children:
		child_data.append(child.to_dictionary())

	var else_data: Array = []
	for child in else_children:
		else_data.append(child.to_dictionary())

	return {
		"uid": String(uid),
		"definition_id": String(definition.id) if definition != null else "",
		"arguments": arguments.duplicate(true),
		"children": child_data,
		"else_children": else_data,
	}

static func from_dictionary(data: Dictionary, catalog: Dictionary) -> BlockInstance:
	var definition_id: StringName = StringName(str(data.get("definition_id", "")))
	var definition: BlockDefinition = null
	if catalog.has(definition_id):
		definition = catalog[definition_id]

	var result: BlockInstance = BlockInstance.new(definition)
	result.uid = StringName(str(data.get("uid", result.uid)))
	result.arguments = data.get("arguments", {}).duplicate(true)

	for child_data in data.get("children", []):
		result.children.append(BlockInstance.from_dictionary(child_data, catalog))

	for child_data in data.get("else_children", []):
		result.else_children.append(BlockInstance.from_dictionary(child_data, catalog))

	return result
