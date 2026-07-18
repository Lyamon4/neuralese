
extends Control
class_name Quest

func _enter_tree():
	ui.quest = self

@export var scroll_cont: ScrollContainer
@export var row_spacing: float = 8.0

var indexed: Array = []

@onready var cont = $ColorRect/ScrollContainer/c
var types: Dictionary = {}
var _content_h: float = 0.0


func apply_extents():
	var sb = scroll_cont.get_v_scroll_bar()

	var o = scroll_cont.global_position.y + 5.0
	var i = global_position.y + scroll_cont.size.y * scale.y * scroll_cont.scale.y - 10.0
	var maxval = sb.max_value - sb.page - 5.0

	var top = o if sb.value > 5.0 else 0.0
	var bot = i if sb.value < maxval else 0.0
	
	for node in indexed:
		glob.inst_uniform(node, "extents", Vector4(top, bot, 0, 0))

var should_be_visible: Callable = func(): return true
var target_mod: float = 0.0
func _process(_delta: float) -> void:
	if not visible:
		topr_update(false)
		return
	#if glob.space_just_pressed:
	#	hide_request()
	
	if is_waiting:
		target_mod = 1.0 if should_be_visible.call() else 0.0
		if next:
			next.modulate.a = lerpf(next.modulate.a, target_mod, _delta * 10.0)
			if is_equal_approx(next.modulate.a, 0.0):
				next.hide()
			if target_mod > 0.9:
				next.show()
				next.unblock_input()
			else:
				next.block_input()
	apply_extents()

	if $ColorRect.get_global_rect().has_point(get_global_mouse_position()):
		topr_update(true)
		glob.set_menu_type(self, "o")
	else:
		glob.reset_menu_type(self, "i")
		topr_update(false)
func _exit_tree() -> void:
	
	topr_update(false)

func topr_update(boolean: bool):
	ui.upd_topr_inside(self, boolean)

func _snap_layout() -> void:
	var y = 0.0
	for dup in content():
		dup.position.y = y
		y += dup.size.y + row_spacing

	_content_h = y
	cont.custom_minimum_size.y = _content_h


func reindex():
	indexed.clear()
	$ColorRect/ScrollContainer/c.relayout()
	for i in $ColorRect/ScrollContainer/c.get_children():
		indexed.append_array(i.indexed)

@export var MIN_WIDTH_PX      = 200.0
@export var MAX_WIDTH_PX      = 720.0
@export var IDEAL_LINE_CHARS  = 58.0   # sweet spot for reading
@export var CHAR_PX           = 7.5    # average font char width

@export var MIN_HEIGHT_PX     = 50.0
@export var MAX_HEIGHT_PX  = 300   # max % of screen height
@export var V_PADDING         = 24.0



func load_bubble(data: Dictionary):
	for i in content():
		i.queue_free()
	await get_tree().process_frame
	indexed.clear()
	_snap_layout()
	await get_tree().process_frame
	
	if data:
		return await layout_bubble(data)

func autosize_bubble():
	var viewport = get_viewport_rect().size
	var max_h = MAX_HEIGHT_PX
	
	# -------------------------------------------------
	# 1. Estimate optimal width
	# -------------------------------------------------
	var longest_text = 0
	for node in content():
		if node.unit_type == BubbleUnit.UnitType.Text:
			longest_text = max(longest_text, node.passed_data.text.length())
	
	var ideal_text_width = IDEAL_LINE_CHARS * CHAR_PX
	var est_width = clamp(
		ideal_text_width,
		MIN_WIDTH_PX,
		MAX_WIDTH_PX
	)
	
	$ColorRect.size.x = est_width
	await get_tree().process_frame
	
	# -------------------------------------------------
	# 2. Measure natural content height
	# -------------------------------------------------
	_snap_layout()
	var natural_h = _content_h + V_PADDING
	
	# -------------------------------------------------
	# 3. Decide final height & scrolling
	# -------------------------------------------------
	var final_h = natural_h
	
	#if natural_h > max_h:
		#final_h = max_h
		#scroll_cont.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	#else:
		#scroll_cont.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	final_h = min(max(final_h, MIN_HEIGHT_PX), max_h)
	
	# -------------------------------------------------
	# 4. Apply
	# -------------------------------------------------
	$ColorRect.size.y = final_h
	scroll_cont.size.y = final_h - 13




var selected_state = {}

signal submit
var child_map = []
var result = {}
var data = {}
var next = null

var pressed_once = [false]
var press_func = func(a): 
		pressed_once[0] = true
var is_waiting: bool = false
func layout_bubble(_data: Dictionary) -> Array:
	data = _data
	var classes = glob.to_set("checkbox", "radio")
	var index_map = []
	result.clear()
	child_map.clear()
	var ref = [null]

	var answer_received = func answer_received(on: bool, index: int):
		child_map[index].set_persistent(on)
		var was_empty = result.size() == 0
		if on:
			result[index] = true
		else:
			result.erase(index)
	#pressed_once[0] = false
	for i in data["elements"]:
		var dup = types[i.type].duplicate()
		dup.abstract = false
		dup.passed_data = i

		dup.size.x = $ColorRect.size.x
		cont.add_child(dup)
		
		if data.type == "text":
			dup.modulate.a = 0
		if i.type in classes:
			dup.modulate.a = 0
			dup.toggled.connect(answer_received.bind(len(index_map)))
			index_map.append(i)
			child_map.append(dup)
		if i.type == "next":
			next = dup
			dup.toggled.connect(press_func)
			dup.hide()
			dup.modulate.a = 0

		dup.root = self
		dup.reinit()
	
	await get_tree().process_frame
	reindex()
	
	autosize_bubble()
	layout()
	await show_anim(_data)
	is_waiting = true
	while not pressed_once[0]:
		await get_tree().process_frame
	pressed_once[0] = false
	is_waiting = false
	
	var correct: bool = false
	if data.flags and data.flags.show_correct:
		show_correct()
		while not pressed_once[0]:
			await get_tree().process_frame
	await hide_anim()
	learner.ack_explain_next()
	
	return [result.keys(), correct]

