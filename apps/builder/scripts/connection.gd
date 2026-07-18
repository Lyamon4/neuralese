extends ColorRect
class_name Connection

@export var config_conn: bool = false
static var INPUT: int = 0
static var OUTPUT: int = 1
@export var dynamic: bool = false
@export var virtual: bool = false

var accepted_datatypes: Dictionary[StringName, bool] = {}
var datatype: StringName = ""
@export var _accepted_datatypes: String = "": ##any(empty), float, config
	set(v):
		_accepted_datatypes = v
		if not is_node_ready():
			await ready
		repoll_accepted()

func repoll_accepted():
	accepted_datatypes = {}
	if _accepted_datatypes:
		for i in _accepted_datatypes.split(" "):
			if not datatype:
				datatype = i
			accepted_datatypes[i] = true

@export var hint: int = 0
@export var server_name: StringName = "":
	set(v):
		assert(v, "Please set server_name for server execution identification")
		server_name = v
@export var keyword: StringName = &""
@export_enum("Input", "Output") var connection_type: int = INPUT
@export var area_paddings: Vector4 = Vector4(10,10,10,10)
@export var multiple_splines: bool = false
@export var origin_offset: Vector2 = Vector2()
@export var unpadded_area: Vector4 = Vector4()
@export var max_splines_by_keyword: Dictionary[StringName, int] = {}

@export var dir_vector: Vector2 = Vector2.RIGHT

@export var parent_graph: Graph

var outputs: Dictionary[int, Spline] = {}
var active_outputs: Dictionary[int, Spline] = {}
var inputs: Dictionary[Spline, int] = {}
var connected: Dictionary[Connection, bool] = {}

var mouse_just_pressed: bool = false
var mouse_pressed: bool = false

var _rev_spline: Spline = null
var _rev_slot: int = -1

func _rev_start():
	_rev_slot = randi_range(111111, 999999)
	_rev_spline = glob.get_spline(self)
	_rev_spline.turn_into(keyword)
	_rev_spline.origin = self
	_rev_spline.tied_to = self
	glob.activate_spline(_rev_spline, false)
	_rev_spline.show()
	_rev_spline.end_dir_vec = dir_vector
	_rev_spline.top_level = true
	_stylize_spline(_rev_spline, false)

	graphs.rev_input = self
	parent_graph.hold_for_frame()

func _rev_end():
	if _rev_spline:
		glob.deactivate_spline(_rev_spline)
		_rev_spline.disappear()
	_rev_spline = null
	_rev_slot = -1
	if graphs.rev_input == self:
		graphs.rev_input = null

func _rev_active() -> bool:
	return _rev_spline != null

func disconnect_all(disconn: bool = true):
	delete(disconn)

var reg_actions: bool = true
func delete(disconn: bool = true):
	reg_actions = disconn
	if connection_type == INPUT:
		var dup = inputs.duplicate()
		for i in dup:
			detatch_spline(i)
			i.origin.end_spline(dup[i])
	else:
		for i in outputs.duplicate():
			outputs[i].tied_to.detatch_spline(outputs[i])
			end_spline(i)
	reg_actions = true

func is_mouse_inside(padding:Vector4=-Vector4.ONE) -> bool:
	if parent_graph.rect.get_global_rect().grow(-2).has_point(get_global_mouse_position()):
		return false
	var pd = padding
	if padding == -Vector4.ONE:
		pd = Vector4.ONE * 55 * pow(glob.cam.zoom.x, -0.5)
	else:
		pd = Vector4()
	if glob.get_display_mouse_position().y < glob.space_begin.y\
	or glob.get_display_mouse_position().x > glob.space_end.x: return false
	var top_left = global_position - Vector2(pd.x, pd.y) * parent_graph.scale * scale
	var padded_size = size * parent_graph.scale * scale + Vector2(pd.x+pd.z, pd.y+pd.w)
	var has: bool = Rect2(top_left, padded_size).has_point(get_global_mouse_position())
	return has

