extends Control
class_name VirtualTable

@export var uniform_row_heights: bool = false
var uniform_row_height: float = 0.0
var disabled: bool = false

@export var addition_enabled: bool = false



@export var vscrollbar: VScrollBar
@export var grid_line_color: Color = Color(1, 1, 1, 0.15)
@export var odd_row_tint: Color = Color(1, 1, 1, 0.04)
@export var grid_line_thickness: float = 1.0
@export var scroll_spawn_delay: float = 0.1
var _last_scroll_y: float = 0.0
@export var spawn_delay_threshold: float = 256.0
var _scroll_dirty: bool = false
var _scroll_cooldown: float = 0.0
@onready var _content_area: Control = Control.new()
const max_pool: int = 256
@export var content_margin: Vector4 = Vector4(4, 4, 4, 4)
@onready var _overlay = TableOverlay.new()



@export var column_ratios: PackedFloat32Array = PackedFloat32Array([])
@export var hscrollbar: HScrollBar
enum ColumnWidthMode { FIT, RELAXED, FIXED }
@export var column_width_mode: ColumnWidthMode = ColumnWidthMode.RELAXED
@export_range(0.1, 3.0, 0.1) var max_total_width_scale: float = 1.25
@export_range(0.1, 3.0, 0.1) var min_total_column_ratio: float = 1.0
@export_range(10.0, 2000.0, 1.0) var min_column_width: float = 48.0

@export_group("Header")
# Pseudo-header/column color configuration
@export var header_bg_color: Color = Color(0.08, 0.08, 0.08, 1.0)
@export var header_text_color: Color = Color(1, 1, 1, 0.85)
@export var header_grid_color: Color = Color(1, 1, 1, 0.25)
@export var header_font_size: int = 14
@export var header_height: float = 28.0
@export var header_width: float = 64.0

@export var column_names: Array[String] = []
signal col_dtypes
var column_datatypes = []
func set_column_datatypes(names: Array, upd: bool = false) -> void:
	types_changed = true
	column_datatypes = names
	#dataset_obj["col_dtypes"] = names
	col_dtypes.emit()

func set_column_names(names: Array, upd: bool = false) -> void:
	cols = len(names)
	column_names.clear()
	_clear_hover()
	var new_dtypes = []
	for n in names:
		var splited = n.rsplit(":", true, 1)
		column_names.append(splited[0])
		new_dtypes.append(splited[1])
	set_column_datatypes(new_dtypes)
	if cols == outputs_from:
		set_outputs_from(cols-1)
	#(column_names)
	#if upd:
	#	print("kms")
	#	dataset_obj["col_names"] = column_names
	#cols = column_names.size()
	if cols == 0:
		return
	_ensure_column_arg_capacity(cols)

	# Ensure column ratios
	if column_ratios.size() != cols:
		column_ratios = PackedFloat32Array()
		column_ratios.resize(cols)
		for i in range(cols):
			column_ratios[i] = 1.0
	
	# Rebuild metrics (even if dataset empty)
	_rebuild_column_metrics()
	if hscrollbar:
		_update_hscrollbar_range()
	
	queue_redraw()





var default_type_heights: Dictionary[StringName, float] = {}

func mark_created(row: int, col: int, dict: Dictionary):
	cell_defaults[dict.type]._creating(row, col, dict)

var col_caches = {}

func mark_deleting(row: int, col: int, dict: Dictionary):
	cell_defaults[dict.type]._deleting(row, col, dict)

var cell_templates: Dictionary[StringName, PackedScene] = {
	"text": preload("res://scenes/cell.tscn"),
	"num": preload("res://scenes/num.tscn"),
	"image": preload("res://scenes/img.tscn"),
	"float": preload("res://scenes/float.tscn"),
}
var cell_defaults: Dictionary[StringName, TableCell] = {}

func _enter_tree() -> void:
	for i in cell_templates:
		cell_defaults[i] = cell_templates[i].instantiate()
		cell_defaults[i].table = self
		default_type_heights[i] = cell_defaults[i].height
	glob.virtualt = self

var dataset: Array = []
var rows: int = 0
var cols: int = 0

var active_cells: Dictionary = {}

var pool_by_type: Dictionary = {}

var row_heights: PackedFloat32Array = PackedFloat32Array([])
var row_offsets: PackedFloat32Array = PackedFloat32Array([])

var col_widths: PackedFloat32Array = PackedFloat32Array([])
var col_offsets: PackedFloat32Array = PackedFloat32Array([])

var scroll_y: float = 0.0
var scroll_speed_wheel: float = 48.0

var _need_layout: bool = true
var _need_visible_refresh: bool = true

func _update_content_area_rect() -> void:
	if not is_instance_valid(_content_area):
		return

	var left = content_margin.x
	var top = content_margin.y
	var right = content_margin.z
	var bottom = content_margin.w

	_content_area.position = Vector2(left, top)


	var new_width: float = _content_area.size.x
	if column_width_mode != ColumnWidthMode.RELAXED:
		new_width = size.x - (left + right)

	_content_area.size = Vector2(new_width, size.y - (top + bottom))


#


func _ready() -> void:
	add_child(_content_area)
	add_child(_overlay)
	_overlay.table = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 0
	_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL

	content_margin.x += header_width
	content_margin.y += header_height
	glob.menus["row_mod"].child_button_release.connect(_hide)
	#content_margin.z -= header_width*2
	#content_margin.w -= header_height
	#_content_area.clip_contents = true
	_update_content_area_rect()

	if vscrollbar:
		move_child(vscrollbar, -1)
		vscrollbar.scale.x = 1.2
		vscrollbar.anchor_top = 0
		vscrollbar.anchor_bottom = 1
		vscrollbar.offset_top = header_height
		vscrollbar.offset_bottom = 0
		#vscrollbar.offset_left = vscrollbar.size.x
		vscrollbar.position.x -= vscrollbar.size.x * 0.3
		vscrollbar.value_changed.connect(_on_vscrollbar_value_changed)

	if hscrollbar:
		move_child(hscrollbar, -1)
		hscrollbar.scale.y = 1.2
		hscrollbar.anchor_left = 0
		hscrollbar.anchor_right = 1
		hscrollbar.offset_left = header_width
		hscrollbar.offset_right = 0
		hscrollbar.position.y -= hscrollbar.size.y * 0.3
		hscrollbar.value_changed.connect(_on_hscrollbar_value_changed)
		hscrollbar.size.x -= 10
	move_child(_overlay, -1)
	await get_tree().process_frame
	load_empty_dataset()


