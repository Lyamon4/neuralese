extends Control

func _ready() -> void:
	pass
	

func relayout() -> float:
	var max_y := 0.0
	for c in get_children():
		if not c is BubbleUnit:
			continue
		if c.abstract: continue

		var bottom = c.position.y + c.size.y
		max_y = max(max_y, bottom)
	
	custom_minimum_size.y = max_y + 20
	return max_y
