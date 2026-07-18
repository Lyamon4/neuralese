extends Node

## A compact reference of how to instantiate the richer Lua blocks from code.
## Use this as a unit-test style file while building the visual editor.

const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const LuaBlockLibraryClass = preload("res://player_block_coding/library/lua_block_library.gd")
const LuaEmitterClass = preload("res://player_block_coding/languages/lua_emitter.gd")

func _ready() -> void:
	var catalog: Dictionary = LuaBlockLibrary.build_catalog()
	var program: BlockProgram = BlockProgram.new()

	var require_json: BlockInstance = LuaBlockLibrary.create_instance(&"require_assign", catalog)
	require_json.set_argument(&"name", "json")
	require_json.set_argument(&"module", "json")
	program.add_root(require_json)

	var score_fn: BlockInstance = LuaBlockLibrary.create_instance(&"local_function", catalog)
	score_fn.set_argument(&"name", "score_items")
	score_fn.set_argument(&"params", "items")

	var total: BlockInstance = LuaBlockLibrary.create_instance(&"local_assign", catalog)
	total.set_argument(&"name", "total")
	total.set_argument(&"value", 0)
	score_fn.add_child_block(total)

	var loop: BlockInstance = LuaBlockLibrary.create_instance(&"generic_for", catalog)
	loop.set_argument(&"names", "_, item")
	loop.set_argument(&"iterator", "ipairs(items)")

	var add: BlockInstance = LuaBlockLibrary.create_instance(&"assign", catalog)
	add.set_argument(&"target", "total")
	add.set_argument(&"value", _raw_expr(catalog, "total + item.value"))
	loop.add_child_block(add)
	score_fn.add_child_block(loop)

	var ret: BlockInstance = LuaBlockLibrary.create_instance(&"return", catalog)
	ret.set_argument(&"values", "total")
	score_fn.add_child_block(ret)
	program.add_root(score_fn)

	var data: BlockInstance = LuaBlockLibrary.create_instance(&"local_assign", catalog)
	data.set_argument(&"name", "items")
	data.set_argument(&"value", _raw_expr(catalog, "{ { value = 10 }, { value = 25 }, { value = 5 } }"))
	program.add_root(data)

	var output: BlockInstance = LuaBlockLibrary.create_instance(&"print_many", catalog)
	output.set_argument(&"values", "\"score\", score_items(items)")
	program.add_root(output)

	var lua: LuaEmitter = LuaEmitter.new()
	print("\n--- GENERATED REAL-LUA EXAMPLE ---")
	print(lua.emit_program(program))

func _raw_expr(catalog: Dictionary, code: String) -> BlockInstance:
	var block: BlockInstance = LuaBlockLibrary.create_instance(&"raw_expression", catalog)
	block.set_argument(&"code", code)
	return block
