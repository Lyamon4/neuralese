extends Node

const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const DefaultBlockLibraryClass = preload("res://player_block_coding/library/default_block_library.gd")
const LuaEmitterClass = preload("res://player_block_coding/languages/lua_emitter.gd")

func _ready() -> void:
	var catalog: Dictionary = DefaultBlockLibrary.build_catalog()
	var program: BlockProgram = BlockProgram.new()

	var start: BlockInstance = DefaultBlockLibrary.create_instance(&"event_start", catalog)
	var set_score: BlockInstance = DefaultBlockLibrary.create_instance(&"set_var", catalog)
	set_score.set_argument(&"name", "score")
	set_score.set_argument(&"value", 0)

	var print_block: BlockInstance = DefaultBlockLibrary.create_instance(&"print", catalog)
	print_block.set_argument(&"value", "Game started")

	start.add_child_block(set_score)
	start.add_child_block(print_block)
	program.add_root(start)

	var lua: LuaEmitter = LuaEmitter.new()
	print(lua.emit_program(program))
