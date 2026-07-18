extends CodeEdit

var parser := Commands.CommandParser.new()

@export var table: VirtualTable = null
var dataset: Array = []
@export var console: RichTextLabel

var ct: int = -1



func connect_ds(ds: Array):
	dataset = ds

func dataset_updated(force_full: bool = false):
	if table == null:
		return
	if force_full or table.rows != dataset.size():
		table.load_dataset(dataset, (dataset[0].size() if dataset.size() > 0 else 0), dataset.size())
	else:
		table.refresh_dataset(true)


func debug_print(text: String):
	ct += 1
	console.append_text("[color=gray][%d][/color] %s\n" % [ct, text])



func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ENTER:
		var line = text.strip_edges().strip_escapes()
		if line == "":
			await get_tree().process_frame
			clear()
			return
		compile()
		var result = parser.parse(line)
		if result.has("error"):
			debug_print("[color=coral]" + result["error"] + "[/color]")
		else:
			var cmd_name = result["command"]
			var def: Commands.CommandDef = parser.registry[cmd_name]
			await glob.join_ds_processing()
			if table.dataset_obj:
				
				def.handler.call(result)
		await get_tree().process_frame
		clear()



func _ready():
	table.ds_cleared.connect(func(): dataset = table.dataset)
	compile()


func compile():
	syntax_highlighter.define_group("commands", syntax_highlighter.C_CMD, 
		["go", "filter", "shuffle", "delete", "drop", "nrow", "drow", "cols", "keep", "outs", "acol", "dcol", "conv"])
	syntax_highlighter.define_group("meta", syntax_highlighter.C_META, 
		["begin", "commit", "undo", "redo"])
	syntax_highlighter.define_group("arguments", syntax_highlighter.C_ARG, 
		["col", "row", "as", "by", "on"])
	syntax_highlighter.define_group("etc", syntax_highlighter.C_COMMENT, 
		["txt", "float", "text", "img", "image", "num", "int", "and", "or", "not", "if", "else"])
		#C_SYMBOL

	parser.registry.clear()
	
	# FILTER
	parser.register(Commands.CommandDef.new(
		"filter",
		_on_filter_command,
		[],
		[],
		"Filters dataset rows based on condition.\n   filter if row > 5\n   filter drop if col == 0",
		false,
		["keep", "drop"],
		false
	))

	parser.register(Commands.CommandDef.new(
		"acol",
		_on_acol_command,
		[],
		[],
		"Adds a new column. Can append or insert by index.\nExamples:\n   acol salary:num\n   acol 0 salary:num\n   acol -1 id:txt",
		false,
		[],
		false
	))


	# SHUFFLE
	parser.register(Commands.CommandDef.new(
		"shuffle",
		_on_shuffle_command,
		[],
		[],
		"Randomly shuffles dataset rows.",
		false,
		[],
		true
	))

	# DELETE
	parser.register(Commands.CommandDef.new(
		"delete",
		_on_delete_command,
		[],
		[],
		"Deletes the dataset.",
		false,
		[],
		true
	))

	# DROP
	parser.register(Commands.CommandDef.new(
		"drop",
		_on_drop_command,
		[],
		[],
		"Drops dataset entirely.",
		false,
		[],
		true
	))

	# nrow
	parser.register(Commands.CommandDef.new(
		"nrow",
		_on_nrow_command,
		[],
		[],
		"Adds or inserts a new row, setting corresponding datatypes from columns.\nExamples:\n   nrow (text=\"hi\")\n   nrow 3 hi\n   nrow",
		false,
		[],
		true
	))

	parser.register(Commands.CommandDef.new(
		"dcol",
		_on_dcol_command,
		[],
		[],
		"Deletes a column by index",
		false,
		[],
		false
	))

	parser.register(Commands.CommandDef.new(
		"go",
		_on_go_command,
		[],
		[],
		"Scrolls to specified row",
		false,
		[],
		false
	))

	parser.register(Commands.CommandDef.new(
		"outs",
		_on_outs_command,
		[],
		[],
		"Sets output range to begin from specified column ID\nExample:\n   outs 2",
		false,
		[],
		false
	))


	# drow
	parser.register(Commands.CommandDef.new(
		"drow",
		_on_drow_command,
		[],
		[],
		"Removes row by index. Example:\n   drow 3",
		false,
		[],
		false
	))
	
	parser.register(Commands.CommandDef.new(
		"cols",
		_on_cols_command,
		[],
		["force"],
		"Sets all column names.\nExamples:\n   cols name:txt age:num salary:num\n   cols name:txt,age:num,salary:num",
		false,
		[],
		false
	))

	parser.register(Commands.CommandDef.new(
		"conv",
		_on_convert_command,
		[],
		["force"],
		"Converts a column’s datatype by index.\nExample:\n   conv 2 txt",
		false,
		[],
		false
	))

