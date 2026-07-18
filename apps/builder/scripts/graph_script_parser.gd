extends Node

var tags = ["change_nodes", "connect_ports", "delete_nodes", "disconnect_ports", "thinking"]

# ---- persistent tag index & spawn cursor to avoid overlap across calls
var _tag_index: Dictionary = {}            # String (llm_tag) -> Graph


func tag_strip(text: String) -> Array:
	var out = ""
	var i = 0
	var stack: Array[String] = []
	var did_remove = false

	while i < text.length():
		var next_open = -1
		var next_close = -1
		var found_tag = ""
		var closing_tag = false

		for tag in tags:
			var pos_open = text.find("<%s>" % tag, i)
			var pos_close = text.find("</%s>" % tag, i)
			if pos_open != -1 and (next_open == -1 or pos_open < next_open):
				next_open = pos_open
				found_tag = tag
				closing_tag = false
			if pos_close != -1 and (next_close == -1 or pos_close < next_close):
				next_close = pos_close
				if next_open == -1 or next_close < next_open:
					found_tag = tag
					closing_tag = true

		if next_open == -1 and next_close == -1:
			out += text.substr(i)
			break

		var min_pos = INF
		if next_open != -1:
			min_pos = min(min_pos, next_open)
		if next_close != -1:
			min_pos = min(min_pos, next_close)

		out += text.substr(i, min_pos - i)
		i = min_pos

		if closing_tag:
			if stack.size() > 0 and stack.back() == found_tag:
				stack.pop_back()
			i += ("</%s>" % found_tag).length()
			did_remove = true
		else:
			stack.append(found_tag)
			i += ("<%s>" % found_tag).length()
			var close_pos = text.find("</%s>" % found_tag, i)
			if close_pos == -1:
				did_remove = true
				break
			i = close_pos + ("</%s>" % found_tag).length()
			did_remove = true

	return [out, did_remove]


func _match_tag_token(buf: String, pos: int) -> Variant:
	if pos >= buf.length() or buf[pos] != '<':
		return null

	for tag in tags:
		var open_tok = "<%s>" % tag
		var close_tok = "</%s>" % tag
		if buf.substr(pos, open_tok.length()) == open_tok:
			return {"kind": "open", "tag": tag, "len": open_tok.length()}
		if buf.substr(pos, close_tok.length()) == close_tok:
			return {"kind": "close", "tag": tag, "len": close_tok.length()}

	var tail = buf.substr(pos)
	for tag in tags:
		var open_tok = "<%s>" % tag
		var close_tok = "</%s>" % tag
		if open_tok.begins_with(tail) or close_tok.begins_with(tail):
			return {"kind": "partial"}
	return null






func parse_stream_tags(sock, chunk: String) -> String:
	var state = sock.cache.get_or_add("parser_state", {"buf": "", "stack": [], "acc": []})
	var actions = sock.cache.get_or_add("actions", {})  # { tag: [body1, body2, ...] }

	state.buf += chunk
	var result: String = ""
	var i: int = 0

	while i < state.buf.length():
		var token = null
		if state.buf[i] == '<':
			token = _match_tag_token(state.buf, i)
			if token == null:
				if state.stack.size() == 0:
					result += state.buf[i]
				else:
					state.acc[state.acc.size() - 1] += state.buf[i]
				i += 1
				continue

			if token.has("kind") and token.kind == "partial":
				break

			if token.kind == "open":
				var current_is_same = state.stack.size() > 0 and state.stack.back() == token.tag
				if current_is_same:
					if state.stack.size() == 0:
						result += "<%s>" % token.tag
					else:
						state.acc[state.acc.size() - 1] += "<%s>" % token.tag
					i += token.len
					continue

				state.stack.append(token.tag)
				state.acc.append("")
				i += token.len
				continue

			if token.kind == "close":
				var top_ok = state.stack.size() > 0 and state.stack[state.stack.size() - 1] == token.tag
				if top_ok:
					var body: String = state.acc.pop_back()
					state.stack.pop_back()

					if not actions.has(token.tag):
						actions[token.tag] = []
					actions[token.tag].append(body)

					if state.acc.size() > 0:
						state.acc[state.acc.size() - 1] += "<%s>%s</%s>" % [token.tag, body, token.tag]

					i += token.len
					continue
				else:
					if state.stack.size() == 0:
						result += "</%s>" % token.tag
					else:
						state.acc[state.acc.size() - 1] += "</%s>" % token.tag
					i += token.len
					continue

		if state.stack.size() == 0:
			result += state.buf[i]
		else:
			state.acc[state.acc.size() - 1] += state.buf[i]
		i += 1

	state.buf = state.buf.substr(i)

	for j in tags:
		if not j in actions:
			actions[j] = []

	return result