func _update_hscrollbar_range() -> void:
	if not hscrollbar:
		return

	if cols <= 0:
		hscrollbar.min_value = 0.0
		hscrollbar.max_value = 0.0
		hscrollbar.page = 1.0
		hscrollbar.visible = false
		return

	var content_w: float = col_offsets[cols]
	var view_w: float = size.x - (content_margin.x + content_margin.z)

	hscrollbar.min_value = 0.0
	hscrollbar.max_value = max(content_w, 0.0)  # TOTAL content width, not scroll_range
	hscrollbar.page = max(view_w, 0.0)

	var max_scroll: float = max(0.0, content_w - view_w)
	scroll_x = clamp(scroll_x, 0.0, max_scroll)
	hscrollbar.set_value_no_signal(scroll_x)

	hscrollbar.visible = content_w > view_w + 1.0




func _set_scroll_x(new_value: float, from_bar: bool = false) -> void:
	var content_w: float = col_offsets[cols]
	var view_w: float = size.x - (content_margin.x + content_margin.z)

	var max_scroll = max(0.0, content_w - view_w)
	var clamped = clamp(new_value, 0.0, max_scroll)

	if abs(clamped - scroll_x) < 0.01:
		return

	scroll_x = clamped
	if hscrollbar and not from_bar:
		hscrollbar.set_value_no_signal(scroll_x)

	_need_layout = true
	queue_redraw()







func _on_hscrollbar_value_changed(value: float) -> void:
	_set_scroll_x(value, true)

var scroll_x: float = 0.0
var scroll_speed_horizontal: float = 48.0

@export_range(0.0, 0.5, 0.01) var min_vgrabber_ratio: float = 0.08
@export_range(0.0, 200.0, 1.0) var min_vgrabber_pixels: float = 24.0

func _compute_visual_page(content_h: float, view_h: float) -> float:
	if content_h <= 0.0:
		return view_h
	var track_len = (vscrollbar.size.y if vscrollbar else 0.0)
	var px_ratio = 0.0
	if track_len > 0.0 and min_vgrabber_pixels > 0.0:
		px_ratio = clamp(min_vgrabber_pixels / track_len, 0.0, 0.95)

	var target_ratio = max(min_vgrabber_ratio, px_ratio)

	var R = content_h
	var P_floor = 0.0
	if target_ratio >= 0.999:
		P_floor = R
	else:
		P_floor = (target_ratio * R) / max(1.0 - target_ratio, 0.0001)

	return clamp(max(view_h, P_floor), 0.0, content_h)


func _on_vscrollbar_value_changed(value: float) -> void:
	var content_h: float = _sum_heights
	var view_h: float = _content_area.size.y
	var page_vis = _compute_visual_page(content_h, view_h)

	var max_real = max(0.0, content_h - view_h)
	var max_vis = max(0.0, content_h - page_vis)

	var new_scroll = 0.0
	if max_vis > 0.0 and max_real > 0.0:
		new_scroll = clamp(value, 0.0, max_vis) * (max_real / max_vis)
	else:
		new_scroll = 0.0

	_set_scroll_y(new_scroll, true)


func _update_scrollbar_range() -> void:
	if not vscrollbar:
		return
	var content_h: float = (uniform_row_height * rows) if uniform_row_heights else _sum_heights
	var view_h: float    = _content_area.size.y
	var page_vis = _compute_visual_page(content_h, view_h)
	vscrollbar.min_value = 0.0
	vscrollbar.max_value = max(content_h, 0.0)
	vscrollbar.page      = max(page_vis, 0.0)
	var max_real = max(0.0, content_h - view_h)
	var max_vis  = max(0.0, content_h - page_vis)
	var bar_value = 0.0
	if max_real > 0.0 and max_vis > 0.0:
		bar_value = clamp(scroll_y * (max_vis / max_real), 0.0, max_vis)
	vscrollbar.set_value_no_signal(bar_value)
	vscrollbar.visible = content_h > view_h + 0.5





var adapter_data = null
func _adapter_on_load(data, cols: int, rows: int) -> void:
	adapter_data = data
	self.cols = cols
	self.rows = rows

func _get_cell(row: int, col: int) -> Dictionary:
	#if len(adapter_data[row]) < 3:
	#	print(adapter_data[row] )
	return adapter_data[row][col] if rows > 0 else {}

func _set_cell(row: int, col: int, data: Dictionary) -> void:
	adapter_data[row][col] = data
	if active_cells.has(Vector2i(row, col)):
		active_cells[Vector2i(row, col)].map_data(data)

func _init_row_metrics() -> void:
	row_heights.resize(rows)
	row_offsets.resize(rows + 1)
	row_offsets[0] = 0.0
	var acc = 0.0
	for r in range(rows):
		row_heights[r] = 0.0
		row_offsets[r + 1] = acc

func _ensure_row_metrics_visible(r0: int, r1: int) -> void:
	if uniform_row_heights:
		return
	for r in range(r0, r1 + 1):
		if row_heights[r] == 0.0:
			var max_h = 0.0
			for c in range(cols):
				var cell_info: Dictionary = _get_cell(r, c)
				var cell_type: StringName = cell_info.type
				var default_cell: TableCell = cell_defaults[cell_type]
				max_h = max(max_h, default_cell._estimate_height(cell_info))
			row_heights[r] = max_h
	for r in range(r0, r1 + 1):
		row_offsets[r + 1] = row_offsets[r] + row_heights[r]

signal ds_cleared
func load_empty_dataset(clear_cols: bool = true, object = null) -> void:
	cl_cache()
	_clear_table_state(false, clear_cols)
	adapter_data = []
	dataset = []
	if object != null:
		dataset_obj["arr"] = object
		adapter_data = object
		dataset = object
	ds_cleared.emit()
	rows = 0
	if clear_cols:
		column_arg_packs.clear()
		if dataset_obj != null:
			dataset_obj["col_args"] = column_arg_packs
		cols = 0
		col_widths.clear()
		col_offsets.clear()
	_sum_heights = 0.0
	row_heights.clear()
	row_offsets.clear()
	active_cells.clear()

	if vscrollbar:
		vscrollbar.min_value = 0.0
		vscrollbar.max_value = 0.0
		vscrollbar.page = 1.0
		vscrollbar.visible = false

	if hscrollbar:
		hscrollbar.min_value = 0.0
		hscrollbar.max_value = 0.0
		hscrollbar.page = 1.0
		hscrollbar.visible = false

	_clear_hover()
	_need_layout = false
	_need_visible_refresh = false
	queue_redraw()
	#(cols)
	refresh_preview()
	#(Array(column_names))
	#set_column_names(Array(column_names.duplicate()))


