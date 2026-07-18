extends Control

func is_focus(control: Control):
	if control is HSlider: return (control.get_global_rect().has_point(get_global_mouse_position()))
	return control and get_viewport().gui_get_focus_owner() == control

func graph_shot(rect: Rect2, path: String) -> void:
	#("ff")
	for i in graphs._graphs.values():
		i.set_screenshotting()
	var bg = glob.bg_trect
	bg.visible = false
	#bg.set_screenshotting()
	await get_tree().process_frame

	var img := get_viewport().get_texture().get_image().get_region(rect)
	img.save_png(path)

	bg.visible = true
	#DisplayServer.clipboard_set(img)
	for i in graphs._graphs.values():
		i.set_not_screenshotting()
	#bg.set_not_screenshotting()

var mist: ColorRect
var is_ai_building: bool = false
func set_ai_building():
	#return
	# TODO: make it look good
	
	is_ai_building = true
	axon_donut.target_visible()
	mist.target_visible()

func set_uni(who, what, val):
	who.material.set_shader_parameter(what, val)
func get_uni(who, what):
	return who.material.get_shader_parameter(what)

func stop_ai_building():
	#return
	
	
	is_ai_building = false
	axon_donut.target_invisible()
	mist.target_invisible()



func get_focus():
	return get_viewport().gui_get_focus_owner()

var topr: Control = null

func set_topr_text(text: String):
	topr.show_text(text)

func hide_topr():
	topr.hide()

var _active_splashed: bool = false

func active_splashed() -> bool:
	return _active_splashed

var mouse_buttons: Dictionary = {1: true, 2: true, 3: true}
var wheel_buttons: Dictionary = {
	MOUSE_BUTTON_WHEEL_UP: true,
	MOUSE_BUTTON_WHEEL_DOWN: true,
	MOUSE_BUTTON_WHEEL_LEFT: true,
	MOUSE_BUTTON_WHEEL_RIGHT: true,
}

func line_block(line: LineEdit):
	line.editable = false
	line.selecting_enabled = false
	line.release_focus()
	line.mouse_filter = MOUSE_FILTER_IGNORE

func line_unblock(line: LineEdit):
	line.editable = true
	line.selecting_enabled = true
	line.mouse_filter = MOUSE_FILTER_STOP

func window_changed(who):
	if is_ai_building:
		if who == "graph":
			axon_donut.resume()
			mist.show()
		else:
			axon_donut.stop()
			mist.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in wheel_buttons:
			var hovered = get_viewport().gui_get_hovered_control()
			if hovered and hovered is Slider:
				accept_event()
				return
	#	elif event.button_index == MOUSE_BUTTON_LEFT:
	#		print(get_focus())

	if event is InputEventMouse:
		var focused = get_viewport().gui_get_focus_owner()
		#var occ = glob.is_occupied(focused, "menu_inside")
		#(occ)
		if event is InputEventMouseButton and event.pressed:
			#(glob.is_occupied(focused, "menu_inside"))
			if event.button_index in mouse_buttons:
				if focused and (focused is LineEdit or focused is Slider or focused is TextEdit or focused is RichTextLabel):
					var rect = focused.get_global_rect()
					if not rect.has_point(get_global_mouse_position()) and not event.has_meta("_emulated"):
						focused.release_focus()
						#if focused is ValidInput:
						focused.focus_exited.emit()
		elif not glob.mouse_pressed:
			if focused is Slider and not event.has_meta("_emulated"):
				#("fj")
				focused.release_focus()
				focused.focus_exited.emit()

var expanded_menu: SubMenu = null
var _buttons = []

func move_mouse(pos: Vector2) -> void:
	var vp = get_viewport()
	var motion = InputEventMouseMotion.new()
	motion.global_position = pos
	motion.position = pos
	motion.relative = Vector2.ZERO
	motion.set_meta("_emulated", true)

	vp.push_input(motion)


var topr_inside: bool = false