func clean_message(s: String):
	s = s.replace("json", "")
	s = s.replace("``` ```", "")
	s = s.replace("```  ```", "")
	s = s.replace("```\n```", "")
	#(s)
	return tag_strip(s)[0].strip_edges()


func preprocess(actions: Dictionary):
	var res = {}
	for tag in tags:
		if tag == "thinking": continue
		res[tag] = []
		if not actions.has(tag):
			res[tag] = []
		else:
			for el in len(actions[tag]):
				if actions[tag][el] is String:
					res[tag].append(JSON.parse_string(actions[tag][el]))
	return res


func _grid_snap(p: Vector2, step: float = 8.0) -> Vector2:
	return Vector2(round(p.x / step) * step, round(p.y / step) * step)




func _choose_origins(nodes) -> Array:
	var origins: Array = []
	for tag in nodes.keys():
		var g: Graph = nodes[tag]
		if g.server_typename == "InputNode" or g.server_typename == "TrainBegin":
			origins.append(g)
	if origins.is_empty() and nodes.size() > 0:
		origins.append(nodes.values()[0])
	return origins

func _find_best_position(bbox: Rect2, padding: float) -> Vector2:
	if _subgraph_slots.is_empty():
		return Vector2.ZERO
	
	var candidate_positions = []
	
	for slot in _subgraph_slots:
		var pos = Vector2(slot.end.x + padding, slot.position.y)
		candidate_positions.append(pos)
	
	for slot in _subgraph_slots:
		var pos = Vector2(slot.position.x, slot.end.y + padding)
		candidate_positions.append(pos)
	
	var max_x = -INF
	var min_y = INF
	for slot in _subgraph_slots:
		max_x = max(max_x, slot.end.x)
		min_y = min(min_y, slot.position.y)
	candidate_positions.append(Vector2(max_x + padding, min_y))
	
	var min_x = INF
	var max_y = -INF
	for slot in _subgraph_slots:
		min_x = min(min_x, slot.position.x)
		max_y = max(max_y, slot.end.y)
	candidate_positions.append(Vector2(min_x, max_y + padding))
	
	var best_pos = candidate_positions[0]
	var best_score = INF
	
	for pos in candidate_positions:
		var test_rect = Rect2(pos, bbox.size)
		
		var has_overlap = false
		for slot in _subgraph_slots:
			if test_rect.intersects(slot):
				has_overlap = true
				break
		
		if has_overlap:
			continue
		
		var score = pos.length_squared() + test_rect.end.length_squared()
		
		if score < best_score:
			best_score = score
			best_pos = pos
	
	return best_pos






func model_changes_apply(actions: Dictionary, txt: String):
	if not (actions.get("change_nodes", []).size() > 0 and actions.get("change_nodes", [""])[0] is not String):
		#(actions)
		actions = preprocess(actions)
		#(actions)


	if not actions["connect_ports"] and not actions["change_nodes"] and\
	not actions["delete_nodes"] and not actions["disconnect_ports"]:
		return
	#(actions)
	for i in actions:
		for a in actions[i]:
			if a == null:
				return
	nn.request_save()
	ui.set_topr_text(txt)
	#actions["connect_ports"][-1].remove_at(1)
