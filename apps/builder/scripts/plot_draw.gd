extends ColorRect
class_name FunctionPlot

# ============================================================
# Function
# ============================================================

## Callable: f(x) -> float
## Example: plot.set_function(func(x): return sin(x))
var function: Callable = Callable()

func set_function(f: Callable) -> void:
	function = f

# ============================================================
# Viewport (world → screen mapping)
# ============================================================

## World coordinate at the center of the rect
@export var view_center: Vector2 = Vector2.ZERO

## Zoom: world units per pixel (smaller = zoom in)
@export var zoom: float = 50.0

# ============================================================
# Appearance
# ============================================================

@export var graph_color: Color = Color(0.2, 0.9, 1.0)
@export var axis_color: Color  = Color(0.7, 0.7, 0.7)

@export var axis_width: float = 1.0
@export var graph_width: float = 2.0

## Sampling density: points per pixel
@export_range(0.1, 4.0)
var samples_per_pixel: float = 1.0:
	set(v):
		samples_per_pixel = v
		queue_redraw()

# ============================================================
# Internal helpers
# ============================================================

func _world_to_screen(p: Vector2) -> Vector2:
	return Vector2(
		(p.x - view_center.x) * zoom + size.x * 0.5,
		(size.y * 0.5) - (p.y - view_center.y) * zoom
	)

func _screen_to_world_x(x: float) -> float:
	return (x - size.x * 0.5) / zoom + view_center.x

# ============================================================
# Drawing
# ============================================================

func _draw() -> void:
	# Background
	
	_draw_grid()
	_draw_axes()
	_draw_function()

@export var grid_color: Color = Color(0.25, 0.25, 0.25)
@export var grid_width: float = 1.0

## Distance between grid lines in WORLD units
@export var grid_step: float = 1.0

func _world_to_screen_x(x: float) -> float:
	return (x - view_center.x) * zoom + size.x * 0.5

func _world_to_screen_y(y: float) -> float:
	return size.y * 0.5 - (y - view_center.y) * zoom

func _draw_grid() -> void:
	if grid_step <= 0.0:
		return

	var half_w_world = size.x * 0.5 / zoom
	var half_h_world = size.y * 0.5 / zoom

	var min_x = floor((view_center.x - half_w_world) / grid_step) * grid_step
	var max_x = ceil((view_center.x + half_w_world) / grid_step) * grid_step

	var min_y = floor((view_center.y - half_h_world) / grid_step) * grid_step
	var max_y = ceil((view_center.y + half_h_world) / grid_step) * grid_step

	# Vertical grid lines
	var x = min_x
	while x <= max_x:
		var sx = _world_to_screen_x(x)
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), grid_color, grid_width)
		x += grid_step

	# Horizontal grid lines
	var y = min_y
	while y <= max_y:
		var sy = _world_to_screen_y(y)
		draw_line(Vector2(0, sy), Vector2(size.x, sy), grid_color, grid_width)
		y += grid_step

func _clip_segment_liang_barsky(
	p0: Vector2,
	p1: Vector2,
	r: Rect2
) -> PackedVector2Array:
	var x_min = r.position.x
	var y_min = r.position.y
	var x_max = r.end.x
	var y_max = r.end.y

	var dx = p1.x - p0.x
	var dy = p1.y - p0.y

	var t0 = 0.0
	var t1 = 1.0

	var clip = func clip(p: float, q: float) -> bool:
		if is_zero_approx(p):
			return q >= 0.0
		var t = q / p
		if p < 0.0:
			if t > t1:
				return false
			if t > t0:
				t0 = t
		else:
			if t < t0:
				return false
			if t < t1:
				t1 = t
		return true

	if not clip.call(-dx, p0.x - x_min):
		return PackedVector2Array()
	if not clip.call(dx, x_max - p0.x):
		return PackedVector2Array()
	if not clip.call(-dy, p0.y - y_min):
		return PackedVector2Array()
	if not clip.call(dy, y_max - p0.y):
		return PackedVector2Array()

	var c0 = p0 + Vector2(dx * t0, dy * t0)
	var c1 = p0 + Vector2(dx * t1, dy * t1)

	var out := PackedVector2Array()
	out.append(c0)
	out.append(c1)
	return out


func _draw_axes() -> void:
	var half_w = size.x * 0.5
	var half_h = size.y * 0.5

	# Y axis (x = 0)
	if abs(view_center.x) * zoom <= half_w:
		var x = _world_to_screen(Vector2(0, 0)).x
		draw_line(Vector2(x, 0), Vector2(x, size.y), axis_color, axis_width)

	# X axis (y = 0)
	if abs(view_center.y) * zoom <= half_h:
		var y = _world_to_screen(Vector2(0, 0)).y
		draw_line(Vector2(0, y), Vector2(size.x, y), axis_color, axis_width)

func _draw_function() -> void:
	if not function.is_valid():
		return

	var r := Rect2(Vector2.ZERO, size)

	var step_px = 1.0 / samples_per_pixel
	var max_px = size.x + step_px
	var px = 0.0

	var prev_valid = false
	var prev_p = Vector2.ZERO
	var prev_x_world = 0.0

	while px <= max_px:
		var x_world = _screen_to_world_x(px)
		var res = function.call(x_world)

		if typeof(res) == TYPE_FLOAT or typeof(res) == TYPE_INT:
			var y_world = float(res)
			if not is_nan(y_world) and not is_inf(y_world):
				var p = _world_to_screen(Vector2(x_world, y_world)) + graph_offset

				# ---------- EXTRA POINT AT x = 0 ----------
				if prev_valid and prev_x_world < 0.0 and x_world > 0.0:
					var y0 = function.call(0.0)
					if typeof(y0) == TYPE_FLOAT or typeof(y0) == TYPE_INT:
						var y0f = float(y0)
						if not is_nan(y0f) and not is_inf(y0f):
							var p0 = _world_to_screen(Vector2(0.0, y0f)) + graph_offset
							var seg0 = _clip_segment_liang_barsky(prev_p, p0, r)
							if seg0.size() == 2:
								draw_line(seg0[0], seg0[1], graph_color, graph_width)
							prev_p = p0
				# -----------------------------------------

				if prev_valid:
					var seg = _clip_segment_liang_barsky(prev_p, p, r)
					if seg.size() == 2:
						draw_line(seg[0], seg[1], graph_color, graph_width)

				prev_p = p
				prev_x_world = x_world
				prev_valid = true
				px += step_px
				continue

		prev_valid = false
		px += step_px



func load_dump(_func: Callable, trans: Vector2, pixels_on_s: int = 1, offset_y: float = 0):
	samples_per_pixel = 1.0 / float(pixels_on_s)
	view_center = Vector2(0, trans.x)
	zoom = trans.y if not is_zero_approx(trans.y) else 33.0
	set_function(_func)
	graph_offset = Vector2(0, offset_y)
	queue_redraw()

@export var graph_offset: Vector2 = Vector2()
func _ready() -> void:
	pass
