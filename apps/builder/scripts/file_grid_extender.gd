extends GridContainer

@export var file_icon: Texture2D
@export var dir_icon: Texture2D

@export var icon_size: Vector2 = Vector2(64, 64)
@export var cell_size: Vector2 = Vector2(112, 120)
@export var label_font_scale: float = 0.85
@export var vertical_padding: int = 6
@export var max_label_chars: int = 48
@export var batch_size: int = 32

var current_dir: String
var filter_extensions: Dictionary = {}
var scroll_cache: Dictionary = {}

var selected_tile: Control = null
var selected_path: String = ""
var selected_is_dir: bool = false

signal file_selected(path: String)
signal directory_entered(path: String)
signal scan_finished

# === Theme / cache ===
var _base_font
var _scaled_font_size: int
var _sb_default: StyleBoxFlat
var _sb_hover: StyleBoxFlat
var _sb_selected: StyleBoxFlat
var _width_cache: Dictionary = {}
var _tile_pool: Array[PanelContainer] = []
var _scan_thread: Thread = null

var _loading_overlay: Label
var _tile_index: Dictionary = {}

func _ready() -> void:
	#current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_prepare_caches()
	_create_loading_overlay()
	#await _refresh()


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

signal refreshed
func _refresh() -> void:

	if _scan_thread and _scan_thread.is_alive():
		return
	_tile_index.clear()
	_clear_selection()
#	print_stack()

	visible = false
	_loading_overlay.visible = true

	for child in get_children():
		if child is PanelContainer:
			_recycle_tile(child)

	_scan_thread = Thread.new()
	_scan_thread.start(_thread_scan_dir.bind(current_dir))
	await scan_finished
	_loading_overlay.visible = false
	visible = true
	refreshed.emit()


func _thread_scan_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return

	var dirs = dir.get_directories()
	var files = dir.get_files()

	if not filter_extensions.is_empty():
		var filtered = PackedStringArray()
		for f in files:
			var ext = f.get_extension().to_lower()
			if filter_extensions.has(ext):
				filtered.append(f)
		files = filtered
	#("fjfddj")

	dirs.sort()
	files.sort()
	_on_scan_finished.call_deferred(dirs, files)



func _on_scan_finished(dirs: PackedStringArray, files: PackedStringArray) -> void:
	await _create_entries_async(dirs, files)
	if _scan_thread:
		_scan_thread.wait_to_finish()
		_scan_thread = null
	scan_finished.emit()


func _create_entries_async(dirs: PackedStringArray, files: PackedStringArray) -> void:
	var counter = 0
	for fname in dirs:
		if fname.begins_with("."): continue
		_add_entry(fname, true)
		counter += 1
		if counter % batch_size == 0:
			await get_tree().process_frame

	for fname in files:
		_add_entry(fname, false)
		counter += 1
		if counter % batch_size == 0:
			await get_tree().process_frame


func _get_tile() -> PanelContainer:
	if _tile_pool.size() > 0:
		return _tile_pool.pop_back()
	return PanelContainer.new()


func _recycle_tile(tile: PanelContainer) -> void:
	# if this tile was selected previously, clear selection to restore two-click logic
	if tile == selected_tile:
		_clear_selection()
	if tile.has_meta("path"):
		var old_path = tile.get_meta("path")
		if _tile_index.has(old_path):
			_tile_index.erase(old_path)
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	tile.visible = false
	_tile_pool.append(tile)


