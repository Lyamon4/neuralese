extends TabWindow


@onready var page_scroll: ScrollContainer = $CanvasLayer/Control/PageScroll
@onready var page_body: VBoxContainer = $CanvasLayer/Control/PageScroll/PageBody
@onready var root_control: Control = $CanvasLayer/Control

@onready var featured_scroll: ScrollContainer = $CanvasLayer/Control/PageScroll/PageBody/FeaturedSection/FeaturedScroll
@onready var featured_grid: SandboxProjectGrid = $CanvasLayer/Control/PageScroll/PageBody/FeaturedSection/FeaturedScroll/FeaturedGrid

@onready var sandbox_grid: SandboxProjectGrid = $CanvasLayer/Control/PageScroll/PageBody/ProjectsSection/SandboxProjectGrid


@export var project_total_count: int = 1000

# First load: only a handful of rows.
@export var initial_project_rows: int = 2

# Next loads: also a handful of rows.
@export var project_page_rows: int = 2

# Start downloading before the exact bottom.
# Example: 3 means "when user is within roughly 3 rows from the bottom".
@export var project_prefetch_rows: int = 3

@export var project_download_delay_seconds: float = 0.12

# Padding is applied through a real MarginContainer, not VBoxContainer.
# Horizontal padding is the minimum edge padding; the page is centered around
# whole project-grid columns so both sections keep the same visual width.
@export var page_scroll_padding_left: int = 122
@export var page_scroll_padding_top: int = 58
@export var page_scroll_padding_right: int = 122
@export var page_scroll_padding_bottom: int = 34
@export var center_page_content_on_project_columns: bool = true

@export var page_section_separation: int = 18
@export var featured_scroll_height_padding: float = 8.0

@export var custom_scrollbar_enabled: bool = true
@export var custom_scrollbar_width: float = 10.0
@export var custom_scrollbar_min_grabber_height: float = 76.0
@export var custom_scrollbar_margin_top: float = 14.0
@export var custom_scrollbar_margin_right: float = 10.0
@export var custom_scrollbar_margin_bottom: float = 14.0
@export var custom_scrollbar_smooth_seconds: float = 0.12
@export var custom_scrollbar_track_color: Color = Color(0.16, 0.16, 0.16, 0.55)
@export var custom_scrollbar_grabber_color: Color = Color(0.55, 0.55, 0.55, 0.95)

@export var mouse_wheel_scroll_pixels: int = 96


var _project_feed_loading: bool = false
var _project_feed_has_more: bool = true
var _project_next_cursor: String = ""
var _project_scroll_check_queued: bool = false
var _project_vertical_scroll_bar: VScrollBar = null

var _page_margin: MarginContainer = null
var _resolved_page_content_width: float = 0.0
var _resolved_project_columns: int = 1
var _page_layout_sync_queued: bool = false

var _custom_scrollbar_track: Panel = null
var _custom_scrollbar_grabber: Panel = null
var _custom_scrollbar_tween: Tween = null
var _custom_scrollbar_dragging: bool = false
var _custom_scrollbar_drag_offset_y: float = 0.0


func _ready() -> void:
	_sync_root_control_layout()
	_fix_scene_scroll_layout()
	_connect_viewport_resize_signal()
	_configure_unified_page_scroll()
	_configure_featured_scroll()
	_configure_grids()
	_sync_responsive_page_layout()
	_connect_grid_signals()
	_connect_project_scroll_signals()
	_connect_featured_scroll_mouse_redirect()
	_create_custom_vertical_scrollbar()

	cookies.reset_sandbox_projects_feed(project_total_count, "generated")

	await _load_initial_project_rows()
	await _load_featured_projects()

	await get_tree().process_frame
	_sync_responsive_page_layout()
	_update_custom_vertical_scrollbar(false)


func _fix_scene_scroll_layout() -> void:
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg = root_control.get_node_or_null("ColorRect")
	if bg != null and bg is ColorRect:
		var bg_rect: ColorRect = bg
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_rect.z_index = -100
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.offset_left = 0
		bg_rect.offset_top = -90
		bg_rect.offset_right = 0
		bg_rect.offset_bottom = 0


	page_scroll.z_index = 0
	page_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fill only inside CanvasLayer/Control.
	# The Control itself still keeps the TabWindow offset through glob.space_begin.y.
	page_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_scroll.offset_left = 0
	page_scroll.offset_top = 0
	page_scroll.offset_right = 0
	page_scroll.offset_bottom = 0

	_ensure_page_margin_wrapper()

	page_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _sync_root_control_layout() -> void:
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.offset_left = 0
	root_control.offset_top = glob.space_begin.y
	root_control.offset_right = 0
	root_control.offset_bottom = 0