signal dataset_loaded

func set_uniform_row_height(new_height: float) -> void:
	if not uniform_row_heights:
		return

	if new_height <= 0.0:
		return

	uniform_row_height = new_height
	_sum_heights = uniform_row_height * rows

	if vscrollbar:
		_update_scrollbar_range()

	_need_layout = true
	_need_visible_refresh = true
	queue_redraw()


var cached_once: Dictionary = {}
func reindex_cache():
	_dataset_cache = dataset_obj["cache"]
	var columns = _dataset_cache.get_or_add("cols", [])
	if not columns:
		for i in cols:
			create_column_cache(0)
	if not cached_once.has(dataset_obj["name"]):
		for i in rows:
			for c in cols:
				mark_created(i, c, _get_cell(i, c))
		cached_once[dataset_obj["name"]] = true

var _dataset_cache: Dictionary = {}
func load_dataset(data, _cols: int, _rows: int) -> void:
	if not data:
		load_empty_dataset(false)
		return
	
	_clear_table_state(false)
	dataset = []
	dataset_obj["arr"] = data
	cols = _cols
	rows = _rows
	dataset_loaded.emit()
	_adapter_on_load(data, cols, rows)
	_ensure_column_ratios()
	
#	_ensure_column_arg_capacity(cols)

	if uniform_row_heights:
		if rows > 0 and cols > 0:
			re_uni.call_deferred()
			#var cell_info = _get_cell(0, 0)
			#var maximal = 0
			#if cell_defaults.has(cell_info.type):
				#var default_cell: TableCell = cell_defaults[cell_info.type]
				#maximal = max(maximal, default_cell._estimate_height(cell_info))
			##uniform_row_height = maximal
			#set_uniform_row_height.call_deferred(maximal)
			#(uniform_row_height)
		else:
			uniform_row_height = 0.0

	_rebuild_row_offsets()
	_offset_valid_upto = rows
	_sum_heights = row_offsets[rows] if not uniform_row_heights else uniform_row_height * rows
	_rebuild_column_metrics()

	if vscrollbar:
		_update_scrollbar_range()
	_need_layout = true
	_need_visible_refresh = true
	_clear_hover()
	queue_redraw()
	refresh_preview()





func get_row_at_position(local_pos: Vector2) -> int:
	if rows <= 0:
		return -1

	var y_in_content = local_pos.y + scroll_y - content_margin.y

	if y_in_content < 0.0 or y_in_content > _sum_heights:
		return -1

	_extend_offsets_to(rows)
	return clamp(_find_row_for_y(y_in_content), 0, rows - 1)




func serialize() -> Array:
	var out: Array = []
	for r in rows:
		var row_data: Array = []
		for c in cols:
			var key = Vector2i(r, c)
			if active_cells.has(key):
				var cell: Node = active_cells[key]
				row_data.append(cell.get_data())
			else:
				row_data.append(_get_cell(r, c))
		out.append(row_data)
	return out


func set_column_ratios(ratios: PackedFloat32Array) -> void:
	column_ratios = ratios.duplicate()
	_ensure_column_ratios()
	_rebuild_column_metrics()
	_need_layout = true
	_need_visible_refresh = true
	queue_redraw()

func _ensure_column_ratios() -> void:
	if cols <= 0:
		column_ratios = PackedFloat32Array([])
		return
	if column_ratios.is_empty() or column_ratios.size() != cols:
		var even: float = 1.0
		column_ratios = PackedFloat32Array()
		column_ratios.resize(cols)
		for i in cols:
			column_ratios[i] = even

