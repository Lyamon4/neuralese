class_name DSLRuntime 
extends RefCounted

var reg: DSLRegistry
var graph: DSLGraphUtils
signal _event_requirement_met(token: int)

var _event_wait_token: int = 0

func run_action_explain_button(act: Dictionary, lesson) -> bool:
	await ui.quest.finish_exp()
	return true

func run_action_prohibit_deletion(act: Dictionary, lesson) -> bool:
	await glob.tree.process_frame

	lesson.set_bind_prohibit(act.get("nodes", []), true)

	var ids = resolve_node_ids({ "bind": act["nodes"] }, lesson.node_bindings)
	for i in ids:
		graphs._graphs[i].prohibit_deletion()
	return true


func run_action_allow_deletion(act: Dictionary, lesson) -> bool:
	lesson.set_bind_prohibit(act.get("nodes", []), false)

	var ids = resolve_node_ids({ "bind": act["nodes"] }, lesson.node_bindings)
	for i in ids:
		graphs._graphs[i].allow_deletion()
	return true

	
func run_action_explain_next(act: Dictionary, lesson) -> bool:
	await ui.quest.finish_and_hide()
	return true

func run_action_set_dense_units(act: Dictionary, lesson) -> bool:
	ui.set_dense_units(act["per_unit"], act["max_units"])
	return true

func run_action_multi_input(act: Dictionary, lesson) -> bool:
	glob.set_multi_input(bool(act.get("enabled", false)))
	return true

func run_action_ask(act: Dictionary, lesson) -> bool:
	if act.get("_asked", false):
		return true

	act["_asked"] = true

	var head = act["head"]
	var options = act["options"]
	var correct = act.get("correct", [])
	var show = act.get("show", false)
	for i in len(correct):
		correct[i] -= 1

	var ans = int((await ui.quest.ask(head, options, correct, show))[0][0]+1)
	
	var on_answer: Dictionary = act.get("on_answer", {})
	var target: Dictionary = on_answer.get(ans, {})

	if target.is_empty() and act.has("default"):
		target = act.get("default", {})
	
	print(on_answer)
	print(target)
	
	if not target.is_empty():
		var op = str(target.get("op", ""))
		if op == "goto":
			var br = str(target.get("target", "")).strip_edges()
			if br != "":
				lesson.call_branch(br)
				return false

	return true



func run_action_select(act: Dictionary, lesson) -> bool:
	var exprs: Dictionary = act.get("exprs", {})

	var eligible: Dictionary = {}

	for node in graphs._graphs.values():
		if exprs.is_empty():
			eligible[node.graph_id] = true
			continue
		
		if graph.eval_cfg_expressions(node.cfg, exprs):
			eligible[node.graph_id] = true

	var chosen: Dictionary = await ui.choose()
	var filtered: Array = []
	for g in chosen.keys():
		var id = g.graph_id
		if eligible.has(id):
			filtered.append(id)
	#lesson.last_highlighted_nodes = filtered
	return true



func run_action_explain(act: Dictionary, lesson) -> bool:
	var text_val = act.get("text", "")
	var wait_mode = str(act.get("wait", "next")).strip_edges()
	var t = float(act.get("time", 1.0))

	# normalize text -> Array[String]
	var segs: Array = []
	if typeof(text_val) == TYPE_ARRAY:
		for s in text_val:
			segs.append(str(s))
	else:
		segs.append(str(text_val))

	# optional signal for other listeners
	lesson.explain_requested.emit(segs, wait_mode)

	# fire-and-forget
	if wait_mode == "none":
		ui.quest.say(segs, false) # no await by design
		return true

	if wait_mode == "time":
		await ui.quest.say(segs, false)
		await glob.wait(t)
		return true

	# press-based
	if wait_mode == "next":
		await ui.quest.say(segs, true)
		return true

	push_error("Unknown explain.wait: %s" % wait_mode)
	return false