func _ensure_page_margin_wrapper() -> void:
	if page_body == null:
		return

	if page_body.get_parent() is MarginContainer:
		_page_margin = page_body.get_parent() as MarginContainer
		return

	var old_parent = page_body.get_parent()

	if old_parent == null:
		return

	old_parent.remove_child(page_body)

	_page_margin = MarginContainer.new()
	_page_margin.name = "PageMargin"
	_page_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	page_scroll.add_child(_page_margin)
	_page_margin.add_child(page_body)


func _connect_viewport_resize_signal() -> void:
	var viewport = get_viewport()

	if viewport != null:
		if not viewport.size_changed.is_connected(_on_viewport_size_changed):
			viewport.size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	_sync_responsive_page_layout()
	_queue_project_scroll_load_check()
	_queue_responsive_page_layout_sync()
	call_deferred("_update_custom_vertical_scrollbar", true)


func _configure_unified_page_scroll() -> void:
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	if custom_scrollbar_enabled:
		page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	else:
		page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.mouse_filter = Control.MOUSE_FILTER_STOP

	page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page_body.add_theme_constant_override("separation", page_section_separation)
	_apply_page_margin_layout()


func _configure_featured_scroll() -> void:
	featured_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	featured_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	featured_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	featured_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	featured_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_sync_featured_scroll_minimum_size()


func _configure_grids() -> void:
	featured_grid.configure_parent_scroll_container = false
	featured_grid.activate_on_single_click = true
	featured_grid.set_horizontal_rail()
	featured_grid.reset_project_cards()

	sandbox_grid.configure_parent_scroll_container = false
	sandbox_grid.activate_on_single_click = true
	sandbox_grid.auto_vertical_grid_columns = false
	_sync_project_grid_columns()
	sandbox_grid.reset_project_cards()


func _sync_responsive_page_layout() -> void:
	_sync_root_control_layout()
	_apply_page_margin_layout()
	_sync_featured_scroll_minimum_size()
	_sync_project_grid_columns()


func _queue_responsive_page_layout_sync() -> void:
	if _page_layout_sync_queued:
		return

	_page_layout_sync_queued = true
	call_deferred("_run_responsive_page_layout_sync")


func _run_responsive_page_layout_sync() -> void:
	_sync_responsive_page_layout()

	await get_tree().process_frame
	_sync_responsive_page_layout()

	await get_tree().process_frame
	_sync_responsive_page_layout()
	_update_custom_vertical_scrollbar(true)

	_page_layout_sync_queued = false


func _apply_page_margin_layout() -> void:
	var metrics = _calculate_page_layout_metrics()

	_resolved_page_content_width = float(metrics["content_width"])
	_resolved_project_columns = int(metrics["columns"])

	if _page_margin != null:
		_page_margin.add_theme_constant_override("margin_left", int(metrics["margin_left"]))
		_page_margin.add_theme_constant_override("margin_top", page_scroll_padding_top)
		_page_margin.add_theme_constant_override("margin_right", int(metrics["margin_right"]))
		_page_margin.add_theme_constant_override("margin_bottom", page_scroll_padding_bottom)
		_page_margin.minimum_size_changed.emit()

	page_body.custom_minimum_size = Vector2(
		_resolved_page_content_width,
		page_body.custom_minimum_size.y
	)
	page_body.minimum_size_changed.emit()


func _sync_featured_scroll_minimum_size() -> void:
	featured_scroll.custom_minimum_size = Vector2(
		_resolved_page_content_width,
		featured_grid.default_project_cell_size.y + featured_scroll_height_padding
	)
	featured_scroll.minimum_size_changed.emit()


func _sync_project_grid_columns() -> void:
	if sandbox_grid == null:
		return

	var columns_count = max(1, _resolved_project_columns)
	sandbox_grid.auto_vertical_grid_columns = false
	sandbox_grid.vertical_grid_columns = columns_count
	sandbox_grid.set_vertical_grid()
	sandbox_grid.minimum_size_changed.emit()


