extends Graph

var _dragging: Node = null
var drag_offset: Vector2

func _can_drag() -> bool:
	return not _dragging and not some_focus()


func some_focus():
	return ui.is_focus($Label4/HSlider) or ui.is_focus($Label5/HSlider) or ui.is_focus($Label6/HSlider)

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



func params():
	pass

func _ready() -> void:
	super()
	if Engine.is_editor_hint(): return
	await get_tree().process_frame
	#$TextureRect.texture.get_image().put_pixel()


func _after_process(delta: float):
	super(delta)
	var mouse_pos =  $TextureRect.get_local_mouse_position()

	var to_img = $TextureRect._local_to_img_coords
	var sc = $TextureRect.scale * 0.5
	params()

var lumi: float = 0.0
var cont: float = 0.0
var thres: float = 0.0

func upd():
	$TextureRect.set_instance_shader_parameter("vals", Vector4(lumi, cont, thres, 0))

func thre_changed(value: float) -> void:
	thres = 1.0-value / 100.0
	upd()


func lumi_changed(value: float) -> void:
	lumi = lerpf(-1, 1, value / 100.0, )
	upd()


func cont_changed(value: float) -> void:
	cont = lerpf(0, 2, value / 100.0, )
	upd()
