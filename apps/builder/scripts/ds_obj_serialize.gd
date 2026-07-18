class_name DsObjRLE

# Auto-sized: smaller blocks reduce suffix rebuild cost,
# larger blocks keep headers smaller on very big datasets.
const BLOCK_ROWS_DEFAULT: int = 256
const UNSAFE_FAST_HASH := true   # set false for stronger but slower hashing

# =========================
# Preview (unchanged API)
# =========================
static func get_preview(dataset_obj: Dictionary, validate_cols: bool = false) -> Dictionary:
	if not dataset_obj or not dataset_obj.has("arr"):
		return {"fatal": "no_dataset", "fail": true}
	var arr: Array = dataset_obj["arr"]
	if arr.is_empty():
		return {"fatal": "empty", "fail": true}
	var cols: int = (arr[0].size() if arr.size() > 0 else 0)
	if cols <= 0:
		return {"fatal": "no_columns", "fail": true}

	var col_names: Array = dataset_obj.get("col_names", [])
	if col_names.is_empty():
		return {"fatal": "missing_schema", "fail": true}

	var col_dtypes: Array = []
	for name in col_names:
		var parts = name.rsplit(":", true, 1)
		col_dtypes.append(parts[1] if parts.size() > 1 else "text")

	var outputs_from: int = dataset_obj.get("outputs_from", 1)
	var cache_cols: Array = dataset_obj.get("cache", {}).get("cols", [])
	if cols == 1:
		return {"fail": "no_outputs"}

	var res: Dictionary = {
		"size": arr.size(),
		"name": dataset_obj.get("name", "unnamed"),
		"input_hints": [],
	}

	var cur_out = {"label_names": [], "datatype": "1d", "x": 0, "label": "Output"}
	for i in range(outputs_from, cols):
		if i >= col_dtypes.size() or col_dtypes[i] == "image":
			return {"fail": "no_1d_outs"}
		if col_dtypes[i] == "text":
			return {"fail": "preprocess_txt"}
		cur_out["label_names"].append(col_names[i].split(":")[0])
		cur_out["x"] = cols-outputs_from
	res["outputs"] = [cur_out]
	#(res)

	var inputs: Dictionary = {"datatype": "", "x": 0}
	var to_validate = -1
	for i in range(0, max(1, outputs_from)):
		var dt = col_dtypes[i]
		if dt == "text":
			return {"fail": "preprocess_txt"}
		if dt == "image":
			if inputs["datatype"]:
				return {"fail": "mix_2d"}
			inputs["datatype"] = "2d"
			to_validate = i
		else:
			if inputs["datatype"] == "2d":
				return {"fail": "mix_2d"}
			inputs["datatype"] = "1d(len:1)"
			inputs["x"] += 1
			res["input_hints"].append({
				"name": col_names[i].split(":")[0],
				"value": ds_to_val(dataset_obj, i),
				"dtype": col_dtypes[i]
			})
	
	#(cache_cols[0])
	var got_x: int = 0
	var got_y = null
	var dt = "1d"
	if to_validate != -1:
		dt = "2d"
		if cache_cols.is_empty() or to_validate >= cache_cols.size():
			return {"fail": "bad_img"}
		var got_col_container = cache_cols[to_validate]
		var got: Dictionary = {}
	#	if got_col_container.size() == 1 and got_col_container.has(0):
		#	got = got_col_container[0]
		#else:
		got = got_col_container
		#(got)
		if got.is_empty() or got.size() != 1 or got.keys()[0] == 0:
			return {"fail": "bad_img"}
		var key: int = got.keys()[0]
		var xs = key >> 16
		var ys = key & 0xFFFF
		got_y = ys
		if xs <= 0 or ys <= 0:
			return {"fail": "bad_img"}
		got_x = xs; got_y = ys
		res["input_hints"].append({
			"name": col_names[to_validate].split(":")[0],
			"value": str(xs) + "x" + str(ys),
			"dtype": "image"
		})
	else:
		got_x = dataset_obj.outputs_from
	#("REGOT!!!")
	res["inputs"] = {"x": got_x, "datatype": dt}
	if got_y != null:
		res["inputs"]["y"] = got_y
	#(res)
	return res