func reposition_splines():
	var ct: int = 0
	for id in outputs.keys():
		var spline = outputs[id]
		var a = spline.origin
		var b = spline.tied_to
		if !is_instance_valid(b):
			continue

		var ga = a.parent_graph
		var gb = b.parent_graph
		var both_dragging = ga.is_being_group_dragged() and gb.is_being_group_dragged() and ga.group_drag_leader == gb.group_drag_leader
		if both_dragging:
			# just shift by the delta of origin since last frame
			var cur = a.get_origin()
			var prev = spline._last_origin_pos
			var offset = cur - prev
			spline.update_points_fast(offset)
			spline._last_origin_pos = cur
			spline._last_target_pos = b.get_origin()
			continue

		spline.update_points(a.get_origin(), b.get_origin(), dir_vector, b.dir_vector)
		spline._last_origin_pos = a.get_origin()
		spline._last_target_pos = b.get_origin()
		ct += 1

	for spline in inputs.keys():
		var a = spline.origin
		var b = spline.tied_to
		if !is_instance_valid(a) or !is_instance_valid(b):
			continue

		var ga = a.parent_graph
		var gb = b.parent_graph
		var both_dragging = ga.is_being_group_dragged() and gb.is_being_group_dragged() and ga.group_drag_leader == gb.group_drag_leader
		if both_dragging:
			var cur = b.get_origin()
			var prev = spline._last_target_pos
			var offset = cur - prev
			spline.update_points_fast(offset)
			spline._last_origin_pos = a.get_origin()
			spline._last_target_pos = cur
			continue

		spline.update_points(a.get_origin(), b.get_origin(), a.dir_vector, dir_vector)
		ct += 1
		spline._last_origin_pos = a.get_origin()
		spline._last_target_pos = b.get_origin()
	#(ct)

func add_spline() -> int:
	var slot = randi_range(111111,999999)
	var spline = glob.get_spline(self)
	spline.turn_into(keyword)
	spline.origin = self
	spline.set_fork_color(gradient_color)
	key_by_spline[spline] = slot
	outputs[slot] = spline
	return slot

var key_by_spline: Dictionary[Spline, int] = {}
func start_spline(id: int):
	#_stack()
	var spline = outputs[id]
	var node = spline.tied_to
	if is_instance_valid(node):
		node.inputs.erase(spline)
	spline.set_meta("old_tied_to", spline.tied_to)
	spline.tied_to = null
	parent_graph.active_output_connections[self] = true
	spline.show()
	graphs.conns_active[self] = true
	active_outputs[id] = spline


var allow_reverse: bool = false

var is_fork: bool = false
func set_fork_allowed(fork: bool):
	is_fork = fork
	allow_reverse = true if not fork else false
	if !fork:
		$plot.hide()
		$plot3.hide()
	else:
		$plot.hide()
		$plot3.hide()
		if connection_type == OUTPUT:
			$plot.show()
		if connection_type == INPUT:
			$plot3.show()



func end_spline(id, hide: bool = true):
	if hide:
		show_forks()
		var spline
		if id is int:
			if not id in outputs: return
			spline = outputs[id]
		else:
			spline = id; id = key_by_spline[id]
		glob.deactivate_spline(spline)
		var node = spline.tied_to
		if spline.get_meta("old_tied_to"):
			if reg_actions:
				glob.disconnect_action(spline.origin, spline.get_meta("old_tied_to"))
		if node:
			node.detatch_spline(spline)
		spline.disappear()
		key_by_spline.erase(spline)
		if is_instance_valid(node):
			node.forget_spline(spline, self)
		outputs.erase(id)
	glob.deactivate_spline(active_outputs[id])
	if id in active_outputs:
		active_outputs[id].set_fork_output()
	active_outputs.erase(id)
	graphs.conns_active.erase(self)
	parent_graph.hold_for_frame()

