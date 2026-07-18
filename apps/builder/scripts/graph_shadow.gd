@tool

extends ColorRect
class_name GraphShadow

@export var outline: bool = false
var _offset: Vector2 = Vector2()
var _size_add: Vector2 = Vector2()
@export var extents: Vector2 = Vector2(50,50):
	set(v):
		set_size(v + _size_add)
		#set_deferred("size", v + _size_add)
		extents = v

@export_range(1.0,100.0) var blur_size: float = 2.0:
	set(v):
		_offset = -Vector2(v,v)/(1.5 if outline else 2.0)
		_size_add = Vector2(v,v)*(1.3 if outline else 1.0); extents = extents
		blur_size = v
		material.set_shader_parameter("data", Vector4(v, _offset.x, _offset.y, 0.0))

func _ready() -> void:
	extents = extents; blur_size = blur_size
