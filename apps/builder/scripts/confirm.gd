extends Control
class_name ControlConfirmer

signal valid(input: String)

var cursor: int = 0
var inputs: Array[ValidNumber] = []

var _nav_lock: bool = false

func _ready() -> void:
	var i: int = -1
	for child in get_children():
		if child is ValidNumber:
			i += 1
			var vn: ValidNumber = child
			inputs.append(vn)
			vn.changed.connect(_on_child_changed.bind(i))
			vn.backspace_attempt.connect(_on_child_bsp.bind(i))
			vn.focus_entered.connect(_on_child_focus.bind(i))

	if inputs.size() > 0:
		cursor = 0

func _input(event: InputEvent) -> void:
	if _nav_lock:
		return
	if inputs.is_empty():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("ui_left"):
			_move_relative(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action("ui_right"):
			_move_relative(1)
			get_viewport().set_input_as_handled()

func _move_relative(dir: int) -> void:
	var current: int = _focused_index()
	if current < 0:
		current = cursor

	var target: int = clamp(current + dir, 0, inputs.size() - 1)
	if target == current:
		return

	_nav_lock = true
	inputs[target].grab_focus()
	ui.click_screen(inputs[target].global_position)
	call_deferred("_unlock_nav")
	await get_tree().process_frame
	inputs[target].set_caret_column(1)

func _unlock_nav() -> void:
	_nav_lock = false

func _focused_index() -> int:
	var owner := get_viewport().gui_get_focus_owner()
	if owner is ValidNumber:
		return inputs.find(owner)
	return -1

func _on_child_focus(idx: int) -> void:
	if idx >= 0:
		cursor = idx

func _on_child_bsp(idx: int):
	if inputs[idx].text == "":
		_move_relative(-1)
	

func _on_child_changed(idx: int) -> void:
	var who = inputs[idx]
	
	if len(get_input()) == len(inputs):
		result()
		return
	if idx + 1 < inputs.size() and inputs[idx+1].text != "":
		return
	if who.text == "":
		pass
	elif idx + 1 == inputs.size():
		result()
	else:
		who.release_focus()
		_nav_lock = true
		inputs[idx + 1].grab_focus()
		call_deferred("_unlock_nav")

func begin():
	pass

func validate():
	pass

var input = ""
func get_input() -> String:
	input = ""
	for i in inputs:
		input += i.text
	return input

func result():
	valid.emit(get_input())
