extends Node

## Attach this to an empty Node and run the scene.
## It creates a real nested Lua program entirely from blocks and prints the result.

const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const LuaBlockLibraryClass = preload("res://player_block_coding/library/lua_block_library.gd")
const LuaEmitterClass = preload("res://player_block_coding/languages/lua_emitter.gd")

func _ready() -> void:
	var catalog: Dictionary = LuaBlockLibrary.build_catalog()
	var program: BlockProgram = BlockProgram.new()

	var start: BlockInstance = LuaBlockLibrary.create_instance(&"event_start", catalog)
	start.add_child_block(_local(catalog, "player", _table(catalog, [], {
		"x": 0,
		"y": 0,
		"name": "Neri",
		"hp": 100,
	})))
	start.add_child_block(_print(catalog, "Lua blocks ready"))
	program.add_root(start)

	var update: BlockInstance = LuaBlockLibrary.create_instance(&"event_update", catalog)
	update.set_argument(&"delta", "dt")

	var move_x: BlockInstance = LuaBlockLibrary.create_instance(&"table_field_set", catalog)
	move_x.set_argument(&"table", "player")
	move_x.set_argument(&"field", "x")
	move_x.set_argument(&"value", _binary(catalog, _field(catalog, "player", "x"), "+", _binary(catalog, 60, "*", _var(catalog, "dt"))))
	update.add_child_block(move_x)

	var branch: BlockInstance = LuaBlockLibrary.create_instance(&"if_elseif_else", catalog)
	branch.set_argument(&"condition", _compare(catalog, _field(catalog, "player", "x"), ">", 500))
	branch.add_child_block(_print_many(catalog, "\"reached edge\", player.x"))

	var low_hp_print: BlockInstance = _print(catalog, "low hp")
	branch.set_argument(&"elseif_branches", [
		{
			"condition": _compare(catalog, _field(catalog, "player", "hp"), "<", 30),
			"children": [low_hp_print],
		},
	])
	branch.add_else_child_block(_print_many(catalog, "\"x\", player.x"))
	update.add_child_block(branch)

	program.add_root(update)

	var lua: LuaEmitter = LuaEmitter.new()
	print("\n--- GENERATED LUA ---")
	print(lua.emit_program(program))

func _local(catalog: Dictionary, name: String, value: Variant) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"local_assign", catalog)
	block.set_argument(&"name", name)
	block.set_argument(&"value", value)
	return block

func _print(catalog: Dictionary, value: Variant) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"print", catalog)
	block.set_argument(&"value", value)
	return block

func _print_many(catalog: Dictionary, values: String) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"print_many", catalog)
	block.set_argument(&"values", values)
	return block

func _var(catalog: Dictionary, name: String) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"var", catalog)
	block.set_argument(&"name", name)
	return block

func _field(catalog: Dictionary, table: String, field: String) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"table_field_get", catalog)
	block.set_argument(&"table", table)
	block.set_argument(&"field", field)
	return block

func _binary(catalog: Dictionary, left: Variant, op: String, right: Variant) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"binary_op", catalog)
	block.set_argument(&"left", left)
	block.set_argument(&"op", op)
	block.set_argument(&"right", right)
	return block

func _compare(catalog: Dictionary, left: Variant, op: String, right: Variant) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"compare", catalog)
	block.set_argument(&"left", left)
	block.set_argument(&"op", op)
	block.set_argument(&"right", right)
	return block

func _table(catalog: Dictionary, items: Array, fields: Dictionary) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"table_constructor", catalog)
	block.set_argument(&"items", items)
	block.set_argument(&"fields", fields)
	return block