# =========================
# Helpers / cache
# =========================
static func _derive_col_dtypes(col_names: Array) -> Array:
	var out := []
	for n in col_names:
		var spl = n.rsplit(":", true, 1)
		out.append(spl[1] if spl.size() > 1 else "text")
	return out

static func _choose_block_rows(rows: int) -> int:
	# Heuristic: keep suffix cost small on typical 10k–100k sets,
	# relax for 200k+ to keep metadata lighter.
	if rows <= 100_000:
		return 256
	elif rows <= 300_000:
		return 512
	else:
		return 1024

static func _ensure_cache(name: String) -> Dictionary:
	if not glob.rle_cache.has(name):
		glob.rle_cache[name] = {}
	var c = glob.rle_cache[name]
	if not c.has("header"):
		c["header"] = {}
	if not c.has("data"):
		c["data"] = [[], []]
	if not c["header"].has("dirty_from"):
		c["header"]["dirty_from"] = -1
	return c

static func _mark_dirty_from(cache: Dictionary, idx: int) -> void:
	var hdr = cache["header"]
	if not hdr.has("dirty_from") or hdr["dirty_from"] == -1:
		hdr["dirty_from"] = idx
	else:
		hdr["dirty_from"] = min(hdr["dirty_from"], idx)
	cache["header"] = hdr

static func _clear_dirty(cache_or_full: Dictionary) -> void:
	# Works for both cache stub and full packed object
	if cache_or_full.has("header"):
		cache_or_full["header"]["dirty_from"] = -1

static func _cc(ds: Dictionary) -> Array:
	if not ds.has("cache"):
		ds["cache"] = {}
	if not ds["cache"].has("cols"):
		ds["cache"]["cols"] = []
	return ds["cache"]["cols"]

static func _ensure_col_entry(ds: Dictionary, col: int, dtype: String) -> Dictionary:
	var cols: Array = _cc(ds)
	if cols.size() <= col:
		var old = cols.size()
		cols.resize(col + 1)
		for i in range(old, col + 1):
			cols[i] = {}
	var e: Dictionary = cols[col]
	if not e.has("dtype"):
		e["dtype"] = dtype
	elif String(e["dtype"]) != dtype:
		e.clear(); e["dtype"] = dtype
	cols[col] = e
	ds["cache"]["cols"] = cols
	return e

static func _build_num_full(ds: Dictionary, col: int) -> PackedInt32Array:
	var arr: Array = ds["arr"]
	var out := PackedInt32Array()
	out.resize(arr.size())
	for r in range(arr.size()):
		out[r] = int(arr[r][col].get("num", 0))
	return out

static func _build_float_full(ds: Dictionary, col: int) -> PackedByteArray:
	var arr: Array = ds["arr"]
	var out := PackedByteArray()
	out.resize(arr.size())
	for r in range(arr.size()):
		var v: float = float(arr[r][col].get("val", 0.0))
		out[r] = clamp(int(v * 255.0), 0, 255)
	return out

static func _ensure_num_cache(ds: Dictionary, col: int) -> PackedInt32Array:
	var dtypes = ds.get("col_dtypes", [])
	var dtype = (dtypes[col] if col < dtypes.size() else "num")
	var e = _ensure_col_entry(ds, col, dtype)
	if not e.has("num_vals") or e["num_vals"].size() != ds["arr"].size():
		e["num_vals"] = _build_num_full(ds, col)
	return e["num_vals"]

static func _ensure_float_cache(ds: Dictionary, col: int) -> PackedByteArray:
	var dtypes = ds.get("col_dtypes", [])
	var dtype = (dtypes[col] if col < dtypes.size() else "float")
	var e = _ensure_col_entry(ds, col, dtype)
	if not e.has("float_q") or e["float_q"].size() != ds["arr"].size():
		e["float_q"] = _build_float_full(ds, col)
	return e["float_q"]

