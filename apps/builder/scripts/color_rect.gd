extends ColorRect

@export var rect: TextureRect
@export var offset_mult: float = 1.0

func process(delta: float) -> void:
	var cam = glob.cam
	$"../../Camera2D".position = cam.position
	$"../../Camera2D".zoom = cam.zoom
	$"../..".size = glob.window_size + Vector2(20,20)
	position = cam.get_screen_center_position() - glob.window_size/2.0/cam.zoom*offset_mult 
	#rect.position = ( cam.position- get_viewport_rect().size/2/cam.zoom)
