extends ColorRect
class_name MovingAnalytics

@export var alive: bool = false:
	set(v):
		alive = v; killed = false
@export var dot_represents: float = 0.3
@export_enum("Lines", "Polygon") var mode = 0
@export var tweener: bool = false

@export_group("Drawing Settings")
@export var origin_y: float = 65.0
@export var y_mult: float = 60.0
@export var spacing: float = 10.0
@export var width: float = 4.0
@export var offset_x: float = 2.5
@export var window_width: float = 0.0
@export var fade_width: float = 20
@export var smoothed: bool = false
@export_group("")

var _draw_offset_x: float = 0.0
var line: Line2D = null
var lines = {}
var _points = []

var points: Dictionary = {}
var points_q: Dictionary = {}
var t_last_frame: float = 0.0
var sliding_origin: int = 0
@export var window_size: int = 20
@export var snapshot_every: float = 0.1
var _window_end: int = window_size
var last_known: float = 0.0
var last_known_pos: int = 0
var known: Dictionary[int, int] = {}
var t: float = 0.0
var killed: bool = true
@export var max_value: float = 1.0

var timing_offset: float = 0.0
func get_time() -> float:
	return (sliding_origin - 1) * dot_represents + t_last_frame + timing_offset

func _ready() -> void:
	for i in window_size:
		points[i] = 0.0
	window_width = window_size * spacing
	if mode == 0:
		_init_columns()
	else:
		_init_polygon()
	_point_step()

func get_last_value() -> float:
	return points[_window_end-1]

func push_input(time: float, value: float, last: int = 0) -> void:
	#(value)
	if killed: return
	if alive:
		if value > max_value:
			max_value = value
		points_q[int(time / dot_represents) if not last else last] = value / max_value

func _process(delta: float) -> void:
	#(killed)
	if killed: return
	t += delta
	t_last_frame += delta

	if tweener:
		_draw_offset_x = lerp(0.0, -spacing, t_last_frame / snapshot_every)
		_reline()
		if not alive and _draw_offset_x > -0.1:
			_draw_offset_x = 0
			killed = true
			_point_step()
			_reline()
			return

	if t_last_frame <= snapshot_every:
		if tweener and mode == 0:
			_process_fade(delta)
		return

	t_last_frame = 0.0
	_draw_offset_x = 0.0
	if not alive:
		killed = true
		_point_step()
		return
	_point_step()

func _point_step() -> void:
	var new_points = points.duplicate()
	new_points.erase(sliding_origin)
	sliding_origin += 1
	_window_end = sliding_origin + window_size
	new_points[_window_end - 1] = last_known

	for i: int in points_q.keys():
		if not i in new_points: continue
		for j: int in range(i, max(_window_end, last_known_pos)):
			if j > _window_end: break
			if j in known and i < known[j]: break
			known[j] = i
			if j in new_points:
				new_points[j] = points_q[i]
		new_points[i] = points_q[i]
		if i > last_known_pos:
			last_known = points_q[i]
			last_known_pos = i
		points_q.erase(i)

	points = new_points
	_points = points
	_reline()

func _init_polygon() -> void:
	if has_node("Line2D"):
		$"Line2D".queue_free()

func _init_columns() -> void:
	if has_node("Line2D"):
		line = $"Line2D".duplicate()
		$"Line2D".queue_free()
	if has_node("Polygon2D"):
		$"Polygon2D".queue_free()

func _reline() -> void:
	if mode == 0:
		_reline_columns()
	elif mode == 1:
		_reline_polygon()

func _reline_polygon() -> void:
	#if not has_node("Polygon2D"):
	#	return
	var polygon = PackedVector2Array()
	var id = -1
	var last_point = Vector2()
	var first_x = null
	for point in _points:
		id += 1
		var x = spacing * id + spacing / 2.0 + offset_x + _draw_offset_x
		var y = origin_y - _points[point] * y_mult
		if first_x == null:
			first_x = x
		last_point = Vector2(x, y)
		polygon.append(last_point)
	polygon.append(Vector2(last_point.x, origin_y))
	polygon.append(Vector2(first_x if first_x != null else 0.0, origin_y))
	$"Polygon2D".polygon = polygon

func _reline_columns() -> void:
	var id: int = -1
	for point in _points:
		id += 1
		if not id in lines:
			lines[id] = [line.duplicate(), line.duplicate()]
			add_child(lines[id][0])
			add_child(lines[id][1])

		var x = spacing * id + spacing / 2.0 + offset_x + _draw_offset_x
		var point_diff = origin_y - _points[point] * y_mult
		if point_diff > origin_y: point_diff = origin_y

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

	if mode == 0:
		_process_fade(0.0)

func _process_fade(_delta: float) -> void:
	if mode != 0:
		return
	if window_width <= 0.0 or fade_width <= 0.0:
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
		var screen_x = local_x

		var a = 1.0
		if screen_x < left or screen_x > right:
			a = 0.0
		else:
			if screen_x < left + fade_width:
				a *= clamp((screen_x - left) / fade_width, 0.0, 1.0)
			if screen_x > right - fade_width:
				a *= clamp((right - screen_x) / fade_width, 0.0, 1.0)

		var m0 = pair[0].modulate; m0.a = a; pair[0].modulate = m0
		var m1 = pair[1].modulate; m1.a = a; pair[1].modulate = m1


func clear_window() -> void:
	# Reset points and state
	points.clear()
	points_q.clear()
	known.clear()
	_points.clear()
	lines.clear()

	sliding_origin = 0
	_window_end = window_size
	last_known = 0.0
	last_known_pos = 0
	t = 0.0
	t_last_frame = 0.0
	killed = true
	_draw_offset_x = 0.0

	# Reinitialize with zeros
	for i in window_size:
		points[i] = 0.0
	_points = points

	# Remove any Line2D / Polygon2D children currently rendered
	for child in get_children():
		if child is Line2D or child is Polygon2D:
			child.queue_free()

	# Re-init visuals
	if mode == 0:
		_init_columns()
	else:
		_init_polygon()
	_reline()
