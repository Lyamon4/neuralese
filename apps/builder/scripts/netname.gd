extends Graph

func _can_drag() -> bool:
	return not ui.is_focus($LineEdit)

func _proceed_hold() -> bool:
	return ui.is_focus($LineEdit)

var do_push: bool = true
func _just_connected(who: Connection, to: Connection):
	if to.parent_graph.server_typename == "InputNode":
		if graphs.get_input_graph_by_name(cfg["name"]) and graphs.get_input_graph_by_name(cfg["name"]) != to:
			#("ret")
			do_push = false
			return
		do_push = true
		if cfg["name"]:
			graphs.add_input_graph_name(to.parent_graph, cfg["name"])
		#graphs.set_graph_name(graphs._reach_input(to.parent_graph), cfg["name"])
	if to.parent_graph.server_typename == "RunModel":
		#(graphs.get_input_graph_by_name(cfg["name"]))
		to.parent_graph.set_name_graph(cfg["name"])

func _disconnecting(who: Connection, to: Connection):
	if to.parent_graph.server_typename == "InputNode" and do_push:
		graphs.forget_input_graph(to.parent_graph)
	if to.parent_graph.server_typename == "RunModel":
		to.parent_graph.set_name_graph("")


func _is_valid() -> bool:
	var d = get_named_descendant("InputNode")
	#(d)
	#if d and d.base_dt == "2d":
		#if graphs.get_input_graph_by_name(cfg["name"]):
		#	print(graphs.get_input_graph_by_name(cfg["name"]).base_dt)
	if d and graphs.get_input_graph_by_name(cfg["name"]) and graphs.get_input_graph_by_name(cfg["name"]) != d:
		return false
	#(graphs.input_graph_name_exists(cfg["name"]))
	#(graphs.input_graph_name_exists(cfg["name"]))
	return (!d) or ((cfg["name"]) and ((d and d.server_typename == "InputNode") \
	or graphs.input_graph_name_exists(cfg["name"])))


func _visualise_valid(ok: bool):
	if ok:
		$LineEdit.modulate = Color.WHITE
	else:
		$LineEdit.modulate = Color.INDIAN_RED

var prev_name = ""
func _config_field(field: StringName, value: Variant):
	if field == "name":
		if not upd:
			$LineEdit.set_line(value)
		var desc = get_first_descendants()
		for dess in desc: #deltarune
			if dess.server_typename == "InputNode" and do_push:
				if value:
					if graphs.has_named_input_graph(dess):
						if prev_name and (dess == graphs.get_input_graph_by_name(prev_name)) and not graphs.get_input_graph_by_name(value):
							#(prev_name)
							graphs.rename_input_graph(dess, value)
						#(graphs.input_graph_name_exists(cfg["name"]))
					else:
						graphs.add_input_graph_name(dess, value)
					#graphs.set_graph_name(graphs._reach_input(dess), value)
				else:
					graphs.forget_input_graph(dess)
					#graphs.reset_graph_name(graphs._reach_input(dess))
		for dess in desc: #deltarune
			if dess.server_typename == "RunModel":
				dess.set_name_graph(value)
		prev_name = value

func _ready() -> void:
	super()
	graphs.spline_connected.connect(
	func(x: Connection, y: Connection):
		var reached = graphs._reach_input(x.parent_graph)
		if graphs.get_input_graph_by_name(cfg["name"]) == reached:
			update_config({"name": cfg["name"]})
		if x.parent_graph.server_typename == "ModelName" and y.parent_graph.server_typename == "InputNode":
			if x.parent_graph.cfg["name"] == cfg["name"]:
				update_config({"name": cfg["name"]})
	)
	graphs.model_updated.connect(func(str: String):
		if str == cfg["name"]:
			reload())

	graphs.spline_disconnected.connect(
	func(x: Connection, y: Connection):
		var reached = graphs._reach_input(x.parent_graph)
		#(reached, graphs.get_input_graph_by_name(cfg["name"]))
		if reached and reached == graphs.get_input_graph_by_name(cfg["name"]):
			await get_tree().process_frame
			update_config({"name": cfg["name"]})
		if is_instance_valid(x) and do_push:
			if x.parent_graph.server_typename == "ModelName" and x.parent_graph.do_push:
				if y.parent_graph.server_typename == "InputNode" and cfg["name"] == x.parent_graph.cfg.get("name", ""):
					
					for i in get_first_descendants():
						if i.server_typename == "RunModel":
							#(do_push)
							i.set_name_graph("")
	)

var had_name: String = ""
func recheck(old_name: String, new_name: String):
	#if new_name == cfg["name"]:
		#had_name = new_name
	#if cfg["name"] == old_name and (old_name or get_first_descendants()):
		#update_config({"name": new_name})
	#else:
	update_config({"name": cfg["name"]})

func reload():
	update_config({"name": cfg["name"]})

var upd: bool = false
func _on_line_edit_changed() -> void:
	upd = true
	var old_name = cfg["name"]
	open_undo_redo()
	update_config({"name": $LineEdit.text})
	close_undo_redo()
	upd = false
	for j in graphs.nodes_of_type("ModelName"):
		if j == self: continue
		j.recheck(old_name, cfg["name"])