static func _hash_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var digest: PackedByteArray = ctx.finish()
	var s := ""
	for b in digest:
		s += "%02x" % b
	return s

# =========================
# RLE builders
# =========================
static func _int_width(mn: int, mx: int) -> int:
	var r = max(1, mx - mn)
	if r <= 255: return 1
	if r <= 65535: return 2
	return 4

static func _rle_push(rle_buf: PackedByteArray, last_byte: int, last_cnt: int, b: int) -> Array:
	if last_cnt == 0:
		return [b, 1]
	if b == last_byte and last_cnt < 65535:
		return [b, last_cnt + 1]
	rle_buf.append(last_cnt >> 8)
	rle_buf.append(last_cnt & 0xFF)
	rle_buf.append(last_byte)
	return [b, 1]

static func _rle_flush_tail(buf: PackedByteArray, last_b: int, last_cnt: int) -> void:
	if last_cnt > 0:
		buf.append(last_cnt >> 8)
		buf.append(last_cnt & 0xFF)
		buf.append(last_b)

# --- block encoders ---
static func _build_block_num_stream(raw_ints: PackedInt32Array, s: int, e: int, bias: int, w: int) -> PackedByteArray:
	var rows = max(0, e - s)
	if rows == 0:
		var p := PackedByteArray(); p.append(0); return p
	var raw := PackedByteArray(); raw.resize(rows * w)
	var rle := PackedByteArray()
	var lb = -1; var lc = 0; var ri = 0
	for r in range(s, e):
		var v = raw_ints[r] - bias
		if w == 1:
			var b0 = clamp(v, 0, 255)
			raw[ri] = b0; ri += 1
			var tmp = _rle_push(rle, lb, lc, b0); lb = tmp[0]; lc = tmp[1]
		elif w == 2:
			var b0 = (v >> 8) & 0xFF
			var b1 = v & 0xFF
			raw[ri] = b0; ri += 1
			raw[ri] = b1; ri += 1
			var t0 = _rle_push(rle, lb, lc, b0); lb = t0[0]; lc = t0[1]
			var t1 = _rle_push(rle, lb, lc, b1); lb = t1[0]; lc = t1[1]
		else:
			var b0 = (v >> 24) & 0xFF
			var b1 = (v >> 16) & 0xFF
			var b2 = (v >> 8) & 0xFF
			var b3 = v & 0xFF
			raw[ri] = b0; ri += 1
			raw[ri] = b1; ri += 1
			raw[ri] = b2; ri += 1
			raw[ri] = b3; ri += 1
			var t0 = _rle_push(rle, lb, lc, b0); lb = t0[0]; lc = t0[1]
			var t1 = _rle_push(rle, lb, lc, b1); lb = t1[0]; lc = t1[1]
			var t2 = _rle_push(rle, lb, lc, b2); lb = t2[0]; lc = t2[1]
			var t3 = _rle_push(rle, lb, lc, b3); lb = t3[0]; lc = t3[1]
	_rle_flush_tail(rle, lb, lc)
	if 1 + rle.size() < 1 + raw.size():
		var o := PackedByteArray(); o.append(1); o.append_array(rle); return o
	var o2 := PackedByteArray(); o2.append(0); o2.append_array(raw); return o2

static func _build_block_float_stream(q: PackedByteArray, s: int, e: int) -> PackedByteArray:
	var rows = max(0, e - s)
	if rows == 0:
		var o := PackedByteArray(); o.append(0); return o
	var raw := PackedByteArray(); raw.resize(rows)
	var rle := PackedByteArray(); var lb = -1; var lc = 0
	for i in range(s, e):
		var b0 = q[i]; raw[i - s] = b0
		var t = _rle_push(rle, lb, lc, b0); lb = t[0]; lc = t[1]
	_rle_flush_tail(rle, lb, lc)
	if 1 + rle.size() < 1 + raw.size():
		var o := PackedByteArray(); o.append(1); o.append_array(rle); return o
	var o2 := PackedByteArray(); o2.append(0); o2.append_array(raw); return o2