func forget_spline(spline: Spline, from_conn: Connection):
	inputs.erase(spline)
	connected.erase(from_conn)

var last_connected: Spline = null
func attach_spline(id: int, target: Connection):
	var spline = active_outputs[id]
	parent_graph.connecting(self, target)
	spline.tied_to = target
	target.connected[self] = true
	conn_counts.get_or_add(target.conn_count_keyword, [0])[0] += 1
	target.inputs[spline] = id
	target.last_connected = spline
	spline.update_points(spline.origin.get_origin(), target.get_origin(), dir_vector, target.dir_vector)
	glob.hovered_connection = target
	glob.hovered_connection_changed = true
	_stylize_spline(spline, true, true)
	glob.hovered_connection = null
	graphs.attach_edge(self, target)
	parent_graph.just_connected(self, target)
	target.get_node("plot3").color = Color.WHITE
	target.parent_graph.just_attached(self, target)
	end_spline(id, false)
	spline._last_origin_pos = spline.origin.get_origin()
	spline._last_target_pos = target.get_origin()
	spline._cached_points = spline.baked.duplicate()


func update_conn_id(new: int):
	graphs.del_conn(self)
	conn_id = new
	graphs.reg_conn(self)

var conn_id: int = 0
func _init() -> void:
	conn_id = randi_range(0,9999999)
	if custom_expression:
		custom_expression.parse(suitable_custom_check, ["target"])

func detatch_spline(spline: Spline, manual: bool = false):
	var other = spline.origin
	other.parent_graph.disconnecting(other, self)
	spline.set_fork_uncon()
	var idx = inputs[spline]
	$plot3.color = gradient_color
	if not other.outputs.has(idx):
		return
	other.conn_counts.get_or_add(conn_count_keyword, [1])[0] -= 1
	other.start_spline(idx)
	if manual:
		spline.hide()
		other.end_spline(idx, true)
		#glob.activate_spline(spline, false)
	graphs.remove_edge(spline.origin, spline.tied_to)
	forget_spline(spline, other)
	other.parent_graph.just_disconnected(other, self)
	#if parent_graph.server_typename == "InputNode":
	#	print("AAA")

@export var auto_rename: bool = false

func hide_forks():
	$plot.hide()
	$plot3.hide()
func show_forks():
	if !is_fork:
		return
	if outputs.size() == 1:
		$plot.show()
		if connection_type == INPUT:
			$plot3.show()

func align_plots():
	if connection_type == OUTPUT:
		$plot3.hide()
		$plot.color = gradient_color.lerp(Color.WHITE, 0.5)
		match dir_vector.normalized():
			Vector2.RIGHT:
				$plot.position.y = size.y/2-4
				$plot.position.x = size.x-4
			Vector2.DOWN:
				$plot.position.y = size.y-3
				$plot.position.x = size.x/2-4
	else:
		hide_forks()
		$plot3.show()
		match dir_vector.normalized():
			Vector2.LEFT:
				$plot3.position.y = size.y/2-6 + off
				$plot3.color = gradient_color
				$plot3.position.x = -1.5
				$plot3.size.x = 18
				$plot3.size.y = 35 - off
			Vector2.UP:
				$plot3.position.y = -1.5
				$plot3.color = gradient_color
				$plot3.position.x = size.x/2 - 6 + off
				$plot3.size.x = 35 - off*3
				$plot3.size.y = 18

@export var off: float = 0

var conn_counts: Dictionary = {&"": [0]}
func _ready() -> void:
	if auto_rename:
		server_name += str(hint)
	align_plots()
	set_fork_allowed(graphs.fork_allowed)
		
	if !Engine.is_editor_hint() and !is_instance_valid(parent_graph):
		parent_graph = get_parent()
	if !Engine.is_editor_hint() and parent_graph:
		parent_graph.add_connection(self)
		await get_tree().process_frame
		graphs.reg_conn(self)

