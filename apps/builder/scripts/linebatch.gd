@tool

extends MultiMeshInstance2D
class_name LineDrawer2D

@export var default_thickness: float = 2.0
@export var use_per_instance_color: bool = true
@export var constant_color: Color = Color.WHITE 


func _ready() -> void:
	if multimesh == null:
		multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = use_per_instance_color
	multimesh.use_custom_data = false 
	
	if multimesh.mesh == null:
		multimesh.mesh = _make_unit_quad_mesh()
	
	if !use_per_instance_color:
		modulate = constant_color

func set_count(n: int) -> void:
	multimesh.instance_count = max(n, 0)

func set_line(idx: int, a: Vector2, b: Vector2, thickness: float = default_thickness, color: Color = Color.WHITE) -> void:
	if idx < 0 or idx >= multimesh.instance_count:
		return
	
	var d: Vector2 = b - a
	var len = d.length()
	if len < 0.0001:
		if use_per_instance_color:
			var c = color; c.a = 0.0
			multimesh.set_instance_color(idx, c)
		return

	var angle = d.angle()
	var center = (a + b) * 0.5

	var cos_a = cos(angle)
	var sin_a = sin(angle)
	var x_col = Vector2(cos_a, sin_a) * len
	var y_col = Vector2(-sin_a, cos_a) * thickness
	var xf = Transform2D(x_col, y_col, center)

	multimesh.set_instance_transform_2d(idx, xf)

	if use_per_instance_color:
		multimesh.set_instance_color(idx, color)

	var seg_bounds = Rect2(a, Vector2.ZERO).expand(b)
	seg_bounds = seg_bounds.grow(thickness * 0.5 + 1.0)

func hide_line(idx: int) -> void:
	if idx < 0 or idx >= multimesh.instance_count:
		return
	if use_per_instance_color:
		var c = multimesh.get_instance_color(idx)
		c.a = 0.0
		multimesh.set_instance_color(idx, c)
	else:
		var xf = multimesh.get_instance_transform_2d(idx)
		xf.x = Vector2.ZERO
		xf.y = Vector2.ZERO
		multimesh.set_instance_transform_2d(idx, xf)

func clear_all(alpha_only: bool = true) -> void:
	var n = multimesh.instance_count
	if use_per_instance_color and alpha_only:
		for i in n:
			var c = multimesh.get_instance_color(i)
			if c.a != 0.0:
				c.a = 0.0
				multimesh.set_instance_color(i, c)
	else:
		for i in n:
			hide_line(i)

func _make_unit_quad_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	var verts = PackedVector2Array([
		Vector2(-0.5, -0.5),
		Vector2( 0.5, -0.5),
		Vector2( 0.5,  0.5),
		Vector2(-0.5,  0.5),
	])
	var uvs = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])
	var indices = PackedInt32Array([0, 1, 2, 0, 2, 3])

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
