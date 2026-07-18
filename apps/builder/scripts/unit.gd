extends Control
class_name DynamicGraphUnit

@export var for_conn_size: Vector2 = Vector2()
@export var connections: Array[Connection] = []

var id: int = 0
var connect_position: float = 0.0
var low = {"edit_graph": true}


func set_weight(weight: float, text: String):
	var points = $actual.points
	points[1] = Vector2(lerp($backline.points[0].x, $backline.points[1].x, clamp(weight, 0, 1)), points[0].y)
	
	$actual.points = points
	$Label2.text = text

func _process(delta: float) -> void:
	var loc = get_local_mouse_position()
	var inside: bool = Rect2(0,0,size.x,size.y).has_point(loc)
	#(inside)
	#if graphs.conns_active.has($o) or Rect2(0,0,for_conn_size.x,for_conn_size.y).has_point(loc):
	#	$o.process_mode = Node.PROCESS_MODE_INHERIT
	#	get_parent().hold_for_frame()
	#else:
	#	$o.process_mode = Node.PROCESS_MODE_DISABLED
	if inside:
		glob.set_menu_type(self, &"delete_i", low)
		if glob.mouse_alt_just_pressed:
			glob.menus[&"delete_i"].show_up($Label.text, get_parent().remove_unit.bind(id))
	else:
		glob.reset_menu_type(self, &"delete_i")
		
