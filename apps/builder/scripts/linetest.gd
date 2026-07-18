@tool
extends Node2D

@export var lines: LineDrawer2D

func _process(delta: float) -> void:
	return
	# Prepare space for 100 lines (no reallocation when you update by index)
	lines.set_count(100)

	# Draw a few
	lines.set_line(0, Vector2(0, 0), Vector2(50, 50), 3.0, Color.PALE_VIOLET_RED)
	#lines.set_line(42, Vector2(-50, -50), Vector2(150, 80), 2.0, Color.CORAL)

	# Later, update any one randomly—only that instance is touched:
	#lines.set_line(42, Vector2(-30, -40), Vector2(200, 60), 2.0, Color.CORAL)
