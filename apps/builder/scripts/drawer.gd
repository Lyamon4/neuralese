extends Control

var mode: int = 0
@export var origin_y: float = 0.0
@export var y_mult: float = 70.0
@export var spacing: float = 5.0
@export var width: float = 0.0
@export var offset_x: float = 0.0

var tweener: bool = false
var line: Line2D = null

func _ready() -> void:
	pass

var lines = {}
var _points = []

func init_polygon():
	$Line2D.queue_free()

var smoothed: bool = false

func init_columns():
	line = $Line2D.duplicate()
	$Line2D.queue_free()
	$Polygon2D.queue_free()

func reline() -> void:
	if mode == 0:
		reline_columns()
	elif mode == 1:
		reline_polygon()

func reline_polygon():
	var polygon = PackedVector2Array()
	var id: int = -1
	var last_point = Vector2()
	var first_x = null
	#(-position.x)
	for point in _points:
		id += 1
		var x = spacing * id + spacing / 2.0 + offset_x
		var point_diff = origin_y - _points[point] * y_mult
	#	if id == 0:
	#		x = -position.x
		if first_x == null: first_x = x
		last_point = Vector2(x,point_diff)
		polygon.append(last_point)
	polygon.append(Vector2(last_point.x, origin_y))
	polygon.append(Vector2(first_x if first_x != null else 0.0, origin_y))
	#(polygon.visible)
	$Polygon2D.polygon = polygon


func reline_columns():
	var id: int = -1
	for point in _points:
		id += 1
		if not id in lines:
			lines[id] = [line.duplicate(), line.duplicate()]
			add_child(lines[id][0]); add_child(lines[id][1])

		var x = spacing * id + spacing / 2.0 + offset_x
		var point_diff = origin_y - _points[point] * y_mult

		lines[id][0].points = PackedVector2Array([
			Vector2(x, origin_y), Vector2(x, origin_y - y_mult)
		])
		lines[id][0].width = width
		lines[id][0].default_color = Color(0.2, 0.2, 0.2, 1.0)

		lines[id][1].points = PackedVector2Array([
			Vector2(x, origin_y), Vector2(x, point_diff)
		])
		lines[id][1].width = width
		lines[id][1].default_color = Color.GREEN_YELLOW

@export var window_width: float = 0.0
@export var fade_width: float = 24.0

func _process(_delta: float) -> void:
	if tweener and mode == 0:
		process_fade(_delta)
	

func process_fade(_delta: float):
	if window_width <= 0.0 or fade_width <= 0.0:# or get_parent().killed:
		for pair in lines.values():
			pair[0].modulate.a = 1.0
			pair[1].modulate.a = 1.0
		return

	var left = 0.0
	var right = window_width
	for pair in lines.values():
		if pair[0].points.size() == 0:
			continue
		var local_x = pair[0].points[0].x
		var screen_x = local_x #+ position.x

		var a = 1.0
		if screen_x < left or screen_x > right:
			a = 0.0
		else:
			if screen_x < left + fade_width:
				a *= clamp((screen_x - left) / fade_width, 0.0, 1.0)
			if screen_x > right - fade_width:
				a *= clamp((right - screen_x) / (fade_width), 0.0, 1.0)

		var m0 = pair[0].modulate; m0.a = a; pair[0].modulate = m0
		var m1 = pair[1].modulate; m1.a = a; pair[1].modulate = m1
