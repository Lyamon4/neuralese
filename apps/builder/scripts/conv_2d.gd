extends BaseNeuronLayer
class_name Conv2D

@export var group_size: int = 5:
	set(v):
		group_size = v
		set_grid(grid.x, grid.y)

@export var grid: Vector2i = Vector2i(0, 0):
	set(v):
		grid = v
		set_grid(grid.x, grid.y)

@export var grid_padding: float = 5.0:
	set(v):
		grid_padding = v
		set_grid(grid.x, grid.y)

@export var offset: Vector2 = Vector2():
	set(v):
		offset = v
		set_grid(grid.x, grid.y)

@export var size_add_vec: Vector2 = Vector2():
	set(v):
		size_add_vec = v
		set_grid(grid.x, grid.y)

func _just_connected(who: Connection, to: Connection):
	graphs.push_2d(grid.x, grid.y, to.parent_graph)

var current_units: Array[Control] = []
var _pool: Array[Control] = []
var _fading_in: Dictionary = {}
var _fading_out: Dictionary = {}

var grid_current: Vector2i = Vector2i.ZERO
var _cells: Dictionary = {}

# sizing
var biggest_size_possible: Vector2 = Vector2()
@onready var target_size_vec: Vector2 = rect.size

func _useful_properties() -> Dictionary:
	var conf = get_config_dict()
	conf["activation"] = "none"
	conf["type"] = layer_name
	if 0 in input_keys:
		var ik = input_keys[0]
		if ik and ik.inputs and ik.inputs.size() > 0:
			var first_key = ik.inputs.keys()[0]
			if first_key and first_key.origin and first_key.origin.parent_graph:
				conf["activation"] = first_key.origin.parent_graph.selected_activation
	return {
		"neuron_count": grid.x * grid.y,
		"config": conf,
		"cache_tag": str(graph_id)
	}

@onready var base_output_offset = $o.position - rect.size
@onready var base_input_offset = $ni.position
@onready var base_activ_offset = $activ.position if get_node_or_null("activ") else null

var unfree_mode: bool = false
func _after_ready() -> void:
	super()
	await get_tree().process_frame
	set_grid(0, 0)
	size_changed()
	if layer_name == "Conv2D":
		$filter.size = Vector2()
		$filter2.size = Vector2()
	update_config(base_config.duplicate())
#	size_add_vec = size_add_vec

@export var label_offset: float = 25.0
func _size_changed() -> void:
	$o.position = Vector2(
		base_output_offset.x + rect.size.x,
		rect.size.y / 2.0 + rect.position.y - $o.size.y / 2.0
	)
	$ni.position = Vector2(
		base_input_offset.x,
		rect.size.y / 2.0 + rect.position.y - $ni.size.y / 2.0
	)
	if get_node_or_null("activ"):
		$activ.position = Vector2(
			rect.size.x / 2.0 - $activ.size.x / 2.0 + rect.position.x,
			base_activ_offset.y
		)
	set_extents()
	var label = $ColorRect/root/Label
	label.position.x = rect.size.x / 2.0 - label_offset
	reposition_splines()
	hold_for_frame()

func _dragged():
	set_extents()

func set_extents():
	if not Vector2i() in _cells: return
	var rect_end: Vector2 = Vector2.ONE * max_displayed * \
	(_unit.size + grid_padding*Vector2.ONE) + _cells[Vector2i()].global_position
	for j in _cells:
		var i = _cells[j]
		if j.x >= max_displayed-1 or j.y >= max_displayed-1: pass
		else: continue
		var unit_rect = i.get_node("ColorRect5")
		glob.inst_uniform(unit_rect, "extents", 
		Vector4(0.0, rect_end.y - 2.0,
		0.0, rect_end.x- 2.0))

func get_unit(_kw: Dictionary) -> Control:
	var u: Control = _pool.pop_back() if _pool.size() > 0 else _unit.duplicate()
	u.visible = true
	u.modulate.a = 1.0
	if u.get_parent() == null:
		add_child(u)
	return u

@export var max_size: Vector2 = Vector2()
@export var outline_padding: float = 1.0

func recompute_filter():
	if !grid.x or !grid.y: 
		target_filter_size = Vector2()
		target_filter2_size = Vector2()
		return
	var arr = get_filter_cells(Vector2i(0,0), kernel_size)
	if arr:
		$filter.position = arr[0].position
		target_filter_size = ((arr[1].position+arr[1].get_global_rect().size
		)-$filter.position+Vector2(0.5,0.5))/$filter.scale
	arr = get_filter_cells(Vector2i(stride,0), kernel_size)
	if arr:
		target_filter2_pos = arr[0].position
		target_filter2_size = ((arr[1].position+arr[1].get_global_rect().size
		)-arr[0].position+Vector2(0.5,0.5))/$filter2.scale
	elif ceil(grid.x/group_size) < 1:
		target_filter2_size = Vector2()

