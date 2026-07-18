extends ColorRect

func _process(delta: float) -> void:
	pass

@onready var base_tuning = glob.inst_uniform_read(self, "tuning")

func set_tuning(color_: Color):
	RenderingServer.canvas_item_set_instance_shader_parameter(get_canvas_item(), &"tuning", color_)

	
