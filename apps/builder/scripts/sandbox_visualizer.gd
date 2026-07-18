# SandboxProjectGrid.gd
extends GridVisualiser
class_name SandboxProjectGrid


enum ProjectLayoutMode {
	VERTICAL_GRID,
	HORIZONTAL_RAIL,
}


@export var default_project_cell_size: Vector2 = Vector2(280, 172)

@export var card_padding: int = 10
@export var title_font_scale: float = 1.08
@export var max_title_lines: int = 2

@export var show_card_tooltips: bool = false
@export var show_label_tooltips: bool = false
signal project_cards_appended(projects_added: Array)

# One shared fallback texture. Kept as preload for speed and zero per-card loading.
@export var default_thumbnail_texture: Texture2D = preload("res://game_assets/icons/icon.svg")
@export var thumbnail_expand_mode: int = TextureRect.EXPAND_IGNORE_SIZE
@export var thumbnail_stretch_mode: int = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
@export var thumbnail_modulate: Color = Color(1.0, 1.0, 1.0, 0.78)

# Optional bottom gradient/dim plate behind title for readability.
@export var title_scrim_color: Color = Color(0.08, 0.08, 0.09, 0.72)
@export var title_scrim_height: int = 46

# true = one click opens/activates the sandbox.
# false = first click selects, second click activates.
@export var activate_on_single_click: bool = true

# Layout mode:
# VERTICAL_GRID = normal library grid with vertical scrolling.
# HORIZONTAL_RAIL = one-row horizontal scroller for featured projects.
@export_enum("Vertical Grid", "Horizontal Rail") var project_layout_mode: int = ProjectLayoutMode.VERTICAL_GRID:
	set(value):
		project_layout_mode = value
		if is_inside_tree():
			_apply_project_layout_mode()

@export var configure_parent_scroll_container: bool = true


@export var vertical_grid_columns: int = 3
@export var auto_vertical_grid_columns: bool = true
@export var min_vertical_grid_columns: int = 1
@export var max_vertical_grid_columns: int = 6

@export var vertical_grid_h_gap: int = 12
@export var vertical_grid_v_gap: int = 12

@export var horizontal_rail_gap: int = 12
@export var horizontal_rail_height_padding: int = 4

# Opaque grey cards. Borders are intentionally disabled in _make_card_style().
@export var card_bg_color: Color = Color(0.19, 0.19, 0.205, 1.0)
@export var card_hover_color: Color = Color(0.23, 0.23, 0.25, 1.0)
@export var card_selected_color: Color = Color(0.25, 0.25, 0.275, 1.0)

@export var title_color: Color = Color(0.96, 0.97, 1.0, 1.0)

var projects: Array = []

var selected_project_id: String:
	get:
		return selected_key
	set(value):
		selected_key = value

var selected_project: Dictionary:
	get:
		return selected_meta
	set(value):
		selected_meta = value

var _sb_title_scrim: StyleBoxFlat
var _thumbnail_cache: Dictionary = {}

signal sandbox_selected(project_id: String, project: Dictionary)
signal sandbox_activated(project_id: String, project: Dictionary)
signal sandbox_hovered(project_id: String, project: Dictionary)
signal project_cards_reset


func reset_project_cards() -> void:
	projects.clear()

	if not is_inside_tree():
		return

	_vis_begin_refresh()
	_vis_end_refresh()
	_apply_project_layout_mode(0)
	project_cards_reset.emit()


func add_projects_chunk(chunk: Array) -> void:
	if chunk.is_empty():
		return

	var counter = projects.size()
	var added_projects: Array = []

	for raw_project in chunk:
		var project = _normalise_project(raw_project, counter)
		var base_key = _get_project_base_key(project, counter)
		var key = _make_unique_key(base_key)

		project["grid_key"] = key

		projects.append(project)
		added_projects.append(project)

		add_item(
			key,
			str(project["name"]),
			null,
			_make_project_tooltip(project),
			project
		)

		counter += 1

		if counter % batch_size == 0:
			await get_tree().process_frame

	_apply_project_layout_mode(projects.size())
	project_cards_appended.emit(added_projects)


func get_project_count() -> int:
	return projects.size()


