# GridVisualiser.gd
extends GridContainer
class_name GridVisualiser

@export var icon_size: Vector2 = Vector2(64, 64)
@export var cell_size: Vector2 = Vector2(112, 120)
@export var label_font_scale: float = 0.85
@export var vertical_padding: int = 6
@export var max_label_chars: int = 48
@export var batch_size: int = 32

# Selection (generic)
var selected_tile: Control = null
var selected_key: String = ""
var selected_meta: Dictionary = {}

signal refreshed

# === Theme / cache ===
var _base_font
var _scaled_font_size: int
var _sb_default: StyleBoxFlat
var _sb_hover: StyleBoxFlat
var _sb_selected: StyleBoxFlat
var _width_cache: Dictionary = {}
var _tile_pool: Array[PanelContainer] = []

var _loading_overlay: Label
var _tile_index: Dictionary = {}

var _filename_cache: Dictionary = {}

func _ready() -> void:
	_prepare_caches()
	_create_loading_overlay()

func _prepare_caches() -> void:
	_base_font = get_theme_font("font")
	_scaled_font_size = int(round(get_theme_font_size("font") * label_font_scale))

	var make_box = func(color: Color) -> StyleBoxFlat:
		var sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		return sb

	_sb_default = make_box.call(Color(0, 0, 0, 0))
	_sb_hover = make_box.call(Color(1, 1, 1, 0.08))
	_sb_selected = make_box.call(Color(0.25, 0.45, 0.85, 0.25))

func _create_loading_overlay() -> void:
	_loading_overlay = Label.new()
	_loading_overlay.text = "Loading..."
	_loading_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_overlay.add_theme_font_size_override("font_size", int(_scaled_font_size * 1.1))
	_loading_overlay.modulate = Color(1, 1, 1, 0.5)
	_loading_overlay.anchor_left = 0
	_loading_overlay.anchor_top = 0
	_loading_overlay.anchor_right = 1
	_loading_overlay.anchor_bottom = 1
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loading_overlay)
	_loading_overlay.visible = false

func _vis_begin_refresh() -> void:
	_tile_index.clear()
	_clear_selection()

	visible = false
	_loading_overlay.visible = true

	for child in get_children():
		if child is PanelContainer:
			_recycle_tile(child)

func _vis_end_refresh() -> void:
	_loading_overlay.visible = false
	visible = true
	refreshed.emit()

func _get_tile() -> PanelContainer:
	if _tile_pool.size() > 0:
		return _tile_pool.pop_back()
	return PanelContainer.new()

func _recycle_tile(tile: PanelContainer) -> void:
	if tile == selected_tile:
		_clear_selection()

	if tile.has_meta("key"):
		var old_key = tile.get_meta("key")
		if _tile_index.has(old_key):
			_tile_index.erase(old_key)

	if tile.get_parent():
		tile.get_parent().remove_child(tile)

	tile.visible = false
	_tile_pool.append(tile)

