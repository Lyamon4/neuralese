extends RefCounted
class_name BlockProgram

const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")

var roots: Array[BlockInstance] = []
var variables: Dictionary = {}
var metadata: Dictionary = {}

func clear() -> void:
	roots.clear()
	variables.clear()
	metadata.clear()

func add_root(block: BlockInstance) -> void:
	if block == null:
		return
	roots.append(block)

func to_dictionary() -> Dictionary:
	var root_data: Array = []
	for root in roots:
		root_data.append(root.to_dictionary())
	return {
		"version": 1,
		"variables": variables.duplicate(true),
		"metadata": metadata.duplicate(true),
		"roots": root_data,
	}

static func from_dictionary(data: Dictionary, catalog: Dictionary) -> BlockProgram:
	var result: BlockProgram = BlockProgram.new()
	result.variables = data.get("variables", {}).duplicate(true)
	result.metadata = data.get("metadata", {}).duplicate(true)
	for root_data in data.get("roots", []):
		result.roots.append(BlockInstance.from_dictionary(root_data, catalog))
	return result
