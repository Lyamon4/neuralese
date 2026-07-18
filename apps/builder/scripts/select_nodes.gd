@tool
extends BlockComponent
# select_nodes menu
@export var name_groups: Array[PackedStringArray] = []
@export var skip: Array[String] = []
@export var reset_list_on_hide: bool = true

var _button_template: BlockComponent = null

# name(StringName) -> {hint, title, title_ru, title_kz, outline_color, tuning}
var _def_by_name: Dictionary = {}
var _ordered_names: Array[StringName] = []

# Current optional source list.
# Search/filter works ONLY inside this list.
var _source_names: Array[StringName] = []
var _requested_items: Array = []
var _use_requested_list: bool = false

# Lowercase aliases:
# "input" -> &"input"
# "input2d" -> &"input"
# "Input2D" comes in as "input2d", so it resolves properly.
var _name_alias_to_key: Dictionary = {}

var _last_filter: String = ""

var _content_height_raw: float = 0.0
var _needs_scroll: bool = false

var pending: bool = false
var first: bool = true

var inputs = glob.to_set(["input_1d", "input"])


# ============================================================
# Public API
# ============================================================

func show_nodes(items: Array = [], at_pos: Vector2 = Vector2.ZERO, use_mouse_pos: bool = true, add_call: Callable = glob.def, custom_node_pos: Vector2 = Vector2.INF) -> void:
	if Engine.is_editor_hint():
		return

	if not is_node_ready():
		await ready

	_requested_items = items.duplicate()
	_use_requested_list = not _requested_items.is_empty()
	
	if use_mouse_pos:
		at_pos = get_global_mouse_position()
	custom_pos = custom_node_pos

	# IMPORTANT:
	# menu_show() calls _showing(), and _showing() now respects _requested_items.
	additional_call = add_call
	menu_show(pos_clamp(at_pos))

	state.holding = false
	unblock_input(true)

var additional_call : Callable = glob.def

func menu_show(at_position: Vector2) -> void:
	_showing()
	last_moda = 0.0
	state.expand_t = 0
	if static_mode:
		unroll()
		await get_tree().process_frame
		update_children_reveal()
		return
	if graphs.conning(): return
	if not _proceed_show(at_position): return
	if glob.get_display_mouse_position().y < glob.space_begin.y: return
	#(glob.menu_type)
	#(name)
	if button_type == ButtonType.CONTEXT_MENU and not secondary and _is_not_menu(): 
		#if name == "edit_graph":
		return
	_arm_menu_hit_tests()
	bar.self_modulate.a = 0.0
	state.expanded = false
	show()
	scrolling = false

	last_mouse_pos = at_position
	show_request = true
	scaler.scale = base_scale
	state.tween_hide = false
	state.holding = true
	state.expanding = false
	anchor_position = at_position
	if expand_upwards:
		position = at_position - Vector2(0, base_size.y)
	else:
		position = at_position
	size.y = base_size.y if expand_anim else expanded_size
	modulate = default_modulate
	update_children_reveal()
	await get_tree().process_frame
	update_children_reveal()


func show_all_nodes(at_pos: Vector2 = Vector2.ZERO, use_mouse_pos: bool = true) -> void:
	if Engine.is_editor_hint():
		return

	_requested_items.clear()
	_use_requested_list = false

	if use_mouse_pos:
		at_pos = get_global_mouse_position()

	menu_show(pos_clamp(at_pos))

	state.holding = false
	unblock_input(true)


func set_node_list(items: Array) -> void:
	_requested_items = items.duplicate()
	_use_requested_list = not _requested_items.is_empty()

	_build_defs_and_order()
	_source_names = _resolve_requested_names()

	apply_filter(_last_filter)


func clear_node_list() -> void:
	_requested_items.clear()
	_use_requested_list = false

	_build_defs_and_order()
	_source_names = _ordered_names.duplicate()

	apply_filter(_last_filter)


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	glob.language_changed.connect(apply_filter.bind(""))

	_button_template = $"5".duplicate()

	for child in get_children():
		if child is BlockComponent:
			child.free()

	name_groups = get_parent().namings

	_build_defs_and_order()
	_source_names = _ordered_names.duplicate()

	# Initial build: add as normal children;
	# BlockComponent.initialize() in super() will contain them.
	for n: StringName in _source_names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue

		var btn: BlockComponent = _instantiate_button(def)
		add_child(btn)

	super()


