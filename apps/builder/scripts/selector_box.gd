extends ColorRect

var selecting: bool = false
var select_origin: Vector2 = Vector2()

var target_pos: Vector2
var target_size: Vector2
@export var lerp_speed: float = 15.0  # higher = snappier

func _enter_tree() -> void:
	glob.selector_box = self

func _ready() -> void:
	hide()
	target_pos = position
	target_size = size

signal request_pan(direction: Vector2)


var select_origin_world: Vector2
var prev_cam_pos: Vector2


var to_screen: bool = false
var q: bool = false
func _process(delta: float) -> void:


	#(graphs.conning())
	if not visible:
		ui.selecting_box = false
	if not graphs.conning() or glob.f2_pressed:
		q = true
	else:
		selecting = false
		hide()
		ui.selecting_box = false
		q = false
	if glob.curr_window != "graph":
		hide()
		graphs.unselect_all()
	#if glob.mouse_just_pressed:
	#	print(ui.topr_inside)
	if not ui.topr_inside and q and not ui.active_splashed() and glob.mouse_just_pressed \
	and not glob.is_graph_inside() and not glob.is_occupied(self, "menu_inside") \
	and ((not graphs.dragged and not graphs.conning()) or glob.f2_pressed) and not ui.get_focus() and get_global_mouse_position().y > glob.space_begin.y \
	and not glob.is_occupied(self, "graph_buffer"):
		select_origin = get_global_mouse_position()
		select_origin_world = glob.canvas_to_world(select_origin)
		prev_cam_pos = glob.cam.position
		selecting = true
		ui.selecting_box = true
		show()
		position = select_origin
		size = Vector2.ZERO
		if glob.f2_pressed:
			to_screen = true
		else:
			to_screen = false
	if selecting:
		if not glob.mouse_pressed:
			if glob.f2_pressed:
				hide()
				graphs.unselect_all()
				await ui.graph_shot(Rect2(position, size), cookies.downloads_dir + "/screen_%s.png"%randi_range(0,9999))
				show()
			selecting = false
			hide()
			ui.selecting_box = false
			return
		if glob.cam.position != prev_cam_pos:
			var screen_now = glob.world_to_canvas(select_origin_world)
			select_origin = screen_now
			prev_cam_pos = glob.cam.position

		var curr = get_global_mouse_position()
		curr.y = max(curr.y, glob.space_begin.y)
		var diff = curr - select_origin

		# update target_size and target_pos
		if diff.x >= 0:
			target_size.x = diff.x
			target_pos.x = select_origin.x
		else:
			target_size.x = -diff.x
			target_pos.x = curr.x

		if diff.y >= 0:
			target_size.y = diff.y
			target_pos.y = select_origin.y
		else:
			target_size.y = -diff.y
			target_pos.y = curr.y

	# lerp position & size toward targets every frame
	position = position.lerp(target_pos, lerp_speed * delta)
	size = size.lerp(target_size, lerp_speed * delta)
	
	#if (glob.mouse_alt_just_pressed or glob.mouse_just_pressed) and !visible and not glob.get_occupied("graph"):
		#graphs.unselect_all()
	
	if visible:
		var raw = get_global_rect()
		var p1 = glob.canvas_to_world(raw.position)
		var p2 = glob.canvas_to_world(raw.position + raw.size)
		var rect = Rect2(p1, p2 - p1).abs()  # always positive size

		for g in graphs._graphs:
			var target = graphs._graphs[g].rect.get_global_rect().abs()
			if rect.intersects(target):
				graphs._graphs[g].select()
			else:
				graphs._graphs[g].unselect()

	if selecting and visible and (size.x > 20 or size.y > 20) and !glob.f2_pressed:
		var vp_rect = get_viewport_rect()
		var mouse = get_viewport().get_mouse_position()
		var edge_margin = 80.0  # pixels from edge where panning starts
		var intensity = Vector2.ZERO

		if mouse.x < edge_margin:
			intensity.x = -inverse_lerp(edge_margin, 0.0, mouse.x)
		elif mouse.x > vp_rect.size.x - edge_margin:
			intensity.x = inverse_lerp(vp_rect.size.x - edge_margin, vp_rect.size.x, mouse.x)

		if mouse.y < edge_margin:
			intensity.y = -inverse_lerp(edge_margin, 0.0, mouse.y)
		elif mouse.y > vp_rect.size.y - edge_margin:
			intensity.y = inverse_lerp(vp_rect.size.y - edge_margin, vp_rect.size.y, mouse.y)

		if intensity != Vector2.ZERO:
			emit_signal("request_pan", intensity)