#	actions["connect_ports"][-1].remove_at(1)
	var creating: Dictionary[String, Graph] = {}
	for i in ui.splashed:
		i.go_away()
	
	var has_structure_change: bool = false
	#(actions)
	var skip = []
	var to_map = {}
	# --- create or reuse nodes
	glob.open_action_batch(true)



	
	await get_tree().process_frame
	for pack in actions["disconnect_ports"]:
		for connection in pack:
			var from_graph = glob.tags_1d.get(connection.from.tag, creating.get(connection.from.tag))
			var to_graph = glob.tags_1d.get(connection.to.tag,  creating.get(connection.to.tag))
			if not is_instance_valid(from_graph) or not is_instance_valid(to_graph):
				continue

			var out_ports = from_graph.output_keys
			var in_ports  = to_graph.input_keys
			if len(out_ports) == 1:
				connection.from.port = out_ports.keys()[0]
			if len(in_ports) == 1:
				connection.to.port = in_ports.keys()[0]

			var from_port = int(connection.from.port)
			var to_port = int(connection.to.port)
			var valid_from = out_ports.has(from_port)
			var valid_to = in_ports.has(to_port)

			if not valid_from and valid_to:
				var tmp = connection.from
				connection.from = connection.to
				connection.to = tmp
				from_graph = glob.tags_1d.get(connection.from.tag,  glob.tags_1d.get(connection.from.tag))
				to_graph =  glob.tags_1d.get(connection.to.tag,    glob.tags_1d.get(connection.to.tag))
				out_ports = from_graph.output_keys
				in_ports = to_graph.input_keys
				from_port = int(connection.from.port)
				to_port = int(connection.to.port)
				valid_from = out_ports.has(from_port)
				valid_to = in_ports.has(to_port)

			if not (valid_from and valid_to):
				continue
			
			out_ports[from_port].disconnect_from(in_ports[to_port])
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	
	
	await get_tree().process_frame
	for pack in actions["delete_nodes"]:
		for i in pack:
			if glob.tags_1d.has(i):
				glob.tags_1d[i].delete()

	await get_tree().process_frame


	if actions["change_nodes"]:

		for pack in actions["change_nodes"]:
			for node in pack:
				var typename = glob.llm_name_mapping.get(node.type)
				if not typename:
					continue
				
				var existing: Graph = glob.tags_1d.get(node.tag, null)
				if is_instance_valid(existing):
					creating[node.tag] = existing
					skip.append(node.tag)
					existing.set_meta("llm_pack", node)
					existing.hold_for_frame()
					continue
				else:
					#await get_tree().process_frame
					has_structure_change = true

				var g = graphs.get_graph(typename, Graph.Flags.NEW, 0, node.tag)
				creating[node.tag] = g
				#_tag_index[node.tag] = g
				#(node.tag)
				g.set_meta("llm_pack", node)
				g.set_meta("llm_tag", node.tag)
				if graphs.is_nodes(g, "ModelName", "DatasetName"):
				#	print("MAP!!")
					prop_map(g)
					
				g.hold_for_frame()
	await get_tree().process_frame
	var to_rearrange = []
	var deferred_train_links: Array = []


	for pack: Array in actions["connect_ports"]:
		var front: Array = []
		var back: Array = []
		for c in pack:
			var from_graph = glob.tags_1d.get(c.from.tag, null)
			if from_graph and graphs.is_nodes(from_graph, "DatasetName", "LuaEnv", "ModelName", "InputNode"):
				front.append(c)
				#c["_wait"] = true
			else:
				back.append(c)
		pack = front + back
	#	print(pack)
	#	print(front)
		
		#pack.sort_custom()
		for connection in pack:
			#(connection)
			var from_graph = glob.tags_1d.get(connection.from.tag, creating.get(connection.from.tag))
			var to_graph = glob.tags_1d.get(connection.to.tag, creating.get(connection.to.tag))
			if not is_instance_valid(from_graph) or not is_instance_valid(to_graph):
				print("skip connect: missing graph(s) for tags ", connection.from.tag, " -> ", connection.to.tag)
				continue

			var out_ports = from_graph.output_keys
			var in_ports  = to_graph.input_keys
			if len(out_ports) == 1:
				connection.from.port = out_ports.keys()[0]
			if len(in_ports) == 1:
				connection.to.port = in_ports.keys()[0]

			var from_port = int(connection.from.port)
			var to_port   = int(connection.to.port)
			var valid_from = out_ports.has(from_port)
			var valid_to   = in_ports.has(to_port)

			if not valid_from and valid_to:
				print("swapped reversed connection")
				var tmp = connection.from
				connection.from = connection.to
				connection.to = tmp
				from_graph = glob.tags_1d.get(connection.from.tag, null)
				to_graph =  glob.tags_1d.get(connection.to.tag,null)
				out_ports = from_graph.output_keys
				in_ports = to_graph.input_keys
				from_port = int(connection.from.port)
				to_port = int(connection.to.port)
				valid_from = out_ports.has(from_port)
				valid_to = in_ports.has(to_port)

			if not (valid_from and valid_to):
				print("invalid connection skipped:", connection)
				continue
			
			has_structure_change = true
			if graphs.is_node(from_graph, "TrainBegin"):
				await get_tree().process_frame
			var o = out_ports[from_port].connect_to(in_ports[to_port])
			if not o:
				print("skipping connection (unsuit)", connection)
			var from_tag = from_graph.llm_tag
			var to_tag = to_graph.llm_tag
			if not (creating.has(from_tag) and creating.has(to_tag)):
				to_rearrange.append(connection)
			if graphs.is_node(from_graph, "TrainBegin") and graphs.is_node(to_graph, "RunModel"):
				deferred_train_links.append(connection)
	
	if deferred_train_links:
		await get_tree().process_frame

	for c in deferred_train_links:
		var from_graph = glob.tags_1d.get(c.from.tag)
		var to_graph = glob.tags_1d.get(c.to.tag)
		if not is_instance_valid(from_graph) or not is_instance_valid(to_graph):
			continue
		var anc = graphs.get_input_graph_by_name(to_graph.name_graph)
		var ok = from_graph.output_keys[int(c.from.port)].connect_to(to_graph.input_keys[int(c.to.port)])




	for tag in creating.keys():
	#	var real_node: Graph = creating[tag]
		prop_map( creating[tag])
	for i in skip:
		creating.erase(i)
	
	if has_structure_change:
		_auto_layout(creating, to_rearrange, 100)
	glob.close_action_batch()
