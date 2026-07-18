
class_name LessonCode
extends Node

signal step_started(step_index: int, step: Dictionary)
signal step_completed(step_index: int, step: Dictionary)
signal invariant_broken(step_index: int, step: Dictionary, reason: String)

# NEW: explanations as first-class runtime interaction
signal explain_requested(text: String, wait_mode: String)
signal explain_next_ack()

func ack_explain_next() -> void:
	explain_next_ack.emit()

func _ready() -> void:
	_runtime_req_map = dsl_reg.build_runtime_map_by_type()

var _runtime_req_map: Dictionary = {}
var steps: Array = []
var current_step_index: int = -1

var node_bindings: Dictionary = {}
var pending_node_binds: Array = []
var active_invariants: Array[Callable] = []

# NEW: re-entrancy guard
var _evaluating: bool = false
var _queued_eval: bool = false

func stop() -> void:
	current_step_index = -1
	node_bindings.clear()
	pending_node_binds.clear()
	active_invariants.clear()
	bind_specs.clear()
	bind_to_id.clear()
	id_claims.clear()
	bind_flags.clear()
	_node_seq = 0


	for step in steps:
		step["_completed"] = false
		step.erase("_action_i")

		# legacy requires
		for req in step.get("requires", []):
			req.erase("_resolved")

		# actions requires
		for act in step.get("actions", []):
			if typeof(act) == TYPE_DICTIONARY and str(act.get("type", "")) == "require":
				for req2 in act.get("requires", []):
					req2.erase("_resolved")

func load_code(code: Dictionary) -> void:
	# ------------------------------------------------
	# Validate
	# ------------------------------------------------
	if typeof(code) != TYPE_DICTIONARY:
		push_error("load_code: code must be a Dictionary")
		return

	var entry = str(code.get("entry", "")).strip_edges()
	var src_flows = code.get("flows", null)

	if entry == "" or typeof(src_flows) != TYPE_DICTIONARY:
		push_error("load_code: invalid code structure")
		return

	if not src_flows.has(entry):
		push_error("load_code: entry flow '%s' not found" % entry)
		return

	# ------------------------------------------------
	# Reset ALL runtime state
	# ------------------------------------------------
	flows.clear()
	flow_stack.clear()
	node_bindings.clear()
	pending_node_binds.clear()
	active_invariants.clear()
	bind_specs.clear()
	bind_to_id.clear()
	id_claims.clear()
	bind_flags.clear()
	_node_seq = 0
	
	_evaluating = false
	_queued_eval = false

	# ------------------------------------------------
	# Deep-copy and normalize all flows
	# ------------------------------------------------
	for fname in src_flows.keys():
		var src_steps = src_flows[fname]
		if typeof(src_steps) != TYPE_ARRAY:
			push_error("load_code: flow '%s' must be an Array" % fname)
			return

		var out_steps: Array = []

		for s in src_steps:
			var step = s.duplicate(true)

			# per-step runtime flags
			step["_completed"] = false
			step.erase("_action_i")

			# legacy requires
			for req in step.get("requires", []):
				req.erase("_resolved")

			# action.require requires
			for act in step.get("actions", []):
				if typeof(act) == TYPE_DICTIONARY and str(act.get("type", "")) == "require":
					for req2 in act.get("requires", []):
						req2.erase("_resolved")

			# ask action internal flags
			for act2 in step.get("actions", []):
				if typeof(act2) == TYPE_DICTIONARY and str(act2.get("type", "")) == "ask":
					act2.erase("_asked")

			out_steps.append(step)

		flows[fname] = out_steps

	# ------------------------------------------------
	# Activate entry flow
	# ------------------------------------------------
	active_flow = entry
	main_flow_name = entry
	steps = flows[entry]
	main_flow_steps_count = steps.size()
	current_step_index = -1

func get_main_total_steps() -> int:
	return main_flow_steps_count