static func _build_block_text(arr: Array, col: int, s: int, e: int) -> PackedByteArray:
	var raw := PackedByteArray()
	for r in range(s, e):
		var s0 = str(arr[r][col].get("text", ""))
		raw.append_array(s0.to_utf8_buffer()); raw.append(0)
	var o := PackedByteArray(); o.append(0); o.append_array(raw); return o

static func remove_column(ds: Dictionary, name: String, col_idx: int) -> void:
	var arr: Array = ds["arr"]
	if arr.is_empty():
		return
	
	var cols: int = arr[0].size()
	if col_idx < 0 or col_idx >= cols:
		return
	
	# 1. Remove from raw dataset
	for row in arr:
		row.remove_at(col_idx)
	
	# 2. Update metadata
	if ds.has("col_names") and col_idx < ds["col_names"].size():
		ds["col_names"].remove_at(col_idx)
	if ds.has("col_dtypes") and col_idx < ds["col_dtypes"].size():
		ds["col_dtypes"].remove_at(col_idx)
	if ds.has("col_args") and col_idx < ds["col_args"].size():
		ds["col_args"].remove_at(col_idx)
	
	# 3. Adjust outputs_from
	var outputs_from: int = ds.get("outputs_from", 0)
	if col_idx < outputs_from:
		ds["outputs_from"] = outputs_from - 1
	
	# 4. Remove from cache
	if ds.has("cache") and ds["cache"].has("cols"):
		var cache_cols: Array = ds["cache"]["cols"]
		if col_idx < cache_cols.size():
			cache_cols.remove_at(col_idx)
	
	glob.rle_cache.erase(name)
	# Next compress_blocks() or recompress_changed_blocks() will rebuild from scratch


static func _build_block_image(arr: Array, col: int, s: int, e: int) -> PackedByteArray:
	var raw := PackedByteArray()
	for r in range(s, e):
		var cell = arr[r][col]
		if cell.has("img") and cell["img"] != null:
			var img: Image
			if not cell["img"] is EncodedObjectAsID:
				img = cell["img"].get_image()
			else:
				cell["img"] = null
				continue
			raw.append_array(img.get_data())
	var o := PackedByteArray(); o.append(0); o.append_array(raw); return o

# --- multi-block builder ---
static func _build_blocks_for_col(ds: Dictionary, col_idx: int, rows: int, rows_per_block: int, b_from: int, b_to: int) -> Array:
	var dtype: String = ds["col_dtypes"][col_idx]
	var blocks: Array = []; var hashes: Array = []
	var n = max(0, b_to - b_from); blocks.resize(n); hashes.resize(n)

	if dtype == "num":
		var mn:int = 0; var mx:int = 100
		if ds.has("col_args") and col_idx < ds["col_args"].size():
			var args: Dictionary = ds["col_args"][col_idx]
			mn = int(args.get("min", 0)); mx = int(args.get("max", 100))
		var w = _int_width(mn, mx)
		var ints = _ensure_num_cache(ds, col_idx)
		for bi in range(b_from, b_to):
			var s = bi * rows_per_block
			var e = min(s + rows_per_block, rows)
			var enc = _build_block_num_stream(ints, s, e, mn, w)
			var li = bi - b_from
			blocks[li] = enc
			hashes[li] = _hash_hex(enc)

	elif dtype == "float":
		var q = _ensure_float_cache(ds, col_idx)
		for bi in range(b_from, b_to):
			var s = bi * rows_per_block
			var e = min(s + rows_per_block, rows)
			var enc = _build_block_float_stream(q, s, e)
			var li = bi - b_from
			blocks[li] = enc
			hashes[li] = _hash_hex(enc)

	elif dtype == "text":
		var arr = ds["arr"]
		for bi in range(b_from, b_to):
			var s = bi * rows_per_block
			var e = min(s + rows_per_block, rows)
			var enc = _build_block_text(arr, col_idx, s, e)
			var li = bi - b_from
			blocks[li] = enc
			hashes[li] = _hash_hex(enc)

	else:
		var arr2 = ds["arr"]
		for bi in range(b_from, b_to):
			var s = bi * rows_per_block
			var e = min(s + rows_per_block, rows)
			var enc = _build_block_image(arr2, col_idx, s, e)
			var li = bi - b_from
			blocks[li] = enc
			hashes[li] = _hash_hex(enc)

	return [blocks, hashes, dtype]


