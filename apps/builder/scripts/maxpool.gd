extends Conv2D

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var active = {}

func _after_ready():
	super()
	rng.seed = randi()

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
		"config": conf,
		"cache_tag": str(graph_id)
	}


func _after_process(delta: float):
	super(delta)
	recompute_biggest_size_possible()
	fade_process(delta)
	repush(cr.x, cr.y)

var cr = Vector2i()
func _grid_visualised(columns: int, rows: int):
	repush(columns, rows)
	
func repush(columns: int, rows: int):
	#recompute_visible_grid()
	if columns != -1:
		$Control.target_grid = shrinked_grid
	#columns = grid_current.x
	#rows = grid_current.y
	$Control.position = offset
	$Control.grid_padding = grid_padding
	$Control.group = group
	$Control.grid = Vector2i(columns, rows)
	$Control._unit = _unit
	#$Control.queue_redraw()
	cr = Vector2i(columns, rows)

@export var group: int = 5:
	set(v):
		var old_grid: Vector2i = grid
		group = v
		grid.x = 0
		grid.y = 0
		grid.x = old_grid.x
		grid.y = old_grid.y
		
func _just_connected(who: Connection, to: Connection):
	graphs.push_2d(int(grid.x/group), int(grid.y/group), get_first_descendants())

func _layout_size():
	return target_size_vec

func _proceed_hold() -> bool:
	return false

func _cell_added(x: int, y: int):
	var chunk_x = x / group
	var chunk_y = y / group
	
	var origin = Vector2i(chunk_x, chunk_y) * group
	var center_x = (chunk_x * group + group / 2)
	var center_y = (chunk_y * group + group / 2)
	
	rng.seed = chunk_x * 100 + chunk_y + group + get_instance_id()
	var ext: int = max(1, floor(group / 2) - 2)
	var winner_x = center_x + rng.randi_range(-ext, ext)
	var winner_y = center_y + rng.randi_range(-ext, ext)
	if winner_x < origin.x: winner_x = origin.x
	if winner_y < origin.y: winner_y = origin.y
	if winner_x > origin.x + group - 1: winner_x = origin.x + group - 1
	if winner_y > origin.y + group - 1: winner_y = origin.y + group - 1

	if x == winner_x and y == winner_y:
		_fading_in[Vector2i(x,y)] = 1.0
	else:
		_fading_in[Vector2i(x,y)] = 0.3

func _config_field(field: StringName, val: Variant):
	match field:
		"group":
			if not updating:
				$YY.set_line(str(int(val)))
			group = int(val)
			hold_for_frame()
			#(int(grid.x/group*1.5))
			graphs.push_2d(int(grid.x/group), int(grid.y/group), get_first_descendants())

func _can_drag() -> bool:
	return not ui.is_focus($YY)

func update_grid(x: int, y: int):
	grid.x = x
	grid.y = y
	graphs.push_2d(int(grid.x/group), int(grid.y/group), get_first_descendants())

func _on_yy_submitted(new_text: String) -> void:
	updating = true
	open_undo_redo()
	update_config({"group": int($YY.get_value())})
	updating = false
	close_undo_redo()

var updating: bool = false
func _on_yy_changed() -> void:
	var val = int($YY.get_value())
	if not $YY.is_valid_input():
		return
	updating = true
	update_config({"group": val})
	updating = false
