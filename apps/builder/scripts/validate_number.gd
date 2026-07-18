extends ValidInput
class_name ValidNumber
@export var min_value: float = 0
@export var max_value: float = 2**16
@export var allow_float: bool = false  # New: toggle float support
@export var decimal_places: int = 2    # New: precision for floats
@export var empty_on_min: bool = true

var prev: float = min_value
@onready var bef = text


func _revalidate_limits() -> void:
	var v := _parse_number(text)
	if v < min_value:
		v = min_value
	if v > max_value:
		v = max_value

	prev = v
	text = _format_number(v)
	update_valid()

signal backspace_attempt
func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_BACKSPACE:
			backspace_attempt.emit()
#	print(OS.get_keycode_string(event.keycode))

func _can_change_to(emit: bool) -> String:
	var before = prev
	var prev_text = text
	#("JFJF")
	var o = inte()
	
	if _parse_number(text) < min_value and before > min_value and len(text) > 1:
		o = _format_number(min_value)
		prev = min_value
	
	if empty_on_min and min_value == 0 and o == _format_number(min_value) and !allow_float:
		o = ""
	
	if prev < min_value or prev > max_value:
		set_text_color(Color(1.0, 0.5, 0.5, 1.0))
	else:
		reset_text_color()
	
	if emit:
		bef = o
	return o

func _get_value():
	return prev if prev else min_value

func is_valid_input() -> bool:
	return prev >= min_value and prev <= max_value

func _ready():
	super()
	text_submitted.connect(submit)
	focus_exited.connect(submit.bind(""))

signal submitted(new_text: String)

func submit(new: String):
	var val = _parse_number(text)
	
	if val < min_value:
		prev = min_value
		if text:
			text = _format_number(min_value)
	
	if val > max_value:
		prev = max_value
		text = _format_number(max_value)
	
	submitted.emit(text)
	_resize_label()
	reset_text_color()

func inte():
	#(max_value)
	prev_pos = caret_column
	#(text)
	
	# Remove leading zeros (but keep "0" and "0.")
	if text.begins_with("0") and text.length() > 1 and not text.begins_with("0.") and text != "0-":
		text = text.trim_prefix("0")
	var is_valid_f = _is_valid_float_string(text)
	text = text.replace(".-", ".")
	text = text.replace("-.", "-")
	if text.substr(0,1) == ".":
		text = "0." +text.substr(1)
	
	# Handle valid integer input (existing logic)
	if text.is_valid_int():
		prev = clamp(float(text), 0, float(text))
		return str(int(prev)) if not allow_float else text
	
	# Handle empty text
	if !text:
		prev = 0
		return ""
	
	# New: Check if it's a valid float when float mode is enabled
	#(_is_valid_float_string(text))
	if allow_float and is_valid_f:
		prev = clamp(float(text), 0, float(text))
		return text
	
	# Build valid number string character by character
	var new = ""
	var num: float = clamp(prev, min_value - 1, max_value + 1)
	var idx: int = -1
	var has_decimal: bool = false
	#(num)
	for i in text:
		idx += 1
		
		# Allow digits
		if i.is_valid_int():
			new += i
		# Allow minus sign at start if min_value < 0
		elif min_value < 0 and i == "-" and idx == 0 and text.count("-") == 1 and text != "-0" and text != "0-":
			new += i
		# Allow decimal point if float mode is enabled and no decimal yet
		elif allow_float and i == "." and not has_decimal:
			new += i
			has_decimal = true
		# Handle increment
		elif i == "+" and num < max_value:
			if "." in text:
				var exp = text.split(".")[-1]
				exp = exp.trim_suffix("+")
				#(exp)
				if !exp: exp = "0"
				#(exp)
				new = str(float(num + 1/(pow(10, len(exp)))))
				var new_exp = new.split(".")[-1]
				new += "0".repeat(len(exp)-len(new_exp))
			else:
				new = _format_number(num + 1)
			break
		# Handle decrement
		elif ((min_value >= 0 or idx > 0) and i == "-") and num > min_value:
			#("AA")
			if "." in text:
				var exp = text.split(".")[-1]
				exp = exp.trim_suffix("-")
				new = str(float(num - 1/(pow(10, len(exp)))))
				var new_exp = new.split(".")[-1]
				new += "0".repeat(len(exp)-len(new_exp))
			else:
				new = _format_number(num - 1)# if num - 1 != 0 else ""
			break
	
	# Validate and clamp the result
	var parsed_val = _parse_number(new) if not "." in new else float(new)
	#(parsed_val)
	if parsed_val < min_value:
		new = _format_number(min_value)
	if parsed_val > max_value:
		new = _format_number(max_value)
	
	var old_new = new
	if new != "":
		# Handle special cases: lone minus or decimal point
		if new == "-" or new == "." or new == "-.":
			return new  # Allow typing these intermediate states
		
		prev = clamp(float(new), 0, float(new))
		if not "." in new:
			new = _format_number(prev) if old_new != "-" else "-"
	else:
		prev = min_value
	
	return new

func _text_changed() -> void:
	caret_column = prev_pos + sign(len(text) - len(prev_input))

# Helper function to check if string is a valid float (including intermediate states)
func _is_valid_float_string(s: String) -> bool:
	if s == "" or s == "-" or s == "." or s == "-.":
		return false
	var count: int = -1
	#(s)
	for i in s:
		count += 1
		if count > 0 and i == "-": return false
		#if count == len(s)-1 and i == ".": return false
	# Check if it's a valid integer (which is also a valid float)
	if s.is_valid_int():
		return true
	
	# Check for valid float pattern
	var has_decimal = s.contains(".")
	var has_minus = s.begins_with("-")
	
	# Remove minus and decimal to check remaining characters
	var cleaned = s.replace("-", "").replace(".", "")
	
	# All remaining characters must be digits
	for c in cleaned:
		if not c.is_valid_int():
			return false
	
	# Must have at most one decimal point
	return s.count(".") <= 1 and has_decimal

# Helper function to parse number from string (handles intermediate states)
func _parse_number(s: String) -> float:
	if s == "" or s == "-" or s == "." or s == "-.":
		return 0.0
	
	if s.is_valid_int():
		return float(s)
	
	if allow_float and _is_valid_float_string(s):
		return float(s)
	
	return prev

# Helper function to format number as string
func _format_number(value: float) -> String:
	if allow_float:
		# Round to specified decimal places
		#var multiplier = pow(10, decimal_places)
		#var rounded = round(value * multiplier) / multiplier
		return str(int(value))
	else:
		return str(int(value))
