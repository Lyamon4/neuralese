

extends LineEdit
class_name ValidInput

@export var accept_button: BlockComponent

@export var resize_after: int = 0
@export var auto_red: bool = false
@export var scale_fix: bool = false
func _ready() -> void:
	focus_exited.connect(func(): line_enter.emit())
	text_changed.connect(_input_changed)
	text_submitted.connect(_input_submit)

func set_valid(valid: bool):
	is_valid = valid

func update_valid():
	is_valid = _is_valid(text)
	if auto_red:
		if !is_valid:
			self_modulate = Color.INDIAN_RED
		else:
			self_modulate = Color.WHITE

var custom_is_valid: Callable
func set_is_valid_call(call_: Callable):
	custom_is_valid = call_

func get_value():
	return _get_value()

func _get_value():
	return ""

@onready var base_scale = scale
@onready var base_pos = position
@onready var base_olx = offset_left
@onready var base_orx = offset_right
func _process(delta: float) -> void:
	if scale_fix:
		var parent = get_parent()
		var s = base_scale.x
		#anchor_left = 0.0
		#anchor_right = 1.0
		#anchor_top = 1.0
		#anchor_bottom = 1.0
		offset_left = 0.0
		offset_right = 0.0

		size.x = (parent.size.x) / s-28
		position.x = base_pos.x





@onready var base_text_color = get_theme_color(&"font_color")
func set_text_color(color: Color):
	add_theme_color_override(&"font_color", color)

func reset_text_color():
	add_theme_color_override(&"font_color", base_text_color)


func _gui_input(event: InputEvent) -> void:

	if (event is InputEventMouseButton and
		event.button_index == 2 and
		event.pressed):
		get_viewport().set_input_as_handled()
		return
	if not auto_enter and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		text_submitted.emit(text)

		set_line("")
		get_viewport().set_input_as_handled()
		call_deferred("grab")
		return

	#super(event)

var is_valid: bool = false

func _is_valid(input: String) -> bool:
	if custom_is_valid: return custom_is_valid.call(input)
	return len(input) > 0


@export var change_always_accepted: bool = true
func _can_change_to(emit: bool) -> String:
	return text

func _text_changed() -> void:
	pass

var prev_input: String = ""
func _input_changed(input: String):
	set_line(input, true)
	
var prev_pos: int = 0

@onready var before_text = text
func set_line(input: String, emit: bool = false, force: bool = false):
	if before_text == input and not force: return
	if text != input:
		text = input
		caret_column = prev_pos
	if !change_always_accepted:
		text = _can_change_to(emit)
	is_valid = _is_valid(input)
	if auto_red:
		if !is_valid:
			self_modulate = Color.INDIAN_RED
		else:
			self_modulate = Color.WHITE
	if !change_always_accepted:
		prev_input = input
	_text_changed()
	_resize_label()
	if emit:
		changed.emit()
	before_text = text

@onready var _font = get_theme_font("font")

func _string_width_px(s: String, fs: int) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x

@onready var base_font_size = get_theme_font_size("font_size")
@onready var k = base_font_size/float(get_theme_font_size("font"))
@export var monospaced: bool = true


func _resize_label():
	if monospaced:
		_resize_monospace(); return
	var s = text
	if s.is_empty() or resize_after <= 0:
		add_theme_font_size_override("font_size", base_font_size)
		return
	var limit_px = float(resize_after)
	var sb = get_theme_stylebox("normal", "LineEdit")
	if sb:
		limit_px -= (sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT))
	var w = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base_font_size).x
	if w <= limit_px:
		add_theme_font_size_override("font_size", base_font_size)
		return
	#(resize_after)
	var ratio = clamp(limit_px / max(1.0, w), 0.05, 1.0)
	var new_fs = int(floor(base_font_size * ratio))
	add_theme_font_size_override("font_size", max(6, new_fs))




func _resize_monospace(ret: bool = false):
	var s = text
	var _base_fs = base_font_size * k
	#if text == "egrergger":
#		print(resize_after)
	var n = s.length()
	if n == 0 or resize_after <= 0 or n <= resize_after:
		if base_font_size == override: return
		override = base_font_size
		add_theme_font_size_override("font_size", base_font_size)
		return
	var full_w = len(s) * _base_fs
	if full_w <= 0.0:
		if base_font_size == override: return
		override = base_font_size
		add_theme_font_size_override("font_size", base_font_size)
		return

	#var keep_txt = s.substr(0, resize_after)
	var keep_w = min(resize_after, n) * base_font_size
	#(keep_w)
	var scale = clamp(keep_w / full_w, 0, 1.0)
	var new_fs = int(round(_base_fs * scale))
	if new_fs == override: return override
	override = new_fs
	if ret: return override
	add_theme_font_size_override("font_size", new_fs)
#	print(resize_after)


var override: int = 0





func _input_submit(input: String):
	pass


func grab():
	grab_focus()
	grab_click_focus()
	ui.click_screen(global_position + Vector2(2,2))

var auto_enter: bool = true
signal changed
signal line_enter
@export var auto_click: bool = true
func _input(event: InputEvent) -> void:
	if auto_enter and event is InputEventKey and event.keycode == KEY_ENTER and ui.is_focus(self):
	#	print("ff")
		grab_focus()
		if auto_click:
			if accept_button:
				accept_button.press(0.1)
			ui.click_screen(global_position + Vector2(10,10))
		line_enter.emit()
