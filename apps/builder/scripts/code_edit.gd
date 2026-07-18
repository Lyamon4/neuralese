extends CodeEdit

var words: Array[String] = [
]

var classes = [
	"math", "table", "string"
]

var methods = [
	"pairs","ipairs","next","type","tonumber","tostring",
]

var keywords = [
	"and","break","do","else","elseif","end","for","function","goto",
	"if","in","local","nil","not","or","repeat","return","then",
	"until","while",
]



#KIND_CLASS = 0
#Marks the option as a class.
#● KIND_FUNCTION = 1
#Marks the option as a function.
#● KIND_SIGNAL = 2
#Marks the option as a Godot signal.
#● KIND_VARIABLE = 3
#Marks the option as a variable.
#● KIND_MEMBER = 4
#Marks the option as a member.
#● KIND_ENUM = 5
#Marks the option as an enum entry.
#● KIND_CONSTANT = 6
#Marks the option as a constant.
#● KIND_NODE_PATH = 7
#Marks the option as a Godot node path.
#● KIND_FILE_PATH = 8
#Marks the option as a file path.
#● KIND_PLAIN_TEXT = 9
#Marks the option as unclassified or plain text.

func _ready() -> void:
	methods.append_array(LuaProcess.new("", "").methods)
	text_changed.connect(_on_request_code_completion)
	code_completion_prefixes = ["_", ".", "a","b","c","d","e","f","g","h",
		"i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]

func _on_request_code_completion(...args) -> void:
	for word in classes:
		add_code_completion_option(CodeEdit.KIND_CLASS, word, word, Color(1,1,1,1))
	for word in methods:
		add_code_completion_option(CodeEdit.KIND_FUNCTION, word, word, Color(1,1,1,1))
	for word in keywords:
		add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, word, word, Color(1,1,1,1))
	update_code_completion_options(true)
	