func _calculate_page_layout_metrics() -> Dictionary:
	var scroll_width = _get_layout_viewport_width()

	var base_left = max(0.0, float(page_scroll_padding_left))
	var base_right = max(0.0, float(page_scroll_padding_right))

	if not center_page_content_on_project_columns:
		var direct_content_width = max(0.0, scroll_width - base_left - base_right)
		return {
			"margin_left": int(round(base_left)),
			"margin_right": int(round(base_right)),
			"content_width": direct_content_width,
			"columns": _resolve_project_columns_for_width(direct_content_width),
		}

	var base_horizontal_padding = min(base_left, base_right)
	var max_content_width = max(0.0, scroll_width - base_horizontal_padding * 2.0)
	var columns_count = _resolve_project_columns_for_width(max_content_width)
	var content_width = _get_project_row_width(columns_count)

	if content_width <= 0.0 or content_width > max_content_width:
		content_width = max_content_width

	var extra_width = max(0.0, scroll_width - content_width)
	var equal_margin = floor(extra_width * 0.5)
	content_width = max(0.0, scroll_width - equal_margin * 2.0)

	return {
		"margin_left": int(round(equal_margin)),
		"margin_right": int(round(equal_margin)),
		"content_width": content_width,
		"columns": columns_count,
	}


func _get_layout_viewport_width() -> float:
	var viewport_width = get_viewport_rect().size.x

	if viewport_width > 0.0:
		return viewport_width

	if root_control.size.x > 0.0:
		return root_control.size.x

	return page_scroll.size.x


func _resolve_project_columns_for_width(available_width: float) -> int:
	if available_width <= 0.0:
		return max(1, sandbox_grid.vertical_grid_columns)

	var step = sandbox_grid.cell_size.x + float(sandbox_grid.vertical_grid_h_gap)

	if step <= 0.0:
		return max(1, sandbox_grid.vertical_grid_columns)

	var raw_columns = int(floor((available_width + float(sandbox_grid.vertical_grid_h_gap)) / step))
	var min_columns = sandbox_grid.min_vertical_grid_columns
	var max_columns = sandbox_grid.max_vertical_grid_columns

	return max(1, min(max(raw_columns, min_columns), max_columns))


func _get_project_row_width(columns_count: int) -> float:
	if columns_count <= 0:
		return 0.0

	return (
		float(columns_count) * sandbox_grid.cell_size.x
		+ float(max(0, columns_count - 1) * sandbox_grid.vertical_grid_h_gap)
	)


func _connect_grid_signals() -> void:
	if not sandbox_grid.sandbox_activated.is_connected(_open_sandbox):
		sandbox_grid.sandbox_activated.connect(_open_sandbox)

	if not featured_grid.sandbox_activated.is_connected(_open_sandbox):
		featured_grid.sandbox_activated.connect(_open_sandbox)


func _connect_project_scroll_signals() -> void:
	_project_vertical_scroll_bar = page_scroll.get_v_scroll_bar()

	if _project_vertical_scroll_bar != null:
		if not _project_vertical_scroll_bar.value_changed.is_connected(_on_project_scroll_value_changed):
			_project_vertical_scroll_bar.value_changed.connect(_on_project_scroll_value_changed)

	if not page_scroll.resized.is_connected(_on_project_scroll_resized):
		page_scroll.resized.connect(_on_project_scroll_resized)


func _connect_featured_scroll_mouse_redirect() -> void:
	if not featured_scroll.gui_input.is_connected(_on_featured_scroll_gui_input):
		featured_scroll.gui_input.connect(_on_featured_scroll_gui_input)


func _on_featured_scroll_gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if not mouse_event.pressed:
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			page_scroll.scroll_vertical = max(0, page_scroll.scroll_vertical - mouse_wheel_scroll_pixels)
			featured_scroll.accept_event()
			_update_custom_vertical_scrollbar(false)

		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			page_scroll.scroll_vertical += mouse_wheel_scroll_pixels
			featured_scroll.accept_event()
			_update_custom_vertical_scrollbar(false)


func _on_project_scroll_value_changed(_value: float) -> void:
	_queue_project_scroll_load_check()
	_update_custom_vertical_scrollbar(false)


func _on_project_scroll_resized() -> void:
	_sync_responsive_page_layout()
	_queue_responsive_page_layout_sync()
	_queue_project_scroll_load_check()
	_update_custom_vertical_scrollbar(true)


