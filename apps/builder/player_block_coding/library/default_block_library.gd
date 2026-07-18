extends RefCounted
class_name DefaultBlockLibrary

## Compatibility shim.
## Existing UI code already imports DefaultBlockLibrary, so this file now routes
## the default catalog to the richer Lua catalog.

const LuaBlockLibraryClass = preload("res://player_block_coding/library/lua_block_library.gd")

static func build_catalog() -> Dictionary:
	return LuaBlockLibrary.build_catalog()

static func build_definitions() -> Array[BlockDefinition]:
	return LuaBlockLibrary.build_definitions()

static func create_instance(block_id: StringName, catalog: Dictionary) -> BlockInstance:
	return LuaBlockLibrary.create_instance(block_id, catalog)
