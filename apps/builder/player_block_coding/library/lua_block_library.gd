extends RefCounted
class_name LuaBlockLibrary

## A much larger Lua-first block library.
## Blocks are still language-neutral objects, but this catalog defines Lua syntax
## deeply enough to generate real scripts: variables, functions, tables, branches,
## loops, operators, standard library calls, modules, and raw escape hatches.

const BlockDefinitionClass = preload("res://player_block_coding/core/block_definition.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")

static func build_catalog() -> Dictionary:
	var catalog: Dictionary = {}
	for definition in build_definitions():
		catalog[definition.id] = definition
	return catalog

static func build_definitions() -> Array[BlockDefinition]:
	var result: Array[BlockDefinition] = []

	_add_program_blocks(result)
	_add_value_blocks(result)
	_add_variable_blocks(result)
	_add_operator_blocks(result)
	_add_control_blocks(result)
	_add_function_blocks(result)
	_add_table_blocks(result)
	_add_stdlib_blocks(result)
	_add_game_blocks(result)
	_add_raw_blocks(result)

	return result

static func create_instance(block_id: StringName, catalog: Dictionary) -> BlockInstance:
	if not catalog.has(block_id):
		push_error("Unknown Lua block id: %s" % String(block_id))
		return null
	return BlockInstance.new(catalog[block_id])

static func _add_program_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"event_start", "when program starts", "01 Program", BlockDefinition.BlockKind.ENTRY, &"none", [], {}, {
		&"lua": "function on_start()\n{body}\nend"
	}, "Defines a conventional game/sandbox start callback."))

	result.append(_def(&"event_update", "every frame delta {delta}", "01 Program", BlockDefinition.BlockKind.ENTRY, &"none", [
		_schema(&"delta", &"name")
	], {&"delta": "dt"}, {
		&"lua": "function on_update({{delta}})\n{body}\nend"
	}, "Defines a conventional game/sandbox update callback."))

	result.append(_def(&"do_block", "do block", "01 Program", BlockDefinition.BlockKind.CONTROL, &"none", [], {}, {
		&"lua": "do\n{body}\nend"
	}, "Creates a lexical scope in Lua."))

	result.append(_def(&"comment", "comment {text}", "01 Program", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"text", &"string")
	], {&"text": "TODO"}, {
		&"lua": "-- {{text}}"
	}, "Single-line Lua comment."))

static func _add_value_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"nil_value", "nil", "02 Values", BlockDefinition.BlockKind.VALUE, &"nil", [], {}, {
		&"lua": "nil"
	}))

	result.append(_def(&"number", "number {value}", "02 Values", BlockDefinition.BlockKind.VALUE, &"number", [
		_schema(&"value", &"number")
	], {&"value": 0}, {
		&"lua": "{value}"
	}))

	result.append(_def(&"string", "string {value}", "02 Values", BlockDefinition.BlockKind.VALUE, &"string", [
		_schema(&"value", &"string")
	], {&"value": "hello"}, {
		&"lua": "{value}"
	}))

	result.append(_def(&"multiline_string", "multi-line string {value}", "02 Values", BlockDefinition.BlockKind.VALUE, &"string", [
		_schema(&"value", &"string")
	], {&"value": "hello\nworld"}, {
		&"lua": "[[{{value}}]]"
	}, "Lua long-bracket string. Do not place ]] inside the text."))

	result.append(_def(&"boolean", "boolean {value}", "02 Values", BlockDefinition.BlockKind.VALUE, &"bool", [
		_schema(&"value", &"bool")
	], {&"value": true}, {
		&"lua": "{value}"
	}))

	result.append(_def(&"var", "variable {name}", "02 Values", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"name", &"name")
	], {&"name": "score"}, {
		&"lua": "{{name}}"
	}))

	result.append(_def(&"vararg", "vararg ...", "02 Values", BlockDefinition.BlockKind.VALUE, &"any", [], {}, {
		&"lua": "..."
	}))