func add_item(key: String, display_name: String, icon_tex: Texture2D, tooltip_text: String = "", meta: Dictionary = {}) -> void:
	var tile = _get_tile()

	tile.custom_minimum_size = cell_size
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.add_theme_stylebox_override("panel", _sb_default)

	var box: VBoxContainer
	if tile.get_child_count() == 0:
		box = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.add_theme_constant_override("separation", vertical_padding)
		box.size_flags_horizontal = Control.SIZE_FILL
		tile.add_child(box)
	else:
		box = tile.get_child(0)

	var icon: TextureRect
	var label: Label
	if box.get_child_count() == 0:
		icon = TextureRect.new()
		box.add_child(icon)
		label = Label.new()
		box.add_child(label)
	else:
		icon = box.get_child(0)
		label = box.get_child(1)

	icon.texture = icon_tex
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = icon_size
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	label.text = _format_filename(display_name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.tooltip_text = tooltip_text if tooltip_text != "" else display_name
	label.custom_minimum_size = Vector2(cell_size.x, 0)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.add_theme_font_size_override("font_size", _scaled_font_size)

	# ---- store per-tile data ----
	tile.set_meta("key", key)
	tile.set_meta("meta", meta)
	# also flatten meta keys for compatibility / convenience
	for k in meta.keys():
		tile.set_meta(k, meta[k])

	if not tile.gui_input.is_connected(_on_tile_input_meta):
		tile.gui_input.connect(_on_tile_input_meta.bind(tile))
	if not tile.mouse_entered.is_connected(_on_tile_hover_meta):
		tile.mouse_entered.connect(_on_tile_hover_meta.bind(tile, true))
	if not tile.mouse_exited.is_connected(_on_tile_hover_meta):
		tile.mouse_exited.connect(_on_tile_hover_meta.bind(tile, false))

	add_child(tile)
	tile.visible = true
	_tile_index[key] = tile

func has_item(key: String) -> bool:
	return _tile_index.has(key)

func get_tile(key: String) -> PanelContainer:
	if not _tile_index.has(key):
		return null
	return _tile_index[key]

func select_key(key: String) -> void:
	if not _tile_index.has(key):
		push_warning("select_key(): Key not found in current view: %s" % key)
		return
	var tile: PanelContainer = _tile_index[key]
	var meta: Dictionary = tile.get_meta("meta", {})
	_select_tile(tile, key, meta)

func _on_tile_input_meta(event: InputEvent, tile: Control) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var key = str(tile.get_meta("key", ""))
	var meta: Dictionary = tile.get_meta("meta", {})

	if selected_tile == tile:
		_on_item_activated(key, meta, tile)
	else:
		_on_item_selected(key, meta, tile)
		_select_tile(tile, key, meta)

func _on_tile_hover_meta(tile: Control, entered: bool) -> void:
	if tile == selected_tile:
		return
	tile.add_theme_stylebox_override("panel", _sb_hover if entered else _sb_default)

func _on_item_selected(key: String, meta: Dictionary, tile: Control) -> void:
	# override in subclasses
	pass

func _on_item_activated(key: String, meta: Dictionary, tile: Control) -> void:
	# override in subclasses
	pass

func _select_tile(tile: Control, key: String, meta: Dictionary) -> void:
	if selected_tile and is_instance_valid(selected_tile):
		selected_tile.add_theme_stylebox_override("panel", _sb_default)

	selected_tile = tile
	selected_key = key
	selected_meta = meta

	selected_tile.add_theme_stylebox_override("panel", _sb_selected)

func _clear_selection() -> void:
	if selected_tile and is_instance_valid(selected_tile):
		selected_tile.add_theme_stylebox_override("panel", _sb_default)
	selected_tile = null
	selected_key = ""
	selected_meta.clear()

func _measure_text(text: String) -> float:
	if _width_cache.has(text):
		return _width_cache[text]
	var w = _base_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_font_size).x
	_width_cache[text] = w
	return w

func _format_filename(name: String) -> String:
	if _filename_cache.has(name):
		return _filename_cache[name]

	var dot = name.rfind(".")
	if dot == -1 or dot == 0 or dot == name.length() - 1:
		_filename_cache[name] = name
		return name

	var base = name.substr(0, dot)
	var ext = name.substr(dot)

	if base.length() > max_label_chars:
		base = base.substr(0, max_label_chars) + "..."

	var font = _base_font
	var fs = _scaled_font_size
	var cell_w = max(0.0, cell_size.x - 8.0)

	var base_w = font.get_string_size(base, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ext_w = font.get_string_size(ext, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

	var leftover = cell_w
	if base_w > 0.0:
		var used_in_last = fmod(base_w, cell_w)
		if is_equal_approx(used_in_last, 0.0) or is_equal_approx(used_in_last, 0.5):
			leftover = cell_w
		else:
			leftover = cell_w - used_in_last

	var output: String
	if ext_w <= (leftover - 1.5):
		output = base + ext
	else:
		output = base + "\n" + ext

	_filename_cache[name] = output
	return output