var _subgraph_slots: Array = []
var _next_spawn_x: float = 0.0


func prop_map(real_node):
	#var real_node: Graph = creating[tag]
	var cfg = real_node.get_meta("llm_pack").config
	var map = func(...args):
		var k = args[0]
		var v = args[1] if args.size() > 1 else k
		if real_node.base_config.size() == 1:
			k = real_node.base_config.keys()[0]
		if k in real_node.base_config:
			return glob.cast_variant(v, typeof(real_node.base_config[k]))
		else:
			return v
	cfg = glob.deep_map(cfg, map)
	real_node.llm_map(cfg)

func _get_all_descendants(start_node: Graph) -> Array[Graph]:
	var descendants: Array[Graph] = []
	var queue: Array[Graph] = [start_node]
	var visited: Dictionary = {start_node: true}
	
	while not queue.is_empty():
		var current_node = queue.pop_front()
		descendants.append(current_node)
		
		for port_key in current_node.output_keys:
			var out_port = current_node.output_keys[port_key]
			for c in out_port.outputs.values():
				var connected_node = c.tied_to.parent_graph
				if not visited.has(connected_node):
					visited[connected_node] = true
					queue.append(connected_node)
					
	return descendants


func _find_subgraphs(nodes: Dictionary[String, Graph]) -> Array:
	var visited = {}
	var subgraphs = []
	
	for tag in nodes.keys():
		var node = nodes[tag]
		if node in visited:
			continue
		
		var subgraph = []
		var queue = [node]
		
		while queue.size() > 0:
			var current = queue.pop_front()
			if current in visited:
				continue
			visited[current] = true
			subgraph.append(current)
			
			var descendants = current.get_first_descendants()
			for d in descendants:
				if d in nodes.values() and not (d in visited):
					queue.append(d)
			
			var ancestors = current.get_first_ancestors()
			for a in ancestors:
				if a in nodes.values() and not (a in visited):
					queue.append(a)
		
		if subgraph.size() > 0:
			subgraphs.append(subgraph)
	
	return subgraphs