func _on_go_command(_data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	if parts.size() < 2:
		debug_print("[color=coral]Usage: go <column_index>[/color]")
		return

	var idx_str = parts[1]
	if not idx_str.is_valid_int():
		debug_print("[color=coral]Row index must be an integer.[/color]")
		return

	var row_idx = int(idx_str)
	if row_idx < -table.rows or row_idx >= table.rows:
		debug_print("[color=coral]Invalid row index %d.[/color]" % row_idx)
		return
	if row_idx < 0:
		row_idx += table.rows
	#(col_idx)
	
	table.scroll_to_row(row_idx, "center")
	#(col_names)
	

func _on_dcol_command(_data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	if parts.size() < 2:
		debug_print("[color=coral]Usage: dcol <column_index>[/color]")
		return

	var idx_str = parts[1]
	if not idx_str.is_valid_int():
		debug_print("[color=coral]Column index must be an integer.[/color]")
		return

	var col_idx = int(idx_str)
	if col_idx < -table.cols or col_idx >= table.cols:
		debug_print("[color=coral]Invalid column index %d.[/color]" % col_idx)
		return
	
	if col_idx < 0:
		col_idx += table.cols

	# 1. Mark dirty FIRST
	table.dirtify()
	
	# 2. Call DsObjRLE.remove_column to properly handle RLE cache
	DsObjRLE.remove_column(table.dataset_obj, table.dataset_obj["name"], col_idx)
	
	# 3. Update table metadata (DsObjRLE already updated dataset arrays)
	var col_names: Array = table.dataset_obj.get("col_names", [])
	
	# 4. Destroy and update cache
	table.destroy_column_cache(col_idx)
	
	# 5. Update column names in table
	table.set_column_names(col_names)
	
	dataset_updated(true)
	
	await get_tree().process_frame
	
	table.re_uni()
	table.refresh_preview()
	
	debug_print("Removed column %d" % col_idx)

func _on_outs_command(_data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	if parts.size() < 2:
		debug_print("[color=coral]Usage: dcol <column_index>[/color]")
		return

	var idx_str = parts[1]
	if not idx_str.is_valid_int():
		debug_print("[color=coral]Column index must be an integer.[/color]")
		return

	var col_idx = int(idx_str)
	if col_idx < -table.cols or col_idx >= table.cols:
		debug_print("[color=coral]Invalid column index %d.[/color]" % col_idx)
		return
	if col_idx == 0:
		debug_print("[color=coral]Dataset must have at least 1 input column.[/color]")
		return
	table.dirtify()
	#if col_idx == table.cols:
		#debug_print("[color=coral]Dataset must have at least 1 output column.[/color]" % col_idx)
		#return
	
	table.set_outputs_from(col_idx)
	table.re_uni()
	debug_print("Output format changed.")

func _convert_column(col_idx: int, to_dtype: String, force: bool = false) -> bool:
	#(to_dtype)
	if to_dtype not in type_map:
		debug_print("[color=coral]Unknown datatype: %s[/color]" % to_dtype)
		return false
	var dtype = type_map[to_dtype]

	if col_idx < -table.cols or col_idx >= table.cols:
		debug_print("[color=coral]Invalid column index %d.[/color]" % col_idx)
		return false
	if col_idx < 0:
		col_idx += table.cols
#	print(dtype)
	if table.column_datatypes[col_idx] == dtype:
		debug_print("[color=coral]Datatype didn't change.[/color]" % col_idx)
		return true

	var convs: Array = []
	var cant: Array = []
	var is_range: int = 0

	#(new_names)

	for y in range(dataset.size()):
		var converted = table.convert_cell(y, col_idx, dtype)
		if not "ok" in converted: 
			converted = table.get_type_default(dtype)
			converted["type"] = dtype
		if not force and not converted.get("ok", false):
			is_range += 1
			if is_range == 1:
				cant.append([y, 1])
			else:
				cant[-1][1] = is_range
			continue
		is_range = 0
		converted.erase("ok")
		convs.append(converted)
	
	if cant:
		var cant_str = ""
		for j in len(cant):
			var i = cant[j]
			if i[1] == 1:
				cant_str += str(i[0])
			else:
				cant_str += str(i[0]) + "-" + str(i[1]+i[0])
			if j != len(cant)-1:
				cant_str += ", "
		var err = "[color=coral]Cannot convert these rows: %s\nUse --force flag to override.[/color]" % cant_str
		debug_print(err)
		return false
	
	table.destroy_column_cache(col_idx)
	table.create_column_cache(col_idx)
	for y in range(len(convs)):
		table.mark_created(y, col_idx, convs[y])
		dataset[y][col_idx] = convs[y]

	dataset_updated(true)
	debug_print("Converted column %d → %s" % [col_idx, dtype])
	var new_names = []
	for i in table.cols:
		if i == col_idx:
			new_names.append(table.column_names[i] + ":" +  dtype)
		else:
			new_names.append(table.column_names[i] + ":" +  table.column_datatypes[i])
	
	var colargs = table.dataset_obj["col_args"]
	for i in len(colargs):
		if not colargs[i]:
			colargs[i].merge(table.default_argpacks[table.column_datatypes[i] if i != col_idx else dtype].duplicate(true))
	table.set_column_arg_packs(colargs.duplicate())
	table.set_column_names(new_names)
	table.dataset_obj["col_names"] = new_names
	if table.rows:
		table.re_uni()
		table.types_changed = false
	table._clear_hover()
	return true

func _on_acol_command(_data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	if parts.size() < 2:
		debug_print("[color=coral]Usage: acol [index] <name>:<type>[/color]")
		return
	table.dirtify()

	var insert_at: int = table.cols  # default append mode
	var token: String

	# detect index first
	if parts[1].is_valid_int() and parts.size() >= 3:
		insert_at = int(parts[1])
		token = parts[2]
	else:
		token = parts[1]

	# --- Split name:type(...) ---
	var splited = token.rsplit(":", true, 1)
	if splited.size() != 2:
		debug_print("[color=coral]Column format must be name:type. Example: acol salary:num[/color]")
		return

	var col_name = splited[0].strip_edges()
	var dtype_full = splited[1].strip_edges()
	var dtype_key = dtype_full
	var arg_pack: Dictionary = {}

	# --- Parse parentheses args safely ---
	var open = dtype_full.find("(")
	var close = dtype_full.rfind(")")
	if open != -1:
		if close == -1 or close <= open:
			debug_print("[color=coral]Malformed argument section in '%s'[/color]" % token)
			return
		dtype_key = dtype_full.substr(0, open).strip_edges()
		if dtype_key not in type_map:
			debug_print("[color=coral]Unknown datatype: %s[/color]" % dtype_key)
			return
		arg_pack = _parse_col_args(dtype_full, dtype_key)
		if arg_pack == null:
			return

	if dtype_key not in type_map:
		debug_print("[color=coral]Unknown datatype: %s[/color]" % dtype_key)
		return
	var dtype = type_map[dtype_key]

	if insert_at < 0:
		insert_at = table.cols + insert_at + 1
	insert_at = clamp(insert_at, 0, table.cols)

	var old_names: Array = table.dataset_obj.get("col_names", [])
	var new_col_names: Array = old_names.duplicate()
	var full_name = "%s:%s" % [col_name, dtype]
	new_col_names.insert(insert_at, full_name)
	
	var def = table.get_type_default(dtype)
	if def == null:
		debug_print("[color=coral]Type %s is not supported by VirtualTable.[/color]" % dtype)
		return
	table.create_column_cache(insert_at)
	var cnt: int = -1
	for r in dataset:
		cnt += 1
		def = table.get_type_default(dtype)
		def["type"] = dtype
		r.insert(insert_at, def)
		table.mark_created(cnt, insert_at, def)

	table.cols = new_col_names.size()
	if not arg_pack.is_empty():
		var arg_packs = table.dataset_obj.get("col_args", [])
		while arg_packs.size() < table.cols:
			arg_packs.append({})
		var converted = _conv_args(arg_pack, dtype)
		if converted is String:
			print_debug("[color=coral]Cannot convert argument %s, skipping[/color]" % converted)
		else:
			arg_packs.insert(insert_at, converted)
			table.set_column_arg_packs(arg_packs)
	
	table.set_column_names(new_col_names, true)
	table.re_uni()
	table.dataset_obj["col_names"] = new_col_names



	var ratios = PackedFloat32Array()
	ratios.resize(table.cols)
	ratios.fill(1.0 / table.cols)
	table.set_column_ratios(ratios)
	table._rebuild_column_metrics()
	table._need_layout = true
	table._need_visible_refresh = true
	
	dataset_updated(true)
	table.active_remap()
	debug_print("Inserted column '%s' of type %s at index %d." % [col_name, dtype, insert_at])

	table.refresh_preview()
func _conv_args(args: Dictionary, dtype: String):
	match dtype:
		"num":
			if not args.get("min", "0").is_valid_int():
				return "min"
			if not args.get("max", "0").is_valid_int():
				return "max"
			return {"min": int(args.get("min", 0)), "max": int(args.get("max", 100))}
	return args

func _on_convert_command(_data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	var force: bool = _data["flags"].has("force")

	if parts.size() < 3:
		debug_print("[color=coral]Usage: conv <column_index> <to_dtype>[/color]")
		return

	var idx_str = parts[1]
	if not idx_str.is_valid_int():
		debug_print("[color=coral]Column index must be an integer.[/color]")
		return
	var col_idx = int(idx_str)
	var to_dtype = parts[2]
	
	if table.rows:
		_convert_column(col_idx, to_dtype, force)
	table.refresh_preview()
	await get_tree().process_frame
	table.dirtify()



func _on_cols_command(_data: Dictionary):
	var line = text.strip_edges().strip_escapes()
	var parts = line.split(" ", false)

	if parts.size() < 2:
		debug_print("[color=coral]Usage: cols <name:type> [name:type(...)] [--force][/color]")
		return
	table.dirtify()

	var cols_str = line.substr(line.find(parts[0]) + parts[0].length()).strip_edges()
	var force: bool = _data["flags"].has("force")

	# --- Tokenize safely (respect parentheses, skip --force) ---
	var raw_names: Array = []
	var buf := ""
	var depth := 0
	for ch in cols_str:
		if ch == "(":
			depth += 1
			buf += ch
			continue
		elif ch == ")":
			depth = max(depth - 1, 0)
			buf += ch
			continue
		elif (ch == " " or ch == ",") and depth == 0:
			if buf.strip_edges() != "":
				var token = buf.strip_edges()
				if token != "--force":
					raw_names.append(token)
				buf = ""
		else:
			buf += ch
	if buf.strip_edges() != "":
		var token = buf.strip_edges()
		if token != "--force":
			raw_names.append(token)

	if raw_names.is_empty():
		debug_print("[color=coral]No valid column names provided.[/color]")
		return

	# --- Parse col:type(...) tokens ---
	var col_names: Array = []
	var dtypes: Array = []
	var arg_packs: Array = []

	for j in range(raw_names.size()):
		var token = raw_names[j]
		var splited = token.rsplit(":", true, 1)
		if splited.size() != 2:
			debug_print("[color=coral]Malformed column token: %s[/color]" % token)
			return

		var col_name = splited[0].strip_edges()
		var dtype_full = splited[1].strip_edges()
		var dtype_key = dtype_full
		var arg_pack = {}



		var open = dtype_full.find("(")
		var close = dtype_full.rfind(")")
		if open != -1:
			if close == -1 or close <= open:
				debug_print("[color=coral]Malformed argument section in '%s'[/color]" % token)
				return
			dtype_key = dtype_full.substr(0, open).strip_edges()
			if dtype_key not in type_map:
				debug_print("[color=coral]Unknown datatype: %s[/color]" % dtype_key)
				return
			arg_pack = _parse_col_args(dtype_full, dtype_key)
			if arg_pack == null:
				return
		if dtype_key not in type_map:
			debug_print("[color=coral]Unknown datatype: %s[/color]" % dtype_key)
			return


		var dtype = type_map[dtype_key]
		col_names.append("%s:%s" % [col_name, dtype])
		dtypes.append(dtype)
		var converted = _conv_args(arg_pack, dtype)
		if converted is String:
			debug_print("[color=coral]Cannot convert argument %s" % converted)
			return
		arg_packs.append(converted)

	# --- Autoconversion handling (kept from your old logic) ---
	if table.rows and table.column_datatypes.size() > 0:
		for j in range(min(dtypes.size(), table.column_datatypes.size())):
			var old_dtype = table.column_datatypes[j]
			var new_dtype = dtypes[j]
			if old_dtype != new_dtype:
				if not force:
					debug_print("[color=coral]Column datatype mismatch at column %d. Use --force to autoconvert.[/color]" % j)
					return
				else:
					debug_print("[color=gray]Auto-converting column %d to %s...[/color]" % [j, new_dtype])
					_convert_column(j, new_dtype, true)

	var cols = len(col_names)
	var idx: int = -1
	for j in range(cols, table.cols):
		table.destroy_column_cache(-1)
	for j in range(table.cols, cols):
		table.create_column_cache(-1)
	for r in dataset:
		idx += 1
		var new_r = []
		for i in cols:
			if i >= len(r):
				
				var type = dtypes[i]
				var def = table.get_type_default(type)
				def["type"] = type
				new_r.append(def)
				table.mark_created(idx, i, def)
			else:
				new_r.append(r[i])
		r.clear()
		for i in new_r:
			r.append(i)

	# --- Apply to table ---
	table.cols = cols
	table.set_column_arg_packs(arg_packs)
	table.set_column_names(col_names, true)
	table.dataset_obj["col_names"] = col_names

	var float32 = PackedFloat32Array()
	float32.resize(table.cols)
	float32.fill(1.0 / table.cols)
	table.set_column_ratios(float32)
	table._rebuild_column_metrics()
	table._need_layout = true
	table._need_visible_refresh = true

	dataset_updated(true)
	table.re_uni()
	table.active_remap()
	debug_print("Columns set to: %s" % str(col_names))
	table.refresh_preview()







# ---- FILTER ----
func _on_filter_command(data: Dictionary):
	var cond = data["args"].get("condition", "")
	var action = data["args"].get("action", "keep")

	#if cond == "":
		## Run filter flags without condition
		#if data["flags"].is_empty():
			#debug_print("Filter: no condition or flags provided.")
			#return
		#debug_print("Filter flags applied: %s" % str(data["flags"]))
		#return

	var expr = Expression.new()
	#(cond)
	if expr.parse(cond, ["row"]) != OK:
		debug_print("Invalid expression: %s" % expr.get_error_text())
		return
	#table.dirtify()

	var new_ds: Array = []
	for row in len(dataset):
		var ok = expr.execute([row])
		if (ok and action == "keep") or (not ok and action == "drop"):
			new_ds.append(dataset[row])
		else:
			for i in table.cols:
				table.mark_destroyed(row, i)
	dataset = new_ds
	table._clear_hover()
	if new_ds:
		table.load_dataset(dataset, table.cols, len(new_ds))
	else:
		table.load_empty_dataset(false, dataset)
	#dataset_updated(true)
	debug_print("Filter applied. Rows: %d" % dataset.size())
	await get_tree().process_frame
	table.dirtify()


# ---- SHUFFLE ----
func _on_shuffle_command(_data: Dictionary):
	dataset.shuffle()
	dataset_updated(true)
	debug_print("Dataset shuffled.")
	await get_tree().process_frame
	table.dirtify()

func _on_delete_command(_data: Dictionary):
	table.delete_myself()
	dataset_updated(true)
	debug_print("Dataset deleted.")
	#table.dirtify()


# ---- DROP ----
func _on_drop_command(_data: Dictionary):
	dataset.clear()
	table.cl_cache()
	dataset_updated(true)
	debug_print("Dataset dropped.")

func _parse_col_args(raw_token: String, dtype: String):
	var args_dict: Dictionary = {}

	# --- find parentheses ---
	var open_idx = raw_token.find("(")
	var close_idx = raw_token.rfind(")")

	if open_idx == -1 and close_idx == -1:
		# normal token like hi:txt — no args
		return {}

	if open_idx == -1 or close_idx == -1 or close_idx <= open_idx:
		debug_print("[color=coral]Malformed argument section in '%s'[/color]" % raw_token)
		return null

	var inside = raw_token.substr(open_idx + 1, close_idx - open_idx - 1).strip_edges()
	if inside == "":
		# empty parentheses — allowed but meaningless
		return {}

	var parts = inside.split(",", false)
	var schema: Array = []
	if dtype not in type_map:
		debug_print("[color=coral]Unknown datatype: %s[/color]" % dtype)
		return false
	schema = table.get_arg_schema(type_map[dtype])

	for i in range(parts.size()):
		var part = parts[i].strip_edges()
		if part == "":
			continue

		if part.find("=") != -1:
			var kv = part.split("=", false)
			if kv.size() != 2:
				debug_print("[color=coral]Malformed argument: %s[/color]" % part)
				return {}
			var key = kv[0].strip_edges()
			var val = kv[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
			if schema.size() > 0 and key not in schema:
				debug_print("[color=coral]Unknown argument '%s' for type '%s'. Allowed: %s[/color]" %
					[key, dtype, str(schema)])
				return null
			args_dict[key] = val
		else:
			# positional mapping
			if i >= schema.size():
				debug_print("[color=coral]Too many positional args for type '%s'. Allowed: %s[/color]" %
					[dtype, str(schema)])
				return null
			var key = schema[i]
			var val = part.trim_prefix("\"").trim_suffix("\"")
			args_dict[key] = val

	return args_dict



var type_map = {"txt": "text","float": "float",  "num": "num", "img": "image", "text": "text", "str": "text", "int": "num", "image": "image"}
func _parse_inline_cells(expr: String) -> Array:
	var cells: Array = []
	var buf := ""
	var depth := 0

	# --- Stage 1: tokenize into (...) or raw ---
	for ch in expr:
		if ch == "(":
			if depth == 0 and buf.strip_edges() != "":
				cells.append(buf.strip_edges())
				buf = ""
			depth += 1
			buf += ch
		elif ch == ")":
			buf += ch
			depth -= 1
			if depth == 0:
				cells.append(buf.strip_edges())
				buf = ""
		elif (ch == " " or ch == ",") and depth == 0:
			if buf.strip_edges() != "":
				cells.append(buf.strip_edges())
				buf = ""
		else:
			buf += ch
	if buf.strip_edges() != "":
		cells.append(buf.strip_edges())

	# --- Stage 2: normalize into per-cell dictionaries ---
	var out: Array = []

	for j in range(cells.size()):
		var token = cells[j].strip_edges()
		var dtype = "text"
		if j < table.column_datatypes.size():
			dtype = table.column_datatypes[j]

		var base_field = "value"
		var cell_default = table.cell_defaults.get(dtype, null)
		base_field = cell_default["base_field"]

		var cell_dict: Dictionary = {}

		if not token.begins_with("("):
			cell_dict[base_field] = token.trim_prefix("\"").trim_suffix("\"")
			out.append(cell_dict)
			continue

		var inside = token.substr(1, token.length() - 2).strip_edges()
		if inside == "":
			cell_dict[base_field] = ""
			out.append(cell_dict)
			continue

		var pairs = inside.split(",", false)
		for p in pairs:
			var kv = p.strip_edges().split("=", false)
			if kv.size() == 2:
				var key = kv[0].strip_edges()
				var val = kv[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
				cell_dict[key] = val
			elif kv.size() == 1 and kv[0] != "":
				cell_dict[base_field] = kv[0].strip_edges().trim_prefix("\"").trim_suffix("\"")

		if cell_dict.is_empty():
			cell_dict[base_field] = inside.trim_prefix("\"").trim_suffix("\"")

		out.append(cell_dict)

	return out



func _on_nrow_command(_data: Dictionary):
	var line = text.strip_edges().strip_escapes()
	var parts = line.split(" ", false)

	if parts.size() == 1:
		if table.cols == 0:
			debug_print("[color=coral]Cannot add row: no columns defined.[/color]")
			return
		var def_row = table.get_default_row()
		table.add_row(def_row)
		#for i in def_row:
		#	table.mark_created(table.rows, i, def_row[i])
		dataset = table.adapter_data
		debug_print("Default row appended.")
		return

	var idx := -1
	var row_expr := ""

	if parts[1].is_valid_int():
		idx = int(parts[1])
		row_expr = line.substr(line.find(parts[1]) + parts[1].length()).strip_edges()
	else:
		row_expr = line.substr(line.find(parts[0]) + parts[0].length()).strip_edges()

	if row_expr == "":
		if table.cols == 0:
			debug_print("[color=coral]Cannot add row: no columns defined.[/color]")
			return
		var def_row2 = table.get_default_row()
		table.add_row(def_row2, idx)
		#for i in def_row2:
		#	table.mark_created(table.rows, i, def_row2[i])
		dataset = table.adapter_data
		debug_print("Default row inserted.")
		return

	var raw_cells = _parse_inline_cells(row_expr)

	if raw_cells.size() != table.cols:
		debug_print("[color=coral]Row rejected: expected %d columns, got %d.[/color]" % [table.cols, raw_cells.size()])
		return

	var final_row: Array = []

	for j in table.cols:
		var col_dtype: String = table.column_datatypes[j]
		var cell_dict: Dictionary = raw_cells[j]
		var converter = table.cell_defaults.get(col_dtype)

		if converter == null:
			debug_print("[color=coral]Missing converter for %s[/color]" % col_dtype)
			return

		var converted_dict: Dictionary = {}
		var failed: bool = false

		for field_name in cell_dict.keys():
			var raw_value = cell_dict[field_name]
			var conv = converter._field_convert(field_name, raw_value)
			if conv == null:
				debug_print("[color=coral]Cannot convert '%s=%s' to %s in column %d[/color]" %
					[field_name, str(raw_value), col_dtype, j])
				failed = true
				break
			converted_dict[field_name] = conv

		if failed:
			return

		#table.mark_destroyed(idx, j)
		var new_cell = table.get_type_default(col_dtype)
		#table.mark_created(idx, j, new_cell)
		new_cell["type"] = col_dtype

		for k in converted_dict:
			new_cell[k] = converted_dict[k]
		

		final_row.append(new_cell)

	table.add_row(final_row, idx)
	dataset = table.adapter_data
	debug_print("Row appended.")




func _on_drow_command(data: Dictionary):
	var parts = text.strip_edges().split(" ", false)
	if parts.size() < 2:
		debug_print("Usage: drow <index>")
		return
	var idx = int(parts[1])
	#(table.adapter_data)
	if idx < -table.rows or idx >= table.rows:
		debug_print("Invalid row index.")
		return
	if idx < 0:
		idx += table.rows
	table.remove_row(idx)
	debug_print("Row removed at %d." % idx)
	dataset = table.adapter_data
