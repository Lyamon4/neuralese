extends DynamicGraph


func _useful_properties() -> Dictionary:
	var body = []
	for i in units:
		if i.get_node('o').inputs:
			#(i.position.y ," ", i.get_node('o').server_name)
			body.append(i.get_node('o').server_name)
	
	return {"config": {"concat_order": body}}



func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("Label").text = "Slot " + str(len(units)) if glob.get_lang() == "en" else "Слот "+str(len(units))
	dup.get_node("o").hint = randi_range(0,999999)
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
#	dup.server_name = 
	return dup

func calc_x():
	var x: int = 0
	_request_save()
	for i in units:
		for spline in i.get_node("o").inputs:
			x += spline.origin.parent_graph.get_x()
	return x

func _get_x():
	return calc_x()


func _just_connected(who: Connection, to: Connection):
	graphs.push_1d(get_x(), self)



func _request_save():
	var uns = []
	
	for i in len(units):
		var o = units[i].get_node("o")
		var ins = []
		for j in o.inputs:
			ins.append([j.origin.parent_graph.graph_id, j.origin.hint])
		uns.append(ins)
	cfg["uns"] = uns


func _config_field(field: StringName, value: Variant):
	if field == "uns":
		for i in value:
			add_unit({}, true)
			var nu = units[-1]
			for input in i:
				var graph: Graph = graphs._graphs.get(input[0])
				if not graph: continue
				graph.output_keys[input[1]].connect_to(nu.get_node("o"), true)
				



var trigger: bool = false
func _unit_removal(id: int):
	units[id].get_node('o').queue_free()
	if not glob.is_auto_action():
		var res = len(units)
		glob.add_action((
			func():
				var l = len(units)
				for i in l:
					remove_unit(0)
				for i in res:
					add_unit({}))
			, remove_unit.bind(id))
	await get_tree().process_frame
	for i in len(units):
		units[i].get_node("Label").text = "Slot "+str(i) if glob.get_lang() == "en" else "Слот "+str(i)


func _ready() -> void:
	super()
	size_changed()

func _unit_pos_change(un: Control):
	un.get_node("o").reposition_splines()


func _size_changed():
	$o.position.y = $ColorRect.size.y / 2 + $ColorRect.position.y - $o.size.y / 2
	$o.reposition_splines()


func _just_attached(other_conn: Connection, my_conn: Connection):
	graphs.push_1d(other_conn.parent_graph.get_x(), other_conn.parent_graph)
	#if other_conn.parent_graph.server_typename == "SoftmaxNode":
		#push_values(value_cache, true)
	#else:
		#push_values(value_cache, false)




func _after_process(delta: float):
	super(delta)
	#var body = []
	#for i in units:
	#	if i.get_node('o').inputs:
	#		body.append(i.get_node('o').server_name)
	#_request_save()
	#(cfg)
	#push_values(range(len(units)), true)




func _on_color_rect_2_pressed() -> void:
	add_unit({})