static func _add_variable_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"local_assign", "local {name} = {value}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"name", &"name"),
		_schema(&"value", &"any")
	], {&"name": "x", &"value": 0}, {
		&"lua": "local {{name}} = {value}"
	}))

	result.append(_def(&"local_multi_assign", "local {names} = {values}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"names", &"raw"),
		_schema(&"values", &"raw")
	], {&"names": "x, y", &"values": "0, 0"}, {
		&"lua": "local {{names}} = {{values}}"
	}, "Multiple local assignment, e.g. local x, y = 1, 2."))

	result.append(_def(&"assign", "set {target} = {value}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"target", &"raw"),
		_schema(&"value", &"any")
	], {&"target": "x", &"value": 0}, {
		&"lua": "{{target}} = {value}"
	}))

	result.append(_def(&"multi_assign", "set {targets} = {values}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"targets", &"raw"),
		_schema(&"values", &"raw")
	], {&"targets": "x, y", &"values": "y, x"}, {
		&"lua": "{{targets}} = {{values}}"
	}, "Multiple assignment, useful for swap: x, y = y, x."))

	result.append(_def(&"append_assign", "append {value} to string {target}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"target", &"raw"),
		_schema(&"value", &"any")
	], {&"target": "text", &"value": "!"}, {
		&"lua": "{{target}} = {{target}} .. {value}"
	}))

	result.append(_def(&"change_var", "change {name} by {amount}", "03 Variables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"name", &"name"),
		_schema(&"amount", &"number")
	], {&"name": "score", &"amount": 1}, {
		&"lua": "{{name}} = {{name}} + {amount}"
	}))

static func _add_operator_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"binary_op", "{left} {op} {right}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"left", &"any"),
		_schema(&"op", &"option"),
		_schema(&"right", &"any")
	], {&"left": 1, &"op": "+", &"right": 1}, {
		&"lua": "({left} {{op}} {right})"
	}, "Arithmetic/concat operator. Common Lua ops: + - * / // % ^ ..."))

	result.append(_def(&"compare", "{left} {op} {right}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"bool", [
		_schema(&"left", &"any"),
		_schema(&"op", &"option"),
		_schema(&"right", &"any")
	], {&"left": 1, &"op": "==", &"right": 1}, {
		&"lua": "({left} {{op}} {right})"
	}, "Lua comparison operators: == ~= < <= > >=."))

	result.append(_def(&"logical_and", "{left} and {right}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"bool", [
		_schema(&"left", &"bool"),
		_schema(&"right", &"bool")
	], {&"left": true, &"right": true}, {
		&"lua": "({left} and {right})"
	}))

	result.append(_def(&"logical_or", "{left} or {right}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"bool", [
		_schema(&"left", &"bool"),
		_schema(&"right", &"bool")
	], {&"left": true, &"right": false}, {
		&"lua": "({left} or {right})"
	}))

	result.append(_def(&"logical_not", "not {value}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"bool", [
		_schema(&"value", &"bool")
	], {&"value": false}, {
		&"lua": "(not {value})"
	}))

	result.append(_def(&"unary_minus", "negative {value}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"number", [
		_schema(&"value", &"number")
	], {&"value": 1}, {
		&"lua": "(-{value})"
	}))

	result.append(_def(&"length_op", "length of {value}", "04 Operators", BlockDefinition.BlockKind.VALUE, &"number", [
		_schema(&"value", &"any")
	], {&"value": "hello"}, {
		&"lua": "(#{value})"
	}, "Lua length operator for strings and sequences."))

