extends CanvasLayer

@export var namings: Array[PackedStringArray] = []
@onready var root: Node2D = $Node2D
func _enter_tree() -> void:
	glob.menu_canvas = self
