extends SubViewport

func _process(delta: float) -> void:
	if get_viewport().size != size:
		size = get_viewport().size
	$'bg/ColorRect'.size = size * 5
