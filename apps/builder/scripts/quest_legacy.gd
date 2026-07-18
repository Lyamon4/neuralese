# QuestBubble.gd
extends Control

func _enter_tree():
	ui.quest = self

@export var scroll_cont: ScrollContainer

@export var row_spacing: float = 8.0
@export var layout_lerp_speed: float = 18.0

var indexed = []
var prev = null

@onready var cont = $ColorRect/ScrollContainer/c
var types = {}

var _content_h: float = 0.0

var tg: float = 0.0
var expand_target_node = null


func apply_extents():
	var sb = scroll_cont.get_v_scroll_bar()

	var o = scroll_cont.global_position.y + 5.0
	var i = global_position.y + scroll_cont.size.y * scale.y * scroll_cont.scale.y + 10.0
	var maxval = sb.max_value - sb.page - 5.0

	var base_top = o if sb.value > 5.0 else 0.0
	var base_bot = i if sb.value < maxval else 0.0

	var overlay_start = 0.0
	var overlay_cut = 0.0
	if prev:
		overlay_cut = prev.overlay_cut_y()
		if overlay_cut > 0.0:
			overlay_start = prev.overlay_start_y()
	
	for node in indexed:
		var top = base_top
		if overlay_cut > 0.0:
			if node.global_position.y >= overlay_start:
				top = max(top, overlay_cut + 15)
		glob.inst_uniform(node, "extents", Vector4(top, base_bot, 0, 0))


func _process(delta: float) -> void:
	tg += delta
	if tg > 0.0 and expand_target_node:
		if expand_target_node.mouse_is_in:
			expand_target_node.expand()
		expand_target_node = null

	if not visible:
		ui.upd_topr_inside(self, false)
		return

	var some = false
	var closest = {"who": null, "dist": INF}
	var mouse = get_global_mouse_position()
	var whole = $ColorRect.get_global_rect().end
	
	if mouse.x > whole.x - 90 and mouse.x < whole.x:
		for i in content():
			var r = i.get_global_rect()
			var center = r.position.y + 20.0
			if i.unit_type in i.press_dtypes and mouse.y > r.position.y - 30.0 and mouse.y < r.end.y + 30.0:
				var d = abs(center - mouse.y)
				if d < closest.dist:
					closest.dist = d
					closest.who = i

	if closest.who:
		some = true
		if closest.who != prev:
			if prev:
				prev.mouse_out()
			closest.who.mouse_in()
			prev = closest.who

	if not some and prev:
		prev.mouse_out()
		prev = null

	_smooth_layout(delta)
	apply_extents()

	if $ColorRect.get_global_rect().has_point(get_global_mouse_position()):
		ui.upd_topr_inside(self, true)
		glob.set_menu_type(self, "o")
	else:
		glob.reset_menu_type(self, "i")
		ui.upd_topr_inside(self, false)


func _smooth_layout(delta: float) -> void:
	var t = clamp(layout_lerp_speed * delta, 0.0, 1.0)

	var y = 0.0
	for dup in content():
		var ty = y
		dup.position.y = lerp(dup.position.y, ty, t)
		y += dup.size.y + row_spacing

	_content_h = lerp(_content_h, y, t)
	cont.custom_minimum_size.y = _content_h


func _snap_layout() -> void:
	var y = 0.0
	for dup in content():
		dup.position.y = y
		y += dup.size.y + row_spacing
	_content_h = y
	cont.custom_minimum_size.y = _content_h


func reindex():
	indexed.clear()
	$ColorRect/ScrollContainer/c.relayout()
	for i in $ColorRect/ScrollContainer/c.get_children():
		indexed.append_array(i.indexed)


func load_bubble(data: Dictionary):
	for i in content():
		i.queue_free()

	if data:
		layout_bubble(data)

	reindex()
	_snap_layout()


var selected_state = {}


func layout_bubble(data: Dictionary):
	var flags = data.flags
	var classes = glob.to_set("checkbox", "radio")
	var index_map = []
	var result = {}
	var child_map = []

	var answer_received = func answer_received(on: bool, index: int):
		child_map[index].set_persistent(on)
		if on:
			result[index] = true
		else:
			result.erase(index)

	for i in data["elements"]:
		var dup = types[i.type].duplicate()
		dup.passed_data = i

		dup.size.x = $ColorRect.size.x - 40
		cont.add_child(dup)

		if i.type in classes:
			dup.toggled.connect(answer_received.bind(len(index_map)))
			index_map.append(i)
			child_map.append(dup)

		dup.root = self
		dup.reinit()


func layout():
	for dup in content():
		dup.size.x = $ColorRect.size.x - 40
		dup.reinit()


func content():
	return cont.get_children()


func expand_target(node):
	if node != expand_target_node:
		tg = 0.0
	expand_target_node = node


func _ready() -> void:
	for i in content():
		types[i.name] = i
		cont.remove_child(i)

	$ColorRect/ScrollContainer.clip_contents = true

	load_bubble({
		"elements": [
			{"type": "text", "text": "Когда мы запустим модель, то, что получает последний узел, лучше всего описано как"},
			{"type": "radio", "text": glob.dummy_string},
			{"type": "radio", "text": "А) Вер оятности каждого кла ссаfgggg gggggfff ffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "radio", "text": "А) Вероятности каждого классаfgggggggggfffffffff"},
			{"type": "next", "text": ""},
		],
		"flags": {"show_correct": true, "correct_answers": [1]}
	})


func _on_ai_released() -> void:
	hide()


func _on_item_rect_changed() -> void:
	layout()
