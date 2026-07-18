class_name DSLGraphUtils
extends RefCounted

class BObj:
	func _init() -> void:
		pass

func eval_cfg_expressions(cfg: Dictionary, exprs: Dictionary, node_type: String = "") -> bool:
	var eval_cfg := cfg
	if node_type == "dataset" and exprs.has("dataset_name") and cfg.has("name") and not cfg.has("dataset_name"):
		eval_cfg = cfg.duplicate()
		eval_cfg["dataset_name"] = cfg["name"]
	
	#exprs.erase("mapped")
	for expr_str in exprs.values():
		var expr = Expression.new()
		if expr.parse(str(expr_str), PackedStringArray(eval_cfg.keys())) != OK:
			return false
		if expr.execute(eval_cfg.values(), BObj.new(), true) != true:
			return false
	return true

func graph_has_connection(from_id, to_id, out_port: int, in_port: int) -> bool:
	var from = graphs._graphs.get(from_id)
	var to: Graph = graphs._graphs.get(to_id)
	if from == null or to == null:
		return false
	# Auto-pick first output port if unspecified
	if out_port == -1:
		if from.output_keys.is_empty():
			return false
		out_port = int(from.output_keys.keys()[0])

	if not from.output_keys.has(out_port):
		if from.output_keys.size() == 1:
			out_port = from.output_keys.keys()[0]
		else:
			return false

	if not to.input_keys.has(in_port):
		if to.input_keys.size() == 1:
			in_port = to.input_keys.keys()[0]
		else:
			return false
	
	
	# Validate in_port only if explicitly requested
	if in_port != -1 and not to.input_keys.has(in_port):
		return false

	var out_slot = from.output_keys[out_port]
	if out_slot.outputs.is_empty():
		return false

	# Check ANY connection on that out_port towards 'to'
	for c in out_slot.outputs.values():
		if c.tied_to == null:
			continue
		if c.tied_to.parent_graph == null:
			continue
		if c.tied_to.parent_graph.graph_id != to_id:
			continue

		# If in_port is unspecified: any port into 'to' is OK
		if in_port == -1:
			return true

		# Else match exact input port id
		if int(c.tied_to.hint) == in_port:
			return true

	return false


func graph_has_any_connection(from_id, to_id) -> bool:
	var from = graphs._graphs.get(from_id)
	if from == null:
		return false

	for out_port in from.output_keys.keys():
		for c in from.output_keys[out_port].outputs.values():
			if c.tied_to.parent_graph.graph_id == to_id:
				return true

	return false

func collect_reachable(root) -> Dictionary:
	# NOTE: This is now "connected component around root", not forward-propagation reach.
	# It fixes cases like Activation -> Dense when root is Input1D and Activation is not in data flow.

	var nodes: Dictionary = {}
	var edges: Array = []   # each: {from, to, out_port, in_port}

	if root == null:
		return { "nodes": {}, "edges": [] }

	# ------------------------------------------------------------
	# 1) Build adjacency from *actual* connections in the canvas
	# ------------------------------------------------------------
	var adj: Dictionary = {}  # id -> Array of neighbor ids

	var _adj_add = func _adj_add(a, b):
		if not adj.has(a):
			adj[a] = []
		adj[a].append(b)

	# Collect all directed edges (with ports) by scanning outputs
	for g in graphs._graphs.values():
		if g == null:
			continue
		var from_id = g.graph_id
		if not adj.has(from_id):
			adj[from_id] = []

		for out_port in g.output_keys.keys():
			var out_slot = g.output_keys[out_port]
			if out_slot == null:
				continue
			if not out_slot.outputs or out_slot.outputs.is_empty():
				continue

			for c in out_slot.outputs.values():
				if c == null or c.tied_to == null:
					continue
				var to_graph = c.tied_to.parent_graph
				if to_graph == null:
					continue
				var to_id = to_graph.graph_id
				var in_port = int(c.tied_to.hint)

				# record edge (directed, port-aware)
				edges.append({
					"from": from_id,
					"to": to_id,
					"out_port": int(out_port),
					"in_port": in_port
				})

				# build undirected adjacency for "connected component"
				_adj_add.call(from_id, to_id)
				_adj_add.call(to_id, from_id)

	# ------------------------------------------------------------
	# 2) BFS from root over undirected adjacency
	# ------------------------------------------------------------
	var root_id = root.graph_id
	var q: Array = [root_id]
	var seen: Dictionary = { root_id: true }

	while q.size() > 0:
		var cur = q.pop_front()

		var cur_graph = graphs._graphs.get(cur)
		if cur_graph != null:
			nodes[cur] = cur_graph

		var neigh: Array = adj.get(cur, [])
		for n in neigh:
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)

	# ------------------------------------------------------------
	# 3) Filter edges to the component only (optional, but clean)
	# ------------------------------------------------------------
	var filtered_edges: Array = []
	for e in edges:
		var a = e["from"]
		var b = e["to"]
		if nodes.has(a) and nodes.has(b):
			filtered_edges.append(e)

	return { "nodes": nodes, "edges": filtered_edges }


