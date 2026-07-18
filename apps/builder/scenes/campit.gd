extends GPUParticles2D

func _process(delta: float) -> void:
	if glob.space_just_pressed:
		if emitting: emitting = false
		emitting = true
