extends BlockLanguageEmitter
class_name LuaEmitter

## Lua backend for the player-facing block coding engine.
## This file intentionally keeps most syntax in block templates, and only handles
## Lua-specific escaping, table literals, and a few constructs that need structure.

const LUA_KEYWORDS: Dictionary = {
	"and": true,
	"break": true,
	"do": true,
	"else": true,
	"elseif": true,
	"end": true,
	"false": true,
	"for": true,
	"function": true,
	"goto": true,
	"if": true,
	"in": true,
	"local": true,
	"nil": true,
	"not": true,
	"or": true,
	"repeat": true,
	"return": true,
	"then": true,
	"true": true,
	"until": true,
	"while": true,
}

func _init() -> void:
	language_id = &"lua"
	indent_text = "\t"
	statement_separator = "\n"

func emit_statement(block: BlockInstance, depth: int) -> String:
	if block == null or block.definition == null:
		return ""

	match String(block.definition.id):
		"if_elseif_else":
			return _emit_if_elseif_else(block, depth)
		_:
			return super.emit_statement(block, depth)

func emit_value(block: BlockInstance) -> String:
	if block == null or block.definition == null:
		return "nil"

	match String(block.definition.id):
		"table_constructor":
			return _emit_table_constructor(block)
		"function_expression":
			return _emit_function_expression(block)
		_:
			return super.emit_value(block)

func literal_to_code(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "nil"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_STRING, TYPE_STRING_NAME:
			return quote_string(str(value))
		TYPE_ARRAY:
			return _array_to_lua_table(value)
		TYPE_DICTIONARY:
			return _dictionary_to_lua_table(value)
		TYPE_VECTOR2:
			return "{ x = %s, y = %s }" % [_number_to_lua(value.x), _number_to_lua(value.y)]
		TYPE_VECTOR3:
			return "{ x = %s, y = %s, z = %s }" % [_number_to_lua(value.x), _number_to_lua(value.y), _number_to_lua(value.z)]
		_:
			return str(value)

func raw_argument_to_text(value: Variant) -> String:
	if value is BlockInstance:
		return emit_value(value)
	if typeof(value) == TYPE_ARRAY:
		var parts: Array[String] = []
		for item in value:
			parts.append(argument_to_code(item))
		return ", ".join(parts)
	return str(value)

func quote_string(value: String) -> String:
	var result: String = value
	result = result.replace("\\", "\\\\")
	result = result.replace("\"", "\\\"")
	result = result.replace("\n", "\\n")
	result = result.replace("\r", "\\r")
	result = result.replace("\t", "\\t")
	return "\"%s\"" % result

func get_pass_statement() -> String:
	return "-- pass"

func get_null_literal() -> String:
	return "nil"

func get_bool_literal(value: bool) -> String:
	return "true" if value else "false"

func get_missing_template_statement(block_id: StringName) -> String:
	return "-- Missing Lua template for %s" % String(block_id)

func get_missing_template_value(block_id: StringName) -> String:
	return "nil --[[ missing:%s ]]" % String(block_id)

func _emit_if_elseif_else(block: BlockInstance, depth: int) -> String:
	var lines: Array[String] = []
	var condition: Variant = block.get_argument(&"condition", true)
	lines.append("%sif %s then" % [indent(depth), argument_to_code(condition)])
	lines.append(_safe_body(block.children, depth + 1))

	var branches: Variant = block.get_argument(&"elseif_branches", [])
	if typeof(branches) == TYPE_ARRAY:
		for branch in branches:
			if typeof(branch) != TYPE_DICTIONARY:
				continue
			var branch_condition: Variant = branch.get("condition", true)
			var branch_children: Array = branch.get("children", [])
			lines.append("%selseif %s then" % [indent(depth), argument_to_code(branch_condition)])
			lines.append(_safe_body(branch_children, depth + 1))

	if not block.else_children.is_empty():
		lines.append("%selse" % indent(depth))
		lines.append(_safe_body(block.else_children, depth + 1))

	lines.append("%send" % indent(depth))
	return "\n".join(lines)

func _emit_table_constructor(block: BlockInstance) -> String:
	var parts: Array[String] = []

	var items: Variant = block.get_argument(&"items", [])
	if typeof(items) == TYPE_ARRAY:
		for item in items:
			parts.append(argument_to_code(item))
	elif str(items).strip_edges() != "":
		parts.append(str(items))

	var fields: Variant = block.get_argument(&"fields", {})
	if typeof(fields) == TYPE_DICTIONARY:
		for key in fields.keys():
			parts.append("%s = %s" % [_lua_table_key_to_code(key), argument_to_code(fields[key])])
	elif str(fields).strip_edges() != "":
		parts.append(str(fields))

	return "{ %s }" % ", ".join(parts)

func _emit_function_expression(block: BlockInstance) -> String:
	var params: String = raw_argument_to_text(block.get_argument(&"params", ""))
	var body: String = _safe_body(block.children, 1)
	return "function(%s)\n%s\nend" % [params, body]

func _safe_body(children: Array, depth: int) -> String:
	var typed_children: Array[BlockInstance] = []
	for child in children:
		if child is BlockInstance:
			typed_children.append(child)
	var body: String = emit_children(typed_children, depth)
	if body.strip_edges() == "":
		return indent(depth) + get_pass_statement()
	return body

func _array_to_lua_table(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(argument_to_code(value))
	return "{ %s }" % ", ".join(parts)

func _dictionary_to_lua_table(values: Dictionary) -> String:
	var parts: Array[String] = []
	for key in values.keys():
		parts.append("%s = %s" % [_lua_table_key_to_code(key), argument_to_code(values[key])])
	return "{ %s }" % ", ".join(parts)

func _lua_table_key_to_code(key: Variant) -> String:
	var text: String = str(key)
	if _is_valid_lua_identifier(text):
		return text
	return "[%s]" % literal_to_code(key)

func _is_valid_lua_identifier(text: String) -> bool:
	if text.is_empty():
		return false
	if LUA_KEYWORDS.has(text):
		return false
	if not _is_identifier_first_code(text.unicode_at(0)):
		return false
	for i in range(1, text.length()):
		if not _is_identifier_code(text.unicode_at(i)):
			return false
	return true

func _is_identifier_first_code(code: int) -> bool:
	return code == 95 or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

func _is_identifier_code(code: int) -> bool:
	return _is_identifier_first_code(code) or (code >= 48 and code <= 57)

func _number_to_lua(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT and is_nan(value):
		return "0/0"
	if typeof(value) == TYPE_FLOAT and is_inf(value):
		return "math.huge" if value > 0.0 else "-math.huge"
	return str(value)