var topr_state = {}
func upd_topr_inside(who: Object, val: bool):
	if val:
		topr_state[who] = true
	else:
		topr_state.erase(who)
	topr_inside = len(topr_state) > 0




func ask(packet: Dictionary):
	pass



#var _parent_graphs = {}
func reg_button(b: BlockComponent):
	pass
	#_parent_graphs[b] = [b.graph, b.graph.z_index if b.graph else 0]

func unreg_button(b: BlockComponent):
	pass

var axon_donut: Control

func conf_screen():
	for i in 10:
		await glob.wait(randf_range(0.1,0.4))
		confetti((Vector2(randi_range(0, glob.window_size.x), randi_range(0, glob.window_size.y))), true)
	#confetti((Vector2(glob.window_size.x - 50, 100)), true)
	#confetti((Vector2(glob.window_size.x/2, glob.window_size.y/2)), true)
	#confetti((Vector2(50, glob.window_size.y -50)), true)

func a():
	await confetti(get_global_mouse_position())

var fork = load("res://resources/fork.tscn")

func get_fork():
	return fork.instantiate()

func _process(delta: float):
	#if glob.space_just_pressed:
	#	set_ai_building()
	#	set_dense_units(1, 16)
	#print(splashed)
	var ct: int = 0
	for i in splashed.keys():
		if not is_instance_valid(i): splashed.erase(i); continue
		if not i.visible: splashed.erase(i); continue
		if i.persistent and not i.visible:
			ct += 1
	for i in splashed_in.keys():
		if not is_instance_valid(i): splashed_in.erase(i); continue
		if not i.visible: splashed_in.erase(i); continue
	_active_splashed = len(splashed) != ct
	#(_active_splashed)
#	print(get_viewport().gui_get_focus_owner())
			

var splashed_in = {}
var blur = preload("res://scenes/blur.tscn").instantiate()
var splash_menus = {
	"login": preload("res://scenes/splash.tscn"),
	"signup": preload("res://scenes/signup.tscn"),
	"scene_create": preload("res://scenes/scene_create.tscn"),
	"dataset_create": preload("res://scenes/dataset_create.tscn"),
	"works": preload("res://scenes/works.tscn"),
	"workslist": preload("res://scenes/workslist.tscn"),
	"lessonslist": preload("res://scenes/lessonlist.tscn"),
	"settings": preload("res://scenes/settings.tscn"),
	"project_create": preload("res://scenes/project_create.tscn"),
	"ai_help": preload("res://scenes/ai_help.tscn"),
	"select_dataset": preload("res://scenes/select_dataset.tscn"),
	"model_export": preload("res://scenes/model_export.tscn"),
	"path_open": preload("res://scenes/path_open.tscn"),
	"classroom_create": preload("res://scenes/classroom_create.tscn"),
}

var quest: Quest = null

func confetti(at: Vector2, screen: bool = false):
	var conf = ConfettiSplash.new()
	if screen:
		conf.position = at / 2
		glob.scale_fg.add_child(conf)
	else:
		conf.position = at
		add_child(conf)
	await conf.die

var conf_config = preload("res://resources/confetti.tres")
var quest_scene = preload("res://scenes/quest.tscn")
func recreate_quest():
	var old_pos = quest.position
	var p = quest.get_parent()
	quest.queue_free()
	var q = (quest_scene.instantiate())
	p.add_child(q)
	q.position = old_pos

var cl = CanvasLayer.new()
var hg = preload("res://scenes/hourglass.tscn")
var hourglass: TextureRect

func hourglass_on():
	hourglass.on()

func hourglass_off():
	hourglass.off()

func show_lock():
	await quest.hide_request()
	quest.say(["✋ Подожди, пока другие ученики закончат. Скажи учителю что ты ожидаешь следующего шага."], false, false, Color.YELLOW)

func hide_lock():
	await quest.hide_request()

var chosen = {}