func _showing() -> void:
	_build_defs_and_order()
	_source_names = _resolve_requested_names()

	var names = _filter_names(_last_filter)
	_rebuild_buttons(names)

	if first:
		$Label2.modulate.a = 0.0
		first = false


func _menu_hiding() -> void:
	$Label2.text = ""
	_last_filter = ""

	if reset_list_on_hide:
		_requested_items.clear()
		_use_requested_list = false
		_source_names = _ordered_names.duplicate()

	apply_filter("")


# ============================================================
# Search / Filter
# ============================================================

func apply_filter(filter_text: String) -> void:
	if Engine.is_editor_hint():
		return

	if pending:
		return

	pending = true
	apply_task.call_deferred(filter_text)


func apply_task(filter_text: String) -> void:
	if not is_node_ready():
		await ready

	_last_filter = filter_text

	var names = _filter_names(filter_text)

	_rebuild_buttons(names)

	await get_tree().process_frame
	pending = false


func _filter_names(filter_text: String) -> Array[StringName]:
	var f: String = filter_text.strip_edges().to_lower()

	if f == "":
		return _source_names.duplicate()

	var tokens: PackedStringArray = f.split(" ", false)

	var filtered: Array[StringName] = []

	for n: StringName in _source_names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue

		var title = def.title

		match glob.curr_lang:
			"ru":
				title = def.title_ru
			"kz":
				title = def.title_kz

		var title_lc: String = str(title).to_lower()
		var name_lc: String = str(n).to_lower()

		var ok: bool = true

		for t in tokens:
			if t == "":
				continue

			var token: String = str(t).to_lower()
			var found: bool = title_lc.find(token) != -1 or name_lc.find(token) != -1

			if not found:
				ok = false
				break

		if ok:
			filtered.append(n)

	return filtered


# ============================================================
# Optional list resolving
# ============================================================

func _resolve_requested_names() -> Array[StringName]:
	if not _use_requested_list:
		return _ordered_names.duplicate()
	
	var result: Array[StringName] = []
	var used: Dictionary = {}

	for item in _requested_items:
		var key: StringName = _resolve_item_to_name(item)
		
		if key == &"":
			continue

		if not _def_by_name.has(key):
			continue

		if used.has(key):
			continue

		result.append(key)
		used[key] = true
	
	return result


func _resolve_item_to_name(item) -> StringName:
	if item is StringName:
		return _resolve_text_to_name(str(item))

	if item is String:
		return _resolve_text_to_name(item)

	if item is Dictionary:
		if item.has("name"):
			return _resolve_text_to_name(str(item["name"]))

		if item.has("hint"):
			return _resolve_text_to_name(str(item["hint"]))

		if item.has("title"):
			return _resolve_text_to_name(str(item["title"]))

		if item.has("type"):
			return _resolve_text_to_name(str(item["type"]))

		return &""

	if item is BlockComponent:
		if item.hint != &"":
			return _resolve_text_to_name(str(item.hint))

		if item.text != "":
			return _resolve_text_to_name(item.text)

		return &""

	if item is Object:
		if not is_instance_valid(item):
			return &""

		var name_value = item.get("name")
		if name_value != null:
			var resolved_from_name: StringName = _resolve_text_to_name(str(name_value))
			if resolved_from_name != &"":
				return resolved_from_name

		var hint_value = item.get("hint")
		if hint_value != null:
			var resolved_from_hint: StringName = _resolve_text_to_name(str(hint_value))
			if resolved_from_hint != &"":
				return resolved_from_hint

		var title_value = item.get("title")
		if title_value != null:
			var resolved_from_title: StringName = _resolve_text_to_name(str(title_value))
			if resolved_from_title != &"":
				return resolved_from_title

	return &""


func _resolve_text_to_name(text_value: String) -> StringName:
	var raw: String = text_value.strip_edges()
	
	if raw == "":
		return &""

	var direct_key: StringName = StringName(raw)

	if _def_by_name.has(direct_key):
		return direct_key

	var lc: String = raw.to_lower()
	if _name_alias_to_key.has(lc):
		return _name_alias_to_key[lc]

	var compact: String = _compact_alias(raw)
	if _name_alias_to_key.has(compact):
		return _name_alias_to_key[compact]

	return &""


