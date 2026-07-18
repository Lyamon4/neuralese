extends Graph
class_name DynamicGraph

@export var bottom_attached: bool = false
@export var unit: Control
@export var add_button: BlockComponent
@export var input: Control
@export var padding: float = 0.0
@export var line_edit: ValidInput
@export var unit_offset_y: float = 0.0
@export var wait_enclose: bool = false
@export var enclose_pad: float = 0.0

@onready var _unit = unit.duplicate() if unit else null


func _unit_modulate_updated(unit: Control, fin: bool = false, diss: bool = false):
	pass

var connection_paths = []
func _enter_tree():
	if unit:
		for i in unit.get_children():
			if i is Connection:
				connection_paths.append(NodePath(i.name))

@export var target_size: float = 94
var total_size: float = 0.0
var hint_counter: int = 5
var unit_script = null
func _after_ready():
	#total_size += input.size.y
	if unit:
		unit.queue_free()
		unit_script = unit.get_script()
		size_changed()
	#for i in 100:
	#	add_unit({"text": "hif"})

func _can_drag() -> bool:
	return (! line_edit or not ui.is_focus(line_edit)) and (!add_button or not add_button.state.hovering)

var units = []
var appear_units = {}
var dissapear_units = {}
var offset_units = {}
func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("Label").text = kw["text"]
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
#	dup.server_name = 
	return dup

func _adding_unit(who: Control, kw: Dictionary):
	pass


var key_by_unit: Dictionary = {}
func _unit_removal(id: int):
	pass

func remove_unit(id: int):
	hold_for_frame()
	_unit_removal(id)
	var unit = units[id]; var dec = unit.size.y + padding
	appear_units.erase(unit)
	if glob.cull(unit.global_position, unit.size):
		dissapear_units[unit] = true
	else:
		unit.modulate.a = 0.0
		unit.queue_free()
	total_size -= dec; target_size -= dec
	target_y = total_size
	#units[id].delete()
	units.remove_at(id)
	for i in range(id, len(units)):
		offset_units[units[i]] = (units[i].position.y-dec if units[i].connect_position != null 
		else units[i].connect_position-dec)
		units[i].connect_position = units[i].position.y-dec
		units[i].id -= 1
		if not glob.cull(units[i].global_position, units[i].size):
			units[i].position.y = offset_units[units[i]]
			offset_units.erase(units[i])
	learner.notify_update.call_deferred()

var target_y: float = 0.0
func add_unit(kw: Dictionary = {}, instant=false):
	hold_for_frame()
	if !instant:
		add_q.append(_add_q.bind(kw))
	else:
		_add_q(kw)

@export var min_size: float = 0.0
@export var size_add: float = 0.0

var add_q: Queue = Queue.new()
func _unit_just_added() -> void: # virtual
	pass
	
func _add_q(kw: Dictionary):
	var new_unit = _get_unit(kw)
	new_unit.set_meta("keyw", kw)
	_adding_unit(new_unit, kw)
	appear_units[new_unit] = true
	new_unit.set_script(unit_script)
	new_unit.id = len(units)
	units.append(new_unit)	
	key_by_unit[new_unit] = len(units)-1

	new_unit.position.y = total_size + padding + unit_offset_y
	if bottom_attached:
		new_unit.position.y -= input.size.y
	total_size += new_unit.size.y + padding
	target_y = total_size
	
	#input.position.y = total_size
	target_size += new_unit.size.y + padding
	for path in connection_paths:
		var conn = new_unit.get_node(path)
		hint_counter += 1
		conn.hint = hint_counter
		conn.parent_graph = self
#	graphs.increment_z_counter(3)
	add_child(new_unit)
	if not glob.cull(new_unit.global_position, new_unit.size):
		new_unit.modulate.a = 1.0
		appear_units.erase(new_unit)
		#_unit_modulate_updated(new_unit)
	_unit_just_added()
	learner.notify_update.call_deferred()

@export var lerp_size: bool = true
@export var input_y_add: float = 0.0


func _unit_pos_change(un: Control):
	pass


var prev_frame_changed: bool = false
var prev_adding_size: float = 0.0
func _after_process(delta: float):
	for i in 100:
		if add_q.empty(): break
		var popped = add_q.pop()
		popped.call()
	if offset_units or !add_q.empty() or appear_units or dissapear_units:
		hold_for_frame()
	
	if exist_ticks < 5:
		if bottom_attached:
			input.position.y = target_y + input_y_add
		if lerp_size:
			rect.size.y = max(min_size, target_size + size_add)
			size_changed()
	else:
		if bottom_attached:
			input.position.y = lerpf(input.position.y, target_y + input_y_add, delta*20.0)
		if lerp_size:
			var prev_size = rect.size
			rect.size.y = lerpf(rect.size.y, max(min_size, target_size + size_add + adding_size_y), delta*20.0)
			if !glob.is_vec_approx(prev_size, rect.size):
				size_changed()
				hold_for_frame()
	if adding_size_y != prev_adding_size:
		
		prev_frame_changed = true
	if adding_size_y != prev_adding_size or prev_frame_changed:
	#	print(adding_size_y)
		var prev_size = rect.size
		rect.size.y = lerpf(rect.size.y, max(min_size, target_size + size_add + adding_size_y), delta*20.0)
		if !glob.is_vec_approx(prev_size, rect.size):
			size_changed()
			prev_frame_changed = true
		#(adding_size_y)
		else:
			prev_frame_changed = false
	prev_adding_size = adding_size_y

	var to_del = []
	for appearer in appear_units:
		if (wait_enclose and not rect.get_global_rect().\
		has_point(Vector2(rect.global_position.x + 10, appearer.get_global_rect().end.y - 10))): 
			continue
		appearer.modulate.a = lerpf(appearer.modulate.a, 1.0, 10.0*delta)
		if appearer.modulate.a > 0.9:
			appearer.modulate.a = 1.0
			to_del.append(appearer)
			_unit_modulate_updated(appearer, true)
		else:
			_unit_modulate_updated(appearer, false)
	for unit in to_del:
		appear_units.erase(unit)
	to_del = []
	for dissapearer in dissapear_units:
		dissapearer.modulate.a = lerpf(dissapearer.modulate.a, 0.0, 20.0*delta)
		if dissapearer.modulate.a < 0.1:
			dissapearer.modulate.a = 0
			dissapearer.queue_free()
			to_del.append(dissapearer)
			_unit_modulate_updated(dissapearer, true, true)
		else:
			_unit_modulate_updated(dissapearer, false, true)
	for unit in to_del:
		dissapear_units.erase(unit)
		key_by_unit.erase(unit)
		offset_units.erase(unit)
	to_del = []
	for unit in offset_units:
		var target = offset_units[unit]
		if not is_instance_valid(unit): to_del.append(unit); continue
		unit.position.y = lerpf(unit.position.y, target, delta*20.0)
		_unit_pos_change(unit)
		if abs(target - unit.position.y) < 1:
			unit.position.y = target
			_unit_pos_change(unit)
			to_del.append(unit)
	for unit in to_del:
		offset_units.erase(unit)
	

	if ui.is_focus(line_edit):
		hold_for_frame()

var adding_size_y: float = 0.0


func _on_color_rect_2_pressed() -> void:
	if line_edit.is_valid:
		#ui.click_screen(line_edit.global_position + Vector2(10,10))
		line_edit.grab_focus()
		add_unit({"text": line_edit.text})
		line_edit.clear()
