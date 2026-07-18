extends Graph

var _dragging: Node = null
var drag_offset: Vector2

func _can_drag() -> bool:
	return not _dragging

func _just_connected(who: Connection, to: Connection):
	#if to.parent_graph.server_typename == "Flatten":
	#	to.parent_graph.set_count(cfg.rows * cfg.columns)
	graphs.push_2d(28, 28, to.parent_graph)

func _just_disconnected(who: Connection, to: Connection):
	pass

func _just_attached(other_conn: Connection, my_conn: Connection):
	if other_conn.parent_graph.server_typename == "InputNode":
		$TextureRect.texture = other_conn.parent_graph.get_node("TextureRect").texture
		await get_tree().process_frame
		repos()


func repos():
	var sz = $TextureRect.size
	OO.position = Vector2(0,0)
	OI.position = Vector2(0,sz.y-1)
	IO.position = Vector2(sz.x-1,0)
	II.position = sz-Vector2.ONE
	params()

func params():
	var to_img = $TextureRect._local_to_img_coords
	var param = func(name, vec):
		if name == "p00": 
			var zw = glob.inst_uniform_read($TextureRect, "p00_01")
			glob.inst_uniform($TextureRect, "p00_01", Vector4(vec.x, vec.y, zw.z, zw.w))
		if name == "p01": 
			var zw = glob.inst_uniform_read($TextureRect, "p00_01")
			glob.inst_uniform($TextureRect, "p00_01", Vector4(zw.x, zw.y, vec.x, vec.y))
		if name == "p10": 
			var zw = glob.inst_uniform_read($TextureRect, "p10_11")
			glob.inst_uniform($TextureRect, "p10_11", Vector4(vec.x, vec.y, zw.z, zw.w))
		if name == "p11": 
			var zw = glob.inst_uniform_read($TextureRect, "p10_11")
			glob.inst_uniform($TextureRect, "p10_11", Vector4(zw.x, zw.y, vec.x, vec.y))
	param.call("p00", to_img.call(OO.position))
	param.call("p01", to_img.call(OI.position))
	param.call("p10", to_img.call(IO.position))
	param.call("p11", to_img.call(II.position))

func _ready() -> void:
	super()
	if Engine.is_editor_hint(): return
	await get_tree().process_frame
	repos()

@export var OO: Sprite2D
@export var II: Sprite2D
@export var IO: Sprite2D
@export var OI: Sprite2D

func _after_process(delta: float):
	super(delta)
	var mouse_pos =  $TextureRect.get_local_mouse_position()

	if glob.mouse_just_pressed:
		for n in ["00", "01", "10", "11"]:
			var node = $TextureRect.get_node(n)
			var rect = Rect2(node.position - Vector2(5, 5), Vector2(10, 10)) # small grab box
			if rect.has_point(mouse_pos):
				_dragging = node
				drag_offset = node.position - mouse_pos
				break

	elif !glob.mouse_pressed:
		_dragging = null

	if _dragging and dragging:
		dragging = false
		drag_ended()
		if is_instance_valid(shadow):
			shadow.queue_free()
		putting_back = 0.0

	if _dragging:
		var k = $TextureRect.size / $TextureRect.texture.get_size()
		_dragging.position = (mouse_pos + drag_offset - k/2).snapped(k)
		_dragging.position.x = clamp(_dragging.position.x, 0, $TextureRect.size.x-1)
		_dragging.position.y = clamp(_dragging.position.y, 0, $TextureRect.size.y-1)
		hold_for_frame()

	var to_img = $TextureRect._local_to_img_coords
	var sc = $TextureRect.scale * 0.5
	params()
