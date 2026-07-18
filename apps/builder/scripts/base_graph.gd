extends Control
class_name Graph

@export var base_dt: String = "1d"
@export var server_typename: StringName = ""
@onready var label = $ColorRect/root/Label
@onready var rect: Control = $ColorRect

func set_screenshotting():
	ui.set_uni(rect, "use_bg", true)


func set_not_screenshotting():
	ui.set_uni(rect, "use_bg", true)
	#glob.inst_uniform(rect, "use_bg", true)

@export var z_space: int = 2
@export var is_input: bool = false
@export var is_train_graph: bool = false
@export var is_head: bool = false


enum Flags {NONE=0, NEW=2}
@export_flags("none", "new") var graph_flags = 0
@export var area_padding: float = 10.0

var _inputs: Array[Connection] = []
var outputs: Array[Connection] = []

var output_keys: Dictionary[int, Connection] = {}
var input_keys: Dictionary[int, Connection] = {}
var input_key_by_conn: Dictionary[Connection, int] = {}
var output_key_by_conn: Dictionary[Connection, int] = {}

var hold_process: bool = false

@onready var base_scale = scale
func _new_animate(delta: float): # virtual
	scale = glob.spring(base_scale * 0.5, base_scale, exist_time, 3.5, 16, 0.5)

func _is_suitable_other_conn(other: Connection, mine: Connection) -> bool:
	return true

func hold_for_frame(): 
	#\print_stack()
	
	hold_process = true

@export_group("Base Config")
@export var base_config: Dictionary[StringName, Variant] = {}
@export_group("")

func get_first_descendants() -> Array[Graph]:
	var res: Dictionary[Graph, Variant] = {}
	for i in outputs:
		for j:int in i.outputs:
			if i.outputs[j].tied_to and is_instance_valid(i.outputs[j].tied_to.parent_graph):
				res[i.outputs[j].tied_to.parent_graph] = true
	var a: Array[Graph] = res.keys()
	return a

func get_first_ancestors() -> Array[Graph]:
	var res: Dictionary[Graph, Variant] = {}
	for i in input_keys:
		for j in input_keys[i].inputs:
			if is_instance_valid(j.origin.parent_graph):
				res[j.origin.parent_graph] = true
	var a: Array[Graph] = res.keys()
	return a

func get_descendant() -> Graph:
	var dess = get_first_descendants()
	return dess[0] if dess else null

func get_ancestor() -> Graph:
	var dess = get_first_ancestors()
	return dess[0] if dess else null

func request_save():
	_request_save()

func _request_save(): # virtual
	pass

var _pending_undo_update: Dictionary = {}
var _undo_timer: float = 0.0
var undo_delay: float = 0.2
var _undo_start_snapshot: Dictionary = {}
var _undo_active: bool = false


var undo_redo_opened: bool = false

var right_away: bool = false
func open_undo_redo(no_batch: bool = false):
	undo_redo_opened = true
	right_away = no_batch


func close_undo_redo():
	undo_redo_opened = false

@onready var base_outline = rect.get_instance_shader_parameter("outline_color")
var selected: bool = false
func select():
	if is_blocked: return
	if ui.nodes_choosing: return
	selected = true
	graphs.set_selected(self)
	select_effect(Color.YELLOW)

func select_effect(color: Color):
	rect.set_instance_shader_parameter("outline_color", color)

func unselect():
	if ui.nodes_choosing: return
	selected = false
	graphs.unselect(self)
	select_effect(base_outline)


@onready var cfg: Dictionary[StringName, Variant] = base_config.duplicate()
func update_config(update: Dictionary):

	if undo_redo_opened and not in_abstraction and not glob.is_auto_action():

		if not _undo_active:
			_undo_start_snapshot = cfg.duplicate(true)
			_undo_active = true

		_pending_undo_update.merge(update.duplicate(true), true)
		_undo_timer = undo_delay
		learner.notify_update.call_deferred()
		if right_away:

			_undo_timer = 0
			_commit_batched_undo()

	cfg.merge(update, true)
	for field in update:
		_config_field(field, update[field])
	check_valid(update)
	
	if input_cached:
		#("A")
		input_cached.graph_updated()
	
	learner.notify_update.call_deferred()

func has_config_subfield(query: String) -> bool:
	var splt = query.split("/")
	return cfg.has(splt[0]) and cfg[splt[0]].has(splt[1])

func update_config_subfield(update: Dictionary):
	if undo_redo_opened and not in_abstraction and not glob.is_auto_action():
		var reversion = {}
		var erasure = {}
		for i in update:
			reversion[i] = {}
			for subfield in update[i]:
				if not subfield in cfg[i]:
					if not i in erasure: erasure[i] = {}
					erasure[i][subfield] = true; continue
				reversion[i][subfield] = cfg[i][subfield]
		
		learner.notify_update.call_deferred()
		glob.add_action(
			(func(): 
				for i in erasure:
					for subfield in erasure[i]:
						cfg[i].erase(subfield)
				update_config_subfield(reversion)
				),
			update_config_subfield.bind(update.duplicate(true)))
	for field in update:
		if !cfg.has(field): continue
		cfg[field].merge(update[field], true)
		for subfield in update[field]:
			_config_field(field + "/" + subfield, update[field][subfield])
	check_valid(update)
	if input_cached:
		input_cached.graph_updated()
	learner.notify_update.call_deferred()

func get_named_ancestor(named: String) -> Graph:
	for j in get_first_ancestors():
		if graphs.is_node(j, named):
			return j
	return null

func get_named_descendant(named: String) -> Graph:
	for j in get_first_descendants():
		if graphs.is_node(j, named):
			return j
	return null

func get_config_dict() -> Dictionary:
	return cfg.duplicate(true)

func _config_field(field: StringName, value: Variant):
	pass

func _layout_size() -> Vector2:
	return rect.size

func _llm_config(prev: Dictionary) -> Dictionary:
	return prev

func llm_config() -> Dictionary:
	return _llm_config(get_config_dict())

var llm_mapping: bool = false
var base = base_config.duplicate(true)
func llm_map(pack: Dictionary):
	llm_mapping = true
	update_config(base)
	_llm_map(pack)
	llm_mapping = false

#func llm_property(name: String) -> :
	#pass

func _llm_map(pack: Dictionary):
	if not pack: return
	if len(base_config) == 1:
		update_config({base_config.keys()[0]: pack.values()[0]})
		if pack.values()[0] is Dictionary:
			update_config_subfield({base_config.keys()[0]: pack.values()[0]})
	else:
		update_config(pack)
		for f in pack:
			if pack[f] is Dictionary:
				update_config_subfield({f: pack[f]})