func _layout_subgraph(nodes: Array, origins: Array, padding: float):
	var visited = {}
	
	for origin in origins:
		var reach_func = func(from_conn, to_conn, branch_cache):
			var from_graph = from_conn.parent_graph
			var to_graph = to_conn.parent_graph
			
			if to_graph in visited:
				return
			visited[to_graph] = true
			
			var dir = from_conn.dir_vector
			var from_rect = from_graph.rect.get_global_rect()
			
			var to_rect = Rect2(Vector2.ZERO, from_rect.size)
			
			var base_pos = Vector2()
			
			if dir.x >= 0:
				base_pos.x = from_rect.end.x + padding
			else:
				base_pos.x = from_rect.position.x - to_rect.size.x - padding
			
			if dir.y == 0:
				base_pos.y = from_rect.position.y + (from_rect.size.y - to_rect.size.y) / 2.0
			elif dir.y > 0:
				base_pos.y = from_rect.end.y + padding
			else:
				base_pos.y = from_rect.position.y - to_rect.size.y - padding
			
			to_graph.global_position = base_pos - to_graph.rect.position
			to_graph.reposition_splines()
		
		graphs.reach(origin, reach_func)


func _position_special_nodes(node: Graph):
	if graphs.is_node(node, "LayerConfig"):
		var descendants = node.get_first_descendants()
		if descendants:
			var middle_x = 0.0
			for i in descendants:
				middle_x += i.rect.global_position.x + i.rect.size.x / 2.0
			middle_x /= len(descendants)
			var min_y = INF
			for i in descendants:
				min_y = min(min_y, i.rect.global_position.y)
			if min_y != INF:
				node.position = Vector2(middle_x, min_y - 100)
				node.reposition_splines()
	
	if graphs.is_node(node, "ModelName"):
		var descendants = node.get_first_descendants()
		if descendants:
			var middle_x = INF
			for i in descendants:
				middle_x = min(middle_x, i.rect.global_position.x)
			var min_y = INF
			for i in descendants:
				min_y = min(min_y, i.rect.global_position.y)
			node.position = Vector2(middle_x - 80, min_y - 150)
			node.reposition_splines()
	
	if graphs.is_nodes(node, "DatasetName", "LuaEnv"):
		var descendants = node.get_first_descendants()
		if descendants:
			var middle_x = INF
			for i in descendants:
				middle_x = min(middle_x, i.rect.global_position.x)
			var min_y = INF
			for i in descendants:
				min_y = min(min_y, i.rect.global_position.y)
			node.position = Vector2(middle_x - 200, min_y - 20)
			node.reposition_splines()

func _bbox_of(nodes) -> Rect2:
	var any = true
	var r = Rect2()
	for g in nodes:
		var gr = g.rect.get_global_rect() if g is Graph else nodes[g].rect.get_global_rect()
		if any:
			r = gr
			any = false
		else:
			r = r.merge(gr)
	return r


var _layout_bounds: Rect2 = Rect2()

func _place_subgraph_non_overlapping(nodes: Array, padding: float) -> Vector2:
	var bbox = _bbox_of(nodes)
	var best_pos = _find_best_position(bbox, padding)
	var offset = best_pos - bbox.position
	
	for node in nodes:
		node.global_position = node.global_position + offset
		node.reposition_splines()
	
	var new_bbox = _bbox_of(nodes)
	_subgraph_slots.append(new_bbox)
	
	if _subgraph_slots.size() == 1:
		_layout_bounds = new_bbox
	else:
		_layout_bounds = _layout_bounds.merge(new_bbox)
	
	return offset