func _queue_project_scroll_load_check() -> void:
	if _project_scroll_check_queued:
		return

	_project_scroll_check_queued = true
	call_deferred("_run_project_scroll_load_check")


func _run_project_scroll_load_check() -> void:
	_project_scroll_check_queued = false
	await _load_more_projects_if_needed(false)


func _load_initial_project_rows() -> void:
	var initial_page_size = _rows_to_project_count(initial_project_rows)
	await _request_next_project_page(initial_page_size)


func _load_more_projects_if_needed(force: bool = false) -> void:
	if _project_feed_loading:
		return

	if not _project_feed_has_more:
		return

	if not force and not _is_near_project_scroll_bottom():
		return

	var next_page_size = _rows_to_project_count(project_page_rows)
	await _request_next_project_page(next_page_size)

	# Do not aggressively fill the entire viewport at startup.
	# Only queue another load after actual scroll/resized checks.
	if _project_feed_has_more and _is_near_project_scroll_bottom() and _has_user_scrolled_down():
		_queue_project_scroll_load_check()


func _request_next_project_page(page_size: int) -> void:
	if _project_feed_loading:
		return

	if not _project_feed_has_more:
		return

	_project_feed_loading = true

	var result = await cookies.request_sandbox_projects_page(
		page_size,
		_project_next_cursor,
		project_download_delay_seconds,
		{
			"feed": "community",
		}
	)

	if not result.get("ok", false):
		_project_feed_loading = false
		push_warning("Failed to load sandbox project page: %s" % str(result))
		_update_custom_vertical_scrollbar(true)
		return

	var batch = result.get("items", [])

	if batch is Array and not batch.is_empty():
		_ensure_thumbnail_paths(batch)
		await sandbox_grid.add_projects_chunk(batch)

	_project_next_cursor = str(result.get("next_cursor", _project_next_cursor))
	_project_feed_has_more = bool(result.get("has_more", false))
	_project_feed_loading = false

	await get_tree().process_frame
	_update_custom_vertical_scrollbar(true)


func _load_featured_projects() -> void:
	var featured_projects: Array = []

	for i in range(10):
		featured_projects.append({
			"id": "featured_sound_classifier_%d" % i,
			"slug": "sound_classifier",
			"name": "Sound Classifier",
			"short_description": "Build a small model that recognizes simple audio patterns.",
			"tags": ["Audio", "Signals", "Classifier", "Neuralese Team"],
			"feed": "featured",
			"owner": "Neuralese Team",
			"thumbnail_path": "res://icon.svg",
		})

	featured_grid.set_horizontal_rail()
	await featured_grid.set_projects(featured_projects)

	await get_tree().process_frame
	_update_custom_vertical_scrollbar(true)


func _ensure_thumbnail_paths(projects: Array) -> void:
	for project in projects:
		if not (project is Dictionary):
			continue

		if not project.has("thumbnail_path"):
			project["thumbnail_path"] = "res://icon.svg"


func _rows_to_project_count(row_count: int) -> int:
	var columns_count = _resolve_visible_project_columns()
	return max(1, columns_count * max(1, row_count))


func _resolve_visible_project_columns() -> int:
	return max(1, _resolved_project_columns)


func _is_near_project_scroll_bottom() -> bool:
	if _project_vertical_scroll_bar == null:
		_project_vertical_scroll_bar = page_scroll.get_v_scroll_bar()

	if _project_vertical_scroll_bar == null:
		return true

	var max_scroll = max(0.0, _project_vertical_scroll_bar.max_value - _project_vertical_scroll_bar.page)

	if max_scroll <= 0.0:
		return true

	var prefetch_pixels = _get_project_prefetch_pixels()
	return _project_vertical_scroll_bar.value >= max_scroll - prefetch_pixels


func _get_project_prefetch_pixels() -> float:
	var row_height = sandbox_grid.cell_size.y + float(sandbox_grid.vertical_grid_v_gap)
	return max(row_height, row_height * float(max(1, project_prefetch_rows)))


func _has_user_scrolled_down() -> bool:
	if _project_vertical_scroll_bar == null:
		_project_vertical_scroll_bar = page_scroll.get_v_scroll_bar()

	if _project_vertical_scroll_bar == null:
		return false

	return _project_vertical_scroll_bar.value > 0.0