func animate(delta: float):
	if graph_flags & Flags.NEW:
		if exist_time < 1.0: hold_for_frame(); reposition_splines()
		_new_animate(delta)

func _after_ready():
	pass




func ensure_input_has_context(n: Graph) -> void:
	if not is_instance_valid(n) or not n.is_input:
		return
	if n.root_context_id == 0:
		n.root_context_id = _new_context_id()
	if n.context_id == 0:
		n.context_id = n.root_context_id



func _set_subgraph_context(sub_id: int, ctx: int) -> void:
	if ctx == 0 or not _subgraph_registry.has(sub_id): return
	for node in _subgraph_registry[sub_id]:
		if is_instance_valid(node):
			node.context_id = ctx


func collect_component_nodes(root: Graph) -> Array:
	var res: Array = []
	var sid = root.subgraph_id
	if sid != 0 and _subgraph_registry.has(sid) and not _subgraph_registry[sid].is_empty():
		collect_branch_nodes(root, res, sid)
	else:
		res.append(root)
	return res

func graph_updated():
	pass

var in_abstraction: bool = false
func just_connected(who: Connection, to: Connection):
	if input_cached:
		input_cached.graph_updated()
		var nodes = graphs.simple_reach(self)
		for i in nodes:
			i.input_cached = input_cached
	if to.parent_graph.input_cached:
		input_cached = to.parent_graph.input_cached
		input_cached.graph_updated()
	if is_input:
		graph_updated()
		var nodes = graphs.simple_reach(self)
		for i in nodes:
			i.input_cached = self

	var a: Graph = who.parent_graph
	var b: Graph = to.parent_graph

	ensure_input_has_context(a)
	ensure_input_has_context(b)
	var nodes_a: Array = collect_component_nodes(a)
	var nodes_b: Array = collect_component_nodes(b)

	var ctx_a: int = 0
	var ctx_b: int = 0
	if not nodes_a.is_empty() and is_instance_valid(nodes_a[0]):
		ctx_a = nodes_a[0].context_id
	if not nodes_b.is_empty() and is_instance_valid(nodes_b[0]):
		ctx_b = nodes_b[0].context_id

	var winning_ctx: int = 0

	if ctx_a != 0 and ctx_b == 0:
		winning_ctx = ctx_a
	elif ctx_b != 0 and ctx_a == 0:
		winning_ctx = ctx_b
	elif ctx_a != 0 and ctx_b != 0:
		var dominant_input: Graph = null
		if a.is_input:
			dominant_input = a
		elif b.is_input:
			dominant_input = b
		winning_ctx = _pick_context_for_merge(nodes_a, nodes_b, dominant_input)
	else:
		if a.is_input:
			ensure_input_has_context(a)
			winning_ctx = a.context_id
		elif b.is_input:
			ensure_input_has_context(b)
			winning_ctx = b.context_id
		else:
			winning_ctx = _new_context_id()

	if not a.subgraph_occupied and not b.subgraph_occupied:
		var new_id = _new_subgraph_id()
		a.propagate_subgraph(new_id)
		b.propagate_subgraph(new_id)
	elif a.subgraph_occupied and not b.subgraph_occupied:
		b.propagate_subgraph(a.subgraph_id)
	elif b.subgraph_occupied and not a.subgraph_occupied:
		a.propagate_subgraph(b.subgraph_id)
	elif a.subgraph_id != b.subgraph_id:
		_merge_subgraphs(a.subgraph_id, b.subgraph_id)

	var merged_sub: int = a.subgraph_id
	_set_subgraph_context(merged_sub, winning_ctx)

	in_abstraction = true
	graphs.update_dependencies()
	_just_connected(who, to)
	if not deleting:
		graphs.spline_connected.emit(who, to)
	in_abstraction = false



func _count_connected_nodes(start: Graph, visited = {}) -> int:
	if start in visited:
		return 0
	visited[start] = true
	var total = 1
	for n in start.get_first_ancestors() + start.get_first_descendants():
		if n.subgraph_id == start.subgraph_id:
			total += _count_connected_nodes(n, visited)
	return total



func _choose_context_owner(left: Graph, right: Graph) -> Graph:
	var left_count = _count_connected_nodes(left)
	var right_count = _count_connected_nodes(right)
	if left_count > right_count:
		return left
	elif right_count > left_count:
		return right
	return right



func _is_valid() -> bool:
	return true

func get_title() -> String:
	return $ColorRect/root/Label.text if $ColorRect/root/Label else server_typename

var invalid_fields: Dictionary = {}
var cfg_snapshot: Dictionary = {}
func check_valid(changed_fields: Dictionary) -> void:
	var ok: bool = _is_valid()
	if ok:
		_visualise_valid(true)
		invalid_fields.clear()
		#cfg_snapshot = cfg.duplicate(true)
		return
	#for field in changed_fields.keys():
	invalid_fields = changed_fields
	#if not cfg_snapshot.is_empty():
		#var to_remove: Array[StringName] = []
		#for field in invalid_fields.keys():
			#if cfg_snapshot.has(field) and cfg.get(field) == cfg_snapshot.get(field):
				#to_remove.append(field)
		#for f in to_remove:
			#invalid_fields.erase(f)
	_visualise_valid(false)

func _visualise_valid(ok: bool):
	pass

var input_cached: Graph = null

func just_deattached(other_conn: Connection, my_conn: Connection):
	in_abstraction = true
	_just_deattached(other_conn, my_conn)
	in_abstraction = false



func _just_deattached(other_conn: Connection, my_conn: Connection):
	pass


var subgraph_id: int = 0
var context_id: int = 0
var subgraph_occupied: bool = false

func just_attached(other_conn: Connection, my_conn: Connection):

	in_abstraction = true
	_just_attached(other_conn, my_conn)
	in_abstraction = false

func reload_config():
	update_config(cfg.duplicate())

func get_x():
	return _get_x()

func _get_x() -> Variant:
	return 0

func _is_suitable_conn(who: Connection, other: Connection) -> bool:
	#if is_input and not is_train_graph: 
		#var current = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)
		#if is_instance_valid(current) and current != self:
#
			#return false
	return true

func _just_attached(other_conn: Connection, my_conn: Connection):
	pass

func deattaching(other_conn: Connection, my_conn: Connection):
	if input_cached:
		input_cached.graph_updated()
		#var nodes = graphs.simple_reach(self)
		#for i in nodes:
			#i.input_cached = null
		#input_cached = null
	_deattaching(other_conn, my_conn)

func connecting(my_conn: Connection, other_conn: Connection):
	_connecting(my_conn, other_conn)




func _deattaching(other_conn: Connection, my_conn: Connection):
	pass

