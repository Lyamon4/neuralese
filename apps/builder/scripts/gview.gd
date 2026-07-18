extends Node2D

@export var target_offset: Vector2 = Vector2(0, 0)

func _process(delta: float) -> void:
	position = position.lerp(target_offset, delta * 20.0)
