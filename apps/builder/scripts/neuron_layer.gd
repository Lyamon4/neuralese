extends BaseNeuronLayer
class_name NeuronLayer


func _useful_properties() -> Dictionary:
	#assert (input_keys[0].inputs, "no config. TODO: implement error handling")
	var conf = {"activation": "none"}
	if input_keys[0].inputs:
		conf["activation"] = input_keys[0].inputs.keys()[0].origin.parent_graph.selected_activation
	return {
	"neuron_count": _real_amount,
	"config": conf,
	"cache_tag": str(graph_id)
	}

func _neurons_fix_set(v: bool):
	if v:
		ui.line_block(line_edit)
	else:
		ui.line_unblock(line_edit)

func _layout_size():
	return Vector2(rect.size.x, target_size)

func push_neuron_count(parsed: int):
	update_config({"neuron_count": parsed})

@export var group_size: int = 1:
	set(value):
		group_size = max(1, value)
		_apply_grouping()

var _real_amount: int = 0
@onready var base_size_add: float = size_add

func _get_unit(kw: Dictionary) -> Control:
	var dup = _unit.duplicate()
	dup.modulate.a = 0.0
	dup.show()
	return dup

func _get_info() -> Dictionary:
	return {
		"position": position,
		"neuron_count": cfg.neuron_count,
	}

var last_resized: int = 0
func _size_changed():
	$ni.position.y = (rect.size.y) / 2 + rect.position.y
	$o.position.y = (rect.size.y) / 2 + rect.position.y
	reposition_splines()
	last_resized = 0
	hold_for_frame()

func _dragged():
	last_resized = 0

func _after_process(delta:float):
	if _unit:
		super(delta)
	last_resized += 1
	if last_resized < 20:
		if len(units) > max_units:
			var extents = Vector4(rect.global_position.y, rect.global_position.y + rect.size.y, 0, 0)
			units[-1].set_extents(extents)
			units[0].set_extents(extents)
		elif units:
			units[0].set_extents(Vector4())

func _just_connected(who: Connection, to: Connection):
	graphs.push_1d(_real_amount, self)

func _just_disconnected(who: Connection, from: Connection):
	pass

func _unit_modulate_updated(of: Control, fin: bool = false, diss: bool = false):
	var extents
	var key = key_by_unit[of]
	if not fin or (len(units) > max_units-1 and key == max_units):
		extents = Vector4(rect.global_position.y, rect.global_position.y + rect.size.y, 0, 0)
	else:
		extents = Vector4()
	of.set_extents(extents)

@export var max_units = 20

func _apply_grouping() -> void:
	var MAX_UNITS = max_units + 1
	
	var gs = max(1, group_size)
	var full_groups = int(_real_amount / gs)
	var remainder = int(_real_amount % gs)
	var needed_units = full_groups + (1 if remainder > 0 else 0)

	var visible_units = min(needed_units, MAX_UNITS)

	if needed_units > max_units:
		size_add = base_size_add - 15
	else:
		size_add = base_size_add

	var length = len(units)
	if length > visible_units:
		for i in range(length - visible_units):
			remove_unit(length - i - 1)
	elif length < visible_units:
		for i in range(visible_units - length):
			add_unit({}, true)

	if needed_units <= MAX_UNITS:
		for i in range(visible_units):
			var count_in_group = gs if (i < full_groups) else remainder
			if count_in_group == 0: count_in_group = gs
			units[i].set_text(1)
	else:
		for i in range(MAX_UNITS - 1):
			units[i].set_text(1)
		var covered = gs * (MAX_UNITS - 1)
		var tail = max(0, _real_amount - covered)
		units[MAX_UNITS - 1].set_text(tail, true)

var neuron_count: int = 0
func _config_field(field: StringName, val: Variant):
	match field:
		"neuron_count":
			#(val)
			#val = int(val)
			if 1:#not neurons_fixed:
				neuron_count = val
				line_edit.set_line(str(val))
				_real_amount = max(0, val)
				_apply_grouping()
				for i in get_first_descendants():
					if i.server_typename == "Reshape2D":
						i.update_config({"rows": i.cfg.rows, "columns": i.cfg.columns})
				hold_for_frame()
				#await get_tree().process_frame
				graphs.push_1d(_real_amount, self)
		
			

func _get_x() -> Variant:
	return _real_amount

func re_upd():
	graphs.push_1d(_real_amount, self)

func _on_line_edit_changed() -> void:
	await get_tree().process_frame
	update_config({"neuron_count": int($LineEdit.get_value())})
	#_apply_grouping()


func _on_line_edit_submitted_1(new_text: String) -> void:
	await get_tree().process_frame
	open_undo_redo()
	update_config({"neuron_count": int($LineEdit.get_value())})
	close_undo_redo()