func get_main_step_index() -> int:
	if active_flow != main_flow_name:
		return flow_stack[0].step_index if flow_stack.size() > 0 else current_step_index
	return current_step_index




var main_flow_name: String = "flow"
var main_flow_steps_count: int = 0

func start() -> void:
	node_bindings["lesson"] = self
	await _advance_to_next_step()

func on_graph_changed() -> void:
	_refresh_binds()
	_check_invariants()
	_request_evaluate()


func _request_evaluate() -> void:
	# prevents multiple concurrent evals
	if _evaluating:
		_queued_eval = true
		return
	await _evaluate_current_step()

func on_node_created(node: Graph) -> void:
	if node != null and not node.has_meta("_lesson_seq"):
		node.set_meta("_lesson_seq", _node_seq)
		_node_seq += 1

	on_graph_changed()



func _dbg(msg: String) -> void:
	print("[LESSON][%s] %s" % [active_flow, msg])

func _advance_to_next_step() -> void:
	_dbg("ADVANCE from index=%d steps=%d" %
		[current_step_index, steps.size()])

	if current_step_index + 1 >= steps.size():
		_dbg(" FLOW END detected")

		if _return_from_flow_if_needed():
			_dbg(" RESUMED after return")
			call_deferred("_advance_to_next_step")
			return

		_dbg(" NO FLOW TO RETURN TO — STOP")
		return

	current_step_index += 1
	var step = steps[current_step_index]

	_dbg(" ENTER STEP %d title='%s'" %
		[current_step_index, step.get("title", step.get("id", "?"))])

	if step.has("bind_on_create"):
		var bocs = step["bind_on_create"]
		if typeof(bocs) == TYPE_ARRAY:
			for boc in bocs:
				register_bind_spec(boc)


	step_started.emit(current_step_index, step)
	call_deferred("_request_evaluate")


func register_bind_spec(spec_in: Dictionary) -> void:
	if typeof(spec_in) != TYPE_DICTIONARY:
		return

	var bind_name = str(spec_in.get("bind", "")).strip_edges()
	var want_type = str(spec_in.get("type", "")).strip_edges()
	if bind_name == "" or want_type == "":
		return

	# Persist spec forever (role definition), do NOT delete it after first bind.
	if not bind_specs.has(bind_name):
		bind_specs[bind_name] = {
			"type": want_type,
			"introduced_step": get_main_step_index(),
		}
	else:
		# Keep the original type to avoid chaos if YAML was inconsistent.
		var cur_type = str(bind_specs[bind_name].get("type", ""))
		if cur_type != want_type:
			push_warning("Bind '%s' type mismatch: '%s' vs '%s' (keeping '%s')" % [
				bind_name, cur_type, want_type, cur_type
			])

	_refresh_binds()


func set_bind_prohibit(binds_in, on: bool) -> void:
	var arr: Array = []
	if binds_in is Array:
		arr = binds_in
	else:
		arr = [binds_in]

	for b in arr:
		var bind_name = str(b).strip_edges()
		if bind_name == "":
			continue
		var flags = bind_flags.get(bind_name, {})
		flags["prohibit_deletion"] = on
		bind_flags[bind_name] = flags
		_apply_bind_flags(bind_name)


func _refresh_binds() -> void:
	_ensure_node_seq_meta()

	# 1) Drop dead / invalid bindings
	var to_unbind: Array = []
	for bind_name in bind_to_id.keys():
		var id = int(bind_to_id[bind_name])
		if not graphs._graphs.has(id):
			to_unbind.append(bind_name)
			continue

		# If we have a spec, enforce it
		var spec = bind_specs.get(bind_name, {})
		if not spec.is_empty():
			var g = graphs._graphs.get(id)
			if g == null or not _node_matches_spec(g, spec):
				to_unbind.append(bind_name)

	for b in to_unbind:
		_unbind(b)

	# 2) Ensure every known bind is satisfied if possible
	for bind_name in bind_specs.keys():
		_ensure_bind(bind_name)