var time_passed = true
func button_show_request():
	time_passed = true
	while visible:
		await get_tree().process_frame

func hide_request():
	pressed_once[0] = true
	while visible:
		await get_tree().process_frame

func reset():
	hide_request()
	hide()

func finish_exp():
	time_passed = true
	while visible:
		await get_tree().process_frame


func finish_and_hide():
	hide_request()
	while visible:
		await get_tree().process_frame



func say(text_segments: Array, wait_press = false, add_next = true, col = null):
	#text_segments = [text_segments[0].substr(0,1)]
	pressed_once[0] = false
	if col:
		$ColorRect.color = col
	else:
		$ColorRect.color = Color(0.678, 1.0, 0.796)
	if visible:
		await hide_request()
	if wait_press:
		glob.wait(1.0).connect(func(): time_passed = true)
	else:
		if visible:
			await hide_request()
	var els = []
	show()
	for i in text_segments:
		els.append({"type": "text", "text": i})
	if add_next:
		els.append({"type": "next", "text": ""})
	time_passed = false
	should_be_visible = func(): return time_passed
	if wait_press:
		await load_bubble({"elements":els, "type": "text", 
		"flags": {"show_correct": false, "correct_answers": []}})
	else:
		load_bubble({"elements":els, "type": "text", 
		"flags": {"show_correct": false, "correct_answers": []}})

func show_correct():
	$ColorRect/ScrollContainer.get_v_scroll_bar().value = 0
	for i in len(child_map):
		var unit = child_map[i]
		if i in result:
			if i in data.flags.correct_answers:
				unit.set_valid(BubbleUnit.AnsType.RightSelection)
			else:
				unit.set_valid(BubbleUnit.AnsType.WrongSelection)
		elif i in data.flags.correct_answers:
			unit.set_valid(BubbleUnit.AnsType.WasCorrect)
		else:
			unit.set_valid(BubbleUnit.AnsType.Default)


func layout():
	scroll_cont.get_v_scroll_bar().value = 0
	_snap_layout()
	await get_tree().process_frame
	var is_scrolling = _content_h + 19 > scroll_cont.size.y
	for dup in content():
		dup.size.x = $ColorRect.size.x - (32 if is_scrolling else 25)

		if dup.unit_type in dup.check_dtypes:
			dup.position.x += 3; dup.size.x -= 3
		if dup.unit_type == BubbleUnit.UnitType.Text:
			dup.position.x += 3; dup.size.x -= 10
		dup.reinit()
	_snap_layout()


func content():
	return cont.get_children()


func ask(head: String, options: Array, correct: Array, show_correct: bool = false):
	pressed_once[0] = false
	show()
	for i in len(correct):
		correct[i] = int(correct[i])
	var els = [{"type": "text", "text": head}]
	for i in options:
		els.append({"type": "checkbox" if correct.size() > 1 else "radio", "text": i})
	els.append({"type": "next", "text": ""})
	should_be_visible = func(): return result.size() > 0
	var res = await load_bubble({"elements":els, "type": "check", 
	"flags": {"show_correct": show_correct, "correct_answers": correct}})
	return res

const position_t = 1.0 #1
const mod_t = 0.7 #0.7

func show_anim(data_: Dictionary):
	show()
	$ColorRect.position = Vector2(-30, 0)
	await glob.tween_call({"t": 0},
		func(data, delta): 
			data.t += delta / 1
			$ColorRect.position.x = glob.lerp_expo_out(-30, 0, data.t)
			$ColorRect.modulate.a = glob.lerp_expo_out(0.0, 1.0, data.t)
			if data.t > 1.0:
				return true
			)
	var lerp_call = func(data,delta): 
			data.t += delta / data.div
			if not is_instance_valid(data.obj): return true
			data.obj.modulate.a = glob.lerp_quad(0.0, 1.0, data.t)
			if data.t > 1.0:
				return true
	for i in content():
		if is_instance_valid(i) and i.unit_type in (i.check_dtypes if data.type == "check" else i.text_dtypes):
			var div = 0.7; var t = 0.3
			if i.unit_type == BubbleUnit.UnitType.Text:
				t = max(1.5,learner.estimate_read_time(i.passed_data.text) * 0.6 + 0.1)
				div = 0.5
			glob.tween_call({"t": 0, "obj": i, "div": div}, lerp_call)
			
			await glob.wait(t)
			

var t: float = 0
func hide_anim():
	t = 0
	await glob.tween_call({"t": 0},
		func(data, delta): 
			data.t += delta * 2
			t = data.t
			$ColorRect.position.x = glob.lerp_expo_in(0, 30, data.t)
			$ColorRect.modulate.a = glob.lerp_expo_in(1.0, 0.0, data.t)
			if data.t > 1.0:
				return true
			)
	t = 0
	hide()



func _ready() -> void:
	hide()
	$ColorRect.modulate.a = 0
	for i in content():
		types[i.name] = i
		cont.remove_child(i)
		#await get_tree().process_frame

	$ColorRect/ScrollContainer.clip_contents = true
	hide()
	#say(["[color=medium_orchid]ИмяМодели[/color] и [color=sea_green]ПлотнСлой[/color]"])
	#
	#await glob.wait(1)


func _on_ai_released() -> void:
	hide()


func _on_item_rect_changed() -> void:
	layout()
