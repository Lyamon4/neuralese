extends Graph

func _useful_properties() -> Dictionary:
	return {"config": {"rows": cfg.rows if cfg.rows else -1, "columns": cfg.columns if cfg.columns else -1}}

var dims_fixed: bool = false:
	set(v):
		if v:
			ui.line_block($X)
			ui.line_block($Y)
		else:
			ui.line_unblock($X)
			ui.line_unblock($Y)

func _proceed_hold() -> bool:
	return ui.is_focus($X) or ui.is_focus($Y)

func push_dims(x: int, y: int):
	update_config({"rows": x, "columns": y})

func _find_balanced_factors(n: int) -> Vector2i:
	var sqrt_n = int(sqrt(float(n))); var steps: int = 0
	for i in range(sqrt_n, 0, -1):
		steps += 1
		if n % i == 0:
			return Vector2i(i, n / i)
		if steps > 1000: return Vector2i(1, n)
	return Vector2i(1, n)

func _can_drag() -> bool:
	return not ui.is_focus($X) and not ui.is_focus($Y)

func _just_attached(who: Connection, to: Connection):
	#("A")
#	var cond = graphs.is_layer(who.parent_graph, "Dense")
	if 1:
		var total:int = who.parent_graph.get_x()
		var rows:int = cfg.rows; var columns:int = cfg.columns
		if rows == 0 and columns == 0:
			var factors = _find_balanced_factors(total)
			rows = factors.x; columns = factors.y
		if columns == 0 and rows != 0 and total % rows == 0:
			columns = total / rows
		if rows == 0 and columns != 0 and total % columns == 0:
			rows = total / columns
		update_config({"rows": rows, "columns": columns})

func _just_connected(who: Connection, to: Connection):
	#if to.parent_graph.server_typename == "Flatten":
	#	to.parent_graph.set_count(cfg.rows * cfg.columns)
	if is_valid() and get_ancestor():
		graphs.push_2d(cfg.columns, cfg.rows, to.parent_graph)



	#graphs.unpush_2d(self)
func _just_disconnected(who: Connection, to: Connection):
	if get_ancestor():
		graphs.unpush_2d(to.parent_graph)

func _config_field(field: StringName, value: Variant):
	match field:
		"rows":
			if !setting:
				$Y.set_line(str(value))
			#for i in desc:
				#if i.server_typename == "Flatten":
					#i.set_count(cfg.rows * cfg.columns)
			await get_tree().process_frame
			var desc = get_first_descendants()
			if is_valid() and get_ancestor():
				graphs.push_2d(cfg.columns, cfg.rows, desc)
		"columns":
			if !setting:
				$X.set_line(str(value))
			#for i in desc:
				#if i.server_typename == "Flatten":
					#i.set_count(cfg.rows * cfg.columns)
			var desc = get_first_descendants()
			await get_tree().process_frame
			if is_valid() and get_ancestor():
				graphs.push_2d(cfg.columns, cfg.rows, desc)
				#if glob.is_layer(i, "Conv2D"):
				#	i.update_grid(cfg.columns, cfg.rows)

var types_2d: Dictionary[StringName, bool] = {"Reshape2D": 1, "InputNode": 1}
var layers: Dictionary[StringName, bool] = {"Dense": 1, "Conv2D": 1}

func _is_valid() -> bool:
	var total = cfg.rows * cfg.columns
	var ancestors = get_first_ancestors()
	if ancestors:
		var graph = ancestors[0]
		return total == graph.get_x()
	return true

func _visualise_valid(ok: bool):
	if ok:
		for i in base_config:
			match i:
				"rows":
					$Y.modulate = Color.WHITE
				"columns":
					$X.modulate = Color.WHITE
	else:
		for i in invalid_fields:
			match i:
				"rows":
					$Y.modulate = (Color.INDIAN_RED)
				"columns":
					$X.modulate = (Color.INDIAN_RED)

func _chain_incoming(cache: Dictionary):
	var broke: bool = false
	var chain = cache.get("chain", [])
	var starts_input = len(chain) > 0 and chain[0].server_typename == "InputNode"
	var origin_dims = Vector2i(1,1)
	if len(chain) < 1 or !starts_input:
		broke = true
	else:
		for i: Graph in chain:
			if not i.server_typename in types_2d:
				broke = true; break
	if not broke:
		dims_fixed = true
		push_dims(chain[0].image_dims.x, chain[0].image_dims.y)
	else:
		dims_fixed = false


func _just_deattached(other_conn: Connection, my_conn: Connection):
	#dims_fixed = false
	#await get_tree().process_frame
	graphs.update_dependencies(self)


var setting: bool = false

func _on_x_changed() -> void:
	setting = 1
	
	open_undo_redo()
	update_config({"columns": int($X.get_value())}); setting = 0
	close_undo_redo()


func _on_y_changed() -> void:
	setting = 1
	open_undo_redo()
	update_config({"rows": int($Y.get_value())}); setting = 0
	close_undo_redo()
