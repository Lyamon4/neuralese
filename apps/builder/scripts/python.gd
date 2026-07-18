# PythonishHighlighter.gd
@tool
class_name PythonishHighlighter
extends CodeHighlighter

# Minimal palette; tweak to your UI
const C_KW := Color8(197,134,192)  # keywords (purple)
const C_BUILTIN := Color8(86,156,214)   # builtins (blue)
const C_TYPES := Color8(78,201,176)   # types (teal)
const C_NUM := Color8(181,206,168)  # numbers (green-ish)
const C_STR := Color8(206,145,120)  # strings (salmon)
const C_COMM := Color8(106,153,85)   # comments (olive)
const C_DECOR := Color8(156,220,254)  # decorators (light blue)
const C_SYM := Color8(212,212,212)  # symbols / punctuation
const C_TEXT := Color8(220,220,220)  # default text
const C_FUNC := Color8(220,220,170)  # function identifiers
const C_MEMBER := Color8(156,220,254)  # member variables

func _init() -> void:
	number_color = C_NUM
	symbol_color = C_SYM
	function_color = C_FUNC
	member_variable_color = C_MEMBER

	# keywords
	_add_keywords_color([
		"def","class","if","elif","else","for","while","try","except","finally",
		"raise","return","yield","import","from","as","pass","break","continue",
		"with","lambda","global","nonlocal","del","assert","True","False","None",
		"and","or","not","in","is","async","await","match","case"
	], C_KW)

	# builtins (functions/constants)
	_add_keywords_color([
		"print","len","range","list","dict","set","tuple","int","float","str","bool",
		"enumerate","zip","map","filter","any","all","sum","min","max","open",
		"type","isinstance","hasattr","getattr","setattr","vars","dir","super","object"
	], C_BUILTIN)

	# protocol-ish names (paint like std types)
	_add_keywords_color([
		"Exception","BaseException","ValueError","TypeError","IOError","OSError",
		"RuntimeError","KeyError","IndexError","StopIteration","GeneratorExit",
		"NotImplemented","Ellipsis"
	], C_TYPES)

	# Single-line comments (# ... \n)
	add_color_region("#", "", C_COMM, true)

	# Strings (single/double/triple)
	add_color_region("'", "'", C_STR, false)
	add_color_region("\"", "\"", C_STR, false)
	add_color_region("'''", "'''", C_STR, false)
	add_color_region("\"\"\"", "\"\"\"", C_STR, false)

	# Decorators: color from '@' to end of line
	add_color_region("@", "", C_DECOR, true)

func _add_keywords_color(words: PackedStringArray, color: Color) -> void:
	for w in words:
		add_keyword_color(w, color)
