extends Label

@export var top: Control

func _process(delta: float) -> void:
	global_position.x = top.get_global_rect().end.x - 215 + 95