# =========================
# Public: streaming build
# =========================
static func compress_blocks(ds: Dictionary) -> Dictionary:
	var arr: Array = ds["arr"]
	if arr.is_empty():
		return {"header": {"rows":0,"inputs_count":0,"outputs_count":0,"columns":{},"dirty_from":-1,"rows_per_block":BLOCK_ROWS_DEFAULT},"data":[[],[]]}

	var rows = arr.size()
	var cols = arr[0].size()
	var outputs_from = ds.get("outputs_from", 0)

	# Derive and prime caches
	ds["col_dtypes"] = _derive_col_dtypes(ds.get("col_names", []))
	for c in range(cols):
		match String(ds["col_dtypes"][c]):
			"num": _ensure_num_cache(ds, c)
			"float": _ensure_float_cache(ds, c)
			_: pass

	# Pick rows_per_block once at build (kept stable through suffixes)
	var rpb = _choose_block_rows(rows)

	var header = {
		"rows": rows,
		"inputs_count": outputs_from,
		"outputs_count": cols - outputs_from,
		"columns": {},
		"rows_per_block": rpb,
		"dirty_from": -1
	}

	var inputs := []
	var outputs := []
	var total_blocks = int(ceil(float(rows) / float(rpb)))

	for c in range(cols):
		var res = _build_blocks_for_col(ds, c, rows, rpb, 0, total_blocks)
		var col_data = {"blocks": res[0], "hashes": res[1], "rows_per_block": rpb, "dtype": String(res[2])}
		if c < outputs_from:
			inputs.append(col_data)
		else:
			outputs.append(col_data)

		var dtype = String(res[2])
		var meta = {"dtype": dtype}
		if dtype == "num":
			var mn = 0; var mx = 100
			if ds.has("col_args"):
				var ca: Array = ds["col_args"]
				if c < ca.size():
					var a: Dictionary = ca[c]
					mn = int(a.get("min", 0)); mx = int(a.get("max", 100))
			meta["min"] = mn; meta["max"] = mx
			meta["bits"] = _int_width(mn, mx) * 8
		header["columns"][str(c)] = meta

	return {"header": header, "data": [inputs, outputs]}