var arrows = {}
func hide_arrows():
	await glob.tween_call({}, func(data, delta):
		for i in arrows.keys():
			arrows[i] = false
			i.modulate.a = lerpf(i.modulate.a, 0.0, delta * 20.0)
			if i.modulate.a < 0.01:
				i.queue_free()
				arrows.erase(i)
		if not arrows:
			return true
		)

func show_arrow_conn(points_to: Connection):
	show_arrow(points_to.dir_vector * 50 + points_to.get_origin(), 
	points_to.dir_vector * 10 + points_to.get_origin(), func(): return points_to.get_origin() if is_instance_valid(points_to) else null)

func prect(points_to):
	var lx = Vector2(0.5,1)
	var g = points_to.rect.get_global_rect()
	return Vector2(lerp(g.position.x, g.end.x, lx.x), lerp(g.position.y, g.end.y, lx.y))

func show_arrow_graph(points_to: Graph):
	show_arrow(prect(points_to) + 100 * Vector2.DOWN, 
	prect(points_to) + 40 * Vector2.DOWN, func(): return prect(points_to) if is_instance_valid(points_to) else null)


func base(): return Vector2()

func show_arrow(start: Vector2, end: Vector2, rel: Callable = base):
	var arrow := Arrow2D.new()
	add_child(arrow)

	arrow.position = start
	arrow.end = end - start
	arrow.color = Color.CORAL
	arrow.modulate.a = 0.0

	var normal := start.direction_to(end)
	var anchor = arrow.position - rel.call()

	glob.tween_call({ t = 0.0 }, func(data, delta):
		if not is_instance_valid(arrow):
			return true
			

		data.t += delta

		# Fade-in
		if arrows.get(arrow, false):
			arrow.modulate.a = lerpf(
				arrow.modulate.a,
				1.0,
				delta * FADE_SPEED
			)

		# Damped oscillation
		var amplitude := WOBBLE_AMPL * exp(-DAMPING * data.t)
		var offset := normal * sin(data.t * WOBBLE_FREQ) * amplitude
		
		var c = rel.call()
		if c is Vector2:
			arrow.position = c + anchor + offset

	)

	arrows[arrow] = true


const WOBBLE_FREQ := 8.0      # radians/sec
const WOBBLE_AMPL := 50.0    # pixels
const DAMPING := 1.5         # higher = faster settle
const FADE_SPEED := 3


func _ready():
	cl.layer = 128
	add_child(cl)
	blur.self_modulate.a = 0
	cl.add_child(blur)
	var inst: Control = hg.instantiate()
	hourglass = inst
	hourglass.hide()
	cl.add_child(inst)
	inst.scale = Vector2.ONE * 2.0
	#inst.position = Vector2(30,30)
	#inst.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	inst.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_HEIGHT, 39)
	inst.z_index = 90
	
	configure_richtext_theme_auto(header_theme, header_font, base_font)

var splashed = {}

func add_splashed(who: SplashMenu):
	splashed[who] = true

func rem_splashed(who: SplashMenu):
	splashed.erase(who)

func is_splashed(who: String) -> bool:
	for i in splashed:
		if i.typename == who: return true
	return false

func get_splash(who: String) -> SplashMenu:
	for i in splashed:
		if i.typename == who: return i
	return null

func force_layout_update(node: Control):
	node.propagate_call("minimum_size_changed")
	node.propagate_call("queue_sort")
	node.propagate_call("size_flags_changed")
	node.propagate_call("update_minimum_size")
	node.propagate_call("update")
	node.propagate_call("notification", [NOTIFICATION_LAYOUT_DIRECTION_CHANGED])

func close_top_level_splashes(except_typename: String = "") -> void:
	for s in splashed.keys():
		if not is_instance_valid(s): continue
		if s.inner: continue
		if s.persistent: continue # optional: keep persistent ones
		if except_typename != "" and s.typename == except_typename: continue
		s.can_go = true
		s.go_away()

var nodes_choosing: bool = false

func nodes_choosing_on():
	nodes_choosing = true
	for graph: Graph in graphs._graphs.values():
		graph.enter_selection_mode()

