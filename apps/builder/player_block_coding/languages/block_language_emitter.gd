extends RefCounted
class_name BlockLanguageEmitter

const BlockDefinitionClass = preload("res://player_block_coding/core/block_definition.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")

var language_id: StringName = &"generic"
var indent_text: String = "\t"
var statement_separator: String = "\n"

func emit_program(program: BlockProgram) -> String:
	var lines: Array[String] = []
	for root in program.roots:
		var emitted: String = emit_block(root, 0)
		if emitted.strip_edges() != "":
			lines.append(emitted.rstrip("\n"))
	return statement_separator.join(lines)

func emit_block(block: BlockInstance, depth: int = 0) -> String:
	if block == null or block.definition == null:
		return ""

	match block.definition.kind:
		BlockDefinition.BlockKind.VALUE:
			return emit_value(block)
		BlockDefinition.BlockKind.ENTRY, BlockDefinition.BlockKind.STATEMENT, BlockDefinition.BlockKind.CONTROL:
			return emit_statement(block, depth)
		_:
			return ""

func emit_statement(block: BlockInstance, depth: int) -> String:
	var template: String = block.definition.get_template(language_id)
	if template == "":
		return indent(depth) + get_missing_template_statement(block.definition.id)

	var body: String = emit_children(block.children, depth + 1)
	if body.strip_edges() == "" and _template_uses_body(template):
		body = indent(depth + 1) + get_pass_statement()

	var else_body: String = emit_children(block.else_children, depth + 1)
	if else_body.strip_edges() == "" and _template_uses_else_body(template):
		else_body = indent(depth + 1) + get_pass_statement()

	var code: String = format_template(template, block.arguments, depth, body, else_body)
	return indent_multiline(code, depth)

func emit_value(block: BlockInstance) -> String:
	var template: String = block.definition.get_template(language_id)
	if template == "":
		return get_missing_template_value(block.definition.id)
	return format_template(template, block.arguments, 0, "", "")

func emit_children(children: Array[BlockInstance], depth: int) -> String:
	var lines: Array[String] = []
	for child in children:
		var emitted: String = emit_block(child, depth)
		if emitted.strip_edges() != "":
			lines.append(emitted.rstrip("\n"))
	return statement_separator.join(lines)

func format_template(template: String, arguments: Dictionary, depth: int, body: String, else_body: String) -> String:
	var result: String = template
	result = result.replace("{body}", body)
	result = result.replace("{else_body}", else_body)
	result = result.replace("{indent}", indent(depth))
	result = result.replace("{child_indent}", indent(depth + 1))

	for key in arguments.keys():
		var key_text: String = str(key)
		var value: Variant = arguments[key]
		var code_value: String = argument_to_code(value)
		result = result.replace("{{%s}}" % key_text, raw_argument_to_text(value))
		result = result.replace("{%s}" % key_text, code_value)

	return result

func argument_to_code(value: Variant) -> String:
	if value is BlockInstance:
		return emit_value(value)
	return literal_to_code(value)

func raw_argument_to_text(value: Variant) -> String:
	if value is BlockInstance:
		return emit_value(value)
	return str(value)

func literal_to_code(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return get_null_literal()
		TYPE_BOOL:
			return get_bool_literal(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return quote_string(str(value))
		TYPE_VECTOR2:
			return "Vector2(%s, %s)" % [str(value.x), str(value.y)]
		TYPE_VECTOR3:
			return "Vector3(%s, %s, %s)" % [str(value.x), str(value.y), str(value.z)]
		_:
			return str(value)

func quote_string(value: String) -> String:
	return "\"%s\"" % value.c_escape()

func get_bool_literal(value: bool) -> String:
	return "true" if value else "false"

func get_null_literal() -> String:
	return "null"

func get_pass_statement() -> String:
	return "pass"

func get_missing_template_statement(block_id: StringName) -> String:
	return "# Missing template for %s" % String(block_id)

func get_missing_template_value(block_id: StringName) -> String:
	return "/* missing:%s */" % String(block_id)

func indent(depth: int) -> String:
	return indent_text.repeat(max(depth, 0))

func indent_multiline(code: String, depth: int) -> String:
	var prefix: String = indent(depth)
	var lines: PackedStringArray = code.split("\n", false)
	var result: Array[String] = []
	for line in lines:
		if line.strip_edges() == "":
			result.append("")
		else:
			result.append(prefix + line)
	return "\n".join(result)

func _template_uses_body(template: String) -> bool:
	return template.find("{body}") != -1

func _template_uses_else_body(template: String) -> bool:
	return template.find("{else_body}") != -1