func just_disconnected(who: Connection, from: Connection):
	in_abstraction = true
	from.parent_graph.just_deattached(who, from)
	learner.notify_update()
	_just_disconnected(who, from)

	var a: Graph = who.parent_graph
	var b: Graph = from.parent_graph
	if is_instance_valid(a): a.mark_new_subgraph()
	if is_instance_valid(b): b.mark_new_subgraph()
	in_abstraction = false



func disconnecting(who: Connection, from: Connection):
	#(server_typename)
	if not deleting:
		graphs.spline_disconnected.emit(who, from)
	#graphs.update_dependencies(who.parent_graph)
	from.parent_graph.deattaching(who, from)
	_disconnecting(who, from)

func _just_connected(who: Connection, to: Connection):pass
func _disconnecting(who: Connection, to: Connection):pass
func _connecting(who: Connection, to: Connection):pass
func _just_disconnected(who: Connection, from: Connection):pass

var virtual_inputs = {}

var virtual_outputs = {}

var config_conns = {}

func add_connection(conn: Connection):
	#var input_nm = 
	if conn.dynamic: return
	if conn.virtual: 
		if conn.connection_type == Connection.INPUT:
			virtual_inputs[conn.hint] = conn
		else:
			virtual_outputs[conn.hint] = conn
		return
	match conn.connection_type:
		Connection.INPUT: 
			_inputs.append(conn)
			assert(not conn.hint in input_keys, "Occupied")
			input_keys[conn.hint] = conn
			input_key_by_conn[conn] = conn.hint
			if conn.config_conn:
				config_conns[conn] = conn.hint
		Connection.OUTPUT: 
			outputs.append(conn)
			assert(not conn.hint in output_keys, "Occupied")
			output_keys[conn.hint] = conn
			output_key_by_conn[conn] = conn.hint

var active_output_connections = {}
func get_inputs_set() -> Dictionary[Connection, int]: return input_key_by_conn
func get_outputs_set() -> Dictionary[Connection, int]: return output_key_by_conn

func reach(call: Callable):
	pass

func conn_exit(conn: Connection):
	if conn.dynamic:
		return
	if conn.virtual:
		if conn.connection_type == Connection.INPUT:
			virtual_inputs.erase(conn.hint)
		else:
			virtual_outputs.erase(conn.hint)
		return
			
	match conn.connection_type:
		Connection.INPUT: 
			_inputs.erase(conn)
			input_keys.erase(conn.hint)
			input_key_by_conn.erase(conn)
			if conn.config_conn:
				config_conns.erase(conn)
		Connection.OUTPUT: 
			output_keys.erase(conn.hint)
			outputs.erase(conn)
			output_key_by_conn.erase(conn)

func _exit_tree() -> void:
	events.event_true("node", {"who": self})
	events.event_false("node")
	if _subgraph_registry.has(subgraph_id):
		var arr: Array = _subgraph_registry[subgraph_id]
		if self in arr:
			arr.erase(self)
			if arr.is_empty():
				Graph._subgraph_registry.erase(subgraph_id)
	graphs.remove(self)
	for i in graphs.where_am_i(self):
		graphs.uncache(self, i)
	glob.tags_1d.erase(llm_tag)



static var _subgraph_registry: Dictionary = {}

func register_in_subgraph(id: int) -> void:
	if not _subgraph_registry.has(id):
		_subgraph_registry[id] = []
	if not self in _subgraph_registry[id]:
		_subgraph_registry[id].append(self)

	subgraph_id = id
	subgraph_occupied = true

	if context_id == 0:
		context_id = id




func mark_new_subgraph() -> void:
	if any_input_upstream():
		return

	var old_sub = subgraph_id
	if not _subgraph_registry.has(old_sub):
		return

	var pre_nodes: Array = _subgraph_registry[old_sub].duplicate()
	if pre_nodes.is_empty():
		return
	var pre_context: int = pre_nodes[0].context_id

	var branch_a: Array = []
	collect_branch_nodes(self, branch_a, old_sub)

	if branch_a.is_empty() or branch_a.size() == pre_nodes.size():
		return

	var branch_b: Array = pre_nodes.duplicate()
	for n in branch_a:
		branch_b.erase(n)
	if branch_b.is_empty():
		return

	var root_a: Graph = branch_a[0]
	var root_b: Graph = branch_b[0]
	var winner: Graph = _context_policy(root_a, root_b, branch_a, branch_b)
	var winner_is_a = branch_a.has(winner)

	var new_sub = _new_subgraph_id()

	var new_context = _new_context_id()

	if winner_is_a:
		for n in branch_a:
			if not is_instance_valid(n): continue
			_subgraph_registry[old_sub].erase(n)
			n.register_in_subgraph(new_sub)
			n.context_id = pre_context
		for n in branch_b:
			if is_instance_valid(n):
				n.context_id = new_context
	else:
		for n in branch_a:
			if not is_instance_valid(n): continue
			_subgraph_registry[old_sub].erase(n)
			n.register_in_subgraph(new_sub)
			n.context_id = new_context

	_subgraph_registry[new_sub] = branch_a
	_subgraph_registry[old_sub] = branch_b




func _count_contexts(nodes: Array) -> Dictionary:
	var hist = {}
	for n in nodes:
		if not is_instance_valid(n): continue
		var c: int = n.context_id
		hist[c] = (hist.get(c, 0) + 1)
	return hist

func _pick_context_for_merge(nodes_a: Array, nodes_b: Array, dominant_input: Graph) -> int:
	var all = nodes_a.duplicate()
	all.append_array(nodes_b)
	var hist = _count_contexts(all)

	var winner_ctx = 0
	var winner_cnt = -1
	for c in hist.keys():
		var cnt: int = hist[c]
		if cnt > winner_cnt:
			winner_cnt = cnt
			winner_ctx = c

	if dominant_input and hist.has(dominant_input.root_context_id) and hist[dominant_input.root_context_id] == winner_cnt:
		winner_ctx = dominant_input.root_context_id

	return winner_ctx






func _reassign_subgraph_recursive(old_id: int, new_id: int, visited = {}):
	if self in visited:
		return
	visited[self] = true

	if _subgraph_registry.has(old_id):
		_subgraph_registry[old_id].erase(self)

	register_in_subgraph(new_id)
	subgraph_id = new_id

	for desc in get_first_descendants():
		if desc.subgraph_id == old_id:
			desc._reassign_subgraph_recursive(old_id, new_id, visited)
	for anc in get_first_ancestors():
		if anc.subgraph_id == old_id and not anc.is_input:
			anc._reassign_subgraph_recursive(old_id, new_id, visited)




