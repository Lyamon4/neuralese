@tool
class_name DatasetSyntaxHighlighter
extends SyntaxHighlighter

const C_CMD     := Color8(255, 200, 100)  # Bold coral-orange
const C_META    := Color8(255, 220, 100)  # Bright sunny yellow
const C_ARG     := Color8(255, 140, 180)  # Vibrant pink
const C_STRING  := Color8(140, 240, 200)  # Bright mint/cyan
const C_NUMBER  := Color8(200, 160, 255)  # Rich lavender-purple
const C_COMMENT := Color.LIGHT_CORAL  # Muted blue-gray
const C_SYMBOL  := Color(0.476, 0.668, 0.78, 1.0)  # Soft silver
const C_FLAG    := Color8(140, 145, 150)  # Medium gray (for -- flags)
const C_DEFAULT := Color(1, 1, 1)


# ─────────────────────────────
#  DATA
# ─────────────────────────────
var keyword_groups: Dictionary = {}

# ─────────────────────────────
#  PUBLIC API
# ─────────────────────────────
func define_group(name: String, color: Color, words: PackedStringArray) -> void:
	keyword_groups[name] = {"color": color, "words": words.duplicate()}

func add_keyword_to_group(group_name: String, word: String, color: Color = Color.WHITE) -> void:
	if not keyword_groups.has(group_name):
		keyword_groups[group_name] = {"color": color, "words": PackedStringArray([])}
	if color != Color.WHITE:
		keyword_groups[group_name]["color"] = color
	keyword_groups[group_name]["words"].append(word)

func remove_group(name: String) -> void:
	if keyword_groups.has(name):
		keyword_groups.erase(name)

func clear_groups() -> void:
	keyword_groups.clear()

# ─────────────────────────────
#  HIGHLIGHT LOGIC
# ─────────────────────────────
func _highlight_symbols(s: String, regions: Array) -> void:
	for sym in ["[", "]", "<", ">", "=", "(", ")", "{", "}", ":", "/", "|", "-", "+", "*", ",", ".", "^"]:
		var pos := s.find(sym)
		while pos != -1:
			regions.append({"from": pos, "to": pos + 1, "color": C_SYMBOL})
			pos = s.find(sym, pos + 1)



func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var te := get_text_edit()
	if te == null:
		return {}
	var s := te.get_line(line)
	if s.is_empty():
		return {}

	var regions: Array = []   # {from,to,color}

	# --- numbers ---
	var i := 0
	while i < s.length():
		var c := s.unicode_at(i)
		if c >= 48 and c <= 57:
			var st := i
			while i < s.length() and s.unicode_at(i) >= 48 and s.unicode_at(i) <= 57:
				i += 1
			regions.append({"from": st, "to": i, "color": C_NUMBER})
			continue
		i += 1

	# --- comments ---
	#var comment_pos := s.find("#")
	#if comment_pos != -1:
	##	regions.append({"from": comment_pos, "to": s.length(), "color": C_COMMENT})

	# --- strings ---
	for q in ['"', "'"]:
		var start := 0
		while true:
			var pos := s.find(q, start)
			if pos == -1: break
			var end := s.find(q, pos + 1)
			if end == -1: end = s.length()
			regions.append({"from": pos, "to": end + 1, "color": C_STRING})
			start = end + 1

	# --- flags --flag ---
	i = 0
	while i < s.length() - 2:
		if s[i] == "-" and s[i + 1] == "-" and (i == 0 or s[i - 1] == " " or s[i - 1] == "\t"):
			var st := i
			var k := i + 2
			while k < s.length():
				var ch := s.unicode_at(k)
				if _is_word_char(ch) or ch == 45: # '-' allowed
					k += 1
				else:
					break
			regions.append({"from": st, "to": k, "color": C_FLAG})
			i = k
			continue
		i += 1

	# --- keywords ---
	_highlight_symbols(s, regions)
	for group in keyword_groups.values():
		var col: Color = group["color"]
		for word in group["words"]:
			var pos := s.findn(word)
			while pos != -1:
				var left_ok = pos == 0 or not _is_word_char(s.unicode_at(pos - 1))
				var right_ok = pos + word.length() >= s.length() or not _is_word_char(s.unicode_at(pos + word.length()))
				if left_ok and right_ok:
					regions.append({"from": pos, "to": pos + word.length(), "color": col})
				pos = s.findn(word, pos + word.length())

	# --- build dictionary ---
	regions.sort_custom(func(a,b): return a["from"] < b["from"])
	var color_map: Dictionary = {}
	for r in regions:
		color_map[r["from"]] = {"color": r["color"]}
		color_map[r["to"]] = {"color": C_DEFAULT}

	return color_map

# ─────────────────────────────
#  HELPERS
# ─────────────────────────────
func _is_word_char(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