func _ensure_bind(bind_name: String) -> void:
	# sticky: if already bound and node exists + matches spec, keep it
	if bind_to_id.has(bind_name):
		var id = int(bind_to_id[bind_name])
		var g = graphs._graphs.get(id)
		var spec = bind_specs.get(bind_name, {})
		if g != null and (spec.is_empty() or _node_matches_spec(g, spec)):
			return
		_unbind(bind_name)

	var spec2 = bind_specs.get(bind_name, {})
	if spec2.is_empty():
		return

	var cand_id = _pick_candidate_for_bind(bind_name, spec2)
	if cand_id != -1:
		_claim(bind_name, cand_id)


func _pick_candidate_for_bind(bind_name: String, spec: Dictionary) -> int:
	var want_type = str(spec.get("type", "")).strip_edges()
	if want_type == "":
		return -1

	var best_id = -1
	var best_seq = -1

	for g in graphs._graphs.values():
		if g == null:
			continue
		if str(g.get_meta("created_with", "")) != want_type:
			continue

		var id = int(g.graph_id)

		# avoid assigning same node to multiple binds
		if id_claims.has(id) and str(id_claims[id]) != bind_name:
			continue

		var seq = int(g.get_meta("_lesson_seq", 0))
		if seq > best_seq:
			best_seq = seq
			best_id = id

	return best_id


func _node_matches_spec(g, spec: Dictionary) -> bool:
	var want_type = str(spec.get("type", "")).strip_edges()
	if want_type == "":
		return true
	return str(g.get_meta("created_with", "")) == want_type


func _claim(bind_name: String, id: int) -> void:
	# release previous claim for this bind (if any)
	if bind_to_id.has(bind_name):
		var old_id = int(bind_to_id[bind_name])
		id_claims.erase(old_id)

	bind_to_id[bind_name] = id
	id_claims[id] = bind_name
	node_bindings[bind_name] = id

	_apply_bind_flags(bind_name)


func _unbind(bind_name: String) -> void:
	if bind_to_id.has(bind_name):
		var id = int(bind_to_id[bind_name])
		id_claims.erase(id)
		bind_to_id.erase(bind_name)

	node_bindings.erase(bind_name)


func _apply_bind_flags(bind_name: String) -> void:
	if not bind_to_id.has(bind_name):
		return

	var id = int(bind_to_id[bind_name])
	var g = graphs._graphs.get(id)
	if g == null:
		return

	var flags = bind_flags.get(bind_name, {})
	if bool(flags.get("prohibit_deletion", false)):
		g.prohibit_deletion()
	else:
		# keep permissive unless explicitly prohibited
		# (safe to call if your Graph implements it)
		g.allow_deletion()


func _ensure_node_seq_meta() -> void:
	# If some nodes exist without our meta (loaded before lesson), tag them.
	for g in graphs._graphs.values():
		if g == null:
			continue
		if not g.has_meta("_lesson_seq"):
			g.set_meta("_lesson_seq", _node_seq)
			_node_seq += 1

var bind_specs: Dictionary = {}		# bind -> { type: String, introduced_step: int }
var bind_to_id: Dictionary = {}		# bind -> graph_id
var id_claims: Dictionary = {}		# graph_id -> bind (avoid double-assign)
var bind_flags: Dictionary = {}		# bind -> { prohibit_deletion: bool }

var _node_seq: int = 0		


func call_branch(flow_name: String) -> void:
	_dbg("CALL_BRANCH -> %s" % flow_name)

	if not flows.has(flow_name):
		push_error("Unknown branch: %s" % flow_name)
		return

	var step = steps[current_step_index]
	var next_i = int(step.get("_action_i", 0)) + 1

	_dbg(" PUSH FRAME {flow=%s step=%d action_i=%d}" %
		[active_flow, current_step_index, next_i])

	flow_stack.append({
		"flow": active_flow,
		"step_index": current_step_index,
		"action_i": next_i,
	})

	step["_action_i"] = step.get("actions", []).size()

	_switch_flow(flow_name, true)