func _exit_tree() -> void:
	delete()
	if !Engine.is_editor_hint() and parent_graph:
		parent_graph.conn_exit(self)
	if glob.hovered_connection == self:
		glob.hovered_connection = null
	graphs.del_conn(self)
	_rev_end() # ensure cleanup if the node disappears mid-drag

func get_origin() -> Vector2:
	var global_rect = get_global_rect().size
	var dir: Vector2 = Vector2()
	if is_zero_approx(dir_vector.x):
		dir.x = global_rect.x / 2.0
	elif dir_vector.x > 0.0:
		dir.x = floor(global_rect.x - 0.02)
	else:
		dir.x = 0.0
	
	if is_zero_approx(dir_vector.y):
		dir.y = global_rect.y / 2.0
	elif dir_vector.y > 0.0:
		dir.y = floor(global_rect.y - 0.02)
	else:
		dir.y = 0.0
	return global_position + dir

func _is_suitable(conn: Connection) -> bool: return true # virtual

@export var conn_count_keyword: String = ""

func _accepts(conn: Connection) -> bool:
	if conn.keyword == "activ" and keyword == "activ": return false
	return true

const default_max_splines: int = 1
func multiple(conn: Connection, is_rev: bool = false) -> bool:
	if not multiple_splines:
		return outputs.size() == 0 or (is_rev or (active_outputs and active_outputs.keys()[0] == outputs.keys()[0]))

	var kw: StringName = conn.conn_count_keyword
	var allowed: int = default_max_splines
	if max_splines_by_keyword.has(kw):
		allowed = int(max(1, max_splines_by_keyword[kw]))
	var cur_arr = conn_counts.get_or_add(kw, [0])
	var cur: int = int(cur_arr[0])
	return cur < allowed

@export_custom(PROPERTY_HINT_EXPRESSION, "") var suitable_custom_check: String = ""

var custom_expression: Expression = null if \
!suitable_custom_check else Expression.new()

func get_target() -> Connection:
	if connection_type == Connection.OUTPUT:
		if outputs:
			return outputs.values()[0].tied_to
	return null

func disconnect_from(target: Connection, force: bool = false, manual: bool = false):
	for i in outputs.duplicate():
		if outputs[i].tied_to == target:
			outputs[i].tied_to.detatch_spline(outputs[i], manual)

func connect_to(target: Connection, force: bool = false) -> bool:
	#if parent_graph.server_typename == "TrainBegin":
	#	print(target.parent_graph)
	if not is_instance_valid(target) or target == self:
		return false
	if connection_type != OUTPUT:
		return false

	if not force:
		if not is_suitable(target):
			return false
		if not graphs.validate_acyclic_edge(self, target):
			return false
		if not multiple(target):
			return false
		if target.connected.has(self) or not (target.multiple_splines or len(target.inputs) == 0 or target.conn_count_keyword == &"router"):
			return false

	var slot = add_spline()
	hide_forks()
	start_spline(slot)
	attach_spline(slot, target)
	#if parent_graph.server_typename == "TrainBegin":
		
	#	print("fjfj")
	return true

func dtype(conn: Connection):
	if len(accepted_datatypes) == 1: return conn.accepted_datatypes.has(datatype)
	for i in accepted_datatypes:
		if i in conn.accepted_datatypes:
			return true
	return false

func is_suitable(conn: Connection, is_rev: bool = false) -> bool:
	var cond_1: bool = (conn and conn != self and conn.connection_type == INPUT
		and dtype(conn)
		and not conn.connected.has(self) and (conn.multiple_splines or len(conn.inputs) == 0 or conn.conn_count_keyword == &"router")
		and multiple(conn, is_rev)
		and graphs.validate_acyclic_edge(self, conn)
		and conn._accepts(self)
		and _is_suitable(conn)
		and parent_graph._is_suitable_conn(self, conn)
		and conn.parent_graph._is_suitable_other_conn(self, conn)
		and (custom_expression == null or custom_expression.execute([conn], self)))
	
	if cond_1:
		var my_input = graphs._reach_input(self.parent_graph)
		var other_input = graphs._reach_input(conn.parent_graph)
		cond_1 = cond_1 and (not is_instance_valid(my_input) or not is_instance_valid(other_input) or my_input == other_input)
	
	#(cond_1)
	return cond_1