func mark_chosen(who):
	chosen[who] = true

func unmark_chosen(who):
	chosen.erase(who)

func choose():
	print("CHOOSING STUFF...")
	nodes_choosing_on()
	await choosing_finished
	return lock_chosen()

signal choosing_finished






func emphasize_nodes(nodes):
	glob.cam.emp_node(nodes if nodes is Array else [nodes])
	for i in nodes:
		if i is Graph:
			i.blink()
		else:
			graphs._graphs[i].blink()


func lock_chosen():
	nodes_choosing = false
	for graph: Graph in graphs._graphs.values():
		graph.exit_selection_mode()
	for graph: Graph in graphs._graphs.values():
		graph.exit_selection_mode()
	var old_chosen = chosen
	chosen = {}
	return old_chosen

func highlight_node(move_viewport: bool = false):
	pass

func hide_splash():
	close_top_level_splashes()

func splash(menu: String, splashed_from = null, emitter_ = null, inner = false, passed_data = null) -> SplashMenu:
	hourglass.off(true)
	#(menu)
	#_stack()
#	close_top_level_splashes(menu)
	if splashed_from:
		if !is_splashed(menu):
			splashed_from.in_splash = true
		else:
			splashed_from.in_splash = false
			get_splash(menu).go_away()
			return null
	var m: SplashMenu 
	if menu in already_splashed:
		m = already_splashed[menu]
	else:
		m = splash_menus[menu].instantiate()
	m.inner = inner
	hide_topr()
	if passed_data: m.passed_data = passed_data
	if not menu in already_splashed:
		cl.add_child(m)
	else:
		m.readys()
		m.splash()
	already_splashed[menu] = m
	m.splashed_from = splashed_from
	var emitter = ResultEmitter.new() if !emitter_ else emitter_
	m.emitter = emitter
	if splashed_from:
		emitter.res.connect(func(...args): splashed_from.in_splash = false)
	m.tree_exited.connect(func(): already_splashed.erase(menu))
	return m

func error(text: String):
	print(text)

class ResultEmitter:
	signal res(data: Dictionary, who: String)

var already_splashed: Dictionary = {}
signal result_emit(data: Dictionary)
func splash_and_get_result(menu: String, splashed_from = null, emitter_ = null, inner = false, passed_data = null) -> Dictionary:
	#_stack()
	#if glob.DUMMY_LOGIN and menu == "login":
	#	return {"user": "n", "pass": "1"}
	#close_top_level_splashes(menu)
	
	hourglass.off(true)
	if splashed_from:
		if !is_splashed(menu):
			splashed_from.in_splash = true
		else:
			splashed_from.in_splash = false
			get_splash(menu).go_away()
			return {}
	var m: SplashMenu 
	if menu in already_splashed:
		m = already_splashed[menu]
	else:
		m = splash_menus[menu].instantiate()
	m.inner = inner
	hide_topr()
	if passed_data: m.passed_data = passed_data
	if not menu in already_splashed:
		cl.add_child(m)
	else:
		m.readys()
		m.splash()
	already_splashed[menu] = m
	m.splashed_from = splashed_from
	var emitter = ResultEmitter.new() if !emitter_ else emitter_
	m.emitter = emitter
	if splashed_from:
		emitter.res.connect(func(...args): splashed_from.in_splash = false)
	m.tree_exited.connect(func(): already_splashed.erase(menu))
	var a = await emitter.res
	return a

func set_dense_units(per_unit: int, max_units: int):
	for i in graphs._graphs:
		var g = graphs._graphs[i]
		if graphs.is_layer(g, "Dense"):
			g.group_size = per_unit
			g.max_units = max_units
			g.update_config({"neuron_count": g.cfg["neuron_count"]})

var lesson_bar: ColorRect = null

