extends RichTextLabel


var actual_text: String = ""
var thinking: bool = false
static func strip_unclosed_fences(text: String) -> String:
	var lines := []
	var n := text.length()
	var start := 0

	# Split manually by newline
	for i in n:
		if text[i] == '\n':
			lines.append(text.substr(start, i - start))
			start = i + 1
	if start < n:
		lines.append(text.substr(start, n - start))

	# Track fence open/close state
	var open_indices := []
	for i in lines.size():
		var line = lines[i]
		if line.begins_with("```"):
			if open_indices.is_empty():
				open_indices.append(i)  # opening
			else:
				open_indices.pop_back() # closing

	# Build output, skipping any unclosed openings
	var result := ""
	var skip := {}
	for i in open_indices:
		skip[i] = true

	var appended := false
	for i in lines.size():
		if skip.has(i):
			continue  # remove this unclosed ```
		# Skip *final* empty line(s) caused by trailing fences
		if i == lines.size() - 1 and lines[i].strip_edges().is_empty():
			continue
		result += lines[i]
		if i < lines.size() - 1:
			result += "\n"
			appended = true

	# Trim any accidental final newline
	while result.ends_with("\n") or result.ends_with("\r"):
		result = result.substr(0, result.length() - 1)

	return result



func _strip_trailing_visual_blank(s: String) -> String:
	# 1) unify endings
	s = s.replace("\r\n", "\n").replace("\r", "\n")

	# 2) hard-trim raw \n/\r at the very end
	while s.ends_with("\n") or s.ends_with("\r"):
		s = s.left(s.length() - 1)

	# 3) if the last line becomes empty once tags are removed — drop it
	var last_nl := s.rfind("\n")
	var last_line := s.substr(last_nl + 1) if last_nl >= 0 else s

	# remove BBCode tags from the last line
	var plain := last_line
	#var rx := RegEx.new()
	#rx.compile("\[[^\]]+\]")  # strips [b], [/color], etc.
	#plain = rx.sub(plain, "", true)
	
	
	if plain.strip_edges().is_empty() and last_nl >= 0:
		s = s.substr(0, last_nl)

	return s


func _render_now() -> void:
	var display := actual_text
	
	display = parser.clean_message(display)
	display = strip_unclosed_fences(display)
	#("====")
	#(display)
	if thinking:
		display += "\n[color=gray]Thinking...[/color]"
	if building:
		display += "\n[color=gray]Building...[/color]"

	# Convert once, then normalize & trim, then assign once.
	display = ui.markdown_to_bbcode(display)
	display = _normalize_newlines(display)
	display = display.replace("[code]\n[/code]", "")
	display = display.strip_edges()
	#display.replace("`", "")

	while display.ends_with("\n") or display.ends_with("\r"):
		display = display.substr(0, display.length() - 1)
	text = display

func push_text(chunk: String) -> void:
	if chunk.is_empty():
		return
	actual_text += chunk
	_render_now()

func set_thinking(yes: bool) -> void:
	if thinking == yes:
		return
	thinking = yes
	_render_now()

var building: bool = false
func set_building(yes: bool) -> void:
	if building == yes:
		return
	building = yes
	_render_now()

func set_txt(full: String) -> void:
	actual_text = full if full != null else ""
	_render_now()

func _normalize_newlines(s: String) -> String:
	# Unify endings and collapse multi-blank lines to single.
	s = s.replace("\r\n", "\n").replace("\r", "\n")
	while s.find("\n\n") != -1:
		s = s.replace("\n\n", "\n")
	# Avoid visual gaps across closing/opening tags
	s = s.replace("[/color]\n[", "[/color][")
	return s


func _process(delta: float) -> void:
	#if 1:
	#	print("'" + text + "'")
	if glob.mouse_just_pressed and get_global_rect().has_point(get_global_mouse_position()) and not ui.get_focus():
		#("f")
		#(text)
		#DisplayServer.clipboard_set("")
		DisplayServer.clipboard_set(text)
		#(text)
		#(DisplayServer.clipboard_get())
