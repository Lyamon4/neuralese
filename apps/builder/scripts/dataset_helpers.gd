extends Node

func _normalize_newlines(raw: String) -> String:
	return raw.replace("\r\n", "\n").replace("\r", "\n")


# --- Fast heuristic: detect UTF-8 vs Windows-1251 ---
func _detect_encoding(bytes: PackedByteArray) -> String:
	# UTF-8 BOM check
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return "utf-8"
	# Fast UTF-8 validity check
	var utf8_text := bytes.get_string_from_utf8()
	if utf8_text.find("�") == -1 and utf8_text.is_valid_identifier() == false:
		# no replacement chars: valid UTF-8
		return "utf-8"
	# Otherwise assume CP1251
	return "cp1251"


# --- Efficient CP1251 decode table ---
var _cp1251_table := {
	0xA8: "Ё", 0xB8: "ё"
}
func _decode_cp1251(bytes: PackedByteArray) -> String:
	var sb := ""
	for b in bytes:
		if b >= 0xC0 and b <= 0xFF:
			sb += char(0x410 + b - 0xC0)
		elif _cp1251_table.has(b):
			sb += _cp1251_table[b]
		else:
			sb += char(b)
	return sb


func parse_csv_lines(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return []

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("Failed to open CSV: " + path)
		return []

	# Read once
	var bytes := f.get_buffer(f.get_length())
	f.close()

	# Detect encoding quickly
	var enc := _detect_encoding(bytes)
	var text := ""
	if enc == "utf-8":
		text = bytes.get_string_from_utf8()
	else:
		text = _decode_cp1251(bytes)

	text = _normalize_newlines(text)

	# Detect delimiter from preview
	var delim := detect_csv_delimiter_from_preview(text)

	var rows: Array = []
	for line in text.split("\n", false):
		line = line.strip_edges()
		if line != "":
			rows.append(line.split(delim, false))
	return rows


func detect_csv_delimiter_from_preview(preview_text: String) -> String:
	var delimiters = [",", ";", "\t", "|", " "]
	var lines: Array = []
	preview_text = _normalize_newlines(preview_text)

	for l in preview_text.split("\n", false):
		l = l.strip_edges()
		if l == "":
			continue
		lines.append(l)
		if lines.size() >= 50: # smaller sample for speed
			break

	if lines.size() < 2:
		return ","

	var best := ","
	var best_score := -INF
	for d in delimiters:
		var total := 0
		var counts: Array[int] = []
		for l in lines:
			var c = l.count(d)
			total += c
			counts.append(l.split(d, false).size())
		if total == 0:
			continue
		var mean := 0.0
		for c in counts: mean += c
		mean /= counts.size()
		var var_ := 0.0
		for c in counts: var_ += abs(c - mean)
		var_ /= counts.size()
		var score := ((mean - 1.0) * total) / (1.0 + var_)
		if score > best_score:
			best_score = score
			best = d
	return best

func _row_to_cells(row: Array) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for i in row:
		res.append({"type": "text", "text": i})
	return res


func parse_csv_dataset(path: String) -> Dictionary:
	var ds_obj = {"col_names": [], "arr": [], "outputs_from": 1}
	if not FileAccess.file_exists(path):
		return glob.default_dataset()
	var rows = parse_csv_lines(path)
	if not rows:
		ds_obj["col_names"] = ["Col0:text", "Col1:text"]
		return ds_obj

	ds_obj["outputs_from"] = min(len(rows[0]), int(ceil(float(len(rows[0])) / 2)))

	if len(rows) == 1:
		ds_obj.col_names = []
		for i in len(rows[0]):
			ds_obj.col_names.append("Col" + str(i) + ":text")
		ds_obj.arr.append(_row_to_cells(rows[0]))
		return ds_obj

	ds_obj.col_names = rows[0]
	for i in len(ds_obj.col_names):
		ds_obj.col_names[i] += ":text"

	for i in range(1, len(rows)):
		if len(rows[i]) == len(rows[0]):
			ds_obj.arr.append(_row_to_cells(rows[i]))

	ds_obj.merge(glob.default_dataset().duplicate(true))
	return ds_obj