func get_filter_cells(origin: Vector2i, kernel_size: Vector2i):
	var first_cell = _cells.get(origin)
	recompute_visible_grid()
	var kernel_end: Vector2i = origin+kernel_size
	if (grid.x-1)/group_size < kernel_end.x: 
		kernel_end.x = (grid.x-1)/group_size
	if (grid.y-1)/group_size < kernel_end.y: 
		kernel_end.y = (grid.y-1)/group_size
	if first_cell and not _fading_in.has(origin) and kernel_end in _cells and \
	(kernel_end.x < visible_grid.x):
		return [first_cell, _cells[kernel_end]]
	return []

func _can_drag() -> bool:
	return not ui.is_focus($Label/HSlider) and not ui.is_focus($Label2/HSlider2) \
	 and not ui.is_focus($Y)

var prev_kernel: Vector2i = kernel_size
func _proceed_hold() -> bool:
	var a = !glob.is_vec_approx($filter.size, target_filter_size) \
	or !glob.is_vec_approx($filter2.size, target_filter2_size) \
	or ui.is_focus($Y) \
	or !glob.is_vec_approx($filter2.position, target_filter2_pos)
	return a

var target_filter_size: Vector2 = Vector2()
var target_filter2_size: Vector2 = Vector2()
var target_filter2_pos: Vector2 = Vector2()
@export var kernel_size: Vector2i = Vector2i():
	set(v):
		kernel_size = v
		hold_for_frame()
@export var stride: int = 2:
	set(v):
		stride = v
		hold_for_frame()

func recompute_visible_grid() -> void:
	var max_x = -1
	var max_y = -1
	
	for key in _cells:
		max_x = max(max_x, key.x)
		max_y = max(max_y, key.y)
	
	for key in _fading_in:
		max_x = max(max_x, key.x)
		max_y = max(max_y, key.y)
	
	for key in _fading_out:
		max_x = max(max_x, key.x)
		max_y = max(max_y, key.y)
	
	if max_x >= 0 and max_y >= 0:
		visible_grid = Vector2i(max_x + 1, max_y + 1)
	else:
		visible_grid = Vector2i.ZERO

func _after_process(delta: float) -> void:
	super(delta)
	
	if layer_name == "Conv2D":
		recompute_biggest_size_possible()
		recompute_filter()
		
		$filter.size = $filter.size.lerp(target_filter_size, delta * 20.0)
		$filter2.size = $filter2.size.lerp(target_filter2_size, delta * 20.0)
		$filter2.position = $filter2.position.lerp(target_filter2_pos, delta * 20.0)
		fade_process(delta)

var visible_grid: Vector2i = Vector2i()
func fade_process(delta: float):
	# fading in
	for key in _fading_in.keys():
		var u: Control = _cells.get(key)
		if not u: continue
		var rect_end = u.get_global_rect().size + u.global_position
		if rect.get_global_rect().has_point(rect_end):
			pass
		else:
			u.hide(); u.modulate.a = 0; continue
			#continue
		var m = u.modulate
		u.show()
		hold_for_frame()
		m.a = lerp(m.a, _fading_in[key], delta * 15.0)
		u.modulate = m
		if m.a >= _fading_in[key]-0.07:
			u.modulate.a = _fading_in[key]
			_fading_in.erase(key)
	# fading out
	for key in _fading_out.keys():
		var u: Control = _cells.get(key)
		if not u: continue
		var rect_end = u.get_global_rect().size + u.global_position
		if !rect.get_global_rect().has_point(rect_end):
			u.modulate.a = 0.0
			_fading_out[key] = 0.0
		else:
			u.modulate.a = lerp(u.modulate.a, 0.0, delta * 15.0)
			_fading_out[key] = lerp(_fading_out[key], 0.0, delta * 15)
		hold_for_frame()
		if _fading_out[key] <= 0.07:
			_fading_out.erase(key)
			_cells.erase(key)
			u.queue_free()
	
	# size lerp
	var target: Vector2 = target_size_vec.max(biggest_size_possible)
	if max_size:
		target.x = max(target.x, max_size.x)
		target.y = max(target.y, max_size.y)
	var prev_size = rect.size
	rect.size = rect.size.lerp(target, delta * 15.0)
	if !glob.is_vec_approx(prev_size, rect.size):
		hold_for_frame()
		size_changed()

func update_grid(x: int, y: int):
	grid.x = x
	grid.y = y
	graphs.push_2d(grid.x, grid.y, get_first_descendants())

@export var max_displayed: int = 4
func set_grid(x: int, y: int) -> void:
	if not is_node_ready():
		await ready
	var columns = int(ceil(x / float(group_size))) if x else 0
	var rows = int(ceil(y / float(group_size))) if y else 0
	if columns > max_displayed: columns = max_displayed
	if rows > max_displayed: rows = max_displayed
	visualise_grid(columns, rows)
	hold_for_frame()

