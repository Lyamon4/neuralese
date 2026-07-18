extends Quest

func _ready() -> void:
	super()
	say(["w".repeat(20)], false, false)

func _enter_tree():
	pass

func topr_update(boolean: bool):
	pass

func apply_extents():
	var sb = scroll_cont.get_v_scroll_bar()

	var o = scroll_cont.global_position.y
	var i = global_position.y + scroll_cont.size.y * scale.y * scroll_cont.scale.y+3
	var maxval = sb.max_value - sb.page

	var top = o if sb.value > 5.0 else 0.0
	var bot = i if sb.value < maxval else 0.0
	
	for node in indexed:
		glob.inst_uniform(node, "extents", Vector4(top, bot, 0, 0))

func show_anim(data_: Dictionary):
	show()
	$ColorRect.position = Vector2(-30, 0)
	glob.tween_call({"t": 0},
		func(data, delta): 
			data.t += delta / 1
			$ColorRect.position = -$ColorRect.size / 2
			scale = Vector2.ONE * \
			glob.spring(1 * 0.5, 1, data.t, 4, 16, 1)
			$ColorRect.modulate.a = glob.lerp_expo_out(0.0, 1.0, data.t)
			if data.t > 0.5:
				$ColorRect.modulate.a = 1
				scale = Vector2.ONE
				return true
			)
	for i in content():
		if is_instance_valid(i) and i.unit_type in (i.check_dtypes if data.type == "check" else i.text_dtypes):
			i.modulate.a = 1

func autosize_bubble():
	var viewport = get_viewport_rect().size
	var max_h = viewport.y * MAX_SCREEN_RATIO
	var longest_text = 0
	scroll_cont.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for node in content():
		if node.unit_type == BubbleUnit.UnitType.Text:
			longest_text = max(longest_text, node.get_node('text').get_content_width())
	var est_width =longest_text
	$ColorRect.size.x = (longest_text + 18)
	
	_snap_layout()
	var natural_h = _content_h + V_PADDING
	var final_h = natural_h
	final_h = max(final_h, MIN_HEIGHT_PX)
	$ColorRect.size.y = final_h
	scroll_cont.size.y = final_h

func layout():
	scroll_cont.get_v_scroll_bar().value = 0
	_snap_layout()
	await get_tree().process_frame
	var is_scrolling = _content_h + 19 > scroll_cont.size.y
	for dup in content():
		dup.size.x = $ColorRect.size.x
		dup.reinit()
	_snap_layout()

func hide_anim():
	await glob.tween_call({"t": 0},
		func(data, delta): 
			data.t += delta * 2
			$ColorRect.position.x = glob.lerp_expo_in(0, 30, data.t)
			$ColorRect.modulate.a = glob.lerp_expo_in(1.0, 0.0, data.t)
			if data.t > 1.0:
				return true
			)
	hide()