func configure_richtext_theme_auto(theme: Theme, base_font: FontFile, monospaced_font: FontFile) -> void:
	if theme == null or base_font == null:
		push_warning("configure_richtext_theme_auto: theme/base_font must be non-null")
		return
	if monospaced_font == null:
		monospaced_font = base_font
	var has_axes := func(f: Font, tag: String) -> bool:
		if f and f.has_method(&"get_supported_variation_list"):
			var axes: Dictionary = f.get_supported_variation_list()
			return axes.has(tag)
		return false

	var make_bold := func(f: Font) -> Font:
		var v := FontVariation.new()
		v.base_font = f
		if has_axes.call(f, "wght"):
			var coords := v.variation_opentype
			coords["wght"] = 700.0
			v.variation_opentype = coords
		else:
			v.variation_embolden = 0.8
		return v

	var make_italic := func(f: Font) -> Font:
		var v := FontVariation.new()
		v.base_font = f
		if has_axes.call(f, "ital"):
			var coords := v.variation_opentype
			coords["ital"] = 1.0
			v.variation_opentype = coords
		elif has_axes.call(f, "slnt"):
			var coords := v.variation_opentype
			coords["slnt"] = -12.0
			v.variation_opentype = coords
		else:
			v.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)
		return v

	var make_bold_italic := func(f: Font) -> Font:
		var v := FontVariation.new()
		v.base_font = f
		var used_axes := false
		if has_axes.call(f, "wght"):
			var coords := v.variation_opentype
			coords["wght"] = 700.0
			v.variation_opentype = coords
			used_axes = true
		if has_axes.call(f, "ital") or has_axes.call(f, "slnt"):
			var coords := v.variation_opentype
			if has_axes.call(f, "ital"):
				coords["ital"] = 1.0
			elif has_axes.call(f, "slnt"):
				coords["slnt"] = -12.0
			v.variation_opentype = coords
			used_axes = true
		if not used_axes:
			v.variation_embolden = 0.8
			v.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)
		return v

	var normal_font: Font = base_font
	var bold_font: Font = make_bold.call(base_font)
	var italics_font: Font = make_italic.call(base_font)
	var bold_italics_font: Font = make_bold_italic.call(base_font)
	var mono_font: Font = monospaced_font


	theme.set_font(&"normal_font", &"RichTextLabel", normal_font)
	theme.set_font(&"bold_font", &"RichTextLabel", bold_font)
	theme.set_font(&"italics_font", &"RichTextLabel", italics_font)
	theme.set_font(&"bold_italics_font", &"RichTextLabel", bold_italics_font)
	theme.set_font(&"mono_font", &"RichTextLabel", mono_font)




const _CODEBLOCK_TOKEN = "\uF000CODEBLOCK%03d\uF000"
const _CODESPAN_TOKEN  = "\uF001CODESPAN%03d\uF001"

