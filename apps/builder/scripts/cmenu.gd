@tool
extends BlockComponent

@export var name_groups: Array[PackedStringArray] = []
@export var skip: Array[String] = []

var _button_template: BlockComponent = null


func _rebuild_buttons(names: Array[StringName]) -> void:
	var was_open = visible and (state.expanding or state.expanded) and not state.tween_hide

	_clear_contained_buttons_hard()

	for n: StringName in names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue
		var btn := _instantiate_button(def)
		add_child(btn)
		contain(btn)
		btn.modulate.a = 0.0

	# Phase A: immediate layout
	_recalc_sizes_after_rebuild()
	arrange()
	#(_contained)
	update_children_reveal()

	# If menu is currently open, DO NOT rely on expand animation to show the bar.
	if was_open:
		_arm_menu_hit_tests()
		size.y = (expanded_size if not max_size else min(max_size, expanded_size)) + size_add
		_apply_scrollbar_alpha_now()
	# Phase B: next frame settle (this fixes "bar appears only after hide/show" + width padding)
	_settle_after_rebuild.call_deferred()

func _settle_after_rebuild() -> void:
	await get_tree().process_frame

	_recalc_sizes_after_rebuild()
	arrange()

	if not state.expanding and not state.holding:
		_apply_scrollbar_alpha_now()
	
	update_children_reveal()
	update_children_reveal.call_deferred()

func _menu_hiding():
	$Label2.text = ""
	apply_filter("")

func _recalc_sizes_after_rebuild() -> void:
	# Compute raw content height from contained button base sizes.
	# This becomes correct after 1-frame settle.
	var content := float(base_size.y) + float(size_add)
	for c in _contained:
		if not is_instance_valid(c):
			continue
		content += float(floor(_contained_child_height(c) + arrangement_padding.y))

	_content_height_raw = content

	_unclamped_expanded_size = int(content)
	var desired := float(_unclamped_expanded_size) + float(lerp_size_offset)

	# Keep fixed menu size when content is small:
	if max_size != 0:
		desired = max(desired, float(max_size))

	expanded_size = int(desired)

	# "Needs scroll" must be based on RAW content, not expanded_size (because expanded_size is clamped)
	_needs_scroll = (max_size != 0) and (_content_height_raw + float(lerp_size_offset) > float(max_size) + 0.5)

	if scroll and is_instance_valid(scroll):
		scroll.size = Vector2(
			base_size.x - scrollbar_padding,
			expanded_size if not max_size else max_size - base_size.y - 10
		)


func _apply_scrollbar_alpha_now() -> void:
	if bar == null or not is_instance_valid(bar):
		return

	# If no scrolling is needed, fade it out immediately (no visibility toggles).
	# If scrolling is needed, make it visible immediately (don’t wait for state.expanding).
	bar.self_modulate.a = 1.0 if _needs_scroll else 0.0

	# Also ensure scroll position is sane when switching filter sets
	if scroll and is_instance_valid(scroll):
		if scroll.scroll_vertical != 0:
			scroll.scroll_vertical = 0
	if bar and is_instance_valid(bar):
		if bar.value != 0:
			bar.value = 0


func _clear_contained_buttons_hard() -> void:
	button_by_hint.clear()

	# IMPORTANT: must be immediate free; queue_free causes 1-frame ghosts -> wrong bar/max/page/extents.
	if vbox != null and is_instance_valid(vbox):
		for node in vbox.get_children():
			node.free()

	_contained.clear()

# name(StringName) -> {hint, title, outline_color, tuning}
var _def_by_name: Dictionary = {}
var _ordered_names: Array[StringName] = []

var _last_filter: String = ""


func _menu_handle_release(button: BlockComponent):
	var type = button.hint
	var graph = graphs.get_graph(type, Graph.Flags.NEW)

	var world_pos = graphs.get_global_mouse_position()
	graph.global_position = world_pos - graph.rect.position - graph.rect.size / 2
	menu_hide()


