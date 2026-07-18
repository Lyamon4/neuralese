@tool
extends Node2D
class_name Arrow2D

enum ArrowEnd {
	NONE,
	TRIANGLE,
	CIRCLE,
	SQUARE
}

@export var start: Vector2 = Vector2.ZERO :
	set(v):
		start = v
		queue_redraw()

@export var end: Vector2 = Vector2(200, 0) :
	set(v):
		end = v
		queue_redraw()

@export var color: Color = Color.WHITE :
	set(v):
		color = v
		queue_redraw()

@export_range(1.0, 20.0, 0.5)
var thickness: float = 3.0 :
	set(v):
		thickness = v
		queue_redraw()

@export var dashed: bool = false :
	set(v):
		dashed = v
		queue_redraw()

@export var dash_length: float = 10.0 :
	set(v):
		dash_length = v
		queue_redraw()

@export var gap_length: float = 6.0 :
	set(v):
		gap_length = v
		queue_redraw()

@export var start_end: ArrowEnd = ArrowEnd.NONE :
	set(v):
		start_end = v
		queue_redraw()

@export var end_end: ArrowEnd = ArrowEnd.TRIANGLE :
	set(v):
		end_end = v
		queue_redraw()

@export var end_size: float = 12.0 :
	set(v):
		end_size = v
		queue_redraw()


func _draw() -> void:
	if start == end:
		return

	var dir: Vector2 = (end - start).normalized()
	var len: float = start.distance_to(end)

	var shaft_start = start
	var shaft_end = end

	# Reserve space for end shapes
	var cap_offset := end_size * 0.5

	if start_end != ArrowEnd.NONE:
		shaft_start += dir * cap_offset
	if end_end != ArrowEnd.NONE:
		shaft_end -= dir * cap_offset


	if dashed:
		_draw_dashed_line(shaft_start, shaft_end)
	else:
		draw_line(shaft_start, shaft_end, color, thickness, false)

	_draw_end_shape(start, -dir, start_end)
	_draw_end_shape(end, dir, end_end)


func _draw_dashed_line(a: Vector2, b: Vector2) -> void:
	var total_len = a.distance_to(b)
	if total_len <= 0.0:
		return
	if gap_length < 0.1:
		return
	if dash_length < 0.1:
		return

	var dir = (b - a).normalized()
	var t = 0.0

	while t < total_len:
		var seg_start = a + dir * t
		var seg_end = a + dir * min(t + dash_length, total_len)
		draw_line(seg_start, seg_end, color, thickness, false)
		t += dash_length + gap_length


func _draw_end_shape(pos: Vector2, dir: Vector2, kind: ArrowEnd) -> void:
	if kind == ArrowEnd.NONE:
		return

	match kind:
		ArrowEnd.TRIANGLE:
			_draw_triangle(pos, dir)
		ArrowEnd.CIRCLE:
			draw_circle(pos, end_size * 0.5, color)
		ArrowEnd.SQUARE:
			_draw_square(pos, dir)


func _draw_triangle(pos: Vector2, dir: Vector2) -> void:
	var half := end_size * 0.5
	var right := dir.orthogonal() * half

	var tip := pos + dir * half
	var base := pos - dir * half

	var p1 := base + right
	var p2 := base - right

	draw_polygon(
		PackedVector2Array([tip, p1, p2]),
		PackedColorArray([color])
	)



func _draw_square(pos: Vector2, dir: Vector2) -> void:
	var half := end_size * 0.5
	var right := dir.orthogonal() * half
	var forward := dir * half

	var p1 := pos + forward + right
	var p2 := pos + forward - right
	var p3 := pos - forward - right
	var p4 := pos - forward + right

	draw_polygon(
		PackedVector2Array([p1, p2, p3, p4]),
		PackedColorArray([color])
	)