func markdown_to_bbcode(md: String) -> String:
	var codeblocks: Array[String] = []
	var codespans: Array[String] = []
	var text = md

	# ---------- 1) Extract fenced code blocks: ```...```
	var re_block = RegEx.new()
	re_block.compile("(?s)```(?:[A-Za-z0-9_+-]+)?\\s*(.*?)\\s*```")
	while true:
		var m = re_block.search(text)
		if m == null: break
		var code = m.get_string(1)
		codeblocks.append(code)
		var token = _CODEBLOCK_TOKEN % (codeblocks.size() - 1)
		text = text.substr(0, m.get_start()) + token + text.substr(m.get_end())

	# ---------- 2) Extract inline code: `...`
	var re_span = RegEx.new()
	re_span.compile("`([^`\\n]+?)`")
	while true:
		var m2 = re_span.search(text)
		if m2 == null: break
		var span = m2.get_string(1)
		codespans.append(span)
		var token2 = _CODESPAN_TOKEN % (codespans.size() - 1)
		text = text.substr(0, m2.get_start()) + token2 + text.substr(m2.get_end())

	# ---------- 3) Links: [text](url)
	var re_link = RegEx.new()
	re_link.compile("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)")
	while true:
		var ml = re_link.search(text)
		if ml == null: break
		var label = ml.get_string(1)
		var url = ml.get_string(2)
		var rep = "[url=%s]%s[/url]" % [url, label]
		text = text.substr(0, ml.get_start()) + rep + text.substr(ml.get_end())

	# ---------- 4) Headings: #..######  → just make them bold + newline
	# (Top to bottom to avoid double-processing)
	for level in range(6, 0, -1):
		var pfx = String("#").repeat(level)
		var re_h = RegEx.new()
		re_h.compile("(?m)^%s\\s+(.*)$" % pfx)
		while true:
			var mh = re_h.search(text)
			if mh == null: break
			var body = mh.get_string(1).strip_edges()
			var rep_h = "[b]%s[/b]" % body
			text = text.substr(0, mh.get_start()) + rep_h + text.substr(mh.get_end())

	# ---------- 5) Strikethrough: ~~text~~
	var re_s = RegEx.new()
	re_s.compile("~~(.+?)~~")
	while true:
		var ms = re_s.search(text)
		if ms == null: break
		text = text.substr(0, ms.get_start()) + "[s]" + ms.get_string(1) + "[/s]" + text.substr(ms.get_end())

	# ---------- 6) Bold: **text** and __text__
	for pat in ["\\*\\*(.+?)\\*\\*", "__(.+?)__"]:
		var re_b = RegEx.new()
		re_b.compile(pat)
		while true:
			var mb = re_b.search(text)
			if mb == null: break
			text = text.substr(0, mb.get_start()) + "[b]" + mb.get_string(1) + "[/b]" + text.substr(mb.get_end())

	# ---------- 7) Italic: *text* and _text_  (avoid touching ** already handled)
	for pat_i in ["(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"]:
		var re_i = RegEx.new()
		re_i.compile(pat_i)
		while true:
			var mi = re_i.search(text)
			if mi == null: break
			text = text.substr(0, mi.get_start()) + "[i]" + mi.get_string(1) + "[/i]" + text.substr(mi.get_end())

	# ---------- 8) Simple bullets: lines starting with "- " or "* "
	for pat_bullet in ["(?m)^-\\s+", "(?m)^\\*\\s+"]:
		var re_bu = RegEx.new()
		re_bu.compile(pat_bullet)
		text = re_bu.sub(text, "• ", true)

	# ---------- 9) Restore code spans and blocks as [code]...[/code]
	# Escape BBCode brackets inside code so they render literally.
	var esc = func(s: String) -> String:
		return s.replace("[", "\\[").replace("]", "\\]")

	# Spans first (so blocks can contain tokens without conflict)
	for idx in range(codespans.size()):
		var token = _CODESPAN_TOKEN % idx
		var repl = "[code]" + esc.call(codespans[idx]) + "[/code]"
		text = text.replace(token, repl)

	for idxb in range(codeblocks.size()):
		var tokenb = _CODEBLOCK_TOKEN % idxb
		var body = esc.call(codeblocks[idxb])
		# Ensure code blocks are separated by blank lines for RTL auto-parsing
		var replb = "\n[code]\n%s\n[/code]\n" % body
		text = text.replace(tokenb, replb)

	return text





var base_theme = preload("res://resources/theme.tres")
var header_theme = preload("res://resources/theme_headers.tres")
var header_font = preload("res://game_assets/fonts/JetBrainsSans[wght]-VF.ttf") as FontFile
var base_font = preload("res://game_assets/fonts/JetBrainsMono-VariableFont_wght.ttf") as FontFile



var selecting_box: bool = false
func click_screen(pos: Vector2, button = MOUSE_BUTTON_LEFT, double_click = false) -> void:
	var vp = get_viewport()

	var down = InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.double_click = double_click
	down.position = pos
	down.global_position = pos
	down.set_meta("_emulated", true)
	vp.push_input(down)

	var up = InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.double_click = false
	up.position = pos
	up.global_position = pos
	up.set_meta("_emulated", true)
	vp.push_input(up)
