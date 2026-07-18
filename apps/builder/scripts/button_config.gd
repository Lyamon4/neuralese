extends Resource
class_name ButtonConfig

@export var as_mult: bool = false
@export_subgroup("Hover")
@export var hover_color: Color = Color.BLUE
@export var hover_mult: float = 1.0
func _init() -> void:
	hover_color *= hover_mult
@export_range(0.5, 1.5) var _hover_scale: float = 1.03

@export_subgroup("Press")
@export var press_color: Color = Color.RED
@export_range(0.5, 1.5) var _press_scale: float = 0.9
@export var press_mult: float = 1.0

@export_subgroup("Release")
@export_range(0.0, 30.0) var animation_scale: float = 0.0
@export_range(0.0, 6.0) var animation_speed: float = 0.0
@export_range(1.0, 6.0) var animation_decay: float = 0.0
@export_range(0.5, 6.0) var animation_duration: float = 1.0