func any_input_upstream(visited = {}) -> bool:
	if self in visited:
		return false
	visited[self] = true

	if is_input:
		return true

	for anc in get_first_ancestors():
		if anc.any_input_upstream(visited):
			return true

	return false


func propagate_subgraph(id: int, visited = {}):
	if self in visited:
		return
	visited[self] = true
	register_in_subgraph(id)

	if is_input:
		for desc in get_first_descendants():
			if desc.subgraph_id != id:
				desc.propagate_subgraph(id, visited)
	else:
		for anc in get_first_ancestors():
			if anc.subgraph_id != id:
				anc.propagate_subgraph(id, visited)
		for desc in get_first_descendants():
			if desc.subgraph_id != id:
				desc.propagate_subgraph(id, visited)


func _merge_subgraphs(a_id: int, b_id: int) -> void:
	if a_id == b_id: return
	if not _subgraph_registry.has(a_id) or not _subgraph_registry.has(b_id): return

	var a_nodes = _subgraph_registry[a_id]
	var b_nodes = _subgraph_registry[b_id]

	var a_ctx = a_nodes[0].context_id if not a_nodes.is_empty() else a_id

	for n in b_nodes:
		n.subgraph_id = a_id
		n.subgraph_occupied = true
		n.context_id = a_ctx
		if n not in a_nodes:
			a_nodes.append(n)

	_subgraph_registry[a_id] = a_nodes
	_subgraph_registry.erase(b_id)

	if not a_nodes.is_empty():
		a_nodes[0].propagate_subgraph(a_id)


var root_context_id: int = 0

func _new_subgraph_id() -> int:
	return randi_range(100000, 999999)

func _new_context_id() -> int:
	return randi_range(100000, 999999)


func _chain_incoming(cache: Dictionary):
	pass

func useful_properties() -> Dictionary:
	return _useful_properties()

func _useful_properties() -> Dictionary:
	return {}

var invoked_with: Callable

var is_blocked: bool = false
var input_cache = {}
var allow_drag: bool = true
func block(darken: bool = true, _drag: bool  = false): 
	is_blocked = true
	allow_drag = _drag
	if darken:
		modulate = Color(0.7,0.7,0.7,1)
	for i in glob.rget_children(self):
		if i is LineEdit or i is BlockComponent:
			input_cache[i] = i.mouse_filter
			i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i is BlockComponent:
			i.block_input()
	
func unblock(): 
	is_blocked = false
	allow_drag = true
	modulate = Color.WHITE
	for i in input_cache:
		if not is_instance_valid(i): continue
		i.mouse_filter = input_cache[i]
		if i is BlockComponent:
			i.unblock_input()
	input_cache.clear()

var cbox: CheckBox
func enter_selection_mode():
	block(false, true)
	if is_instance_valid(outl): outl.queue_free()
	outl = graphs.shadow_rect.instantiate()
	add_child(outl)
	outl.position = rect.position
	outl.outline = true
	outl.extents = rect.size
	outl.color = Color.WHITE
	outl.color.a = 0.3
	outl.modulate.a = 1.0
	move_child(outl, 0)

var outl = null
var chosen: bool = false

func choose(effect: bool = false):
	if !effect:
		chosen = true
	outl.z_index = 2
	outl.color = Color.GREEN
	select_effect(Color.GREEN)
	outl.color.a = 0.35
	ui.mark_chosen(self)


func choose_progress():
	if hold_t > 0.3:
		outl.z_index = 2
		outl.color = Color(1,1,1,0.3).lerp(Color(0,1,0,0.35), (hold_t - 0.3) / 0.2)

func unchoose(effect: bool = false):
	if !effect:
		chosen = false
	outl.z_index = 0
	outl.color = Color.WHITE
	select_effect(base_outline)
	outl.color.a = 0.3
	ui.unmark_chosen(self)

func exit_selection_mode():
	outl.queue_free()
	select_effect(base_outline)
	unblock()

var deletion_allowed: bool = true
func prohibit_deletion():
	deletion_allowed = false

func allow_deletion():
	deletion_allowed = true


var blinking = false
func blink_tween(data: Dictionary, delta: float):
	if ui.nodes_choosing: 
		blinking = false
		return true
	var q_del = false
	if not is_instance_valid(outl):
		q_del = true
	data.t += delta
	var prog: float = data.t / data.flow[0]
	var ending = data.t > (data.flow[0] + data.flow[1]) if data.double else blink_end_req
	ending = ending or data.has("mark")
	var ended = false
	if ending: 
		if not data.has("mark"): data["mark"] = true; data.t = 0
		prog = 1.0 - (data.t / data.flow[2])
		if prog < glob.eps:
			ended = true
	else:
		if data.t > data.flow[0]:
			prog = 1.0
	if q_del: ended = true; prog = 0.0
	if is_nan(prog):
		prog = 0.0
	modulate = Color.WHITE.lerp(Color.WHITE*1.3, prog)
	if is_instance_valid(outl):
		outl.modulate.a = lerpf(0, 1, prog)
	if ended: 
		if is_instance_valid(outl):
			outl.queue_free()
		blinking = false
		return true
var blink_end_req: bool = false

func blink_end():
	blink_end_req = true

var tweener = null
func blink(with_end: bool = true):
	if ui.nodes_choosing: return
	if blinking:
		if outl:
			outl.queue_free() 
		await get_tree().process_frame
	blink_end_req = false
	blinking = true
	outl = graphs.shadow_rect.instantiate()
	add_child(outl)
	outl.position = rect.position
	outl.outline = true
	outl.extents = rect.size
	outl.color = Color.WHEAT
	outl.color.a = 0.3
	outl.modulate.a = 0.0
	move_child(outl, 0)
	tweener = glob.tween_call_obj({"t": 0, "flow": [0.2, 3, 0.6], "double": with_end}, blink_tween)

var _create_action_snapshot: Dictionary = {}

func refresh_create_action_snapshot() -> void:
	if _create_action_snapshot.is_empty():
		return

	_create_action_snapshot["position"] = position
	_create_action_snapshot["cfg"] = cfg.duplicate(true)