func add_cell(i: int, j: int) -> void:
	var key = Vector2i(i, j)
	var u: Control
	if _cells.has(key) and not _fading_out.has(key):
		return
	if _fading_out.has(key):
		_fading_out.erase(key)

	if not _cells.has(key):
		u = get_unit({})
		u.modulate.a = 0.0
		_cells[key] = u
	else:
		u = _cells[key]

	u.set_meta("coord", key)

	if not _fading_in.has(key):
		_fading_in[key] = 1.0

	_cell_added(i, j)

func _cell_added(i: int, j: int):
	pass

func _cell_removing(i: int, j: int):
	pass

func remove_cell(i: int, j: int) -> void:
	var key = Vector2i(i, j)
	if not _cells.has(key):
		return
	_fading_out[key] = 1.0
	_cell_removing(i, j)
	_fading_in.erase(key)

func recompute_biggest_size_possible() -> void:
	if _cells.is_empty() and _fading_out.is_empty():
		biggest_size_possible = Vector2.ZERO
		return

	#var unit_size = _unit.size
	#var max_right = 0.0
	#var max_bottom = 0.0
#
	#for key in _cells.keys():
		#var u: Control = _cells.get(key)
		#if not u or key in _fading_out: continue
		#var r = u.position.x + unit_size.x + grid_padding
		#var b = u.position.y + unit_size.y + grid_padding
		#if r > max_right: max_right = r
		#if b > max_bottom: max_bottom = b

	#for key in _fading_out.keys():
		#var u: Control = _cells.get(key)
		#if not u: continue
		#var r = u.position.x + unit_size.x + grid_padding
		#var b = u.position.y + unit_size.y + grid_padding
		#if r > max_right: max_right = r
		#if b > max_bottom: max_bottom = b
	
	if not grid_current-Vector2i.ONE in _cells: return
	biggest_size_possible = _cells[grid_current-Vector2i.ONE].position + _unit.size + size_add_vec

var shrinked_grid: Vector2i = Vector2i()
func _grid_visualised(columns: int, rows: int):
	pass


func visualise_grid(columns: int, rows: int) -> void:
	shrinked_grid = Vector2i(columns, rows)
	_grid_visualised(columns, rows)
	var old_x: int = grid_current.x
	var old_y: int = grid_current.y
	if (columns == 0 or rows == 0):
		for cell in _cells:
			remove_cell(cell.x, cell.y)
	else:

		if columns > old_x:
			for i in range(old_x, columns):
				for j in range(0, rows):
					add_cell(i, j)

		if rows > old_y:
			var max_old_cols = min(old_x, columns)
			for j in range(old_y, rows):
				for i in range(0, max_old_cols):
					add_cell(i, j)

		if columns < old_x:
			for i in range(columns, old_x):
				for j in range(0, old_y):
					remove_cell(i, j)

		if rows < old_y:
			var max_new_cols = min(columns, old_x)
			for j in range(rows, old_y):
				for i in range(0, max_new_cols):
					remove_cell(i, j)

	grid_current = Vector2i(columns, rows)

	var unit_size = _unit.size
	for i in range(0, columns):
		for j in range(0, rows):
			var key = Vector2i(i, j)
			if _cells.has(key):
				var u: Control = _cells[key]
				u.position.x = i * (unit_size.x + grid_padding) + offset.x
				u.position.y = j * (unit_size.y + grid_padding) + offset.y

	target_size_vec.y = rows * (unit_size.y + grid_padding) + size_add_vec.y + offset.y
	target_size_vec.x = columns * (unit_size.x + grid_padding) + size_add_vec.x + offset.x
	size_changed()

func _layout_size():
	return target_size_vec

func _on_h_slider_value_changed(value: float) -> void:
	var a: int = value
	open_undo_redo()
	update_config({"window": a})
	close_undo_redo()


func _config_field(field: StringName, val: Variant):
	match field:
		"window":
			$Label/n.text = str(val)
			$Label/HSlider.value = float(val)
			kernel_size = Vector2i.ONE * int(val) - Vector2i.ONE
		"stride":
			$Label2/n.text = str(val)
			$Label2/HSlider2.value = float(val)
			stride = int(val)
		"filters":
			if not (val == $Y.min_value and $Y.text == ""):
				$Y.set_line(str(val))
			filter_number = int(val)

var filter_number: int = 1
func _on_h_slider_2_value_changed(value: float) -> void:
	var a: int = value
	open_undo_redo()
	update_config({"stride": a})
	close_undo_redo()
	#$Label2/n.text = str(a)
	#$Label2/HSlider2.value = value
	#stride = a




func _on_yf_submitted(new_text: String) -> void:
	open_undo_redo()
	update_config({"filters": int(new_text)})
	close_undo_redo()