func run_action_create(act: Dictionary, lesson) -> bool:
	var bocs: Array = act.get("bind_on_create", [])
	if bocs.is_empty():
		return false

	var all_resolved = true

	for boc in bocs:
		if not boc.has("_registered"):
			boc["_registered"] = true
			lesson.register_bind_spec(boc)

		if not lesson.node_bindings.has(str(boc["bind"])):
			all_resolved = false

	return all_resolved



func run_action_require(act: Dictionary, lesson) -> bool:
	var reqs: Array = act.get("requires", [])

	for req in reqs:
		if not req.has("_resolved"):
			var ok = await lesson._compile_requirement(req).call()
			if not ok:
				return false
			req["_resolved"] = true
	
	return true





# ============================================================
# Runtime requirement checks (canonical req dict -> bool)
# ============================================================

func check_node(req: Dictionary, node_bindings: Dictionary) -> bool:
	var ids = resolve_node_ids(req["node"], node_bindings)
	return ids.size() > 0

func check_connection(req: Dictionary, node_bindings: Dictionary) -> bool:
	var from_ids = resolve_node_ids(req["from"], node_bindings)
	var to_ids = resolve_node_ids(req["to"], node_bindings)

	var out_port: int = int(req.get("out_port", -1))
	var in_port: int = int(req.get("in_port", -1))
	#(req)
	for a in from_ids:
		for b in to_ids:
			if graph.graph_has_connection(a, b, out_port, in_port):
				return true

	return false

func check_config(req: Dictionary, node_bindings: Dictionary) -> bool:
	var ids = resolve_node_ids(req["node"], node_bindings)
	var exprs: Dictionary = req["exprs"]

	for id in ids:
		var node = graphs._graphs.get(id)
		if node == null:
			continue
		if graph.eval_cfg_expressions(node.cfg, exprs, str(node.get_meta("created_with", ""))):
			return true

	return false

func check_topology_graph(req: Dictionary, node_bindings: Dictionary) -> bool:
	# -----------------------------
	# 0) STRICT: текущая логика
	# -----------------------------
	var roots = resolve_node_ids(req["root"], node_bindings)
	if not roots.is_empty():
		for root_id in roots:
			var root = graphs._graphs.get(root_id)
			if root == null:
				continue

			var scene = graph.collect_reachable(root)
			if graph.match_graph(scene, req):
				return true

	# -----------------------------
	# 1) INTENT MODE: авто-ребинд root.bind
	# -----------------------------
	var root_bind := str(req.get("root", {}).get("bind", "")).strip_edges()
	if root_bind == "":
		return false

	var root_alias := _infer_topology_root_alias(req)
	if root_alias == "":
		return false

	var tpl_nodes: Dictionary = req.get("nodes", {})
	if not tpl_nodes.has(root_alias):
		return false

	var root_spec: Dictionary = tpl_nodes[root_alias]
	if typeof(root_spec) != TYPE_DICTIONARY or root_spec.is_empty():
		return false

	# кандидаты на "правильный" root: все ноды нужного типа
	var cand_roots: Array = _find_nodes_matching_topo_spec_global(root_spec)
	if cand_roots.is_empty():
		return false

	# пробуем каждый кандидат как root, но требуем, чтобы он был именно root_alias
	for cand_id in cand_roots:
		var cand = graphs._graphs.get(cand_id)
		if cand == null:
			continue

		var scene2 = graph.collect_reachable(cand)

		# быстрый фильтр: если даже match_graph не проходит, нет смысла копать дальше
		# (обычно match_graph не зависит от req.root, root уже учтён в collect_reachable)
		if not graph.match_graph(scene2, req):
			continue

		# строгая гарантия: кандидат должен быть использован как root_alias (источник шаблона)
		var forced := { root_alias: cand_id }
		var assign := _find_topology_assignment(scene2, req, forced)
		if assign.is_empty():
			continue

		# SUCCESS -> перебиндим root.bind на реально использованный учеником root
		_rebind_bind(node_bindings, root_bind, cand_id)
		return true

	return false