static func _add_control_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"if", "if {condition}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"condition", &"bool")
	], {&"condition": true}, {
		&"lua": "if {condition} then\n{body}\nend"
	}))

	result.append(_def(&"if_else", "if {condition} else", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"condition", &"bool")
	], {&"condition": true}, {
		&"lua": "if {condition} then\n{body}\nelse\n{else_body}\nend"
	}))

	result.append(_def(&"if_elseif_else", "if / elseif / else {condition}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"condition", &"bool"),
		_schema(&"elseif_branches", &"branch_array")
	], {&"condition": true, &"elseif_branches": []}, {}, "Structured Lua elseif support. Set argument elseif_branches to dictionaries with condition and children."))

	result.append(_def(&"while", "while {condition}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"condition", &"bool")
	], {&"condition": true}, {
		&"lua": "while {condition} do\n{body}\nend"
	}))

	result.append(_def(&"repeat_until", "repeat until {condition}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"condition", &"bool")
	], {&"condition": false}, {
		&"lua": "repeat\n{body}\nuntil {condition}"
	}))

	result.append(_def(&"numeric_for", "for {name} = {start}, {finish}, {step}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"name", &"name"),
		_schema(&"start", &"number"),
		_schema(&"finish", &"number"),
		_schema(&"step", &"number")
	], {&"name": "i", &"start": 1, &"finish": 10, &"step": 1}, {
		&"lua": "for {{name}} = {start}, {finish}, {step} do\n{body}\nend"
	}))

	result.append(_def(&"generic_for", "for {names} in {iterator}", "05 Control", BlockDefinition.BlockKind.CONTROL, &"none", [
		_schema(&"names", &"raw"),
		_schema(&"iterator", &"raw")
	], {&"names": "k, v", &"iterator": "pairs(t)"}, {
		&"lua": "for {{names}} in {{iterator}} do\n{body}\nend"
	}, "Generic Lua for loop, e.g. for k, v in pairs(t) do."))

	result.append(_def(&"break", "break", "05 Control", BlockDefinition.BlockKind.STATEMENT, &"none", [], {}, {
		&"lua": "break"
	}))

static func _add_function_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"function_decl", "function {name}({params})", "06 Functions", BlockDefinition.BlockKind.ENTRY, &"none", [
		_schema(&"name", &"raw"),
		_schema(&"params", &"raw")
	], {&"name": "main", &"params": ""}, {
		&"lua": "function {{name}}({{params}})\n{body}\nend"
	}, "Global or table function: function name(a, b), function tbl.name(x)."))

	result.append(_def(&"local_function", "local function {name}({params})", "06 Functions", BlockDefinition.BlockKind.ENTRY, &"none", [
		_schema(&"name", &"name"),
		_schema(&"params", &"raw")
	], {&"name": "helper", &"params": ""}, {
		&"lua": "local function {{name}}({{params}})\n{body}\nend"
	}))

	result.append(_def(&"method_function", "function {table}:{method}({params})", "06 Functions", BlockDefinition.BlockKind.ENTRY, &"none", [
		_schema(&"table", &"raw"),
		_schema(&"method", &"name"),
		_schema(&"params", &"raw")
	], {&"table": "Player", &"method": "move", &"params": "dx, dy"}, {
		&"lua": "function {{table}}:{{method}}({{params}})\n{body}\nend"
	}, "Lua colon method declaration. self is implicit."))

	result.append(_def(&"function_expression", "function expression ({params})", "06 Functions", BlockDefinition.BlockKind.VALUE, &"function", [
		_schema(&"params", &"raw")
	], {&"params": ""}, {}, "Anonymous function value. Children become the body."))

	result.append(_def(&"return", "return {values}", "06 Functions", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"values", &"raw")
	], {&"values": ""}, {
		&"lua": "return {{values}}"
	}))

	result.append(_def(&"call_stmt", "call {name}({args})", "06 Functions", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"name", &"raw"),
		_schema(&"args", &"raw")
	], {&"name": "print", &"args": "\"hello\""}, {
		&"lua": "{{name}}({{args}})"
	}))

	result.append(_def(&"call_value", "value call {name}({args})", "06 Functions", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"name", &"raw"),
		_schema(&"args", &"raw")
	], {&"name": "math.max", &"args": "1, 2"}, {
		&"lua": "{{name}}({{args}})"
	}))

	result.append(_def(&"method_call_stmt", "call {object}:{method}({args})", "06 Functions", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"object", &"raw"),
		_schema(&"method", &"name"),
		_schema(&"args", &"raw")
	], {&"object": "player", &"method": "move", &"args": "10, 0"}, {
		&"lua": "{{object}}:{{method}}({{args}})"
	}))

	result.append(_def(&"method_call_value", "value call {object}:{method}({args})", "06 Functions", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"object", &"raw"),
		_schema(&"method", &"name"),
		_schema(&"args", &"raw")
	], {&"object": "player", &"method": "get_score", &"args": ""}, {
		&"lua": "{{object}}:{{method}}({{args}})"
	}))