func _switch_flow(flow_name: String, restart: bool) -> void:
	_dbg("SWITCH_FLOW -> %s restart=%s" % [flow_name, restart])

	active_flow = flow_name
	steps = flows[flow_name]

	if restart:
		current_step_index = -1
	else:
		current_step_index = max(current_step_index, -1)

	_dbg(" current_step_index=%d steps=%d" %
		[current_step_index, steps.size()])

	call_deferred("_advance_to_next_step")



func _return_from_flow_if_needed() -> bool:
	if flow_stack.is_empty():
		_dbg("RETURN_FLOW: stack empty")
		return false

	var fr = flow_stack.pop_back()

	_dbg("RETURN_FLOW -> flow=%s step=%d action_i=%d" %
		[fr["flow"], fr["step_index"], fr["action_i"]])

	active_flow = fr["flow"]
	steps = flows[active_flow]
	current_step_index = int(fr["step_index"])

	var step = steps[current_step_index]
	step["_action_i"] = int(fr["action_i"])

	_dbg(" RESTORED step_index=%d action_i=%d" %
		[current_step_index, step["_action_i"]])

	return true



var flows: Dictionary = {}     # name -> steps Array
var flow_stack: Array = []     # stack of frames
var active_flow: String = "flow"

func _evaluate_current_step() -> void:
	if current_step_index < 0 or current_step_index >= steps.size():
		return

	_evaluating = true
	while true:
		_queued_eval = false

		var step = steps[current_step_index]
		var ok = await _run_actions(step)
		if ok:
			_complete_step(step)

		if not _queued_eval:
			break

	_evaluating = false


# ============================================================
# NEW: action execution
# ============================================================

func _run_actions(step: Dictionary) -> bool:
	# returns true when all actions completed for this step
	if not step.has("_action_i"):
		step["_action_i"] = 0

	var actions: Array = step.get("actions", [])
	while int(step["_action_i"]) < actions.size():
		var i: int = int(step["_action_i"])
		var act = actions[i]
		var done = await _run_action(step, act)
		if not done:
			return false # blocked
		step["_action_i"] = i + 1

	return true


func _run_action(step: Dictionary, act: Dictionary) -> bool:
	var t = str(act.get("type", ""))
	var fn = dsl_reg.action.get(t, {}).get("runtime", null)
	print(act)
	if fn == null:
		push_error("Unknown action type: %s" % t)
		return false

	return await fn.call(act, self)




func _requirements_satisfied(reqs: Array) -> bool:
	for req in reqs:
		if not req.has("_resolved"):
			var ok = await _compile_requirement(req).call()
			if not ok:
				return false
			req["_resolved"] = true
	return true

# ============================================================
# Existing completion + requirement runtime (unchanged)
# ============================================================

func _complete_step(step: Dictionary) -> void:
	if step["_completed"]:
		return

	step["_completed"] = true
	step_completed.emit(current_step_index, step)

	if step.get("persistent", false):
		for req in step.get("requires", []):
			active_invariants.append(_compile_requirement(req))

	_advance_to_next_step()

func _step_satisfied(step: Dictionary) -> bool:
	for req in step.get("requires", []):
		if not req.has("_resolved"):
			var ok = await _compile_requirement(req).call()
			if not ok:
				return false
			req["_resolved"] = true
	return true

func _compile_requirement(req: Dictionary) -> Callable:
	var t = str(req.get("type", ""))
	var fn_name = _runtime_req_map.get(t, null)

	if fn_name == null:
		push_error("Unknown requirement type: %s" % t)
		return func() -> bool:
			return false

	return func() -> bool:
		return await fn_name.call(req, node_bindings)

func _check_invariants() -> void:
	for inv in active_invariants:
		if not inv.call():
			invariant_broken.emit(current_step_index, steps[current_step_index], "Invariant broken")
			return