func _ready() -> void:
	#block()
	#(graph_flags)
	events.event_true("node", {"who": self})
	if ui.nodes_choosing:
		enter_selection_mode()
	#(invoked_with.get_bound_arguments())
	if graph_flags & Flags.NEW:
		var created_type: StringName = StringName(get_meta("created_with"))
		var created_id: int = graph_id
		var created_llm_tag: String = llm_tag

		_create_action_snapshot = {
			"position": position,
			"cfg": cfg.duplicate(true),
		}

		var snapshot := _create_action_snapshot

		glob.add_action(
			graphs.delete_graph_by_id.bind(created_id),
			func():
				if is_instance_valid(graphs._graphs.get(created_id, null)):
					return

				var g: Graph = graphs.get_graph(created_type, Graph.Flags.NEW, created_id, created_llm_tag)

				if snapshot.has("position"):
					g.position = snapshot["position"]

				if snapshot.has("cfg"):
					g.update_config(snapshot["cfg"].duplicate(true))

				g.reposition_splines()
		)
	#ui.show_arrow_conn(input_key_by_conn.keys()[0])
	#ui.show_arrow_graph(self)
	#glob.open_action(self, "create_graph")
	#glob.push_action(self, invoked_with, delete)
	#glob.close_action(self)
	#("FWRJFPKWEPFJ")

	position -= rect.position
	animate(0)
	#graphs.add(self)
	_after_ready()
	#graphs.mark_rect(self)
	if is_input and root_context_id == 0:
		root_context_id = _new_context_id()
		context_id = root_context_id
	await get_tree().process_frame
	if llm_tag:
		glob.set_llm_tag(self, llm_tag)
	else:
		glob.get_llm_tag(self)
#	if not llm_tag:
	#llm_tag = glob.get_llm_tag(self)
	#graphs.collider(rect)

func all_connections() -> Array[Connection]:
	var a: Array[Connection] = []
	for i in input_key_by_conn:
		a.append(i)
	for i in output_key_by_conn:
		a.append(i)
	return a



func _collect_inputs_in_subgraph(sub_id: int) -> Array:
	var res: Array = []
	if _subgraph_registry.has(sub_id):
		for n in _subgraph_registry[sub_id]:
			if is_instance_valid(n) and n.is_input:
				res.append(n)
	return res


func collect_branch_nodes(root: Graph, out: Array, old_id: int, visited = {}):
	if root in visited:
		return
	visited[root] = true
	out.append(root)
	for d in root.get_first_descendants():
		if d.subgraph_id == old_id:
			collect_branch_nodes(d, out, old_id, visited)
	for a in root.get_first_ancestors():
		if a.subgraph_id == old_id:
			collect_branch_nodes(a, out, old_id, visited)



func _recompute_context_for_subgraph(sub_id: int, dominant_input: Graph = null) -> void:
	if not _subgraph_registry.has(sub_id):
		return

	var winner: Graph = null
	if dominant_input and dominant_input.is_input and dominant_input.subgraph_id == sub_id:
		winner = dominant_input
	else:
		var inputs = _collect_inputs_in_subgraph(sub_id)
		if inputs.is_empty():
			return
		inputs.sort_custom(func(a, b): return a.root_context_id < b.root_context_id)
		winner = inputs[0]

	var ctx = winner.root_context_id
	for n in _subgraph_registry[sub_id]:
		if is_instance_valid(n):
			n.context_id = ctx


func _context_policy(a: Graph, b: Graph, a_nodes: Array, b_nodes: Array) -> Graph:
	if a_nodes.size() > b_nodes.size():
		return a
	if b_nodes.size() > a_nodes.size():
		return b
	var a_inputs = a_nodes.any(func(n): return n.is_input)
	var b_inputs = b_nodes.any(func(n): return n.is_input)
	if a_inputs and not b_inputs:
		return a
	if b_inputs and not a_inputs:
		return b
	return a






func is_mouse_inside(rectangle: float = area_padding) -> bool:
	# Only the manager-chosen top graph may claim the mouse
	if graphs.top_graph_at_mouse != self:
		return false

	if glob.get_display_mouse_position().y < glob.space_begin.y \
	or glob.get_display_mouse_position().x > glob.space_end.x:
		return false

	var top_left = rect.global_position - Vector2.ONE * rectangle
	var padded_size = rect.size + Vector2(rectangle, rectangle) * 2.0
	var bounds = Rect2(top_left, padded_size)
	var has: bool = bounds.has_point(get_global_mouse_position())
	if has:
		glob.consume_input(self, "mouse")
	return has


var dragging: bool = false
var attachement_position: Vector2 = Vector2()
var exist_time: float = 0.0

func _io(inputs: Dictionary) -> Variant:
	$ColorRect/root/Label.text = str(inputs[0][0]+1)
	return inputs[0][0]+1

var pushed_inputs = {}
func _seq_push_input(connection_key: int, value) -> void:
	pushed_inputs.get_or_add(connection_key, []).append(value)
	if len(pushed_inputs) >= len(input_keys):
		propagate(pushed_inputs)
		pushed_inputs.clear()

func get_info() -> Dictionary:
	var inputs = {}
	var outputs_ = {}
	for i in input_keys:
		inputs[input_keys[i].conn_id] = i
	for i in output_keys:
		var port = []
		for o in output_keys[i].outputs:
			port.append(output_keys[i].outputs[o].tied_to.conn_id)
		port.append(output_keys[i].conn_id)
		outputs_[i] = port
			#input_spline.
	var base = {
		"position": position,
		"cfg": cfg,
		"inputs": inputs,
		"outputs": outputs_,
		"created_with": get_meta("created_with"),
		"subgraph_id": subgraph_id,
		"context_id": context_id,
		"root_context_id": root_context_id,
		"subgraph_occupied": subgraph_occupied,
		"llm_tag": llm_tag,
	}
	base.merge(_get_info(), true)
	return base

var llm_tag: String = ""

func map_properties(pack: Dictionary, careful: bool = false):
	#for i in pack:
	#	if not i in 
	position = pack.position
	subgraph_id = pack.subgraph_id
	context_id = pack.context_id
	root_context_id = pack.root_context_id
	subgraph_occupied = pack.subgraph_occupied
	if not Graph._subgraph_registry.has(subgraph_id):
		Graph._subgraph_registry[subgraph_id] = []
	if not self in Graph._subgraph_registry[subgraph_id]:
		Graph._subgraph_registry[subgraph_id].append(self)
	if  pack.get("llm_tag", ""):
		glob.set_llm_tag(self, pack.llm_tag)
	else:
		glob.get_llm_tag(self)
	update_config(pack.cfg)
	for f in pack.cfg:
		if pack.cfg[f] is Dictionary:
			update_config_subfield({f: pack.cfg[f]})
	_map_properties(pack)

static func get_ctx_groups() -> Dictionary:
	var ctx_groups: Dictionary = {}
	for sub_id in _subgraph_registry:
		for n in _subgraph_registry[sub_id]:
			if not is_instance_valid(n):
				continue
			var ctx = n.context_id
			if not ctx_groups.has(ctx):
				ctx_groups[ctx] = []
			ctx_groups[ctx].append(n)
	return ctx_groups