func _register_alias(alias_value, key: StringName) -> void:
	var alias: String = str(alias_value).strip_edges()

	if alias == "":
		return

	_name_alias_to_key[alias.to_lower()] = key
	_name_alias_to_key[_compact_alias(alias)] = key


func _compact_alias(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")


# ============================================================
# Button rebuild core
# ============================================================

func _rebuild_buttons(names: Array[StringName]) -> void:
	var was_open: bool = visible and (state.expanding or state.expanded) and not state.tween_hide

	_clear_contained_buttons_hard()

	for n: StringName in names:
		var def = _def_by_name.get(n, null)
		if def == null:
			continue

		var btn: BlockComponent = _instantiate_button(def)
		add_child(btn)
		contain(btn)
		btn.modulate.a = 0.0

	# Phase A: immediate layout.
	_recalc_sizes_after_rebuild()
	arrange()
	update_children_reveal()

	# If menu is currently open, do not rely on expand animation to show the bar.
	if was_open:
		_arm_menu_hit_tests()
		size.y = (expanded_size if not max_size else min(max_size, expanded_size)) + size_add
		_apply_scrollbar_alpha_now()

	# Phase B: next-frame settle.
	_settle_after_rebuild.call_deferred()


func _settle_after_rebuild() -> void:
	await get_tree().process_frame

	_recalc_sizes_after_rebuild()
	arrange()

	if not state.expanding and not state.holding:
		_apply_scrollbar_alpha_now()

	update_children_reveal()
	update_children_reveal.call_deferred()


func _recalc_sizes_after_rebuild() -> void:
	var content: float = float(base_size.y) + float(size_add)

	for c in _contained:
		if not is_instance_valid(c):
			continue

		content += float(floor(_contained_child_height(c) + arrangement_padding.y))

	_content_height_raw = content

	_unclamped_expanded_size = int(content)

	var desired: float = float(_unclamped_expanded_size) + float(lerp_size_offset)

	# Keep fixed menu size when content is small.
	if max_size != 0:
		desired = max(desired, float(max_size))

	expanded_size = int(desired)

	# Needs-scroll must be based on raw content, not expanded_size.
	_needs_scroll = (max_size != 0) and (_content_height_raw + float(lerp_size_offset) > float(max_size) + 0.5)

	if scroll and is_instance_valid(scroll):
		scroll.size = Vector2(
			base_size.x - scrollbar_padding,
			expanded_size if not max_size else max_size - base_size.y - 10
		)


func _apply_scrollbar_alpha_now() -> void:
	if bar == null or not is_instance_valid(bar):
		return

	bar.self_modulate.a = 1.0 if _needs_scroll else 0.0

	if scroll and is_instance_valid(scroll):
		if scroll.scroll_vertical != 0:
			scroll.scroll_vertical = 0

	if bar and is_instance_valid(bar):
		if bar.value != 0:
			bar.value = 0


func _clear_contained_buttons_hard() -> void:
	button_by_hint.clear()

	# Immediate free is intentional.
	# queue_free() causes one-frame ghosts and wrong scroll/page/extents.
	if vbox != null and is_instance_valid(vbox):
		for node in vbox.get_children():
			node.free()

	_contained.clear()


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
		_:
			dup.text = def.title

	dup.set_instance_shader_parameter("outline_color", def.outline_color)
	dup.set_instance_shader_parameter("tuning", def.tuning)

	return dup


# ============================================================
# Release behavior
# ============================================================

var custom_pos: Vector2 = Vector2.INF

func _menu_handle_release(button: BlockComponent) -> void:
	var type: StringName = button.hint

	var call: Callable = additional_call
	var node_pos: Vector2 = custom_pos

	additional_call = glob.def
	custom_pos = Vector2.INF

	glob.open_action_batch()

	await glob.wait(1, true)

	var graph = graphs.get_graph(type, Graph.Flags.NEW)

	if call.is_valid() and not call.is_null():
		await call.call()

	var world_pos = graphs.get_global_mouse_position()
	if node_pos != Vector2.INF:
		world_pos = node_pos

	graph.global_position = world_pos - graph.rect.position - graph.rect.size / 2
	graph.refresh_create_action_snapshot()
	menu_hide()

	await glob.wait(2, true)
	glob.close_action_batch()


# ============================================================
# Definitions + canonical order
# ============================================================

func ru_title(i: Dictionary):
	var title: String = i.title_ru

	match i.name:
		"model_name":
			title = "ИмяМодели"
		"neuron":
			title = "Активация"
		"softmax":
			title = "Софтмакс"
		"classifier":
			title = "ВыводОтвет"
		"layer":
			title = "ПлотнСлой"
		"conv2d":
			title = "СвёртСлой2D"
		"flatten":
			title = "Плоск1D"
		"lua_env":
			title = "РЛПространтв"
		"train_input":
			title = "ШагОбучения"
		"input":
			title = "Ввод2D"

	return title


func kz_title(i: Dictionary):
	var title: String = i.title_ru

	match i.name:
		"model_name":
			title = "МодельАтауы"
		"neuron":
			title = "Активация"
		"softmax":
			title = "Софтмакс"
		"classifier":
			title = "ҚорытЖауап"
		"layer":
			title = "ТығызҚабат"
		"conv2d":
			title = "СвёртҚабат2D"
		"flatten":
			title = "Жазық1D"
		"lua_env":
			title = "РЛКеңістік"
		"train_input":
			title = "ОқытуҚадам"
		"input":
			title = "Кіріс2D"

	return title


func _build_defs_and_order() -> void:
	_def_by_name.clear()
	_ordered_names.clear()
	_name_alias_to_key.clear()

	for i in graphs.graph_buttons:
		if not i.name in glob.base_node.importance_chain:
			continue

		if i.name in skip:# or (i.name in inputs and is_instance_valid(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME))):
			continue

		var title: String = i.title

		match i.name:
			"model_name":
				title = "ModelName"
			"neuron":
				title = "Activation"
			"softmax":
				title = "Softmax"
			"classifier":
				title = "Classifier"
			"layer":
				title = "DenseLayer"
			"conv2d":
				title = "Conv2DLayer"
			"flatten":
				title = "Flatten1D"
			"lua_env":
				title = "RLEnviron"
			"train_input":
				title = "TrainStep"
			"input":
				title = "Input2D"

		if i.name == "flatten" or i.name == "reshape2d":
			i.outline_color = Color(1.0, 0.722, 0.957)

		if i.name == "classifier":
			i.outline_color = Color(0.605, 0.84, 0.773, 1.0)
			i.tuning_color = Color(0.051, 0.051, 0.051, 0.541)

		var outline_color: Color = _lift_color(i.outline_color, 0.65)
		var tuning_color: Color = _lift_color(i.tuning, 0.65)
		tuning_color.a = 0.7

		var key: StringName = StringName(i.name)

		var title_ru = ru_title(i)
		var title_kz = kz_title(i)
		
		_def_by_name[key] = {
			"hint": key,
			"title": title,
			"title_ru": title_ru,
			"title_kz": title_kz,
			"outline_color": outline_color,
			"tuning": tuning_color,
		}

		_register_alias(i.name, key)
		_register_alias(title, key)
		_register_alias(title_ru, key)
		_register_alias(title_kz, key)

	# Order: groups first, then remaining in discovery order.
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


# ============================================================
# Color helpers
# ============================================================

func _lift_color(c: Color, min_v: float = 0.55) -> Color:
	var hsv = _rgb_to_hsv(c)

	if hsv.v < min_v:
		hsv.v = min_v

	return _hsv_to_rgb(hsv.h, hsv.s, hsv.v, c.a)


func _rgb_to_hsv(c: Color) -> Dictionary:
	var r: float = c.r
	var g: float = c.g
	var b: float = c.b

	var max_c: float = max(r, g, b)
	var min_c: float = min(r, g, b)
	var delta: float = max_c - min_c

	var h: float = 0.0

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

	var s: float = 0.0 if max_c == 0.0 else delta / max_c

	return {
		"h": h / 360.0,
		"s": s,
		"v": max_c,
	}


func _hsv_to_rgb(h: float, s: float, v: float, a: float = 1.0) -> Color:
	h *= 6.0

	var i: int = int(floor(h)) % 6
	var f: float = h - floor(h)

	var p: float = v * (1.0 - s)
	var q: float = v * (1.0 - f * s)
	var t: float = v * (1.0 - (1.0 - f) * s)

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