func _ready():
	if Engine.is_editor_hint():
		return
	glob.language_changed.connect(apply_filter.bind(""))

	_button_template = $"5".duplicate()

	for child in get_children():
		if child is BlockComponent:
			child.free()

	name_groups = get_parent().namings

	_build_defs_and_order()

	# Initial build: add as normal children; BlockComponent.initialize() in super() will contain them.
	for n: StringName in _ordered_names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue
		var btn := _instantiate_button(def)
		add_child(btn)
	super()

var first = true

func _showing():
	_build_defs_and_order()
	_rebuild_buttons(_ordered_names)
	if first:
		$Label2.modulate.a = 0
		first = false

# ============================================================
# Public API
# ============================================================

var pending = false
var _queued_filter_text: String = ""
var _has_queued_filter: bool = false
func apply_filter(filter_text: String) -> void:
	if Engine.is_editor_hint():
		return
	if pending:
		_queued_filter_text = filter_text
		_has_queued_filter = true
		return
	pending = true
	apply_task.call_deferred(filter_text)


func _finish_filter_task(completed_filter: String) -> void:
	pending = false
	if not _has_queued_filter:
		return
	var next_filter := _queued_filter_text
	_queued_filter_text = ""
	_has_queued_filter = false
	if next_filter != completed_filter:
		apply_filter(next_filter)

func apply_task(filter_text):
	if not is_node_ready():
		await ready

	_last_filter = filter_text
	var f = filter_text.strip_edges().to_lower()

	if f == "":
		_rebuild_buttons(_ordered_names)
		await get_tree().process_frame
		_finish_filter_task(filter_text)
		return

	# AND-match tokens
	var tokens: PackedStringArray = f.split(" ", false)

	var filtered: Array[StringName] = []
	for n: StringName in _ordered_names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue
		var tit = def.title
		match glob.curr_lang:
			"ru":
				tit = def.title_ru
			"kz":
				tit = def.title_kz
		var title_lc: String = str(tit).to_lower()
		var ok := true
		for t in tokens:
			if t == "":
				continue
			if title_lc.find(t) == -1:
				ok = false
				break
		if ok:
			filtered.append(n)

	_rebuild_buttons(filtered)
	await get_tree().process_frame
	_finish_filter_task(filter_text)


# ============================================================
# Definitions + canonical order
# ============================================================

func ru_title(i: Dictionary):
	var title: String = i.title_ru
	match i.name:
		"model_name":  title = "ИмяМодели"
		"neuron":      title = "Активация"
		"softmax":     title = "Софтмакс"
		"classifier":  title = "ВыводОтвет"
		"layer":       title = "ПлотнСлой"
		"conv2d":      title = "СвёртСлой2D"
		"flatten":     title = "Плоск1D"
		"lua_env":     title = "РЛПространтв"
		"train_input": title = "ШагОбучения"
		"input":       title = "Ввод2D"
	return title

func kz_title(i: Dictionary):
	var title: String = i.title_ru
	match i.name:
		"model_name":  title = "МодельАтауы"
		"neuron":      title = "Активация"
		"softmax":     title = "Софтмакс"
		"classifier":  title = "ҚорытЖауап"
		"layer":       title = "ТығызҚабат"
		"conv2d":      title = "СвёртҚабат2D"
		"flatten":     title = "Жазық1D"
		"lua_env":     title = "РЛКеңістік"
		"train_input": title = "ОқытуҚадам"
		"input":       title = "Кіріс2D"
	return title

var inputs = glob.to_set(["input_1d", "input"])