func _open_sandbox(project_id: String, project: Dictionary) -> void:
	print("Open sandbox: ", project_id, " / ", project.get("name", ""))


func _create_custom_vertical_scrollbar() -> void:
	if not custom_scrollbar_enabled:
		return

	if _custom_scrollbar_track != null:
		return

	_custom_scrollbar_track = Panel.new()
	_custom_scrollbar_track.name = "CustomPageVScrollTrack"
	_custom_scrollbar_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_custom_scrollbar_track.z_index = 1000

	var track_style = StyleBoxFlat.new()
	track_style.bg_color = custom_scrollbar_track_color
	track_style.corner_radius_top_left = int(custom_scrollbar_width * 0.5)
	track_style.corner_radius_top_right = int(custom_scrollbar_width * 0.5)
	track_style.corner_radius_bottom_left = int(custom_scrollbar_width * 0.5)
	track_style.corner_radius_bottom_right = int(custom_scrollbar_width * 0.5)
	_custom_scrollbar_track.add_theme_stylebox_override("panel", track_style)

	$CanvasLayer/Control.add_child(_custom_scrollbar_track)

	_custom_scrollbar_grabber = Panel.new()
	_custom_scrollbar_grabber.name = "CustomPageVScrollGrabber"
	_custom_scrollbar_grabber.mouse_filter = Control.MOUSE_FILTER_STOP

	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = custom_scrollbar_grabber_color
	grabber_style.corner_radius_top_left = int(custom_scrollbar_width * 0.5)
	grabber_style.corner_radius_top_right = int(custom_scrollbar_width * 0.5)
	grabber_style.corner_radius_bottom_left = int(custom_scrollbar_width * 0.5)
	grabber_style.corner_radius_bottom_right = int(custom_scrollbar_width * 0.5)
	_custom_scrollbar_grabber.add_theme_stylebox_override("panel", grabber_style)

	_custom_scrollbar_track.add_child(_custom_scrollbar_grabber)

	if not _custom_scrollbar_track.gui_input.is_connected(_on_custom_scrollbar_track_input):
		_custom_scrollbar_track.gui_input.connect(_on_custom_scrollbar_track_input)

	if not _custom_scrollbar_grabber.gui_input.is_connected(_on_custom_scrollbar_grabber_input):
		_custom_scrollbar_grabber.gui_input.connect(_on_custom_scrollbar_grabber_input)

	var native_bar = page_scroll.get_v_scroll_bar()

	if native_bar != null:
		if not native_bar.value_changed.is_connected(_on_native_scroll_changed_for_custom_bar):
			native_bar.value_changed.connect(_on_native_scroll_changed_for_custom_bar)

	if not page_scroll.resized.is_connected(_on_page_scroll_resized_for_custom_bar):
		page_scroll.resized.connect(_on_page_scroll_resized_for_custom_bar)

	call_deferred("_update_custom_vertical_scrollbar", false)


func _on_native_scroll_changed_for_custom_bar(_value: float) -> void:
	_update_custom_vertical_scrollbar(false)


func _on_page_scroll_resized_for_custom_bar() -> void:
	_update_custom_vertical_scrollbar(true)