func _rebind_bind(node_bindings: Dictionary, bind_name: String, graph_id: int) -> void:
	# Если у тебя позже появится "умный биндинг" с claim-структурами,
	# можно сюда подцепить lesson-метод и поддерживать их в консистентности.
	var lesson = node_bindings.get("lesson", null)

	# Опционально: если ты добавишь в LessonCode метод force_bind(bind, id)
	if lesson != null and lesson.has_method("force_bind"):
		lesson.force_bind(bind_name, graph_id)
		return

	# fallback (работает уже сейчас)
	node_bindings[bind_name] = graph_id


func _infer_topology_root_alias(req: Dictionary) -> String:
	var tpl_nodes: Dictionary = req.get("nodes", {})
	var edges: Array = req.get("edges", [])

	if tpl_nodes.is_empty():
		return ""

	# indegree по алиасам
	var indeg: Dictionary = {}
	for a in tpl_nodes.keys():
		indeg[str(a)] = 0

	for e in edges:
		if typeof(e) != TYPE_ARRAY or e.size() != 2:
			continue
		var to_alias = str(e[1]).strip_edges()
		if indeg.has(to_alias):
			indeg[to_alias] = int(indeg[to_alias]) + 1

	# источники = indegree == 0
	var sources: Array = []
	for a in indeg.keys():
		if int(indeg[a]) == 0:
			sources.append(a)

	if sources.is_empty():
		return ""

	# эвристика именования (твои кейсы: inp)
	if "inp" in sources:
		return "inp"
	if "input" in sources:
		return "input"
	if "root" in sources:
		return "root"

	# иначе первый
	return str(sources[0])


func _find_nodes_matching_topo_spec_global(spec: Dictionary) -> Array:
	var want_type := str(spec.get("type", "")).strip_edges()
	if want_type == "":
		return []

	var want_cfg: Dictionary = spec.get("config", {})
	var out: Array = []

	for g in graphs._graphs.values():
		if g == null:
			continue
		if str(g.get_meta("created_with", "")) != want_type:
			continue
		if not want_cfg.is_empty():
			if not graph.eval_cfg_expressions(g.cfg, want_cfg, want_type):
				continue
		out.append(int(g.graph_id))

	# небольшой приоритет: новые выше (если есть мета), иначе по id
	out.sort_custom(func(a, b):
		var ga = graphs._graphs.get(a)
		var gb = graphs._graphs.get(b)
		var sa = ga.get_meta("_lesson_seq", a) if ga != null else a
		var sb = gb.get_meta("_lesson_seq", b) if gb != null else b
		return int(sa) > int(sb)
	)

	return out


func _find_topology_assignment(scene: Dictionary, topo_req: Dictionary, forced: Dictionary) -> Dictionary:
	# scene ожидается как в collect_reachable: { "nodes": Dictionary, "edges": Array }
	if not scene.has("nodes"):
		return {}

	var tpl_nodes: Dictionary = topo_req.get("nodes", {})
	var edges: Array = topo_req.get("edges", [])

	if tpl_nodes.is_empty():
		return {}

	# 1) кандидаты по каждому алиасу
	var cand: Dictionary = {} # alias -> Array[graph_id]
	for alias in tpl_nodes.keys():
		var a := str(alias).strip_edges()
		var spec: Dictionary = tpl_nodes[alias]

		var want_type := str(spec.get("type", "")).strip_edges()
		if want_type == "":
			return {}

		var want_cfg: Dictionary = spec.get("config", {})
		var arr: Array = []

		for node in scene["nodes"].values():
			if node == null:
				continue
			if str(node.get_meta("created_with", "")) != want_type:
				continue
			if not want_cfg.is_empty():
				if not graph.eval_cfg_expressions(node.cfg, want_cfg, want_type):
					continue
			arr.append(int(node.graph_id))

		if arr.is_empty():
			return {}

		cand[a] = arr

	# 2) применяем forced (root_alias обязателен)
	for fa in forced.keys():
		var a2 := str(fa).strip_edges()
		var id2 := int(forced[fa])
		if not cand.has(a2):
			return {}
		if not (id2 in cand[a2]):
			return {}
		cand[a2] = [id2]

	# 3) порядок алиасов: сначала самые узкие кандидаты
	var names: Array = cand.keys()
	names.sort_custom(func(x, y):
		return cand[str(x)].size() < cand[str(y)].size()
	)

	# 4) DFS backtracking
	var assigned: Dictionary = forced.duplicate()
	var used: Dictionary = {}
	for idv in assigned.values():
		used[int(idv)] = true

	var ok := _dfs_assign(names, 0, cand, assigned, used, edges)
	return assigned if ok else {}


