extends TextureRect


func _ready() -> void:
	#RenderingServer.global_shader_parameter_add("bg", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null)
	RenderingServer.global_shader_parameter_set("bg", texture)
	#$"../SubViewport".world_2d = get_world_2d()

func _process(delta: float):
	$"../SubViewport/bg/ColorRect".process(delta)
	#global_position = glob.cam.global_position-glob.window_size/2
