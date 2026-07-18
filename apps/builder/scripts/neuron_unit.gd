extends Control

var id: int = 0

@export var resize_after: int = 0

@onready var label: Label = $ColorRect5/Label
@onready var base_scale: float = label.scale.x
@onready var _base_scale: float = label.scale.x

func set_extents(vec: Vector4) -> void:
	$ColorRect5.set_instance_shader_parameter("extents", vec)
	$ColorRect5/Label.set_instance_shader_parameter("extents", vec)


func _center_label(text_str: String, scale: float, font: Font, fs: int) -> void:
	var parent_ctrl = label.get_parent() as Control
	if parent_ctrl == null: return
	var tsize: Vector2 = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs) * scale
	var container: Vector2 = parent_ctrl.size
	label.position.x = ((container - tsize) * 0.5).x

func set_text(text: int, last: bool = false) -> void:
	if text <= 1: 
		label.hide()
		return
	else:
		label.show()
	
	var s = glob.compact(text)
	if last:
		s += "+"
		base_scale = _base_scale
	else:
		base_scale = _base_scale
	label.text = s

	var font = label.get_theme_font("font")
	var fs = label.get_theme_font_size("font_size")
	var n = s.length()
	var full_sz: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)

	var final_scale = base_scale

	if resize_after > 0 and n > resize_after and full_sz.x > 0.0:
		var keep_txt = s.substr(0, resize_after)
		var keep_sz: Vector2 = font.get_string_size(keep_txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)

		var base_full_w = full_sz.x * base_scale
		var target_w = keep_sz.x * base_scale
		var mult = clamp(target_w / base_full_w, 0.1, 1.0)
		final_scale = base_scale * mult

	label.scale = Vector2.ONE * final_scale
	_center_label(s, final_scale, font, fs)
	if text < 1000 and text > 99:
		label.position.x += 1
	#if last:
		#label.position.y -= 3
	