static func debug_print_contexts() -> void:
	var ctx_groups = get_ctx_groups()

	for ctx_id in ctx_groups.keys():
		var nodes = ctx_groups[ctx_id]
		print("Context %s (%d nodes):" % [str(ctx_id), nodes.size()])
		for n in nodes:
			var t = n.server_typename if n.server_typename != "" else n.get_class()
			var info = "%-12s  subgraph=%d  graph_id=%d  input=%s" % [
				t, n.subgraph_id, n.graph_id, str(n.is_input)
			]
			print(info)




func _map_properties(pack: Dictionary):
	pass
	#for i in pack:
		


var info_nested_fields: Array = []
func _get_info() -> Dictionary:
	return {}

func propagate(input_vals: Dictionary, sequential_branching: bool = false) -> void:
	var out = _io(input_vals) if not gather else null
	var output_vals = {}

	match typeof(out):
		TYPE_ARRAY:
			for i in out.size():
				output_vals[i] = out[i]
		TYPE_DICTIONARY:
			for i in out.keys():
				output_vals[i] = out[i]
		_:
			for i in outputs.size():
				output_vals[i] = out

	for out_key in output_vals:
		var next_conn = output_keys[out_key]
		for branch_key in next_conn.outputs:
			var spline = next_conn.outputs[branch_key]
			if not spline.tied_to: continue
			var other_node: Graph = spline.tied_to.parent_graph
			var connection_key: int = other_node.input_key_by_conn[spline.tied_to]
			#other_node._seq_push_input(connection_key, output_vals[out_key])
			graphs.next_frame_from(spline.origin, spline.tied_to)
			graphs.next_frame_propagate(spline.tied_to, connection_key, output_vals[out_key] if not graphs.reach_mode else spline.origin)
			

func gather():
	pass

	#(out)

func _can_drag() -> bool:
	return true

func _default_info() -> void: # virtual
	pass

var _info = {}
func set_info(name: String, value: Variant):
	pass

@onready var prev_size_: Vector2 = rect.size
var inside: bool = false

func get_center_pos() -> Vector2:
	return rect.get_global_rect().get_center()

func get_graph_rect() -> Rect2:
	return rect.get_global_rect()

var take_offset_y: float = 0.0
var shadow: GraphShadow = null
func drag_start():
	if shadow:
		put_back()
	putting_back = 0.0
	take_offset_y = 0.0
	graphs.drag(self)

	shadow = graphs.shadow_rect.instantiate()
	add_child(shadow)
	shadow.position = rect.position + Vector2(0,12)
	shadow.outline = true
	shadow.extents = rect.size
	shadow.modulate.a = 0.0
	if ui.nodes_choosing:
		shadow.hide()
	move_child(shadow, 0)

	var sel = graphs.selected_nodes
	if selected and sel.size() > 1:
		group_dragging = true
		group_drag_leader = self
		group_drag_nodes = sel.duplicate()
		group_drag_nodes.erase(self)
		group_drag_start_mouse = get_global_mouse_position()
		group_drag_start_positions.clear()
		group_drag_before_positions.clear()

		group_drag_start_positions[self] = global_position
		group_drag_before_positions[self] = position
		for n in group_drag_nodes:
			if not is_instance_valid(n): continue
			n._enter_group_drag(self)
			n.take_offset_y = take_offset_y  # sync immediately
			n.shadow.modulate.a = 0.0
			group_drag_start_positions[n] = n.global_position
			group_drag_before_positions[n] = n.position

	



func drag_ended():
	putting_back_anchor = global_position.y
	if shadow:
		putting_back = 1.0
		hold_for_frame()
	# sync start of put-back for all followers
	if group_dragging and group_drag_leader == self:
		for n in group_drag_nodes:
			if not is_instance_valid(n): continue
			n.putting_back = putting_back
			n.take_offset_y = take_offset_y
			n.putting_back_anchor = n.global_position.y
			n.hold_for_frame()

	graphs.stop_drag(self)

	if group_dragging and group_drag_leader == self:
		# capture after positions for undo
		var after_positions: Dictionary = {}
		for g in group_drag_start_positions.keys():
			if not is_instance_valid(g): continue
			after_positions[g] = g.position

		var before_positions := group_drag_before_positions.duplicate(true)
		glob.add_action(
			(func():
				for g in before_positions.keys():
					if is_instance_valid(g):
						g.push_position(before_positions[g])),
			(func():
				for g in after_positions.keys():
					if is_instance_valid(g):
						g.push_position(after_positions[g]))
		)

		for n in group_drag_nodes:
			if is_instance_valid(n):
				#(n.get_title())
				n._exit_group_drag()

		group_dragging = false
		group_drag_leader = null
		group_drag_nodes.clear()
		group_drag_start_positions.clear()
		group_drag_before_positions.clear()

	#shadow_rect

func stopped_processing():
	if glob.hovered_connection in input_key_by_conn:
		glob.hovered_connection = null
	#for i in output_key_by_conn:
#		i.cached_other_rev = null
	glob.reset_menu_type(self, &"edit_graph")
	glob.un_occupy(self, &"graph")
	drag_ended()
	if glob.get_occupator() is Connection and glob.get_occupator() in output_key_by_conn:
		glob.reset_menu_type(glob.get_occupator(), "detatch")
	if glob.is_occupied(self, "conn_active"):
		glob.un_occupy(glob.occ_layers["conn_active"], "conn_active")
	_stopped_processing()



func _stopped_processing():
	pass
		#hold_for_frame()
	#for i in graphs.conns_active:
		#if i in output_key_by_conn:
		#	glob.un_occupy(i, "conn_active")

func delete(disconn: bool = true):
	if !deletion_allowed:
		return

	graphs.unselect(self)
	_stopped_processing()
	
	for conn in output_key_by_conn:
		conn.disconnect_all(disconn)

	for conn in input_key_by_conn:
		conn.disconnect_all(disconn)

	learner.on_graph_deleted(self)

	await get_tree().process_frame
	queue_free()



func _size_changed(): # virtual
	pass

var changed_size_frame: bool = true
func size_changed():
	changed_size_frame = true
	_size_changed()

var graph_id: int = 0

func _init() -> void:
	graph_id = randi_range(0,99999999)
	subgraph_id = randi_range(0,99999999)
	context_id = subgraph_id
	subgraph_occupied = false

func _dragged():
	pass

func _proceed_hold() -> bool:
	return false

var exist_ticks: int = 0
var putting_back: float = 0.0
var putting_back_anchor: float = 0.0
func put_back():
	if is_instance_valid(shadow):
		shadow.queue_free()
		shadow = null   # prevent stale pointer
	putting_back = 0.0
	global_position.y = putting_back_anchor - take_offset_y


