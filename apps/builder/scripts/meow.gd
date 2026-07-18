extends Node2D
class_name ConfettiSplash

func dying():
	#("a")
	die.emit()
	gpu.queue_free()

signal die
var gpu = GPUParticles2D.new()
func _ready() -> void:
	gpu.process_material = ui.conf_config
	gpu.amount = 40
	gpu.emitting = false
	add_child(gpu)
	gpu.emitting = true
	gpu.lifetime = 1.5
	gpu.speed_scale = 2
	gpu.one_shot = true
	gpu.explosiveness = 0.93
	glob.wait(1).connect(dying)