# =========================
# Incremental recompression (fast)
# =========================
static func recompress_changed_blocks(ds: Dictionary, changed_rows: Array) -> Dictionary:
#	print("rec...")
	var name = ds.get("name", "unnamed")
	var prev = glob.rle_cache.get(name, {})
	if prev.is_empty() or not prev.has("header"):
		var built = compress_blocks(ds)
		glob.rle_cache[name] = built
		return built

	if not ds.has("col_dtypes"):
		ds["col_dtypes"] = _derive_col_dtypes(ds.get("col_names", []))

	var rows = ds["arr"].size()
	var cols = ds["arr"][0].size()

	# keep per-column caches fresh so deltas rebuild correct bytes
	for c in range(cols):
		match String(ds["col_dtypes"][c]):
			"num": _ensure_num_cache(ds, c)
			"float": _ensure_float_cache(ds, c)
			_: pass

	var inputs_count   = prev["header"]["inputs_count"]
	var rows_per_block = int(prev["header"].get("rows_per_block", BLOCK_ROWS_DEFAULT))
	var total_blocks   = int(ceil(float(rows) / float(rows_per_block)))
	var header_dirty   = int(prev["header"].get("dirty_from", -1))

	# Suffix (insert/delete): rebuild from dirty_from to end, then publish rows
	if header_dirty != -1:
		var start_block = header_dirty / rows_per_block
		for side_i in [0, 1]:
			var side_arr: Array = prev["data"][side_i]
			var base_col = (0 if side_i == 0 else inputs_count)
			for k in range(side_arr.size()):
				var col_idx = base_col + k
				var col: Dictionary = side_arr[k]
				var blocks: Array = col["blocks"]
				var hashes: Array = col["hashes"]

				if blocks.size() < total_blocks:
					blocks.resize(total_blocks)
					hashes.resize(total_blocks)

				var res = _build_blocks_for_col(ds, col_idx, rows, rows_per_block, start_block, total_blocks)
				for bi in range(start_block, total_blocks):
					var li = bi - start_block
					blocks[bi] = res[0][li]
					hashes[bi] = res[1][li]

				col["blocks"] = blocks
				col["hashes"] = hashes
				side_arr[k] = col
			prev["data"][side_i] = side_arr

		# publish new rows exactly here, atomically with rebuilt blocks:
		prev["header"]["rows"] = rows
		prev["header"]["dirty_from"] = -1
		glob.rle_cache[name] = prev
		return prev

	# Delta (pure edits): rebuild touched blocks only
	_apply_row_deltas_to_caches(ds, changed_rows)

	var touched := {}
	for r in changed_rows:
		var rr = int(r)
		if rr >= 0 and rr < rows:
			touched[rr / rows_per_block] = true
	if touched.is_empty():
		# nothing to re-encode at block level; but caches are now up-to-date
		return prev

	for side_i in [0, 1]:
		var side_arr: Array = prev["data"][side_i]
		var base_col = (0 if side_i == 0 else inputs_count)
		for k in range(side_arr.size()):
			var col_idx = base_col + k
			var col: Dictionary = side_arr[k]
			var blocks: Array = col["blocks"]
			var hashes: Array = col["hashes"]

			if blocks.size() < total_blocks:
				blocks.resize(total_blocks)
				hashes.resize(total_blocks)

			for bstr in touched.keys():
				var b = int(bstr)
				var res = _build_blocks_for_col(ds, col_idx, rows, rows_per_block, b, b + 1)
				blocks[b] = res[0][0]
				hashes[b] = res[1][0]

			col["blocks"] = blocks
			col["hashes"] = hashes
			side_arr[k] = col
		prev["data"][side_i] = side_arr

	glob.rle_cache[name] = prev
	return prev




# =========================
# Edits (unchanged signatures)
# =========================
static func insert_rows(ds: Dictionary, name: String, at: int, new_rows: Array) -> void:
	var c = _ensure_cache(name)
	var arr: Array = ds["arr"]
	var tot = arr.size()
	at = clamp(at, 0, tot)
	# mark only; do NOT touch header.rows here
	_mark_dirty_from(c, at)
	glob.rle_cache[name] = c

static func delete_rows(ds: Dictionary, name: String, f: int, t: int) -> void:
	var c = _ensure_cache(name)
	var arr: Array = ds["arr"]
	var tot = arr.size()
	f = clamp(f, 0, tot)
	t = clamp(t, f, tot)
	# mark only; do NOT touch header.rows here
	_mark_dirty_from(c, f)
	glob.rle_cache[name] = c




# =========================
# Flush (unchanged signature)
# =========================
static func flush_now(name: String, ds: Dictionary) -> void:
	var c = _ensure_cache(name)
	if c.is_empty() or not c.has("header"):
		glob.rle_cache[name] = compress_blocks(ds)
		return
	var dirty = int(c["header"].get("dirty_from", -1))
	if dirty == -1:
		return
	var rebuilt = recompress_changed_blocks(ds, [])  # uses header.dirty_from suffix path
	var meta: Dictionary = rebuilt.get("meta", {"base_version": 0})
	meta["base_version"] = int(meta.get("base_version", 0)) + 1
	rebuilt["meta"] = meta
	_clear_dirty(rebuilt)
	glob.rle_cache[name] = rebuilt