static func _add_table_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"table_constructor", "table constructor", "07 Tables", BlockDefinition.BlockKind.VALUE, &"table", [
		_schema(&"items", &"array"),
		_schema(&"fields", &"dictionary")
	], {&"items": [], &"fields": {}}, {}, "Structured table constructor. items is an array; fields is a dictionary."))

	result.append(_def(&"table_raw", "raw table {body}", "07 Tables", BlockDefinition.BlockKind.VALUE, &"table", [
		_schema(&"body", &"raw")
	], {&"body": "x = 0, y = 0"}, {
		&"lua": "{ {{body}} }"
	}))

	result.append(_def(&"table_get", "{table}[{key}]", "07 Tables", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"table", &"raw"),
		_schema(&"key", &"any")
	], {&"table": "t", &"key": "name"}, {
		&"lua": "({{table}})[{key}]"
	}))

	result.append(_def(&"table_field_get", "{table}.{field}", "07 Tables", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"table", &"raw"),
		_schema(&"field", &"name")
	], {&"table": "t", &"field": "name"}, {
		&"lua": "({{table}}).{{field}}"
	}))

	result.append(_def(&"table_set", "set {table}[{key}] = {value}", "07 Tables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"table", &"raw"),
		_schema(&"key", &"any"),
		_schema(&"value", &"any")
	], {&"table": "t", &"key": "name", &"value": "value"}, {
		&"lua": "{{table}}[{key}] = {value}"
	}))

	result.append(_def(&"table_field_set", "set {table}.{field} = {value}", "07 Tables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"table", &"raw"),
		_schema(&"field", &"name"),
		_schema(&"value", &"any")
	], {&"table": "t", &"field": "name", &"value": "value"}, {
		&"lua": "{{table}}.{{field}} = {value}"
	}))

	result.append(_def(&"table_insert", "table.insert({table}, {value})", "07 Tables", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"table", &"raw"),
		_schema(&"value", &"any")
	], {&"table": "items", &"value": 1}, {
		&"lua": "table.insert({{table}}, {value})"
	}))

	result.append(_def(&"table_remove", "table.remove({table}, {index})", "07 Tables", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"table", &"raw"),
		_schema(&"index", &"number")
	], {&"table": "items", &"index": 1}, {
		&"lua": "table.remove({{table}}, {index})"
	}))

static func _add_stdlib_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"print", "print {value}", "08 Standard Library", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"value", &"any")
	], {&"value": "hello"}, {
		&"lua": "print({value})"
	}))

	result.append(_def(&"print_many", "print {values}", "08 Standard Library", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"values", &"raw")
	], {&"values": "\"x\", x"}, {
		&"lua": "print({{values}})"
	}))

	result.append(_def(&"type_of", "type({value})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"string", [
		_schema(&"value", &"any")
	], {&"value": 0}, {
		&"lua": "type({value})"
	}))

	result.append(_def(&"tostring", "tostring({value})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"string", [
		_schema(&"value", &"any")
	], {&"value": 0}, {
		&"lua": "tostring({value})"
	}))

	result.append(_def(&"tonumber", "tonumber({value})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"number", [
		_schema(&"value", &"any")
	], {&"value": "0"}, {
		&"lua": "tonumber({value})"
	}))

	result.append(_def(&"pairs", "pairs({table})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"iterator", [
		_schema(&"table", &"raw")
	], {&"table": "t"}, {
		&"lua": "pairs({{table}})"
	}))

	result.append(_def(&"ipairs", "ipairs({table})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"iterator", [
		_schema(&"table", &"raw")
	], {&"table": "items"}, {
		&"lua": "ipairs({{table}})"
	}))

	result.append(_def(&"require_assign", "local {name} = require({module})", "08 Standard Library", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"name", &"name"),
		_schema(&"module", &"string")
	], {&"name": "json", &"module": "json"}, {
		&"lua": "local {{name}} = require({module})"
	}))

	result.append(_def(&"require_value", "require({module})", "08 Standard Library", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"module", &"string")
	], {&"module": "json"}, {
		&"lua": "require({module})"
	}))