@export var gradient_color: Color = Color.WHITE

func _stylize_spline(spline: Spline, hovered_suitable: bool, finalize: bool = false):
	hovered_suitable = hovered_suitable and is_instance_valid(glob.hovered_connection)
	if hovered_suitable:
		spline.modulate = Color(1.1, 1.1, 1.1)
		spline.turn_into(keyword, glob.hovered_connection.keyword)
		spline.color_a = spline.origin.gradient_color
	else:
		spline.modulate = Color(0.7,0.7,0.7)
		spline.turn_into(keyword)
		spline.color_a = gradient_color
	if hovered_suitable:
		spline.set_fork_color(glob.hovered_connection.gradient_color)
		spline.color_b = glob.hovered_connection.gradient_color
	else:
		spline.set_fork_color(gradient_color)
		spline.color_b = gradient_color
	if finalize: spline.modulate.a = 1.0
	else: spline.modulate.a = 1.0

var hovered: bool = false
var prog: float = 0.0
func hover():
	hovered = true
@onready var base_modulate = modulate

var low = {"detatch": true, "edit_graph": true}
var cached_other_rev = null

func _process(delta: float) -> void:
	if not visible or not parent_graph.visible:
		return

	if glob.f2_pressed:
		return
	var inside = is_mouse_inside()

	var active_out: Connection = null
	for k in graphs.conns_active:
		active_out = k
		break

	var rev_input: Connection = graphs.rev_input

	if inside:
		graphs.register_conn_candidate(self, "activate")

		if connection_type == INPUT and active_out != null:
			if active_out.is_suitable(self):
				graphs.register_conn_candidate(self, "hover")

		if connection_type == OUTPUT and is_instance_valid(rev_input) and rev_input != self:
			if is_suitable_callable_for_output_to_input(self, rev_input):
				graphs.register_conn_candidate(self, "hover")
	if active_outputs or _rev_active():
		parent_graph.hold_for_frame()

	mouse_pressed = glob.mouse_pressed
	var not_occ = not glob.is_occupied(self, &"menu") and not glob.is_occupied(self, &"graph")
	mouse_just_pressed = glob.mouse_just_pressed and not_occ
	var unpadded = is_mouse_inside(Vector4())


	var occ = glob.is_occupied(self, "conn_active")
	var chosen_activate = graphs.chosen_conn("activate") == self
	if graphs.selected_nodes.size() <= 1:
		if unpadded and chosen_activate:
			glob.set_menu_type(self, "detatch", low)
			#("AA")
		#	print(glob.menu_type)
		else:
			glob.reset_menu_type(self, "detatch")
	else:
		glob.reset_menu_type(self, "detatch")
	var hover_target: Connection = graphs.chosen_conn("hover")

	if chosen_activate and not parent_graph.is_blocked and not ui.topr_inside:
		var base_cond = connection_type == INPUT and inside and not occ and !graphs.conning()
		var aux_cond = (not glob.is_occupied(self, "menu_inside") or glob.get_occupied(&"menu_inside").hint == "detatch")
		
		if connection_type == OUTPUT and inside and not occ and not glob.is_consumed(self, "mouse_press"):
			if mouse_just_pressed:
				if not glob.is_occupied(self, &"menu_inside") and !graphs.conning():
					if (multiple_splines or outputs.size() == 0):
						if !graphs.conning():
							var nspline = add_spline()
							hide_forks()
							start_spline(nspline)
							glob.activate_spline(outputs[nspline])
					elif is_instance_valid(cached_other_rev) and (!multiple_splines and outputs.size() == 1) and allow_reverse:
						pass
						disconnect_from(cached_other_rev, false, false)
						await get_tree().process_frame
						cached_other_rev._rev_start()
						for spline in active_outputs.keys():
							end_spline(spline)
			elif glob.mouse_alt_just_pressed and unpadded:
				glob.menus["detatch"].show_up(outputs, self)

		elif base_cond:
			if allow_reverse and aux_cond and mouse_just_pressed and inputs.size() == 0 and not _rev_active():
				_rev_start()
			elif glob.mouse_alt_just_pressed and unpadded:
				#("AA")
				glob.menus["detatch"].show_up(inputs, self)
			elif aux_cond and mouse_just_pressed and inputs:
				var detatch = inputs.keys()[-1]
				glob.activate_spline(detatch)
				detatch_spline(detatch)

	var to_end: Array = []
	var to_attach: Array = []

	if active_outputs or _rev_active():
		glob.occupy(self, &"conn_active")
	else:
		glob.un_occupy(self, &"conn_active")

	var chosen_hover = (hover_target == self)
	if chosen_hover or hovered:
		prog = 0
		modulate = modulate.lerp(Color(1.5, 1.5, 1.5), delta * 23.0)
		parent_graph.hold_for_frame()
	elif prog < 0.95:
		parent_graph.hold_for_frame()
		prog = lerpf(prog, 1, delta * 23.0)
		if prog < 0.95:
			modulate = modulate.lerp(base_modulate, delta * 23.0)
		else:
			modulate = base_modulate

	var suit = false
	if active_outputs:
		if hover_target != _last_hovered_conn:
			_last_hovered_conn = hover_target
			_last_suit = is_instance_valid(hover_target) and is_suitable(hover_target)
		suit = _last_suit
		parent_graph.active_output_connections[self] = true
		parent_graph.hold_for_frame()
	else:
		parent_graph.active_output_connections.erase(self)


	for id in active_outputs:
		var spline = active_outputs[id]
		var add = spline.end_dir_vec*5
		if !spline.draw_fork:
			add = Vector2()
		spline.update_points(spline.origin.get_origin(), get_global_mouse_position() + add, dir_vector)

		if not mouse_pressed:
			if suit and is_instance_valid(hover_target):
				glob.occupy(hover_target, &"conn_active")
				to_attach.append(id)
				hover_target.parent_graph.hold_for_frame()
			else:
				if not is_instance_valid(hover_target):
					to_end.append(id)

		_stylize_spline(spline, suit)

	if _rev_active():
		var hovered_ok = is_instance_valid(hover_target) and hover_target.connection_type == OUTPUT \
			and is_suitable_callable_for_output_to_input(hover_target, self)
		_rev_spline.update_points(get_origin() + Vector2.RIGHT * 0.5, get_global_mouse_position(), dir_vector, -dir_vector)

		if not mouse_pressed:
			if hovered_ok:
				hover_target.connect_to(self)
				hover_target.cached_other_rev = self
				_rev_end()
			else:
				_rev_end()
		else:
			_stylize_spline(_rev_spline, hovered_ok)

	if is_instance_valid(hover_target) and (suit or (_rev_active() and hover_target.connection_type == OUTPUT)):
		hover_target.hover()
		hover_target.parent_graph.hold_for_frame()

	for id in to_end:
		end_spline(id)

	if is_instance_valid(hover_target) and suit:
		for id in to_attach:
			attach_spline(id, hover_target)

	hovered = false

var _last_hovered_conn: Connection = null
var _last_suit: bool = false

static func is_suitable_callable_for_output_to_input(out_conn: Connection, in_conn: Connection) -> bool:
	if not is_instance_valid(out_conn) or not is_instance_valid(in_conn): return false
	if out_conn == in_conn: return false
	if out_conn.connection_type != OUTPUT or in_conn.connection_type != INPUT: return false
#	print("asa")
	#(out_conn.is_suitable(in_conn, true))
	return out_conn.is_suitable(in_conn, true)