func _dfs_assign(
	names: Array,
	idx: int,
	cand: Dictionary,
	assigned: Dictionary,
	used: Dictionary,
	edges: Array
) -> bool:
	if idx >= names.size():
		# финальная проверка edges
		for e in edges:
			if typeof(e) != TYPE_ARRAY or e.size() != 2:
				return false
			var a := str(e[0]).strip_edges()
			var b := str(e[1]).strip_edges()
			if not assigned.has(a) or not assigned.has(b):
				return false
			if not graph.graph_has_any_connection(int(assigned[a]), int(assigned[b])):
				return false
		return true

	var name := str(names[idx]).strip_edges()

	# если уже зафиксирован (forced) — просто идём дальше
	if assigned.has(name):
		return _dfs_assign(names, idx + 1, cand, assigned, used, edges)

	for id in cand[name]:
		var gid := int(id)
		if used.has(gid):
			continue

		assigned[name] = gid
		used[gid] = true

		# ранний prune: если какая-то дуга уже полностью назначена — проверяем сразу
		var bad := false
		for e in edges:
			if typeof(e) != TYPE_ARRAY or e.size() != 2:
				bad = true
				break
			var a := str(e[0]).strip_edges()
			var b := str(e[1]).strip_edges()
			if assigned.has(a) and assigned.has(b):
				if not graph.graph_has_any_connection(int(assigned[a]), int(assigned[b])):
					bad = true
					break

		if not bad:
			if _dfs_assign(names, idx + 1, cand, assigned, used, edges):
				return true

		used.erase(gid)
		assigned.erase(name)

	return false


func check_wait(req: Dictionary, _node_bindings: Dictionary) -> bool:
	var t = float(req.get("time", 0))
	if t <= 0:
		return true
	await glob.wait(t)
	return true


func check_event(req: Dictionary, _node_bindings: Dictionary) -> bool:
	var event_name: StringName = StringName(str(req.get("name", "")).strip_edges())
	if event_name == StringName(""):
		return false

	var required_meta: Dictionary = req.get("meta", {})

	if events.is_event(event_name, required_meta):
		return true

	_event_wait_token += 1
	var token: int = _event_wait_token

	var callback: Callable = func(_event_meta: Dictionary, active: bool) -> void:
		if not active:
			return

		if events.is_event(event_name, required_meta):
			_event_requirement_met.emit(token)

	var err: Error = events.connect_event(event_name, callback)
	if err != OK:
		push_error("DSL: failed to connect to event '%s'" % str(event_name))
		return false

	while true:
		var got_token: int = int(await _event_requirement_met)
		if got_token == token:
			break

	events.disconnect_event(event_name, callback)
	return true


func check_ask(req: Dictionary, _node_bindings: Dictionary) -> bool:
	if req.get("_asked", false):
		return false

	req["_asked"] = true

	await ui.quest.ask(
		req["head"],
		req["options"],
		req["correct"],
		req.get("show", false)
	)
	return true