static func _add_game_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"move_self", "move self x {x} y {y}", "09 Game Sandbox", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"x", &"number"),
		_schema(&"y", &"number")
	], {&"x": 10, &"y": 0}, {
		&"lua": "self.x = self.x + {x}\nself.y = self.y + {y}"
	}, "Sandbox convenience block. Keep or remove depending on your Lua runtime."))

	result.append(_def(&"set_self_position", "set self position x {x} y {y}", "09 Game Sandbox", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"x", &"number"),
		_schema(&"y", &"number")
	], {&"x": 0, &"y": 0}, {
		&"lua": "self.x = {x}\nself.y = {y}"
	}, "Sandbox convenience block. Keep or remove depending on your Lua runtime."))

static func _add_raw_blocks(result: Array[BlockDefinition]) -> void:
	result.append(_def(&"raw_statement", "raw statement {code}", "99 Raw Lua", BlockDefinition.BlockKind.STATEMENT, &"none", [
		_schema(&"code", &"raw")
	], {&"code": "-- raw Lua here"}, {
		&"lua": "{{code}}"
	}, "Escape hatch for advanced users."))

	result.append(_def(&"raw_expression", "raw expression {code}", "99 Raw Lua", BlockDefinition.BlockKind.VALUE, &"any", [
		_schema(&"code", &"raw")
	], {&"code": "math.random()"}, {
		&"lua": "{{code}}"
	}, "Escape hatch for expressions."))

static func _def(
	id: StringName,
	label: String,
	category: String,
	kind: int,
	output_type: StringName,
	input_schema: Array[Dictionary],
	defaults: Dictionary,
	templates: Dictionary,
	description: String = ""
) -> BlockDefinition:
	var definition: BlockDefinition = BlockDefinition.new(id, label, category, kind, output_type, input_schema, defaults, templates, description)
	definition.color = _color_for(category, kind)
	return definition

static func _color_for(category: String, kind: int) -> Color:
	if kind == BlockDefinition.BlockKind.ENTRY:
		return Color(0.95, 0.63, 0.16)
	if kind == BlockDefinition.BlockKind.CONTROL:
		return Color(0.94, 0.49, 0.13)
	if kind == BlockDefinition.BlockKind.VALUE:
		if category.begins_with("02"):
			return Color(0.52, 0.36, 0.92)
		if category.begins_with("04"):
			return Color(0.29, 0.70, 0.28)
		if category.begins_with("07"):
			return Color(0.20, 0.58, 0.88)
		return Color(0.42, 0.42, 0.86)
	if category.begins_with("03"):
		return Color(0.95, 0.58, 0.18)
	if category.begins_with("06"):
		return Color(0.82, 0.27, 0.67)
	if category.begins_with("07"):
		return Color(0.20, 0.58, 0.88)
	if category.begins_with("08"):
		return Color(0.22, 0.68, 0.78)
	if category.begins_with("09"):
		return Color(0.23, 0.50, 0.95)
	if category.begins_with("99"):
		return Color(0.74, 0.23, 0.23)
	return Color(0.23, 0.56, 0.93)

static func _schema(name: StringName, type: StringName, options: Array = []) -> Dictionary:
	return {
		"name": name,
		"type": type,
		"options": options,
	}
