@tool
class_name LuaHighlighter
extends CodeHighlighter

# Balanced blue–purple palette with stronger separation
const C_KW     := Color8(120, 170, 255)   # soft sky-blue keywords
const C_BUILTIN:= Color8(90, 140, 255)    # deep cobalt builtins
const C_TYPES  := Color8(150, 200, 255)   # icy blue libs
const C_NUM    := Color8(200, 100, 220)   # violet numbers
const C_STR    := Color8(100, 220, 200)   # teal strings (contrast!)
const C_COMM   := Color8(120, 130, 150)   # muted grey-blue comments
const C_SYM    := Color8(210, 215, 230)   # cool grey symbols
const C_TEXT   := Color8(235, 240, 245)   # default slightly blue text
const C_FUNC   := Color8(180, 130, 255)   # purple functions
const C_MEMBER := Color8(100, 160, 230)   # blue-violet members

func _init() -> void:
	number_color = C_NUM
	symbol_color = C_SYM
	function_color = C_FUNC
	member_variable_color = C_MEMBER

	# Lua reserved words
	_add_keywords_color([
		"and","break","do","else","elseif","end","false","for","function","goto",
		"if","in","local","nil","not","or","repeat","return","then","true",
		"until","while"
	], C_KW)

	# Builtins
	_add_keywords_color([
		"pairs","ipairs","next","type","tonumber","tostring","error",
	], C_BUILTIN)

	# Standard libs
	_add_keywords_color([
		"math","table","string"
	], C_TYPES)

	# Comments
	add_color_region("--", "", C_COMM, true)
	add_color_region("--[[", "]]", C_COMM, false)

	# Strings
	add_color_region("'", "'", C_STR, false)
	add_color_region("\"", "\"", C_STR, false)
	add_color_region("[[", "]]", C_STR, false)

func _add_keywords_color(words: PackedStringArray, color: Color) -> void:
	for w in words:
		add_keyword_color(w, color)