func check_lock(req: Dictionary, _node_bindings: Dictionary) -> bool:
	if req.get("_locked", false):
		return false

	req["_locked"] = true
	if !cookies.profile("teacher") and glob._logged_in:
		await learner.push_classroom_event({"awaiting": true})
		await glob.wait(1.0)
		ui.show_lock()
		await learner.wait_unblock()
		ui.hide_lock()
	return true


# ============================================================
# Runtime helpers
# ============================================================

func resolve_node_ids(spec: Dictionary, node_bindings: Dictionary) -> Array:
	#(node_bindings)
	#(spec)
	if spec.has("bind"):
		if spec["bind"] is Array:
			var res = []
			for b in spec["bind"]:
				b = str(b)
				if node_bindings.has(b): res.append(node_bindings[b])
			return res
		var b = str(spec["bind"])
		if node_bindings.has(b):
			return [node_bindings[b]]
		return []

	var ids: Array = []
	for node in graphs._graphs.values():
		var ok = true
		for k in spec.keys():
			var kk = str(k)
			match kk:
				"type":
					if node.get_meta("created_with") != spec[kk]:
						ok = false
						break
				_:
					if not node.has_meta(kk) or node.get_meta(kk) != spec[kk]:
						ok = false
						break
		if ok:
			ids.append(node.graph_id)

	return ids

func run_action_highlight(act: Dictionary, lesson) -> bool:
	await glob.tree.process_frame
	await glob.tree.process_frame
	var targets: Array = act.get("targets", [])
	if targets.is_empty():
		return true

	var uniq: Dictionary = {} # id -> true

	for sel in targets:
		var ids: Array = _resolve_highlight_selector(sel, lesson.node_bindings)
		for id in ids:
			uniq[id] = true

	var out: Array = uniq.keys()
	ui.emphasize_nodes(out)
	return true

func run_action_arrow(act: Dictionary, lesson) -> bool:
	await glob.tree.process_frame
	await glob.tree.process_frame

	match act.get("mode", ""):
		"node":
			var ids = resolve_node_ids(act["node"], lesson.node_bindings)
			if ids.is_empty():
				return true

			# single-shot → first match only
			var g = graphs._graphs.get(ids[0])
			if g != null:
				ui.show_arrow_graph(g)
			return true

		"port":
			# FROM (output port)
			if act.has("from"):
				var ids = resolve_node_ids(act["from"], lesson.node_bindings)
				if ids.is_empty():
					return true

				var g = graphs._graphs.get(ids[0])
				if g == null:
					return true

				var out_port: int = int(act.get("out_port", -1))
				if out_port == -1:
					out_port = g.output_keys.keys()[0]

				if not g.output_keys.has(out_port):
					return true

				var conns = g.output_keys[out_port]

				ui.show_arrow_conn(conns)
				return true

			# TO (input port)
			if act.has("to"):
				var ids = resolve_node_ids(act["to"], lesson.node_bindings)
				if ids.is_empty():
					return true

				var g = graphs._graphs.get(ids[0])
				if g == null:
					return true

				var in_port: int = int(act.get("in_port", -1))
				if in_port == -1:
					in_port = g.input_keys.keys()[0]

				if not g.input_keys.has(in_port):
					return true

				var conns = g.input_keys[in_port]

				ui.show_arrow_conn(conns)
				return true

	return true

func run_action_hide_arrows(_act: Dictionary, _lesson) -> bool:
	await glob.tree.process_frame
	await ui.hide_arrows()
	return true


func run_action_confetti(act: Dictionary, lesson) -> bool:
	await glob.tree.process_frame
	await glob.tree.process_frame
	
	if act["whole"]:
		ui.conf_screen()
	else:
		var targets: Array = act.get("targets", [])
		if targets.is_empty():
			return true

		var uniq: Dictionary = {}

		for sel in targets:
			var ids: Array = _resolve_highlight_selector(sel, lesson.node_bindings)
			for id in ids:
				uniq[id] = true
		for i in uniq:
			ui.confetti(graphs._graphs[i].rect.get_global_rect().get_center())
		if act.wait:
			await glob.wait(1.0)
	return true