func _update_custom_vertical_scrollbar(animated: bool = true) -> void:
	if not custom_scrollbar_enabled:
		return

	if _custom_scrollbar_track == null or _custom_scrollbar_grabber == null:
		return

	var native_bar = page_scroll.get_v_scroll_bar()

	if native_bar == null:
		_custom_scrollbar_track.visible = false
		return

	var scrollable_range = max(0.0, native_bar.max_value - native_bar.page)

	if scrollable_range <= 0.0:
		_custom_scrollbar_track.visible = false
		return

	_custom_scrollbar_track.visible = true

	var control_size = page_scroll.size
	var track_height = max(
		1.0,
		control_size.y - custom_scrollbar_margin_top - custom_scrollbar_margin_bottom
	)

	var track_pos = page_scroll.position + Vector2(
		control_size.x - custom_scrollbar_margin_right - custom_scrollbar_width,
		custom_scrollbar_margin_top
	)

	var track_size = Vector2(custom_scrollbar_width, track_height)

	_custom_scrollbar_track.position = track_pos
	_custom_scrollbar_track.size = track_size

	var actual_grabber_height = track_height * (native_bar.page / max(native_bar.max_value, 1.0))
	var grabber_height = clamp(
		max(custom_scrollbar_min_grabber_height, actual_grabber_height),
		1.0,
		track_height
	)

	var travel = max(1.0, track_height - grabber_height)
	var ratio = native_bar.value / scrollable_range
	var grabber_y = travel * clamp(ratio, 0.0, 1.0)

	var target_position = Vector2(0.0, grabber_y)
	var target_size = Vector2(custom_scrollbar_width, grabber_height)

	if _custom_scrollbar_dragging:
		_kill_custom_scrollbar_tween()
		_custom_scrollbar_grabber.position = target_position
		_custom_scrollbar_grabber.size = target_size
		return

	if not animated or custom_scrollbar_smooth_seconds <= 0.0:
		_kill_custom_scrollbar_tween()
		_custom_scrollbar_grabber.position = target_position
		_custom_scrollbar_grabber.size = target_size
		return

	_kill_custom_scrollbar_tween()

	_custom_scrollbar_tween = create_tween()
	_custom_scrollbar_tween.set_parallel(true)

	_custom_scrollbar_tween.tween_property(
		_custom_scrollbar_grabber,
		"position",
		target_position,
		custom_scrollbar_smooth_seconds
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_custom_scrollbar_tween.tween_property(
		_custom_scrollbar_grabber,
		"size",
		target_size,
		custom_scrollbar_smooth_seconds
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _kill_custom_scrollbar_tween() -> void:
	if _custom_scrollbar_tween == null:
		return

	_custom_scrollbar_tween.kill()
	_custom_scrollbar_tween = null


func _on_custom_scrollbar_grabber_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_event.pressed:
			_custom_scrollbar_dragging = true
			_custom_scrollbar_drag_offset_y = mouse_event.position.y
			_kill_custom_scrollbar_tween()
			_custom_scrollbar_grabber.accept_event()
		else:
			_custom_scrollbar_dragging = false
			_custom_scrollbar_grabber.accept_event()

	elif event is InputEventMouseMotion:
		if not _custom_scrollbar_dragging:
			return

		var mouse_motion = event as InputEventMouseMotion
		var target_global_y = (
			_custom_scrollbar_grabber.global_position.y
			+ mouse_motion.position.y
			- _custom_scrollbar_drag_offset_y
		)

		_scroll_page_from_custom_grabber_global_y(target_global_y)
		_custom_scrollbar_grabber.accept_event()


func _on_custom_scrollbar_track_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var target_global_y = _custom_scrollbar_track.global_position.y + mouse_event.position.y
			_scroll_page_from_custom_grabber_global_y(
				target_global_y - _custom_scrollbar_grabber.size.y * 0.5
			)
			_custom_scrollbar_track.accept_event()

		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			page_scroll.scroll_vertical = max(0, page_scroll.scroll_vertical - mouse_wheel_scroll_pixels)
			_custom_scrollbar_track.accept_event()
			_update_custom_vertical_scrollbar(false)

		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			page_scroll.scroll_vertical += mouse_wheel_scroll_pixels
			_custom_scrollbar_track.accept_event()
			_update_custom_vertical_scrollbar(false)


func _scroll_page_from_custom_grabber_global_y(global_y: float) -> void:
	var native_bar = page_scroll.get_v_scroll_bar()

	if native_bar == null:
		return

	var scrollable_range = max(0.0, native_bar.max_value - native_bar.page)

	if scrollable_range <= 0.0:
		return

	var track_top = _custom_scrollbar_track.global_position.y
	var track_height = _custom_scrollbar_track.size.y
	var grabber_height = _custom_scrollbar_grabber.size.y
	var travel = max(1.0, track_height - grabber_height)

	var local_y = clamp(global_y - track_top, 0.0, travel)
	var ratio = local_y / travel

	page_scroll.scroll_vertical = int(round(scrollable_range * ratio))
	_update_custom_vertical_scrollbar(false)


func _window_hide():
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	$CanvasLayer.hide()

	if glob.cam is GraphViewport:
		glob.cam.reset()


func _window_show():
	process_mode = Node.PROCESS_MODE_ALWAYS
	show()
	$CanvasLayer.show()
	_sync_responsive_page_layout()

	if glob.cam is GraphViewport:
		glob.cam.reset()

	_queue_project_scroll_load_check()
	_queue_responsive_page_layout_sync()
	call_deferred("_update_custom_vertical_scrollbar", true)