func _add_entry(file_name: String, is_dir: bool) -> void:
	var full_path = current_dir.path_join(file_name)
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

	icon.texture = dir_icon if is_dir else file_icon
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = icon_size
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	label.text = _format_filename(file_name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.tooltip_text = file_name
	label.custom_minimum_size = Vector2(cell_size.x, 0)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.add_theme_font_size_override("font_size", _scaled_font_size)

	# ---- store per-tile data (no fragile closures) ----
	tile.set_meta("path", full_path)
	tile.set_meta("is_dir", is_dir)

	# Connect once; reuse safely with metas
	if not tile.gui_input.is_connected(_on_tile_input_meta):
		tile.gui_input.connect(_on_tile_input_meta.bind(tile))
	if not tile.mouse_entered.is_connected(_on_tile_hover_meta):
		tile.mouse_entered.connect(_on_tile_hover_meta.bind(tile, true))
	if not tile.mouse_exited.is_connected(_on_tile_hover_meta):
		tile.mouse_exited.connect(_on_tile_hover_meta.bind(tile, false))

	add_child(tile)
	tile.visible = true
	_tile_index[full_path] = tile

func select_path(path: String, emit_signal_on_select: bool = false) -> void:
	if not _tile_index.has(path):
		push_warning("select_path(): Path not found in current view: %s" % path)
		return

	var tile: PanelContainer = _tile_index[path]
	var is_dir = tile.get_meta("is_dir", false)

	_select_tile(tile, path, is_dir)

	if emit_signal_on_select:
		if is_dir:
			current_dir = path
			await _refresh()
			directory_entered.emit(path)
		else:
			file_selected.emit(path)



func _measure_text(text: String) -> float:
	if _width_cache.has(text):
		return _width_cache[text]
	var w = _base_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_font_size).x
	_width_cache[text] = w
	return w


var filename_cache = {}
func _format_filename(name: String) -> String:
	if name in filename_cache: return filename_cache[name]
	var dot = name.rfind(".")
	if dot == -1 or dot == 0 or dot == name.length() - 1:
		return name

	var base = name.substr(0, dot)
	var ext = name.substr(dot)

	if base.length() > max_label_chars:
		base = base.substr(0, max_label_chars) + "..."

	var font = _base_font
	var fs = _scaled_font_size

	var cell_w = max(0.0, cell_size.x - 8.0)

	var base_w = font.get_string_size(base, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ext_w  = font.get_string_size(ext,  HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

	var leftover = cell_w
	if base_w > 0.0:
		var used_in_last = fmod(base_w, cell_w)
		if is_equal_approx(used_in_last, 0.0) or is_equal_approx(used_in_last, 0.5):
			leftover = cell_w
		else:
			leftover = cell_w - used_in_last
	
	var output  
	if ext_w <= (leftover - 1.5):
		output =  base + ext
	else:
		output = base + "\n" + ext
	filename_cache[name] = output
	return output





func _on_tile_input_meta(event: InputEvent, tile: Control) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var path = tile.get_meta("path", "")
	var is_dir = tile.get_meta("is_dir", false)

	if selected_tile == tile:
		if is_dir:
			current_dir = path
			await _refresh()
			directory_entered.emit(path)
		else:
			#("djdj")
			file_selected.emit(path)
	else:
		file_hovered.emit(path, is_dir)
		_select_tile(tile, path, is_dir)

signal file_hovered(path: String, is_dir: bool)

func _on_tile_hover_meta(tile: Control, entered: bool) -> void:
	if tile == selected_tile:
		return
	tile.add_theme_stylebox_override("panel", _sb_hover if entered else _sb_default)


func _select_tile(tile: Control, path: String, is_dir: bool) -> void:
	if selected_tile and is_instance_valid(selected_tile):
		selected_tile.add_theme_stylebox_override("panel", _sb_default)
	selected_tile = tile
	selected_path = path
	selected_is_dir = is_dir
	selected_tile.add_theme_stylebox_override("panel", _sb_selected)


func _clear_selection() -> void:
	if selected_tile and is_instance_valid(selected_tile):
		selected_tile.add_theme_stylebox_override("panel", _sb_default)
	selected_tile = null
	selected_path = ""
	selected_is_dir = false


func go_up() -> void:
	var parent = current_dir.get_base_dir()
	if parent != current_dir:
		current_dir = parent
		await _refresh()
		directory_entered.emit(current_dir)


func refresh() -> void:
	await _refresh()