# =========================
# Compatibility encoder (unchanged)
# =========================
static func encode_partial_column(ds: Dictionary, col: int, f: int, t: int) -> PackedByteArray:
	var dtypes = ds.get("col_dtypes", [])
	if col >= dtypes.size(): return PackedByteArray()
	var dtype = dtypes[col]
	match dtype:
		"num":
			var mn:int = 0; var mx:int = 100
			if ds.has("col_args") and col < ds["col_args"].size():
				var args: Dictionary = ds["col_args"][col]
				mn = int(args.get("min", 0)); mx = int(args.get("max", 100))
			var w = _int_width(mn, mx); var ints = _ensure_num_cache(ds, col)
			return _build_block_num_stream(ints, f, t, mn, w)
		"float":
			var q = _ensure_float_cache(ds, col); return _build_block_float_stream(q, f, t)
		"text":
			return _build_block_text(ds["arr"], col, f, t)
		"image":
			return _build_block_image(ds["arr"], col, f, t)
		_:
			return PackedByteArray()


# =========================
# Utility for previews
# =========================
static func ds_to_val(ds: Dictionary, col_idx: int) -> String:
	var col_dtypes = ds.get("col_dtypes", [])
	var col_args = ds.get("col_args", [])
	if col_idx >= col_dtypes.size(): return "_"
	var dt = col_dtypes[col_idx]
	var args = {}; if col_idx < col_args.size(): args = col_args[col_idx].duplicate(true)
	var defaults = {"text": {}, "num": {"min": 0, "max": 100}, "image": {}, "float": {}}
	args.merge(defaults.get(dt, {}), true)
	match dt:
		"num": return str(args.get("min", 0)) + "-\n" + str(args.get("max", 100))
		"float": return "0..1"
		"text": return "_"
		_: return "_"

static func _apply_row_deltas_to_caches(ds: Dictionary, changed_rows: Array) -> void:
	if changed_rows.is_empty():
		return
	if not ds.has("arr") or ds["arr"].is_empty():
		return

	# Ensure dtype list
	if not ds.has("col_dtypes"):
		ds["col_dtypes"] = _derive_col_dtypes(ds.get("col_names", []))

	var arr: Array = ds["arr"]
	var rows: int = arr.size()
	var cols: int = (arr[0].size() if rows > 0 else 0)


	for c in range(cols):
		var dtype := String(ds["col_dtypes"][c])

		if dtype == "num":
			# Make sure cache exists; then patch only the changed indices
			var num_vals: PackedInt32Array = _ensure_num_cache(ds, c)
			if num_vals.size() != rows:
				# hard resync if size drifted (rare in pure-delta)
				num_vals = _build_num_full(ds, c)
				var e = _ensure_col_entry(ds, c, dtype)
				e["num_vals"] = num_vals
			else:
				for rr in changed_rows:
					var r := int(rr)
					if r >= 0 and r < rows:
						num_vals[r] = int(arr[r][c].get("num", 0))

		elif dtype == "float":
			# Quantized 0..255 snapshot; patch only changed indices
			var float_q: PackedByteArray = _ensure_float_cache(ds, c)
			if float_q.size() != rows:
				float_q = _build_float_full(ds, c)
				var e = _ensure_col_entry(ds, c, dtype)
				e["float_q"] = float_q
			else:
				for rr in changed_rows:
					var r := int(rr)
					if r >= 0 and r < rows:
						var v: float = float(arr[r][c].get("val", 0.0))
						float_q[r] = clamp(int(v * 255.0), 0, 255)
		# text/image: blocks read arr directly, no per-row cache to patch