func _resolve_highlight_selector(sel: Dictionary, node_bindings: Dictionary) -> Array:
	var kind = str(sel.get("kind", "")).strip_edges()

	match kind:
		"bind":
			var b = str(sel.get("bind", "")).strip_edges()
			if b == "":
				return []
			return resolve_node_ids({ "bind": b }, node_bindings)

		"type":
			return _resolve_by_type_and_exprs(sel)

		"topology":
			var topo = sel.get("topology", null)
			if typeof(topo) != TYPE_DICTIONARY:
				return []
			return _resolve_by_rough_topology(topo, node_bindings)

		_:
			return []


func _resolve_by_type_and_exprs(sel: Dictionary) -> Array:
	var node_type = str(sel.get("node_type", "")).strip_edges()
	var exprs: Dictionary = sel.get("exprs", {})

	var out: Array = []
	for node in graphs._graphs.values():
		if node.get_meta("created_with") != node_type:
			continue
		if not exprs.is_empty():
			if not graph.eval_cfg_expressions(node.cfg, exprs, node_type):
				continue
		out.append(node.graph_id)

	return out

func _resolve_by_rough_topology(topo_req: Dictionary, node_bindings: Dictionary) -> Array:
	var roots = resolve_node_ids(topo_req.get("root", {}), node_bindings)
	if roots.is_empty():
		return []

	var out: Dictionary = {}

	for root_id in roots:
		var root = graphs._graphs.get(root_id)
		if root == null:
			continue

		var scene = graph.collect_reachable(root)
		var ids: Array = _collect_topology_nodes(scene, topo_req)

		for id in ids:
			out[id] = true

	return out.keys()


func _collect_topology_nodes(scene: Dictionary, topo_req: Dictionary) -> Array:
	# scene = { "nodes": Dictionary, "edges": Array }

	if not scene.has("nodes") or not scene.has("edges"):
		return []

	# 1) Проверяем, что topology вообще совпадает
	if not graph.match_graph(scene, topo_req):
		return []

	var tpl_nodes: Dictionary = topo_req.get("nodes", {})

	# 2) Если шаблон не уточняет nodes — подсвечиваем всё достижимое
	if tpl_nodes.is_empty():
		return scene["nodes"].keys()

	# 3) Собираем candidates ТОЧНО как match_graph
	var candidates: Dictionary = {} # alias -> [graph_id]

	for alias in tpl_nodes.keys():
		var spec: Dictionary = tpl_nodes[alias]
		var t = spec.get("type", null)
		var exprs: Dictionary = spec.get("config", {})

		var arr: Array = []
		for node in scene["nodes"].values():
			if node.get_meta("created_with") != t:
				continue
			if not exprs.is_empty() and not graph.eval_cfg_expressions(node.cfg, exprs, str(t)):
				continue
			arr.append(node.graph_id)

		if arr.is_empty():
			return []

		candidates[alias] = arr

	# 4) Collect all ids used in any valid assignment
	var used: Dictionary = {}
	_collect_assignments(
		tpl_nodes.keys(),
		candidates,
		{},
		topo_req.get("edges", []),
		used
	)

	return used.keys()


func _collect_assignments(
	names: Array,
	cand: Dictionary,
	assigned: Dictionary,
	edges: Array,
	out_used: Dictionary
) -> void:
	if assigned.size() == names.size():
		# Проверяем edges точно так же
		for e in edges:
			if not graph.graph_has_any_connection(assigned[e[0]], assigned[e[1]]):
				return
		# Валидное сопоставление — сохраняем все graph_id
		for id in assigned.values():
			out_used[id] = true
		return

	var name = names[assigned.size()]
	for id in cand[name]:
		if id in assigned.values():
			continue
		assigned[name] = id
		_collect_assignments(names, cand, assigned, edges, out_used)
		assigned.erase(name)