func push_position(pos: Vector2):
	position = pos
	reposition_splines()
	hold_for_frame()


func _commit_batched_undo():
	if _undo_start_snapshot.is_empty():
		return
	if glob.is_auto_action() or glob.in_batch:
		return
	#if glob.is_auto_action(): return
	var reversion = {}
	for i in _pending_undo_update:
		if i in _undo_start_snapshot:
			reversion[i] = _undo_start_snapshot[i]
		else:
			reversion[i] = base_config[i]

	var before_state = reversion.duplicate(true)
	var after_state = _pending_undo_update.duplicate(true)

	glob.add_action(
		update_config.bind(before_state),
		update_config.bind(after_state)
	)

	_pending_undo_update.clear()
	_undo_start_snapshot.clear()
	_undo_active = false


var group_dragging: bool = false
var group_drag_leader: Graph = null
var group_drag_nodes = {}
var group_drag_start_mouse: Vector2
var group_drag_start_positions: Dictionary = {}
var group_drag_before_positions: Dictionary = {}

func _selected_nodes():
	return graphs.selected_nodes


func _enter_group_drag(leader: Graph) -> void:
	group_dragging = true
	group_drag_leader = leader

	if shadow:
		shadow.queue_free()
	shadow = graphs.shadow_rect.instantiate()
	add_child(shadow)
	shadow.position = rect.position + Vector2(0, 12)
	shadow.outline = true
	shadow.extents = rect.size
	shadow.modulate.a = 0.0
	move_child(shadow, 0)

	# cache the local Y offset for put_back animation later
	take_offset_y = 0.0
	putting_back_anchor = global_position.y



func _exit_group_drag() -> void:
	if shadow:
		putting_back_anchor = global_position.y
		take_offset_y = -4.0
		putting_back = 1.0
		hold_for_frame()
	group_dragging = false
	group_drag_leader = null



func sync_group_visuals():
	if not group_dragging or group_drag_leader == null or group_drag_leader == self:
		return
	var leader := group_drag_leader
	if is_instance_valid(leader):
		take_offset_y = leader.take_offset_y
		putting_back = leader.putting_back
		putting_back_anchor = leader.putting_back_anchor
		if is_instance_valid(shadow) and is_instance_valid(leader.shadow):
			shadow.modulate.a = leader.shadow.modulate.a




func get_inputs() -> Array[Spline]:
	var res: Array[Spline] = []
	for i in input_key_by_conn:
		for input in i.inputs:
			res.append(input)
	#(input_key_by_conn)
	return res


func get_outputs() -> Array[Spline]:
	var res: Array[Spline] = []
	for i in output_key_by_conn:
		for o in i.outputs:
			res.append(i.outputs[o])
	#(res)
	return res

func delete_call():
	if !deletion_allowed:
		return
	var res = []
	var dup = graphs.selected_nodes.duplicate()
	dup[self] = true
	var existed = {}
	for g: Graph in dup:
		for i in g.get_inputs() + g.get_outputs():
			var dict = {}
			dict["from_id"] = i.origin.parent_graph.graph_id
			dict["from_port"] = i.origin.hint
			dict["to_id"] = i.tied_to.parent_graph.graph_id
			dict["to_port"] = i.tied_to.hint
			var val = ""
			for j in dict.values():
				val += str(j)
				val += ":"
			if val in existed: continue
			existed[val] = true
			res.append(dict)
	#(res)
	#if len(res) != 1:
	glob.open_action_batch()
	for i in dup:
		var pos = i.position
		i.deleting = true
		var callb = graphs.get_graph.bind(i.get_meta("created_with"), Flags.NEW, i.graph_id, i.llm_tag)
		glob.add_action(glob.bound.bind(callb, pos, i.cfg.duplicate(true), selected), 
		graphs.delete_graph_by_id.bind(i.graph_id))
		#(i.get_title())
		i.delete(false)
	glob.add_action(glob.create_conns.bind(res), glob.destroy_conns.bind(res))
	
	#if len(res) != 1:
	#await get_tree().process_frame
	#await get_tree().process_frame
	glob.delay_close()
	#else:
		#glob.open_action_batch()
		#var pos = i.position
		#i.deleting = true
		#var callb = graphs.get_graph.bind(i.get_meta("created_with"), Flags.NEW, i.graph_id, i.llm_tag)
		#glob.add_action(glob.bound.bind(callb, pos, i.cfg.duplicate(true)), 
		#graphs.delete_graph_by_id.bind(i.graph_id))
		##(i.get_title())
		#i.delete(false)
		#glob.add_action(glob.create_conns.bind(res), glob.destroy_conns.bind(res))
		#glob.close_action_batch()
		#deleting = false


var deleting: bool = false
var hold_committed: bool = false
func copy():
	request_save()
	var a = graphs.get_graph(get_meta("created_with"), Graph.Flags.NEW)
	a.position = position + rect.size / 2
	await get_tree().process_frame
	a.update_config(cfg.duplicate(true))

func define_graph():
	glob.menus["edit_graph"].menu_call = func():
		if deletion_allowed:
			delete_call()
		else:
			ui.error("Cannot delete this node - it is a part of a lesson!")
	glob.menus["edit_graph"].menu_call_alt = func():
		if not (is_input and !is_train_graph):
			copy()
		else:
			ui.error("Cannot duplicate - only one Input node per project is allowed!")
	glob.menus["edit_graph"].of_node = self
	glob.show_menu("edit_graph")



var low = {"detatch": true}
var first_drag: bool = false
var beginned_at: Vector2 = Vector2()
var hold_t: float = 0
func _process(delta: float) -> void:
#	print(group_dragging)
	if Engine.is_editor_hint(): return
	if glob.f2_pressed:
		return
	#if glob.space_just_pressed:
	#	unblock()
	
	var follower_in_group := group_dragging and group_drag_leader != null and group_drag_leader != self
	exist_ticks += 1
	if _undo_timer > 0.0:
		_undo_timer -= delta
		hold_for_frame()
		if _undo_timer <= 0.0 and not _pending_undo_update.is_empty():
			_commit_batched_undo()
	#if position != prev_graph_pos:
	#	reposition_conns()
	if rect.get_global_rect().grow(10.0).has_point(get_global_mouse_position()):
		glob.occupy(self, "graph_buffer")
	else:
		glob.un_occupy(self, "graph_buffer")
	
	animate(delta)