func _auto_layout(creating: Dictionary[String, Graph], to_rearrange, padding: float = 100.0):
	if not creating:
		return

	# --- classify config-type nodes
	var is_config_node = func(g: Graph) -> bool:
		return graphs.is_node(g, "LayerConfig") \
			or graphs.is_node(g, "ModelName") \
			or graphs.is_nodes(g, "DatasetName", "LuaEnv") \
			or graphs.is_node(g, "Activation")

	for tag in creating.keys():
		var g = creating[tag]
		g.hold_for_frame()

	var subgraphs = _find_subgraphs(creating)
	var leftover_groups = []
	var all_changed_nodes: Array = []
	var config_nodes: Array[Graph] = []

	# collect config nodes separately (so we can reposition them later)
	for subgraph in subgraphs:
		for g in subgraph:
			if is_config_node.call(g):
				config_nodes.append(g)

	# --- relayout only subgraphs that contain structural nodes
	for subgraph in subgraphs:
		var has_non_config = false
		for g in subgraph:
			if not is_config_node.call(g):
				has_non_config = true
				break
		if not has_non_config:
			continue  # skip config-only group layout

		var nodes_dict = {}
		for node in subgraph:
			var tag = node.get_meta("llm_tag") if node.has_meta("llm_tag") else ""
			if tag:
				nodes_dict[tag] = node

		var origins = _choose_origins(nodes_dict)
		for origin in origins:
			if graphs.is_node(origin, "TrainBegin"):
				origin.position.y -= 310
				origin.reposition_splines()

		_layout_subgraph(subgraph, origins, padding)
		for g in subgraph:
			if is_config_node.call(g):
				_position_special_nodes(g)
				g.reposition_splines()

		var leftover = []
		for node in subgraph:
			var was_visited = false
			for origin in origins:
				if node == origin:
					was_visited = true
					break
				var check_func = func(from_conn, to_conn, branch_cache):
					if to_conn.parent_graph == node:
						was_visited = true
				graphs.reach(origin, check_func)
				if was_visited:
					break
			if not was_visited:
				leftover.append(node)
		leftover_groups.append(leftover)

		for origin in origins:
			if graphs.is_node(origin, "TrainBegin"):
				origin.position.y += 0

		_place_subgraph_non_overlapping(subgraph, padding)
		all_changed_nodes.append_array(subgraph)

	# --- selective rearrangement (config → non-config)
	for connection in to_rearrange:
		var from_graph = glob.tags_1d.get(connection.from.tag, null)
		var to_graph   = glob.tags_1d.get(connection.to.tag, null)
		if not is_instance_valid(from_graph) or not is_instance_valid(to_graph):
			continue

		var from_is_cfg = is_config_node.call(from_graph)
		var to_is_cfg = is_config_node.call(to_graph)

		# Case 1: config → structural
		if from_is_cfg and not to_is_cfg:
			_position_special_nodes(from_graph)
			from_graph.reposition_splines()
			all_changed_nodes.append(from_graph)
			continue

		# Case 2: structural → config (rare, but possible)
		if to_is_cfg and not from_is_cfg:
			_position_special_nodes(to_graph)
			to_graph.reposition_splines()
			all_changed_nodes.append(to_graph)
			continue

		# Case 3: both structural → do normal offset layout
		var out_ports = from_graph.output_keys
		var in_ports  = to_graph.input_keys
		var from_rect = from_graph.rect.get_global_rect()
		var to_rect = to_graph.rect.get_global_rect()

		var new_to_pos = Vector2(
			from_rect.end.x + padding,
			from_rect.position.y + (from_rect.size.y - to_rect.size.y) / 2.0
		)

		new_to_pos = _grid_snap(new_to_pos)

		var current_to_pos = to_graph.rect.get_global_rect().position
		var offset = new_to_pos - current_to_pos

		var subgraph_to_move = _get_all_descendants(to_graph)
		for node in subgraph_to_move:
			node.global_position += offset
			node.hold_for_frame()
			node.reposition_splines()

		all_changed_nodes.append_array(subgraph_to_move)

	# --- apply special positioning for config nodes that were newly created
	for cfg in config_nodes:
		_position_special_nodes(cfg)
		cfg.reposition_splines()
		all_changed_nodes.append(cfg)

	# --- apply special positioning for leftovers (orphans etc.)
	for leftover in leftover_groups:
		for node in leftover:
			_position_special_nodes(node)
			all_changed_nodes.append(node)

	# --- smart viewport zoom/focus
	if all_changed_nodes.size() > 0 and glob.cam is GraphViewport:
		var bbox = _bbox_of(all_changed_nodes)
		var center = bbox.position + bbox.size / 2.0
		var span = max(bbox.size.x, bbox.size.y)
		var zoom = clamp(800.0 / max(span, 100.0), 0.4, 1.5)
		glob.cam.change_cam(zoom, center)
