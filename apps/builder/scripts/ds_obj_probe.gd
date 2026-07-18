extends Node
class_name DsObjProbe

# =========================
# BitReader (unchanged)
# =========================
class _BitReader:
	var _data: PackedByteArray
	var _bit_pos: int
	var _total_bits: int

	func _init(buf: PackedByteArray) -> void:
		_data = buf
		_bit_pos = 0
		_total_bits = buf.size() * 8

	func set_pos(bitpos: int) -> void:
		_bit_pos = clamp(bitpos, 0, _total_bits)

	func pop(bits: int) -> int:
		var v = 0
		for i in range(bits):
			var byte_i = _bit_pos >> 3
			if byte_i >= _data.size():
				break
			var bit_i = 7 - (_bit_pos & 7)
			var b = (_data[byte_i] >> bit_i) & 1
			v = (v << 1) | b
			_bit_pos += 1
		return v


# =========================================================
# RLE decoder (kept minimal, same semantics)
# =========================================================
static func _rle_decode(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var i := 0
	while i + 2 < data.size():
		var cnt = (data[i] << 8) | data[i + 1]
		var val = data[i + 2]
		for _j in range(cnt):
			out.append(val)
		i += 3
	return out


# =========================================================
# Adaptive block decoder (1-byte flag prefix)
# =========================================================
static func _decode_block(block: PackedByteArray) -> PackedByteArray:
	if block.is_empty():
		return PackedByteArray()
	var flag = block[0]
	var payload = block.slice(1, block.size())
	match flag:
		0:
			return payload
		1:
			return _rle_decode(payload)
		_:
			return payload


# =========================================================
# Probe: safe preview of numeric, float, text, image columns
# =========================================================
static func probe_dataset(name: String, sample_rows: int = 3, from_row: int = 0, to_row: int = -1) -> Dictionary:
	if not glob.rle_cache.has(name):
		return {"ok": false, "reason": "no cache entry"}

	var cached: Dictionary = glob.rle_cache[name]
	if not cached.has("header") or not cached.has("data"):
		return {"ok": false, "reason": "incomplete cache"}

	var header: Dictionary = cached["header"]
	var inputs: Array = cached["data"][0]
	var outputs: Array = cached["data"][1]

	var total_rows: int = int(header.get("rows", 0))
	var rpb: int = int(header.get("rows_per_block", DsObjRLE.BLOCK_ROWS_DEFAULT))
	if rpb <= 0:
		rpb = 256

	# ---- normalize range ----
	if to_row < 0:
		to_row = total_rows + to_row + 1
	if from_row < 0:
		from_row = total_rows + from_row
	from_row = clamp(from_row, 0, total_rows)
	to_row = clamp(to_row, from_row, total_rows)

	var span = max(0, to_row - from_row)
	var rows_to_show = min(sample_rows, (span if span > 0 else total_rows))
	if rows_to_show <= 0:
		return {"ok": false, "reason": "empty range"}

	var info := {
		"ok": true,
		"name": name,
		"rows": total_rows,
		"inputs": header.get("inputs_count", inputs.size()),
		"outputs": header.get("outputs_count", outputs.size()),
		"sample": {},
		"errors": [],
	}

	# ---------------- helpers ----------------

	var _col_meta = func(col_i: int) -> Dictionary:
		return header.get("columns", {}).get(str(col_i), {})

	var _decode_num_block = func(block: PackedByteArray, meta: Dictionary) -> PackedInt32Array:
		var mn: int = int(meta.get("min", 0))
		var mx: int = int(meta.get("max", 100))
		var rng: int = max(1, mx - mn)
		var w: int = 1
		if rng > 255: w = 2
		if rng > 65535: w = 4

		var dec = _decode_block(block)
		var nvals = int(dec.size() / w)
		var out := PackedInt32Array()
		out.resize(nvals)

		var ri = 0
		for i in range(nvals):
			var v: int = 0
			if w == 1:
				v = int(dec[ri])
				ri += 1
			elif w == 2:
				v = (int(dec[ri]) << 8) | int(dec[ri + 1])
				ri += 2
			else:
				v = (int(dec[ri]) << 24) | (int(dec[ri + 1]) << 16) | (int(dec[ri + 2]) << 8) | int(dec[ri + 3])
				ri += 4
			out[i] = v + mn
		return out

	var _decode_float_block = func(block: PackedByteArray) -> PackedFloat32Array:
		var dec = _decode_block(block)
		var out := PackedFloat32Array()
		out.resize(dec.size())
		for i in range(dec.size()):
			out[i] = float(dec[i]) / 255.0
		return out

	var _decode_text_block = func(block: PackedByteArray) -> Array:
		var dec = _decode_block(block)
		var out: Array = []
		var cur := []
		for b in dec:
			if b == 0:
				out.append("".join(cur))
				cur.clear()
			else:
				cur.append(char(b))
		if not cur.is_empty():
			out.append("".join(cur))
		return out

	# --- main per-type accessors ---
	var _get_at = func(col_entry: Dictionary, col_i: int, logical_row: int, dtype: String) -> Variant:
		var block_idx = logical_row / rpb
		var within = logical_row - block_idx * rpb
		var blocks: Array = col_entry.get("blocks", [])
		if block_idx < 0 or block_idx >= blocks.size():
			return null
		var block = blocks[block_idx]
		if dtype == "num":
			var vals = _decode_num_block.call(block, _col_meta.call(col_i))
			return (vals[within] if within < vals.size() else 0)
		elif dtype == "float":
			var vals = _decode_float_block.call(block)
			return (vals[within] if within < vals.size() else 0.0)
		elif dtype == "text":
			var vals = _decode_text_block.call(block)
			return (vals[within] if within < vals.size() else "")
		elif dtype == "image":
			var raw = _decode_block(block)
			return str(raw.size()) + " bytes img"
		else:
			return "unknown"

	var _extract_preview = func(side: Array, offset: int, label: String):
		var side_samples: Dictionary = {}
		for i in range(side.size()):
			var col_entry: Dictionary = side[i]
			var col_i = i + offset
			var dtype: String = str(col_entry.get("dtype", header.get("columns", {}).get(str(col_i), {}).get("dtype", "unknown")))
			var vals: Array = []
			for k in range(rows_to_show):
				vals.append(_get_at.call(col_entry, col_i, from_row + k, dtype))
			side_samples["col_%d:%s" % [col_i, dtype]] = vals
		info["sample"][label] = side_samples

	# --- run ---
	_extract_preview.call(inputs, 0, "inputs")
	_extract_preview.call(outputs, int(header.get("inputs_count", 0)), "outputs")

	return info