func match_graph(scene: Dictionary, tpl: Dictionary) -> bool:
	var tpl_nodes: Dictionary = tpl["nodes"]
	var tpl_edges: Array = tpl["edges"]
	var candidates: Dictionary = {}

	for name in tpl_nodes.keys():
		var spec: Dictionary = tpl_nodes[name]
		candidates[name] = []

		for g in scene["nodes"].values():
			
			#(scene["nodes"])
			if g.get_meta("created_with") != spec["type"]:
				continue
			if spec.has("config"):
				if not eval_cfg_expressions(g.cfg, spec["config"], str(spec["type"])):
					continue
			candidates[name].append(g.graph_id)

		if candidates[name].is_empty():
			#(name)
			return false

	return assign_nodes(tpl_nodes.keys(), candidates, {}, tpl_edges)

func assign_nodes(names: Array, cand: Dictionary, assigned: Dictionary, edges: Array) -> bool:

	if assigned.size() == names.size():
		return check_edges(assigned, edges)

	var name = names[assigned.size()]
	for id in cand[name]:
		if id in assigned.values():
			continue
		assigned[name] = id
		if assign_nodes(names, cand, assigned, edges):
			return true
		assigned.erase(name)

	return false

func check_edges(map: Dictionary, edges: Array) -> bool:
	#print(map, edges)
	for e in edges:
		var a_name := ""
		var b_name := ""
		var out_port := -1
		var in_port := -1

		# New canonical dict edge
		if typeof(e) == TYPE_DICTIONARY:
			a_name = str(e.get("from", "")).strip_edges()
			b_name = str(e.get("to", "")).strip_edges()
			out_port = int(e.get("out_port", -1))
			in_port = int(e.get("in_port", -1))

		# Legacy array edge: ["a", "b"] or ["a",0,"b",1]
		elif typeof(e) == TYPE_ARRAY:
			if e.size() == 2:
				a_name = str(e[0]).strip_edges()
				b_name = str(e[1]).strip_edges()
			elif e.size() == 4:
				a_name = str(e[0]).strip_edges()
				out_port = int(e[1])
				b_name = str(e[2]).strip_edges()
				in_port = int(e[3])
			else:
				return false

		else:
			return false

		if a_name == "" or b_name == "":
			return false
		if not map.has(a_name) or not map.has(b_name):
			return false

		var from_id = map[a_name]
		var to_id = map[b_name]

		# If any port constraint exists, enforce exact connection.
		if out_port != -1 or in_port != -1:
			if not graph_has_connection(from_id, to_id, out_port, in_port):

				return false
		else:
			if not graph_has_any_connection(from_id, to_id):
				return false
	return true