func _rebuild_column_metrics() -> void:
	col_widths = PackedFloat32Array()
	col_offsets = PackedFloat32Array()
	if cols <= 0:
		return

	col_widths.resize(cols)
	col_offsets.resize(cols + 1)

	var sum_ratios: float = 0.0
	for i in range(cols):
		sum_ratios += column_ratios[i]

	var view_w: float = size.x - header_width
	var target_w: float

	match column_width_mode:
		ColumnWidthMode.RELAXED:
			target_w = view_w * max_total_width_scale
		ColumnWidthMode.FIT:
			target_w = view_w
		ColumnWidthMode.FIXED:
			target_w = view_w * sum_ratios / min_total_column_ratio

	# --- Measure header text width for each column ---
	var font = get_theme_font("font", "Label")
	var fsize = header_font_size
	var text_based_widths: Array[float] = []
	for i in range(cols):
		var col_name = column_names[i] if (i < column_names.size()) else ""
		var text_w = 0.0
		if font:
			text_w = font.get_string_size(col_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		text_based_widths.append(max(min_column_width, text_w + 16.0)) # 8px padding each side

	# --- Build final widths & offsets ---
	var acc: float = 0.0
	col_offsets[0] = 0.0
	for i in range(cols):
		var ratio = column_ratios[i]
		var w_ratio = target_w * (ratio / sum_ratios)
		var w_final = max(text_based_widths[i], w_ratio)
		col_widths[i] = w_final
		acc += w_final
		col_offsets[i + 1] = acc

	if hscrollbar:
		_update_hscrollbar_range()



func scroll_to_row(row_index: int, align: String = "top") -> void:
	# Ensure metrics are valid
	if row_index < 0 or row_index >= rows:
		return
	_extend_offsets_to(row_index + 1)

	var target_y = row_offsets[row_index] if not uniform_row_heights else uniform_row_height*row_index
	var row_h = row_heights[row_index] if not uniform_row_heights else uniform_row_height
	var view_h = _content_area.size.y
	var content_h = _sum_heights

	match align:
		"center":
			target_y = clamp(target_y - (view_h - row_h) * 0.5, 0.0, max(0.0, content_h - view_h))
		"bottom":
			target_y = clamp(target_y - (view_h - row_h), 0.0, max(0.0, content_h - view_h))
		_:
			# Default = top
			target_y = clamp(target_y, 0.0, max(0.0, content_h - view_h))

	_set_scroll_y(target_y)



var _height_cache: Dictionary = {}
var _offset_valid_upto: int = 0
var _sum_heights: float = 0.0

func _rebuild_row_heights_estimate() -> void:
	if rows <= 0 or cols <= 0:
		row_heights.clear()
		_sum_heights = 0.0
		return

	row_heights.resize(rows)
	var total = 0.0
	for r in range(rows):
		var max_h = 0.0
		for c in range(cols):
			var cell_info: Dictionary = adapter_data[r][c]
			var cell_type: StringName = cell_info.type
			var default_cell: TableCell = cell_defaults[cell_type]
			if not cell_type in _height_cache:
				_height_cache[cell_type] = {}
			var key = default_cell._height_key(cell_info)
			var h: float
			if _height_cache[cell_type].has(key):
				h = _height_cache[cell_type][key]
			else:
				h = default_cell._estimate_height(cell_info)
				_height_cache[cell_type][key] = h
			if h > max_h:
				max_h = h
		row_heights[r] = max_h
		total += max_h
	_sum_heights = total

signal deleted
func delete_myself():
	glob.del_dataset_file(dataset_obj.name)
	glob.ds_dump.erase(dataset_obj.name)
	glob.dataset_datas.erase(dataset_obj.name)
	glob.rle_cache.erase(dataset_obj.name)
	dataset_obj.clear()
	load_empty_dataset(true)
	deleted.emit()

func _ensure_offsets_capacity() -> void:
	if row_offsets.size() == 0:
		row_offsets.resize(1)
		row_offsets[0] = 0.0
	if row_offsets.size() < rows + 1:
		var old = row_offsets.size()
		row_offsets.resize(rows + 1)
		for i in range(old, rows + 1):
			row_offsets[i] = row_offsets[i - 1]

func _invalidate_offsets_from(index: int) -> void:
	# All offsets from index onward may change
	_offset_valid_upto = min(_offset_valid_upto, clamp(index, 0, rows))

func _extend_offsets_to(target: int) -> void:
	if uniform_row_heights:
		return
	# ensure row_offsets[0..target] valid (target in [0..rows])
	_ensure_offsets_capacity()
	target = clamp(target, 0, rows)
	if _offset_valid_upto == 0:
		row_offsets[0] = 0.0
	var i = _offset_valid_upto
	while i < target:
		row_offsets[i + 1] = row_offsets[i] + row_heights[i]
		i += 1
	_offset_valid_upto = max(_offset_valid_upto, target)


func _flush_active_from(row_index: int) -> void:
	var to_remove: Array = []
	for key in active_cells.keys():
		if key.x >= row_index:
			_release_cell(active_cells[key])
			to_remove.append(key)
	for k in to_remove:
		active_cells.erase(k)

var dataset_obj = null

func destroy_column_cache(idx: int):
	var got = _dataset_cache.get_or_add("cols", []).pop_at(idx)
	if got != null:
		got.clear()

func get_ccache(c: int):
	return _dataset_cache["cols"][c]

func create_column_cache(idx: int):
	_dataset_cache.get_or_add("cols", []).insert(idx, {})

func _add_cells(at_index: int, cells):
	for i in len(cells):
		mark_created(at_index, i, cells[i])
	adapter_data.insert(at_index, cells)
	dataset_obj["arr"] = adapter_data

func cl_cache():
	for col in _dataset_cache.get_or_add("cols", []):
		col.clear()

func mark_destroyed(r: int, c: int):
	var dict = _get_cell(r,c)
	cell_defaults[dict.type]._deleting(r, c, dict)

func _del_cells(at_index: int):
	for i in len(adapter_data[at_index]):
		#("destroy!")
		mark_destroyed(at_index, i)
	adapter_data.remove_at(at_index)
	dataset_obj["arr"] = adapter_data

var dirty: bool = false

signal dirtified(idx, is_add, is_delete)

func dirtify(idx=null, is_add=false, is_delete=false):
	glob.dirtify_dataset(dataset_obj.name)
	dirtified.emit(idx, is_add, is_delete)


var types_changed: bool = false
func add_row(cells: Array = [], at_index: int = -1) -> void:
	if at_index < 0 or at_index > rows:
		at_index = rows
	#return
	if rows == 0 and cols == 0:
		if cells.size() == 0:
			push_error("Cannot infer column count: empty row inserted into empty table.")
			return
		cols = cells.size()
		_ensure_column_ratios()
		_rebuild_column_metrics()

		if adapter_data == null:
			adapter_data = []
		if not adapter_data:
			adapter_data.clear()

	_add_cells(at_index, cells)
	dirtify(at_index, true)
	rows += 1

	var base_h = 0.0
	for c in range(cols):
		if c >= cells.size():
			continue
		var cell_info = cells[c]
		var t: StringName = cell_info.type
		if cell_defaults.has(t):
			base_h = max(base_h, cell_defaults[t]._estimate_height(cell_info))

	row_heights.insert(at_index, base_h)
	_sum_heights += base_h

	if row_offsets.size() < rows + 1:
		row_offsets.resize(rows + 1)
	_invalidate_offsets_from(at_index + 1)

	_flush_active_from(at_index)
	if uniform_row_height and types_changed:
		re_uni()
		types_changed = false
	_rebuild_row_offsets()

		

	_need_layout = true
	_need_visible_refresh = true
	#(adapter_data)
	queue_redraw()

	if vscrollbar:
		await get_tree().process_frame
		_update_scrollbar_range()
	refresh_preview()

func re_uni():
	var maximal = 0
	if not adapter_data: return
	for i in adapter_data[0]:
		maximal = max(maximal, default_type_heights[i.type])
	set_uniform_row_height(maximal)



func remove_row(index: int) -> void:
	if index < 0 or index >= rows:
		return
	if rows <= 1:
		_del_cells(index)
		dirtify(index, false, true)
		load_empty_dataset(false)
		return
	var old_h: float = 0.0
	if uniform_row_heights:
		old_h = uniform_row_height
	else:
		if row_heights.size() > index:
			old_h = row_heights[index]
		else:
			old_h = 0.0

	_sum_heights -= old_h

	_del_cells(index)
	rows -= 1

	if not uniform_row_heights:
		if row_heights.size() > index:
			row_heights.remove_at(index)

		_invalidate_offsets_from(index)
		if row_offsets.size() >= index + 2:
			row_offsets.remove_at(index + 1)
		if row_offsets.size() < rows + 1:
			row_offsets.resize(rows + 1)

	_flush_active_from(index)

	if vscrollbar:
		_update_scrollbar_range()
	
	_need_layout = true
	_need_visible_refresh = true
	queue_redraw()
	refresh_preview()
	dirtify(index, false, true)





func _rebuild_row_offsets(start_index: int = 0) -> void:
	if uniform_row_heights:
		_sum_heights = uniform_row_height * rows
		return
	if rows <= 0:
		_sum_heights = 0.0
		return

	_ensure_offsets_capacity()
	row_offsets[0] = 0.0
	for i in range(1, rows + 1):
		row_offsets[i] = row_offsets[i - 1] + row_heights[i - 1]
	_sum_heights = row_offsets[rows]


var cell_colors: Dictionary = {}
var row_colors: Dictionary = {}

func set_cell_color(row: int, col: int, color: Color) -> void:
	if row < 0 or row >= rows or col < 0 or col >= cols:
		return
	cell_colors[Vector2i(row, col)] = color
	queue_redraw()

func clear_cell_color(row: int, col: int) -> void:
	cell_colors.erase(Vector2i(row, col))
	queue_redraw()

func set_row_color(row: int, color: Color) -> void:
	if row < 0 or row >= rows:
		return
	row_colors[row] = color
	queue_redraw()

func clear_row_color(row: int) -> void:
	row_colors.erase(row)
	queue_redraw()

func clear_all_colors() -> void:
	cell_colors.clear()
	row_colors.clear()
	queue_redraw()


func _update_row_height_if_needed(row: int, new_height: float) -> void:
	if uniform_row_heights:
		return
	if row < 0 or row >= rows: return
	if new_height > row_heights[row] + 0.5:
		var delta = new_height - row_heights[row]
		row_heights[row] = new_height
		_sum_heights += delta       # <<< keep range correct
		_invalidate_offsets_from(row + 1)  # suffix depends on this row

		_need_layout = true
		_need_visible_refresh = true
		if vscrollbar:
			_update_scrollbar_range()
		queue_redraw()



func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_scroll_y(scroll_y - scroll_speed_wheel)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_scroll_y(scroll_y + scroll_speed_wheel)

func _set_scroll_y(new_value: float, from_bar: bool = false) -> void:
	var content_h: float = _sum_heights
	var view_h: float    = _content_area.size.y

	var clamped = clamp(new_value, 0.0, max(0.0, content_h - view_h))
	if abs(clamped - scroll_y) < 0.5:
		return

	scroll_y = clamped
	if vscrollbar and not from_bar:
		vscrollbar.set_value_no_signal(scroll_y)

	_scroll_dirty = true
	_scroll_cooldown = 0.0
	_need_layout = true
	queue_redraw()
	if _hovered_cell != null and is_instance_valid(_hovered_cell):
		var hk = _hovered_key
		if not active_cells.has(hk) or not _hovered_cell.visible:
			_clear_hover(true)

	glob.hide_all_menus()



var just_resized: bool = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_set_scroll_y(scroll_y)
		_update_content_area_rect()
		just_resized = true
		if column_width_mode != ColumnWidthMode.RELAXED:
			_rebuild_column_metrics()
		_need_layout = true
		_need_visible_refresh = true

		if vscrollbar:
			_update_scrollbar_range()
		if hscrollbar:
			_update_hscrollbar_range()
		queue_redraw()


var _time_since_scroll_move: float = 0.0
var _delay_active: bool = false
var _vel_smoothed: float = 0.0

var _last_scrollbar_rect: Rect2

func get_default_row(where: int = -1):
	var cells = []
	if rows and where != -1:
		for i in cols:
			var uppertype = _get_cell(where+1 if where == 0 else where-1, i)["type"]
			var def = get_type_default(uppertype)
			def["type"] = uppertype
			cells.append(def)
	else:
		for i in cols:
			var def = get_type_default(column_datatypes[i])
			def["type"] = column_datatypes[i]
			cells.append(def)
	return cells

func _hide(arg):
	if !querying:
		glob.menus["row_mod"].menu_hide()
var query_lock = false
func to_query(row: int, mp: Vector2):
	if querying:
		glob.menus["row_mod"].menu_hide()
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	clear_all_colors()
	var menu = glob.menus["row_mod"]
	set_row_color(row, Color(1, 1, 1, 0.1))
	menu.set_txt(str(row) if row != -1 else "")
	var menu_p = mp.clamp(global_position, 
	get_global_rect().end - Vector2(menu.base_size.x, menu.expanded_size) * menu.base_scale)
	querying = true
	var a = await menu.ask_and_wait(menu_p, false, true if !next_query else false)
	next_query = null
	#(a)
	querying = false
	#(a.hint)
	if a and not glob.ds_processing():
		if a.hint == "delete":
			#("FJFJ")
			var old_rows = rows-1
			remove_row(row if row != -1 else 0)
			if row == old_rows:
				menu.menu_hide()
				clear_all_colors()
			else:
				next_query = [row if row != -1 else 0, mp]
		elif a.hint == "insert":
			if row != -1:
				#("dd")
				row += 1
			#add_row(get_default_row(), row)
			add_row(get_default_row(), row)
			#remove_row(row)
			if row == -1:
				set_row_color(0, Color(1, 1, 1, 0.1))
			next_query = [row if row != -1 else 0, mp]
		#if a.hint == "insert" or rows > 0:
			##("AA")
			#next_query = [row if row != -1 else 0, mp]
		#else:
			#menu.menu_hide()
			#clear_all_colors()
	else:
		menu.menu_hide()
		clear_all_colors()

signal dataset_refreshed

func get_type_default(type: String):
	return cell_defaults[type]._defaults()


func convert_cell(row: int, col: int, dtype: String) -> Dictionary:
	var got = _get_cell(row, col)
	return cell_defaults[got["type"]]._convert(got, dtype)


func refresh_dataset(force_full: bool = false) -> void:
	if adapter_data == null:
		return

	var new_rows = adapter_data.size()
	if new_rows == 0:
		_clear_table_state()
		rows = 0
		cols = 0
		queue_redraw()
		dataset_refreshed.emit()
		return

	var new_cols = (adapter_data[0].size() if new_rows > 0 else 0)

	var shape_changed = (new_rows != rows or new_cols != cols)

	rows = new_rows
	cols = new_cols

	if force_full or shape_changed:
		if uniform_row_heights:
			if rows > 0 and cols > 0:
				var cell_info = _get_cell(0, 0)
				var default_cell: TableCell = cell_defaults[cell_info.type]
				uniform_row_height = default_cell._estimate_height(cell_info)
			_sum_heights = uniform_row_height * rows
		else:
			_rebuild_row_heights_estimate()
			_rebuild_row_offsets()
			_sum_heights = row_offsets[rows]

		_rebuild_column_metrics()
		if vscrollbar:
			_update_scrollbar_range()
		if hscrollbar:
			_update_hscrollbar_range()

		_flush_active_from(0)
		_need_visible_refresh = true
		_need_layout = true
		queue_redraw()
		dataset_refreshed.emit()
		return

	for key in active_cells.keys():
		var r: int = key.x
		var c: int = key.y
		if r < rows and c < cols:
			var cell = active_cells[key]
			if cell and is_instance_valid(cell):
				cell.map_data(_get_cell(r, c))
				cell.coord = Vector2i(r, c)

	if not uniform_row_heights:
		var visible_range = get_visible_row_range()
		_ensure_row_metrics_visible(visible_range.x, visible_range.y)

	_sum_heights = (uniform_row_height * rows) if uniform_row_heights else row_offsets[min(row_offsets.size() - 1, rows)]

	if vscrollbar:
		_update_scrollbar_range()
	if hscrollbar:
		_update_hscrollbar_range()

	_need_layout = true
	_need_visible_refresh = true
	queue_redraw()
	dataset_refreshed.emit()

	refresh_preview()

func _clear_table_state(full_reset: bool = true, reset_cols: bool = false) -> void:
	for cell in active_cells.values():
		_release_cell(cell)
	active_cells.clear()

	if full_reset:
		pool_by_type.clear()

	scroll_y = 0.0
	scroll_x = 0.0

	row_heights.clear()
	row_offsets.clear()
	if reset_cols:
		col_widths.clear()
		col_offsets.clear()
	cell_colors.clear()
	row_colors.clear()

	_sum_heights = 0.0
	_offset_valid_upto = 0

	_need_layout = false
	_need_visible_refresh = false

	if vscrollbar:
		vscrollbar.min_value = 0.0
		vscrollbar.max_value = 0.0
		vscrollbar.page = 1.0
		vscrollbar.visible = false

	if hscrollbar:
		hscrollbar.min_value = 0.0
		hscrollbar.max_value = 0.0
		hscrollbar.page = 1.0
		hscrollbar.visible = false



var _hovered_key: Vector2i = Vector2i(-1, -1)
var _hovered_cell: TableCell = null


func _process_hover_detection(row: int) -> void:
	if rows <= 0 or cols <= 0:
		_clear_hover(true)
		return

	var mp_global: Vector2 = get_global_mouse_position()

	if not get_global_rect().has_point(mp_global):
		_clear_hover(true)
		return

	var local_mp: Vector2 = get_local_mouse_position()
	var y_in = local_mp.y + scroll_y - content_margin.y
	var x_in = local_mp.x + scroll_x - content_margin.x

	if y_in < 0.0 or x_in < 0.0 or y_in >= _sum_heights:
		_clear_hover(true)
		return

	if row < 0 or row >= rows:
		_clear_hover(true)
		return

	var col = -1
	for i in range(cols):
		if x_in >= col_offsets[i] and x_in < col_offsets[i + 1]:
			col = i
			break

	if col == -1:
		_clear_hover(true)
		return

	var key = Vector2i(row, col)
	var new_cell: TableCell = null
	if active_cells.has(key):
		new_cell = active_cells[key]

	if new_cell == null or not is_instance_valid(new_cell) or not new_cell.visible:
		_clear_hover(true)
		return

	var rect = Rect2(new_cell.global_position, new_cell.size)
	if not rect.has_point(mp_global):
		_clear_hover(true)
		return

	if _hovered_key == key and _hovered_cell == new_cell:
		return

	_clear_hover(true)
	if ui.active_splashed(): return
	_hovered_key = key
	_hovered_cell = new_cell
	_hovered_cell._mouse_enter()


func _clear_hover(force = false) -> void:
	if _hovered_cell and is_instance_valid(_hovered_cell):
		_hovered_cell._mouse_exit()
	_hovered_cell = null
	_hovered_key = Vector2i(-1, -1)


func active_remap():
	for i in active_cells:
		active_cells[i].map_data(active_cells[i].cell_data)


var rendering_disabled: bool = false
var next_query = null
var querying: bool = false
var prev_row = {}





func _process(delta: float) -> void:
	#if glob.space_just_pressed:
	#	var t = Time.get_ticks_msec()
	#	( DsObjRLE.flush_now(dataset_obj.name, dataset_obj))
		#(Time.get_ticks_msec() - t)
		#(DsObjProbe.probe_dataset(dataset_obj.name))
	#	web.POST("cache_ds", {"dataset": DsObjRLE.compress_and_send(dataset_obj, true)})
	#if dataset_obj:
	#	print(dataset_obj["col_args"])
	#(dataset_obj["col_args"])
	#(column_names)
	if not is_visible_in_tree():
		return
	if rendering_disabled:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_INHERIT
		
	#(glob.menu_type)
	#(disabled)
	#(query_lock)
	#(dataset_obj)
	if addition_enabled and not disabled and dataset_obj and dataset_obj.size() > 1:
		if next_query and not querying and not query_lock:
			query_lock = true
			await to_query.callv(next_query)
			query_lock = false
		var mp: Vector2 = get_global_mouse_position()
		var local_mp = get_local_mouse_position()
		var row = get_row_at_position(local_mp)
		_process_hover_detection(row)
		if get_global_rect().has_point(mp):
			glob.set_menu_type(self, "row_mod")
			#if row != -1:
			#	prev_row
			if glob.mouse_alt_just_pressed:
				if query_lock:
					#("fjfj")
					glob.menus["row_mod"].menu_hide()
				query_lock = false
				#("AA")
				next_query = null
				if row != -1 or rows <= 0:
				#if glob.menus["row_mod"].visible:
				#	glob.menus["row_mod"].menu_hide()
					await to_query(row, mp)
				if row == -1:
					glob.menus["row_mod"].menu_hide()
		elif not querying:
			if row_colors:
				clear_all_colors()
	var dy = abs(scroll_y - _last_scroll_y)
	var inst_vel = dy / delta
	_vel_smoothed = lerp(_vel_smoothed, inst_vel, 5.0 * delta)
	_last_scroll_y = scroll_y

	var fast_scroll = _vel_smoothed > spawn_delay_threshold

	if dy > 0.5:
		_time_since_scroll_move = 0.0
		_delay_active = true
	else:
		_time_since_scroll_move += delta

	var allow_spawning = true
	if fast_scroll:
		if _delay_active and _time_since_scroll_move < scroll_spawn_delay:
			allow_spawning = false
		elif _time_since_scroll_move >= scroll_spawn_delay:
			_delay_active = false

	_refresh_visible_cells(allow_spawning)
	_layout_active_cells()
	just_resized = false
	#if glob.space_just_pressed:
	#	refresh_preview()

var schemas = {"text": [], "num": ["min", "max"], "image": [], "float": []}
var default_argpacks = {"text": {}, "num": {"min": 0, "max": 100}, "image": {}, "float": {}}
func get_arg_schema(dt: String):
	#(dt)
	return schemas.get(dt, [])


var column_arg_packs: Array = []   # index = column index

func _ensure_column_arg_capacity(new_cols: int) -> void:
	if column_arg_packs.size() != new_cols:
		var old = column_arg_packs
		column_arg_packs = []
		column_arg_packs.resize(new_cols)
		for i in range(new_cols):
			column_arg_packs[i] = (old[i].duplicate(true) if i < old.size() else default_argpacks.get(column_datatypes[i], []).duplicate(true))
	
	if dataset_obj != null:
		dataset_obj["col_args"] = column_arg_packs


func set_column_arg_packs(packs: Array) -> void:
	if dataset_obj == null: return
	var out: Array = []
	packs = packs.duplicate()
	out.resize(packs.size())
	for i in range(packs.size()):
		var p = packs[i].duplicate()
		if i < len(dataset_obj["col_args"]):
			p.merge(dataset_obj["col_args"][i].duplicate())
		out[i] = p
	#(packs)
	column_arg_packs = out
	dataset_obj["col_args"] = column_arg_packs
	#await get_tree().process_frame
	#data_map_allowed = true
	#active_remap()

var data_map_allowed: bool = true

func get_column_arg_pack(col: int) -> Dictionary:
	if col < 0 or col >= column_arg_packs.size():
		return {}
	return column_arg_packs[col]


func set_column_arg(col: int, key: String, value: Variant) -> void:
	if col < 0 or col >= column_arg_packs.size():
		return
	column_arg_packs[col][key] = value
	if dataset_obj != null:
		dataset_obj["col_args"] = column_arg_packs


func remove_column_arg(col: int, key: String) -> void:
	if col < 0 or col >= column_arg_packs.size():
		return
	column_arg_packs[col].erase(key)
	if dataset_obj != null:
		dataset_obj["col_args"] = column_arg_packs



func _refresh_visible_cells(allow_spawning: bool = true) -> void:
	
	if rows <= 0 or cols <= 0:
		_hide_all_cells()
		return

	var inner_h = _content_area.size.y
	var view_top = scroll_y
	var view_bottom = scroll_y + inner_h
	var pre = 2

	var r0 = clamp(_find_row_for_y(view_top) - pre, 0, max(0, rows - 1))
	var r1 = clamp(_find_row_for_y(view_bottom) + pre, 0, rows - 1)
	_extend_offsets_to(r1 + 1) 
	_ensure_row_metrics_visible(r0, r1)

	var c0 = 0
	var c1 = cols - 1

	#_ensure_row_metrics_visible(r0, r1)
	var seen = {}
	#(just_resized)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var key = Vector2i(r, c)
			seen[key] = true

			if active_cells.has(key):
				active_cells[key].visible = true
				if just_resized:
					active_cells[key]._resized.call_deferred()
				continue

			var reused = _try_reuse_cell(r, c)
			if reused:
				reused.visible = true
				active_cells[key] = reused
				if just_resized:
					reused._resized.call_deferred()
				continue

			if allow_spawning:
			#	print("fkfk")
				_spawn_cell(r, c)

	if _hovered_cell != null and not seen.has(_hovered_key):
		_clear_hover(true)
	#(len(active_cells))
	for key in active_cells.keys():
		if not seen.has(key):
			var cell = active_cells[key]
			#cell.visible = false
			_release_cell(cell)
			active_cells.erase(key)



func _try_reuse_cell(row: int, col: int) -> TableCell:
	var got = _get_cell(row, col)
	var t: String = String(got.type)
	if not pool_by_type.has(t):
		return null
	var pool = pool_by_type[t]
	if pool.size() == 0:
		return null
	var cell: TableCell = pool.pop_back()
	cell.coord = Vector2i(row, col)
	_content_area.add_child(cell)
	cell._mouse_exit()#
	#("=====")
	#(col, " ", got)
	cell.map_data(got)
	#(col, " ", got)
	cell._resized.call_deferred()
	return cell




func _hide_all_cells() -> void:
	if _hovered_cell != null:
		_clear_hover(true)
	for key in active_cells.keys():
		var cell: TableCell = active_cells[key]
		cell.visible = false

func push_textures(who: TableCell, imgs):
	#(imgs)
	if glob.ds_processing():
		return
	for i in len(imgs):
		var r = i+who.coord.x
		#(r)
		if r < rows: # row
			pass
		else:
			add_row(get_default_row(-1), -1)
		var got = _get_cell(r, who.coord.y)
		var old_dims = Vector2i(got["x"], got["y"])
		got["img"] = imgs[i]
		got["x"] = int(imgs[i].get_width()) if imgs[i] else 0
		got["y"] = int(imgs[i].get_height()) if imgs[i] else 0
		cell_defaults["image"].change_cache(r, who.coord.y, old_dims, got)
		_set_cell(r, who.coord.y, got)
		dirtify(who.coord.x)
			#(got)
	_need_layout = true
	_need_visible_refresh = true
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	refresh_preview()


func _spawn_cell(row: int, col: int) -> void:
	var t: StringName = _get_cell(row, col).type
	var cell: TableCell = _acquire_cell(t)
	#cell._resized()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cell == null:
		return
	_content_area.add_child(cell)
	cell.coord = Vector2i(row, col)
	cell._mouse_exit()
	
	cell.visible = true

	var d: Dictionary = _get_cell(row, col)
	cell.map_data(d)
	active_cells[Vector2i(row, col)] = cell
	cell._resized()
	cell.coord = Vector2i(row, col)
	#_cell_entered_view(cell, row, col)
	var desired: Vector2 = Vector2(col_widths[col], cell.height)
	_update_row_height_if_needed(row, desired.y)
	_need_layout = true


func _acquire_cell(cell_type: StringName) -> TableCell:
	if pool_by_type.has(cell_type) and pool_by_type[cell_type].size() > 0:
		return pool_by_type[cell_type].pop_back()
	return _create_cell_instance(cell_type)



func _release_cell(cell: TableCell) -> void:
	var t: String = cell.cell_type
	if not pool_by_type.has(t):
		pool_by_type[t] = []
	var pool = pool_by_type[t]
	if _hovered_cell == cell:
		_clear_hover(true)
	if pool.size() < max_pool:
		_content_area.remove_child(cell)
		cell._mouse_exit()
		pool.append(cell)
	else:
		cell.queue_free()
	pool_by_type[t] = pool


func _layout_active_cells() -> void:
	var changed = false
	for key in active_cells.keys():
		var row: int = key.x
		var col: int = key.y
		var cell: TableCell = active_cells[key]
		if not cell.visible:
			continue

		var x = col_offsets[col] - scroll_x
		var y = (row * uniform_row_height - scroll_y) if uniform_row_heights else (row_offsets[row] - scroll_y)
		var w = col_widths[col]
		var h = (uniform_row_height if uniform_row_heights else row_heights[row])

		var pos = Vector2(x, y).floor()
		var size_rc = Vector2(w, h).floor()

		if cell.position != pos or cell.size != size_rc:
			cell.position = pos
			cell.size = size_rc
			changed = true
			cell._resized()

	if changed or _need_layout:
		queue_redraw()
		_need_layout = false




func _position_cell(cell: TableCell, row: int, col: int, top_left: Vector2, size_rc: Vector2) -> void:
	cell.position = top_left.floor()
	cell.size = size_rc.floor()

var outputs_from: int = 1
func set_outputs_from(i: int):
	outputs_from = i
	dataset_obj["outputs_from"] = i
	queue_redraw()
	refresh_preview()
	
	
func _draw() -> void:
	_overlay.queue_redraw()

	var left = content_margin.x
	var top = content_margin.y
	var inner_size = _content_area.size
	var content_w: float = (col_offsets[cols] if cols > 0 else 0.0)
	var content_h: float = _sum_heights

	# clear background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), true)
	if rows <= 0 or cols <= 0:
		return

	var view_top = scroll_y
	var view_bottom = scroll_y + inner_size.y
	var r0 = clamp(_find_row_for_y(view_top), 0, max(0, rows - 1))
	var r1 = clamp(_find_row_for_y(view_bottom), 0, rows - 1)

	_extend_offsets_to(r1 + 1)

	for r in range(r0, r1 + 1):
		var y0: float
		var y1: float
		if uniform_row_heights:
			y0 = (r * uniform_row_height) - scroll_y + top
			y1 = ((r + 1) * uniform_row_height) - scroll_y + top
		else:
			y0 = row_offsets[r] - scroll_y + top
			y1 = row_offsets[r + 1] - scroll_y + top
		var h = y1 - y0

		# 1. Odd row background tint
		if not row_colors.has(r) and (r % 2) == 1:
			draw_rect(Rect2(Vector2(left, y0), Vector2(content_w, h)), odd_row_tint, true)

		# 2. Row overlay color (manual highlight)
		if row_colors.has(r):
			draw_rect(Rect2(Vector2(left, y0), Vector2(content_w, h)), row_colors[r], true)

		# 3. Column brightness overlay for outputs
		for c in range(outputs_from, cols):
			var x0 = col_offsets[c] - scroll_x + left
			var x1 = col_offsets[c + 1] - scroll_x + left
			var bright_tint = Color(odd_row_tint.r, odd_row_tint.g, odd_row_tint.b, 0.03) * 1.5
			draw_rect(Rect2(Vector2(x0, y0), Vector2(x1 - x0, h)), bright_tint, true)

		# 4. Per-cell overlays (override row tint)
		for c in range(cols):
			var key = Vector2i(r, c)
			if cell_colors.has(key):
				var x0 = col_offsets[c] - scroll_x + left
				var x1 = col_offsets[c + 1] - scroll_x + left
				draw_rect(Rect2(Vector2(x0, y0), Vector2(x1 - x0, h)), cell_colors[key], true)

	# Horizontal grid lines
	if uniform_row_heights:
		for r in range(r0, r1 + 1):
			var y = (r * uniform_row_height) - scroll_y + top
			draw_line(Vector2(left, y), Vector2(left + content_w, y), grid_line_color, grid_line_thickness)
		var yb = ((r1 + 1) * uniform_row_height) - scroll_y + top
		draw_line(Vector2(left, yb), Vector2(left + content_w, yb), grid_line_color, grid_line_thickness)
	else:
		for r in range(r0, r1 + 1):
			var y = row_offsets[r] - scroll_y + top
			draw_line(Vector2(left, y), Vector2(left + content_w, y), grid_line_color, grid_line_thickness)
		var yb = row_offsets[min(rows, r1 + 1)] - scroll_y + top
		draw_line(Vector2(left, yb), Vector2(left + content_w, yb), grid_line_color, grid_line_thickness)

	# Vertical grid lines
	var vline_top = top
	var view_visible_h = min(inner_size.y, max(0.0, content_h - scroll_y))
	for c in range(cols + 1):
		var x = (col_offsets[c] if c < cols else content_w) - scroll_x + left
		draw_line(Vector2(x, vline_top), Vector2(x, vline_top + view_visible_h), grid_line_color, grid_line_thickness)


func _find_row_for_y(world_y: float) -> int:
	if rows <= 0:
		return 0
	if uniform_row_heights:
		return clamp(int(floor(world_y / uniform_row_height)), 0, rows - 1)
	# fallback to binary search
	while _offset_valid_upto < rows and row_offsets[_offset_valid_upto] <= world_y:
		_extend_offsets_to(_offset_valid_upto + 1)
	var lo = 0
	var hi = max(1, _offset_valid_upto)
	while lo < hi:
		var mid = (lo + hi) >> 1
		if row_offsets[mid] > world_y:
			hi = mid
		elif row_offsets[mid] <= world_y and (mid == rows or row_offsets[mid + 1] > world_y):
			return clamp(mid, 0, rows - 1)
		else:
			lo = mid + 1
	return clamp(lo - 1, 0, rows - 1)




func _create_cell_instance(cell_type: StringName) -> TableCell:
	var scene: PackedScene = cell_templates[cell_type]
	var inst = scene.instantiate()
	inst.table = self
	if not inst is TableCell:
		inst.cell_type = cell_type
		return inst
	inst.cell_type = cell_type
	inst._resized()
	return inst

func _cell_entered_view(cell: TableCell, row: int, col: int) -> void:
	pass

func _cell_exited_view(cell: TableCell, row: int, col: int) -> void:
	pass


#{"name": "mnist", 
		#"size": 70000, "outputs": [
			#{"label": "digit", "x": 10, "datatype": "1d", "label_names": ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]}],
			#"inputs": {"x": 28, "y": 28, "datatype": "2d"},
			#"input_hints": [{"name": "image", "value": "28x28", "dtype": "image"}]}, 

signal preview_refreshed(pr: Dictionary)
var preview = null
func refresh_preview():
	#(dataset_obj)
	preview = get_preview()
	#(preview)
	if preview:
		preview_refreshed.emit(preview)
	#(_dataset_cache)


#no_outputs no_1d_outs mix_2d bad_img
func get_preview(validate_cols: bool = false):
	if not dataset_obj: return {"fatal": ""}
	return DsObjRLE.get_preview(dataset_obj, validate_cols)


func get_visible_row_range() -> Vector2i:
	var top = scroll_y
	var bottom = scroll_y + size.y
	return Vector2i(_find_row_for_y(top), _find_row_for_y(bottom))
