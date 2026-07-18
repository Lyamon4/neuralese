@tool

extends TextureRect

@export var size_pix: Vector2i = Vector2i(28, 28)

@export var brush_radius: int = 4
@export var brush_hardness: float = 0.35
@export var flow_per_second: float = 1.75
@export var max_luma: float = 0.92
@export var headroom_power: float = 1.25

var image_texture: ImageTexture = null
var image: Image = null
var change_version: int = 0

var _was_drawing: bool = false
var _last_img_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	image = Image.create(size_pix.x, size_pix.y, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	if Engine.is_editor_hint():
		image.set_pixelv(size_pix/2, Color.WHITE/2)
	
	image_texture = ImageTexture.create_from_image(image)
	texture = image_texture
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL

func clear():
	image.fill(Color.BLACK)
	image_texture.update(image)
	change_version += 1

func put_pixel(coord: Vector2i, color: Color, reassign: bool = true):
	if coord > Vector2i() and coord < image.get_size() - Vector2i.ONE:
		image.set_pixelv(coord, color)
		if reassign:
			image_texture.update(image)

func get_pixel(coord: Vector2i) -> Color:
	if coord > Vector2i() and coord < image.get_size() - Vector2i.ONE:
		return image.get_pixelv(coord)
	return Color.BLACK

func reassign_image():
	image_texture.update(image)

var mouse_inside: bool = false
func _local_to_img_coords(local_pos: Vector2) -> Vector2:
	var rs: Vector2 = size
	if rs.x <= 0.0 or rs.y <= 0.0:
		return Vector2(-1, -1)
	var uv = local_pos / rs
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		mouse_inside = false
		return Vector2(-1, -1)
	mouse_inside = true
	return Vector2(uv.x * float(size_pix.x), uv.y * float(size_pix.y))

func _accumulate_circle_at(img_center: Vector2, dt: float) -> void:
	var min_x: int = int(floor(img_center.x)) - brush_radius
	var max_x: int = int(floor(img_center.x)) + brush_radius
	var min_y: int = int(floor(img_center.y)) - brush_radius
	var max_y: int = int(floor(img_center.y)) + brush_radius

	min_x = max(min_x, 0)
	min_y = max(min_y, 0)
	max_x = min(max_x, size_pix.x - 1)
	max_y = min(max_y, size_pix.y - 1)

	var r: float = float(brush_radius)
	if r <= 0.0:
		return

	var changed = false
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx = (float(x) + 0.5) - img_center.x
			var dy = (float(y) + 0.5) - img_center.y
			var dist = dx * dx + dy * dy
			if dist > r + 1:
				continue
			var nd = clamp(dist / r, 0.0, 1.0)
			var strength = pow(1.0 - nd, 2.0 - brush_hardness * 1.5)
			var curr = image.get_pixel(x, y).r
			var room = max(0.0, max_luma - curr)
			if room <= 0.0:
				continue
			var add_core = flow_per_second * dt * strength * pow(room, headroom_power)
			var next = min(max_luma, curr + add_core)
			if next > curr:
				image.set_pixel(x, y, Color(next, next, next, 1.0))
				changed = true

	if changed:
		image_texture.update(image)
		change_version += 1

func _add_headroom_limited(x: int, y: int, add: float, changed_ref: bool) -> void:
	var curr = image.get_pixel(x, y).r
	var room = max(0.0, max_luma - curr)
	if room <= 0.0:
		return
	var next = min(max_luma, curr + min(add, room))
	if next > curr:
		image.set_pixel(x, y, Color(next, next, next, 1.0))
		changed_ref = true

func _draw_segment(prev_img: Vector2, curr_img: Vector2, dt: float) -> void:
	var dist = prev_img.distance_to(curr_img)
	var step_px = max(1.0, float(brush_radius) * 0.5)
	var steps = int(ceil(dist / step_px))
	if steps <= 0:
		_accumulate_circle_at(curr_img, dt)
		return

	var dt_per_step = dt / float(steps + 1)
	for i in range(0, steps + 1):
		var t = float(i) / float(steps)
		var p = prev_img.lerp(curr_img, t)
		_accumulate_circle_at(p, dt_per_step)

@export var active: bool = true

var drawing: float = 50.0

var lst = Vector2()
func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if graphs.dragged: return
	if graphs.conning(): return
	if ui.selecting_box: return
	if ui.topr_inside: return
	
	var local = get_local_mouse_position()
	var img_pos = _local_to_img_coords(local)
	if !active: return

	if (not glob.get_occupied("graph") or glob.get_occupied("graph") == get_parent()) and not glob.is_occupied(self, "dropout_inside") and not \
	glob.is_occupied(self, "menu_inside") and Input.is_action_pressed("ui_mouse") and img_pos.x >= 0.0 and get_global_rect().has_point(glob.last_mouse_click_at):
		if _was_drawing:
			_draw_segment(_last_img_pos, img_pos, delta)
		else:
			_accumulate_circle_at(img_pos, delta)
		_last_img_pos = img_pos
		_was_drawing = true
		drawing = 0.5
	else:
		_was_drawing = false
	drawing -= delta
	if is_zero_approx(drawing): drawing = 0

	if Input.is_action_just_pressed("ui_accept") and mouse_inside:
		drawing = 1.0
		clear()
