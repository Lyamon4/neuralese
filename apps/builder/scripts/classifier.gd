extends DynamicGraph
class_name OutputGraph

var value_cache: Array = []
var manually: bool = false
func unit_set(unit, value, text):
	units[unit].set_weight(value, text)

func _request_save():
	var res = []
	for i in units:
		res.append(i.get_node("Label").text)
	cfg["label_names"] = res

func set_names(names: Array):
	glob.open_action_batch(true)
	_config_field("label_names", names)
	await get_tree().process_frame
	await get_tree().process_frame
	glob.close_action_batch()
	if not glob.is_auto_action():
		glob.add_action(set_names.bind([]), func():
			#("ff")
			set_names(names.duplicate()))

func _config_field(field: StringName, value: Variant):
	if not manually and field == "label_names" and not trigger:
		#_stack()
		#_applying_labels += 1
		if units: return
		for i in len(units):
			remove_unit(0)
		for i in len(value):
			add_unit({"text": value[i]}, true)
		push_values(value_cache, per)
		#_applying_labels -= 1
		hold_for_frame()

	if not upd and field == "title":
		$ColorRect/root/Label.set_line(value)
		ch()


func _can_drag() -> bool:
	return super() and not ui.is_focus($ColorRect/root/Label)

func _proceed_hold() -> bool:
	return ui.is_focus($ColorRect/root/Label)


func get_title() -> String:
	return $ColorRect/root/Label.text if $ColorRect/root/Label.text else "LabelGroup"

var per: bool = false
func push_values(values: Array, percent: bool = false):
	per = percent
	var minimal = values.min() if !percent else 0.0
	var maximal = values.max() if !percent else 1.0
	var add = "%" if percent else ""
	for unit in len(values):
		var value = (values[unit] - minimal) / float(maximal - minimal)
		var capped = glob.cap(values[unit], 2) if !percent else round(values[unit]*100.0)
		if unit >= len(units): continue
		if percent:
			unit_set(unit, value, str(capped)+"%")
		else:
			unit_set(unit, value, str(capped))
	for unit in range(len(values), len(units)):
		if percent:
			unit_set(unit, 0.0, "0%")
		else:
			unit_set(unit, 0.0, "0.0")

var _applying_labels: int = 0


func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("Label").text = kw["text"]
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
	#dup.size.y = randi_range(10,60)
#	dup.server_name = 
	return dup



func _unit_just_added() -> void:
#	if 1:#_applying_labels > 0:
#		var ancestor = get_first_ancestors()
#		push_values(value_cache, ancestor and ancestor[0].server_typename == "SoftmaxNode")
#		return

	var ancestor = get_first_ancestors()
	push_values(value_cache, ancestor and ancestor[0].server_typename == "SoftmaxNode")

	if not undo_redo_opened and not manually:
		glob.add_action(remove_unit.bind(len(units)-1), add_unit.bind(units[-1].get_meta("keyw")))
		#var res: Array = []
		#for i in units:
			#res.append(i.get_node("Label").text)
		#open_undo_redo(true)
		#manually = true
		#update_config({"label_names": res})
		#manually = false
		#close_undo_redo()
	for i in 3:
		await get_tree().process_frame
	var res = []
	for i in units:
		res.append(i.get_node("Label").text)
	cfg["label_names"] = res
	learner.notify_update()



	
func _deattaching(other_conn: Connection, my_conn: Connection):
	var ancestor = get_first_ancestors()
	if ancestor: 
		if ancestor[0].server_typename == "SoftmaxNode":
			push_values(value_cache, false)

var trigger: bool = false
func _unit_removal(id: int):
	#await get_tree().process_frame

	# Do not echo changes while we’re applying cfg→UI
	#if _applying_labels > 0:
	#	return

	if not glob.is_auto_action():
		var txt = units[id].get_node("Label").text
		var res = []
		for i in units:
			res.append(i.get_node("Label").text)
		cfg["label_names"] = res
		glob.add_action((
			func():
				var l = len(units)
				for i in l:
					remove_unit(0)
				for i in res:
					add_unit({"text": i}))
			, remove_unit.bind(id))
		#open_undo_redo(true)
		#trigger = true
		#update_config({"label_names": next})
		#(next)
		#trigger = false
		#close_undo_redo()




func _just_attached(other_conn: Connection, my_conn: Connection):
	graphs.push_1d(other_conn.parent_graph.get_x(), other_conn.parent_graph)
	if other_conn.parent_graph.server_typename == "SoftmaxNode":
		push_values(value_cache, true)
	else:
		push_values(value_cache, false)

var res_meta: Dictionary = {}
func push_result_meta(meta: Dictionary):
	res_meta = meta
	ch()


func _after_process(delta: float):
	super(delta)
	#push_values(range(len(units)), true)

func ch():
	var target = graphs._reach_input(self)
	if !target: return
	var got = graphs.get_input_name_by_graph(target)
	if got:
		graphs.model_updated.emit(got)

var upd = false
signal label_changed(text: String)
func _on_label_changed() -> void:
	ch()
	upd = true
	open_undo_redo(true)
	update_config({"title": $ColorRect/root/Label.text})
	close_undo_redo()
	upd = false
	#var netname = target.get_netname()
	#if netname:
	#	netname.reload()
	#label_changed.emit($ColorRect/root/Label.text)