#	graphs.store_delta(self)
	if prev_size_ != rect.size:
		prev_size_ = rect.size
		#graphs.collider(rect)
	exist_time += delta
	
	
	inside = is_mouse_inside()
		
	var conn_free = (not glob.hovered_connection or glob.hovered_connection.connection_type == 0 or z_index >= glob.hovered_connection.parent_graph.z_index)
	
	if inside and conn_free:
		glob.occupy(self, &"graph")
		glob.set_menu_type(self, &"edit_graph")
		if glob.mouse_alt_just_pressed and not dragging:
			glob.menus["edit_graph"].menu_call = func():
				if deletion_allowed:
					delete_call()
				else:
					ui.error("Cannot delete this node - it is a part of a lesson!")
			glob.menus["edit_graph"].menu_call_alt = func():
				if not (is_input and !is_train_graph):
					copy()
				else:
					ui.error("Cannot duplicate - only one Input node per project is allowed!")
			glob.menus["edit_graph"].of_node = self
			glob.show_menu("edit_graph")
	else:
		glob.reset_menu_type(self, &"edit_graph")
		glob.un_occupy(self, &"graph")
	
	# TODO: remove this crutch
	var conn_active_layer = glob.occ_layers.get("conn_active")
	if conn_active_layer:
		if !conn_active_layer.active_outputs:
			glob.un_occupy(conn_active_layer, "conn_active")
	if putting_back > 0.1:
		hold_for_frame()
		putting_back = lerp(putting_back, 0.0, delta * 15.0)
		if is_instance_valid(shadow):
			shadow.modulate.a = putting_back
		reposition_splines()
		if putting_back < 0.1:
			put_back()
			reposition_splines()
		else:
			global_position.y = lerp(putting_back_anchor - take_offset_y, putting_back_anchor, putting_back)

	var unp_inside = is_mouse_inside(0)
	#( glob.get_occupied(&"menu"))
	#(glob.is_occupied(self, &"dropout_inside"))
	#(glob.get_occupied("menu"))
	var mouse_just_pressed = glob.mouse_just_pressed
	var mouse_pressed = glob.mouse_pressed
	if not allow_drag:
		mouse_just_pressed = false
		mouse_pressed = false
	if inside and is_blocked:
		glob.reset_mouse()
	#(inside and mouse_just_pressed)
	if ui.nodes_choosing:
		# detect invalidation (release or drag)
		var drag_cancel := dragging and beginned_at.distance_squared_to(position) > 200
		var holding := mouse_pressed and inside and not drag_cancel

		# start hold
		if mouse_just_pressed and inside:
			hold_t = 0.001
			hold_committed = false
			if not chosen:
				select_effect(Color(0.8, 1, 0.8))

		# accumulate hold
		if holding:
			hold_t += delta
		else:
			# cancel hold → restore visual state
			if hold_t > 0:
				hold_committed = false 
				hold_t = 0

				if chosen:
					outl.z_index = 2
					outl.color = Color.GREEN
					outl.color.a = 0.35
					select_effect(Color.GREEN)
				else:
					outl.z_index = 0
					outl.color = Color.WHITE
					outl.color.a = 0.3
					select_effect(base_outline)

		# preview animation
		if hold_t > 0 and not hold_committed:
			#hold_committed = false
			if chosen:
				# unchoose preview (reverse feel, fade out)
				outl.color = Color(0, 1, 0, 0.35).lerp(
					Color(1, 1, 1, 0.3),
					min(hold_t / 0.5, 1.0)
				)
			else:
				# choose preview (existing behavior)
				if hold_t > 0.3:
					select_effect(Color.GREEN)
				choose_progress()

		# commit transition
		if hold_t > 0.5 and not hold_committed:
			hold_committed = true
			if chosen:
				unchoose()
			else:
				choose()
			hold_t = 0

	if inside and mouse_just_pressed and _can_drag() and (
		not glob.is_occupied(self, &"menu") and 
		not ui.topr_inside and 
		not glob.is_occupied(self, &"graph") and 
		not glob.is_occupied(self, &"menu_inside") and 
		not glob.is_occupied(self, &"conn_active") and
		(not glob.splines_active or unp_inside) and
		not glob.is_occupied(self, &"dropout_inside") and
		conn_free) and not dragging:
		drag_start()
		if not first_drag:
			beginned_at = position
			first_drag = true
		dragging = true; attachement_position = global_position - get_global_mouse_position()
	
	if dragging:
		hold_for_frame()
		if not mouse_pressed or (not unp_inside and glob.splines_active):
			dragging = false
			# use combined undo for group (handled in drag_ended); for single, keep existing
			if group_dragging and group_drag_leader == self:
				for n in group_drag_nodes:
					# keep their shadow fade in sync
					if is_instance_valid(n.shadow):
						n.shadow.modulate.a = shadow.modulate.a
					n.reposition_splines()
			if not group_dragging:
				glob.add_action(push_position.bind(beginned_at), push_position.bind(position))
				beginned_at = position
			drag_ended()
		else:
			var target_vec = get_global_mouse_position() + attachement_position + Vector2(0, take_offset_y)
			take_offset_y = lerpf(take_offset_y, -4.0, delta*15.0)
			if is_instance_valid(shadow):
				shadow.modulate.a = take_offset_y/ -4.0

			var leader_before := global_position
			var leader_after := global_position.lerp(target_vec, delta*40.0)
			global_position = leader_after

			if group_dragging and group_drag_leader == self:
				var d := leader_after - leader_before
				if d.length_squared() > 0.0:
					for n in group_drag_nodes:
						if not is_instance_valid(n): continue
						n.global_position += d
				for n in group_drag_nodes:
					if is_instance_valid(n):
						n.hold_for_frame()
						n.sync_group_visuals()

			# splines for everyone
			reposition_splines()
			if group_dragging and group_drag_leader == self:
				for n in group_drag_nodes:
					# keep their shadow fade in sync
					if is_instance_valid(n.shadow):
						n.shadow.modulate.a = shadow.modulate.a
					n.reposition_splines()

		_dragged()

	
	_after_process(delta)
	if changed_size_frame:
		hold_for_frame()
	changed_size_frame = false
	prev_graph_pos = position
	if _proceed_hold():
		hold_for_frame()

func is_valid() -> bool:
	return false if invalid_fields else true

var prev_graph_pos: Vector2 = position


func is_being_group_dragged() -> bool:
	return group_dragging or (group_drag_leader and group_drag_leader.group_dragging)


func reposition_conns():
	pass

func reposition_splines():
	for input in _inputs:
		input.reposition_splines()
	for output in outputs:
		output.reposition_splines()
	for i in virtual_inputs:
		virtual_inputs[i].reposition_splines()
	for o in virtual_outputs:
		virtual_outputs[o].reposition_splines()

func _after_process(delta: float):
	pass
