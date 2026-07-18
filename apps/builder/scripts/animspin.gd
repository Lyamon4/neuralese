extends Node
class_name AnimSpin

@onready var parent = get_parent()
func play():
	queue_play = true
	t_play = 0
	parent.rotation = 0

var t_play: float = 0.0; var queue_play: bool = false
signal cycle_made
func _process(delta: float) -> void:
	if queue_play:
		t_play += delta
		parent.rotation = glob.lerp_quad(deg_to_rad(1), deg_to_rad(360), t_play)
		if is_equal_approx(t_play, 1.0):
			queue_play = false
			parent.rotation = 0