func _build_defs_and_order() -> void:
	_def_by_name.clear()
	_ordered_names.clear()
	#print((graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)))
	for i in graphs.graph_buttons:
		if not i.name in glob.base_node.importance_chain:
			continue
		#print((i.name in inputs and is_instance_valid(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME))))
		if i.name in skip or (not glob.multi_input and i.name in inputs and is_instance_valid(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME))):
			#print(i.name)
			continue

		var title: String = i.title
		match i.name:
			"model_name":  title = "ModelName"
			"neuron":      title = "Activation"
			"softmax":     title = "Softmax"
			"layer":       title = "DenseLayer"
			"conv2d":      title = "Conv2DLayer"
			"flatten":     title = "Flatten1D"
			"lua_env":     title = "RLEnviron"
			"train_input": title = "TrainStep"
			"input":       title = "Input2D"
		

		if i.name == "flatten" or i.name == "reshape2d":
			i.outline_color = Color(1.0, 0.722, 0.957)
		if i.name == "classifier":
			i.outline_color = Color(0.605, 0.84, 0.773, 1.0)
			i.tuning_color = Color(0.051, 0.051, 0.051, 0.541)
		var outline_color: Color = _lift_color(i.outline_color, 0.65)
		var tuning_color: Color = _lift_color(i.tuning, 0.65)
		tuning_color.a = 0.7

		var key: StringName = StringName(i.name)
		_def_by_name[key] = {
			"hint": key,
			"title": title,
			"title_ru": ru_title(i),
			"title_kz": kz_title(i),
			"outline_color": outline_color,
			"tuning": tuning_color,
		}

	# order: groups first, then remaining in discovery order
	var used: Dictionary = {}

	for group in name_groups:
		for name in group:
			var key: StringName = StringName(name)
			if _def_by_name.has(key) and not used.has(key):
				_ordered_names.append(key)
				used[key] = true

	for i in graphs.graph_buttons:
		var key: StringName = StringName(i.name)
		if _def_by_name.has(key) and not used.has(key):
			_ordered_names.append(key)
			used[key] = true
var _content_height_raw: float = 0.0
var _needs_scroll: bool = false

# ============================================================
# Rebuild core
# ============================================================


func _call_reveal_next_frame() -> void:
	# one-frame settle for scrollbar page/max, extents propagation
	await get_tree().process_frame
	update_children_reveal()




func _instantiate_button(def: Dictionary) -> BlockComponent:
	var dup: BlockComponent = _button_template.duplicate()
	dup.hint = def.hint
	match glob.curr_lang:
		"en":
			dup.text = def.title
		"ru":
			dup.text = def.title_ru
		"kz":
			dup.text = def.title_kz
	dup.set_instance_shader_parameter("outline_color", def.outline_color)
	dup.set_instance_shader_parameter("tuning", def.tuning)
	return dup

# ============================================================
# Color helpers (unchanged)
# ============================================================

func _lift_color(c: Color, min_v: float = 0.55) -> Color:
	var hsv = _rgb_to_hsv(c)
	if hsv.v < min_v:
		hsv.v = min_v
	return _hsv_to_rgb(hsv.h, hsv.s, hsv.v, c.a)


func _rgb_to_hsv(c: Color) -> Dictionary:
	var r = c.r
	var g = c.g
	var b = c.b
	var max_c = max(r, g, b)
	var min_c = min(r, g, b)
	var delta = max_c - min_c
	var h = 0.0
	if delta != 0.0:
		if max_c == r:
			h = fmod((g - b) / delta, 6.0)
		elif max_c == g:
			h = ((b - r) / delta) + 2.0
		else:
			h = ((r - g) / delta) + 4.0
	h *= 60.0
	if h < 0.0:
		h += 360.0
	var s = 0.0 if max_c == 0.0 else delta / max_c
	return {"h": h / 360.0, "s": s, "v": max_c}


func _hsv_to_rgb(h: float, s: float, v: float, a: float = 1.0) -> Color:
	h *= 6.0
	var i = int(floor(h)) % 6
	var f = h - floor(h)
	var p = v * (1.0 - s)
	var q = v * (1.0 - f * s)
	var t = v * (1.0 - (1.0 - f) * s)
	match i:
		0:
			return Color(v, t, p, a)
		1:
			return Color(q, v, p, a)
		2:
			return Color(p, v, t, a)
		3:
			return Color(p, q, v, a)
		4:
			return Color(t, p, v, a)
		_:
			return Color(v, p, q, a)


func _on_label_2_changed() -> void:
	apply_filter($Label2.text)
