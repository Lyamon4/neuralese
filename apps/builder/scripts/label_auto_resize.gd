@tool

extends Label
class_name LabelAutoResize


@export var auto_get_base_size: bool = false
@onready var base_scale: float = scale.x
@export var padding: Vector2 = Vector2(4, 4) # optional extra spacing
@export var min_scale: float = 0.1
@export var parent_indep: bool = false
@export var base_size: Vector2
@export var simple: bool = false
@export var simple_letters: int = 0 

func _ready() -> void:
	if auto_get_base_size:
		base_size = size
	if not simple:
		resize.call_deferred()
	if debug and !Engine.is_editor_hint():
		item_rect_changed.connect(resize)
	if Engine.is_editor_hint():
		get_tree().process_frame.connect(frame)
	#if pivoting:
	#	position.y -= size.y * scale.y * 0.5
	#	position.y += 4

func frame() -> void:
	if pivoting:
		pivot_offset.y = size.y * 0.5
	else:
		pivot_offset.y = 0


@onready var _font = get_theme_font("font")
@onready var base_font_size = get_theme_font_size("font")

func _resize_simple() -> void:
	base_font_size = 32
	var txt = text
	add_theme_font_size_override("font_size", base_font_size)
	if txt.is_empty():
		override = base_font_size
		add_theme_font_size_override("font_size", base_font_size)
		return
	
	var n = txt.length()
	if n <= simple_letters:
		override = base_font_size
		add_theme_font_size_override("font_size", base_font_size)
		return

	# Shrink proportionally to how many letters exceed the limit
	var ratio = float(simple_letters) / float(n)
	var new_fs = int(round(base_font_size * ratio))
	new_fs = clamp(new_fs, 6, base_font_size)
	override = new_fs
	add_theme_font_size_override("font_size", new_fs)

var override: int = 32
@export var unscaled_size: bool = false
@export var debug: bool = false
@export var pivoting: bool = false


func resize() -> void:
	if simple:
		_resize_simple()
		return
	if !parent_indep: resize_dep(); return
	var available: Vector2
	
	if parent_indep:
		available = base_size
	else:
		var parent_ctrl = get_parent()
		if not (parent_ctrl is Control):
			return
		available = parent_ctrl.size - position
	
	padding = Vector2.ZERO
	var text_size: Vector2 = glob.get_label_text_size_unscaled(self) if unscaled_size else glob.get_label_text_size(self, base_scale if !parent_indep else 1.0)
	#(text_size)
	if !parent_indep:
		text_size += padding / scale
	else:
		text_size += padding
	
	if text_size.x <= 0.0 or text_size.y <= 0.0:
		return
	
	var kx: float = available.x / text_size.x
	var ky: float = available.y / text_size.y
	var k: float = min(kx, ky)
	var new_scale: float = clamp(base_scale * k, min_scale, base_scale)
	if pivoting:
		pivot_offset.y = (size.y) * 0.5
	scale = Vector2.ONE * new_scale
	#custom_minimum_size.y = size.y/scale.y
	



func resize_dep() -> void:
	var parent_ctrl = get_parent()
	if not (parent_ctrl is Control):
		return
	var parent_size: Vector2 = parent_ctrl.size
	var available: Vector2 = parent_size - position
	var text_size: Vector2 = glob.get_label_text_size(self, base_scale) + padding / scale
	
	if text_size.x <= 0.0 or text_size.y <= 0.0:
		return

	var kx: float = available.x / text_size.x
	var ky: float = available.y / text_size.y
	var k: float = min(kx, ky)
	
	scale = Vector2.ONE * min(base_scale, max(min_scale, base_scale * k))