func _ready() -> void:
	super._ready()

	if cell_size == Vector2(112, 120):
		cell_size = default_project_cell_size

	_prepare_project_styles()
	_apply_project_layout_mode()

	if not projects.is_empty():
		await refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_inside_tree() and project_layout_mode == ProjectLayoutMode.VERTICAL_GRID:
			_apply_project_layout_mode()


func _prepare_project_styles() -> void:
	_sb_default = _make_card_style(card_bg_color)
	_sb_hover = _make_card_style(card_hover_color)
	_sb_selected = _make_card_style(card_selected_color)
	_sb_title_scrim = _make_title_scrim_style()


func rebuild_project_styles() -> void:
	_prepare_project_styles()

	for key in _tile_index.keys():
		var tile: PanelContainer = _tile_index[key]
		if tile == selected_tile:
			tile.add_theme_stylebox_override("panel", _sb_selected)
		else:
			tile.add_theme_stylebox_override("panel", _sb_default)

		var refs = _ensure_card_layout(tile)
		var title_panel: PanelContainer = refs["title_panel"]
		title_panel.add_theme_stylebox_override("panel", _sb_title_scrim)


func _make_card_style(bg_color: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color

	# No borders by design.
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0

	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12

	sb.content_margin_left = 0
	sb.content_margin_top = 0
	sb.content_margin_right = 0
	sb.content_margin_bottom = 0

	return sb


func _make_title_scrim_style() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = title_scrim_color
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	return sb


func set_projects(value: Array) -> void:
	projects = value.duplicate(true)

	if not is_inside_tree():
		return

	await refresh()


func set_featured_projects(value: Array) -> void:
	project_layout_mode = ProjectLayoutMode.HORIZONTAL_RAIL
	projects = value.duplicate(true)

	if not is_inside_tree():
		return

	await refresh()


func refresh() -> void:
	_apply_project_layout_mode(projects.size())

	_vis_begin_refresh()
	await _create_project_entries_async(projects)
	_vis_end_refresh()

	_apply_project_layout_mode(projects.size())


func clear_projects() -> void:
	projects.clear()

	if not is_inside_tree():
		return

	_vis_begin_refresh()
	_vis_end_refresh()
	_apply_project_layout_mode(0)


func append_project(project: Dictionary, refresh_after: bool = true) -> void:
	projects.append(project.duplicate(true))

	if refresh_after and is_inside_tree():
		await refresh()


func set_vertical_grid() -> void:
	project_layout_mode = ProjectLayoutMode.VERTICAL_GRID
	_apply_project_layout_mode()


func set_horizontal_rail() -> void:
	project_layout_mode = ProjectLayoutMode.HORIZONTAL_RAIL
	_apply_project_layout_mode()


func _apply_project_layout_mode(project_count: int = -1) -> void:
	if project_count < 0:
		project_count = projects.size()

	if project_layout_mode == ProjectLayoutMode.HORIZONTAL_RAIL:
		_apply_horizontal_rail_layout(project_count)
	else:
		_apply_vertical_grid_layout()


func _apply_vertical_grid_layout() -> void:
	var resolved_columns = vertical_grid_columns

	if auto_vertical_grid_columns:
		resolved_columns = _resolve_auto_vertical_columns()

	columns = max(1, resolved_columns)

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	custom_minimum_size = Vector2(0, 0)

	add_theme_constant_override("h_separation", vertical_grid_h_gap)
	add_theme_constant_override("v_separation", vertical_grid_v_gap)

	_configure_scroll_parent(false)


func _apply_horizontal_rail_layout(project_count: int) -> void:
	columns = max(1, project_count)

	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	custom_minimum_size = Vector2(
		0,
		cell_size.y + float(horizontal_rail_height_padding)
	)

	add_theme_constant_override("h_separation", horizontal_rail_gap)
	add_theme_constant_override("v_separation", 0)

	_configure_scroll_parent(true)


func _resolve_auto_vertical_columns() -> int:
	var available_width = size.x

	var scroll_parent = _get_parent_scroll_container()
	if scroll_parent:
		available_width = scroll_parent.size.x

	if available_width <= 0.0:
		return _clamp_int(
			vertical_grid_columns,
			min_vertical_grid_columns,
			max_vertical_grid_columns
		)

	var step = cell_size.x + float(vertical_grid_h_gap)
	var raw_columns = int(floor((available_width + float(vertical_grid_h_gap)) / step))
	var resolved_columns = _clamp_int(
		raw_columns,
		min_vertical_grid_columns,
		max_vertical_grid_columns
	)

	return max(1, resolved_columns)


func _clamp_int(value: int, min_value: int, max_value: int) -> int:
	return min(max(value, min_value), max_value)


func _configure_scroll_parent(horizontal_rail: bool) -> void:
	if not configure_parent_scroll_container:
		return

	var scroll_parent = _get_parent_scroll_container()

	if scroll_parent == null:
		return

	if horizontal_rail:
		scroll_parent.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll_parent.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll_parent.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_parent.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO


func _get_parent_scroll_container() -> ScrollContainer:
	var node = get_parent()

	while node:
		if node is ScrollContainer:
			return node

		node = node.get_parent()

	return null


func _create_project_entries_async(source_projects: Array) -> void:
	var counter = 0

	for raw_project in source_projects:
		var project = _normalise_project(raw_project, counter)
		var base_key = _get_project_base_key(project, counter)
		var key = _make_unique_key(base_key)

		project["grid_key"] = key

		add_item(
			key,
			str(project["name"]),
			null,
			_make_project_tooltip(project),
			project
		)

		counter += 1

		if counter % batch_size == 0:
			await get_tree().process_frame


func _normalise_project(raw_project, fallback_index: int) -> Dictionary:
	var project: Dictionary = {}

	if raw_project is Dictionary:
		project = raw_project.duplicate(true)
	else:
		project["name"] = str(raw_project)

	var name = _first_string(project, ["name", "Name", "title", "Title"])
	if name == "":
		name = "Untitled sandbox"

	project["name"] = name

	if not project.has("id") or str(project["id"]).strip_edges() == "":
		project["id"] = "sandbox_%d" % fallback_index

	return project


func _first_string(source: Dictionary, keys: Array) -> String:
	for key in keys:
		if source.has(key):
			var value = str(source[key]).strip_edges()
			if value != "":
				return value

	return ""


func _first_existing(source: Dictionary, keys: Array):
	for key in keys:
		if source.has(key):
			return source[key]

	return null


func _get_project_base_key(project: Dictionary, fallback_index: int) -> String:
	var base_key = ""

	if project.has("id"):
		base_key = str(project["id"])
	elif project.has("project_id"):
		base_key = str(project["project_id"])
	else:
		base_key = str(project.get("name", "sandbox_%d" % fallback_index))

	base_key = base_key.strip_edges()

	if base_key == "":
		base_key = "sandbox_%d" % fallback_index

	return base_key


func _make_unique_key(base_key: String) -> String:
	var clean_base = base_key.strip_edges()

	if clean_base == "":
		clean_base = "sandbox"

	var key = clean_base
	var index = 2

	while _tile_index.has(key):
		key = "%s_%d" % [clean_base, index]
		index += 1

	return key


func _make_project_tooltip(project: Dictionary) -> String:
	return str(project.get("name", "Untitled sandbox"))


func add_item(key: String, display_name: String, icon_tex: Texture2D, tooltip_text: String = "", meta: Dictionary = {}) -> void:
	var project = meta.duplicate(true)

	if not project.has("id") or str(project["id"]).strip_edges() == "":
		project["id"] = key

	if not project.has("name") or str(project["name"]).strip_edges() == "":
		project["name"] = display_name

	var tile = _get_tile()

	_reset_tile_meta(tile)

	tile.custom_minimum_size = cell_size
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.clip_contents = true
	tile.tooltip_text = _make_project_tooltip(project) if show_card_tooltips else ""
	tile.add_theme_stylebox_override("panel", _sb_default)

	var refs = _ensure_card_layout(tile)

	var thumbnail_rect: TextureRect = refs["thumbnail_rect"]
	var name_label: Label = refs["name_label"]

	name_label.text = str(project.get("name", "Untitled sandbox"))
	name_label.tooltip_text = name_label.text if show_label_tooltips else ""
	thumbnail_rect.texture = _resolve_project_thumbnail(project, icon_tex)
	thumbnail_rect.modulate = thumbnail_modulate

	tile.set_meta("key", key)
	tile.set_meta("meta", project)
	tile.set_meta("project", project)

	for k in project.keys():
		tile.set_meta(k, project[k])

	if not tile.gui_input.is_connected(_on_tile_input_meta):
		tile.gui_input.connect(_on_tile_input_meta.bind(tile))

	if not tile.mouse_entered.is_connected(_on_tile_hover_meta):
		tile.mouse_entered.connect(_on_tile_hover_meta.bind(tile, true))

	if not tile.mouse_exited.is_connected(_on_tile_hover_meta):
		tile.mouse_exited.connect(_on_tile_hover_meta.bind(tile, false))

	add_child(tile)
	tile.visible = true
	_tile_index[key] = tile


func _reset_tile_meta(tile: Control) -> void:
	var meta_keys = tile.get_meta_list()

	for meta_key in meta_keys:
		tile.remove_meta(meta_key)


func _ensure_card_layout(tile: PanelContainer) -> Dictionary:
	var rebuild = false

	if tile.get_child_count() == 0:
		rebuild = true
	elif not (tile.get_child(0) is MarginContainer):
		rebuild = true
	else:
		var first_child = tile.get_child(0)
		if first_child.get_node_or_null("CardRoot") == null:
			rebuild = true

	if rebuild:
		_build_card_layout(tile)

	var margin = tile.get_child(0) as MarginContainer
	var root = margin.get_node("CardRoot") as Control
	var thumbnail_rect = root.get_node("Thumbnail") as TextureRect
	var title_panel = root.get_node("TitlePanel") as PanelContainer
	var title_margin = title_panel.get_node("TitleMargin") as MarginContainer
	var name_label = title_margin.get_node("Name") as Label

	margin.add_theme_constant_override("margin_left", card_padding)
	margin.add_theme_constant_override("margin_top", card_padding)
	margin.add_theme_constant_override("margin_right", card_padding)
	margin.add_theme_constant_override("margin_bottom", card_padding)

	root.custom_minimum_size = Vector2(
		max(0.0, cell_size.x - float(card_padding * 2)),
		max(0.0, cell_size.y - float(card_padding * 2))
	)

	thumbnail_rect.expand_mode = thumbnail_expand_mode
	thumbnail_rect.stretch_mode = thumbnail_stretch_mode
	thumbnail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	title_panel.custom_minimum_size = Vector2(0, title_scrim_height)
	title_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	title_panel.offset_top = -float(title_scrim_height)
	title_panel.offset_bottom = 0.0
	title_panel.add_theme_stylebox_override("panel", _sb_title_scrim)
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	title_margin.add_theme_constant_override("margin_left", 8)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_bottom", 4)

	var text_width = max(0.0, cell_size.x - float(card_padding * 2) - 16.0)
	name_label.custom_minimum_size = Vector2(text_width, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.max_lines_visible = max_title_lines
	name_label.add_theme_font_size_override("font_size", int(round(_scaled_font_size * title_font_scale)))
	name_label.add_theme_color_override("font_color", title_color)

	return {
		"thumbnail_rect": thumbnail_rect,
		"title_panel": title_panel,
		"name_label": name_label,
	}


func _build_card_layout(tile: PanelContainer) -> void:
	for child in tile.get_children():
		tile.remove_child(child)
		child.queue_free()

	var margin = MarginContainer.new()
	margin.name = "CardMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(margin)

	var root = Control.new()
	root.name = "CardRoot"
	root.size_flags_horizontal = Control.SIZE_FILL
	root.size_flags_vertical = Control.SIZE_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true
	margin.add_child(root)

	var thumbnail_rect = TextureRect.new()
	thumbnail_rect.name = "Thumbnail"
	thumbnail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(thumbnail_rect)

	var title_panel = PanelContainer.new()
	title_panel.name = "TitlePanel"
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_panel)

	var title_margin = MarginContainer.new()
	title_margin.name = "TitleMargin"
	title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(title_margin)

	var name_label = Label.new()
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_FILL
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_margin.add_child(name_label)


func _resolve_project_thumbnail(project: Dictionary, icon_tex: Texture2D = null) -> Texture2D:
	if icon_tex != null:
		return icon_tex

	var direct_keys = [
		"thumbnail_texture",
		"ThumbnailTexture",
		"thumbnail",
		"Thumbnail",
		"thumb",
		"Thumb",
	]

	for key in direct_keys:
		if project.has(key) and project[key] is Texture2D:
			return project[key]

	var path = _first_string(project, [
		"thumbnail_path",
		"ThumbnailPath",
		"thumbnail_url",
		"ThumbnailUrl",
		"thumbnail",
		"Thumbnail",
		"thumb_path",
		"ThumbPath",
	])

	if path != "" and path.begins_with("res://") and ResourceLoader.exists(path):
		return _load_thumbnail_cached(path)

	return default_thumbnail_texture


func _load_thumbnail_cached(path: String) -> Texture2D:
	if _thumbnail_cache.has(path):
		var cached = _thumbnail_cache[path]
		if cached is Texture2D:
			return cached

	var loaded = load(path)
	if loaded is Texture2D:
		_thumbnail_cache[path] = loaded
		return loaded

	return default_thumbnail_texture


func set_project_thumbnail(project_id: String, texture: Texture2D) -> void:
	if texture == null:
		texture = default_thumbnail_texture

	_update_project_thumbnail_value(project_id, texture)

	if not is_inside_tree() or not has_item(project_id):
		return

	var tile = get_tile(project_id)
	var refs = _ensure_card_layout(tile)
	var thumbnail_rect: TextureRect = refs["thumbnail_rect"]
	thumbnail_rect.texture = texture

	var meta: Dictionary = tile.get_meta("meta", {})
	meta["thumbnail_texture"] = texture
	tile.set_meta("meta", meta)
	tile.set_meta("project", meta)
	tile.set_meta("thumbnail_texture", texture)


func set_project_thumbnail_path(project_id: String, thumbnail_path: String) -> void:
	var texture: Texture2D = default_thumbnail_texture

	if thumbnail_path.strip_edges() != "" and thumbnail_path.begins_with("res://") and ResourceLoader.exists(thumbnail_path):
		texture = _load_thumbnail_cached(thumbnail_path)

	_update_project_thumbnail_value(project_id, thumbnail_path)

	if not is_inside_tree() or not has_item(project_id):
		return

	var tile = get_tile(project_id)
	var refs = _ensure_card_layout(tile)
	var thumbnail_rect: TextureRect = refs["thumbnail_rect"]
	thumbnail_rect.texture = texture

	var meta: Dictionary = tile.get_meta("meta", {})
	meta["thumbnail_path"] = thumbnail_path
	tile.set_meta("meta", meta)
	tile.set_meta("project", meta)
	tile.set_meta("thumbnail_path", thumbnail_path)


func _update_project_thumbnail_value(project_id: String, value) -> void:
	for i in range(projects.size()):
		var project = projects[i]
		if not (project is Dictionary):
			continue

		var id_value = str(project.get("id", project.get("grid_key", "")))
		var grid_key_value = str(project.get("grid_key", ""))

		if id_value == project_id or grid_key_value == project_id:
			if value is Texture2D:
				project["thumbnail_texture"] = value
			else:
				project["thumbnail_path"] = str(value)
			projects[i] = project
			return


func _on_tile_input_meta(event: InputEvent, tile: Control) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event = event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var key = str(tile.get_meta("key", ""))
	var meta: Dictionary = tile.get_meta("meta", {})
	var was_selected = selected_tile == tile

	if not was_selected:
		_on_item_selected(key, meta, tile)
		_select_tile(tile, key, meta)

	if activate_on_single_click or was_selected:
		_on_item_activated(key, meta, tile)

	tile.accept_event()


func _on_tile_hover_meta(tile: Control, entered: bool) -> void:
	var key = str(tile.get_meta("key", ""))
	var meta: Dictionary = tile.get_meta("meta", {})

	if entered:
		sandbox_hovered.emit(key, meta)

	if tile == selected_tile:
		return

	tile.add_theme_stylebox_override("panel", _sb_hover if entered else _sb_default)


func _on_item_selected(key: String, meta: Dictionary, tile: Control) -> void:
	sandbox_selected.emit(key, meta)


func _on_item_activated(key: String, meta: Dictionary, tile: Control) -> void:
	sandbox_activated.emit(key, meta)


func select_project(project_id: String, emit_signal_on_select: bool = false) -> void:
	if not has_item(project_id):
		push_warning("select_project(): Project not found in current view: %s" % project_id)
		return

	var tile = get_tile(project_id)
	var meta: Dictionary = tile.get_meta("meta", {})

	_select_tile(tile, project_id, meta)

	if emit_signal_on_select:
		sandbox_selected.emit(project_id, meta)
