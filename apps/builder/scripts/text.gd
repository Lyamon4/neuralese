extends TextEdit

@export var children_layer: Array[BlockComponent] = []
@export var enter_event: BlockComponent
@export var max_length: int = 256
@export var max_size_y: int = 200

var _guard: bool = false

func disable():
	editable = false
	modulate = Color(0.9,0.9,0.9,1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(0)
	set_process_input(0)
	for child in children_layer:
		child.block_input()
		var b = child._base_modulate
		child.base_modulate = Color(b.r*0.7, b.g*0.7, b.b*0.7, b.a)
	release_focus()

func enable():
	editable = true
	modulate = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(1)
	set_process_input(1)
	for child in children_layer:
		child.unblock_input()
		var b = child._base_modulate
		child.base_modulate = b

var _snap_text: String = ""
var _snap_line: int = 0
var _snap_col: int = 0
var _snap_vscroll: float = 0.0
var _snap_hscroll: float = 0.0
var _snap_has_sel: bool = false
var _snap_sel_from_line: int = 0
var _snap_sel_from_col: int = 0
var _snap_sel_to_line: int = 0
var _snap_sel_to_col: int = 0

func _ready() -> void:
	connect("text_changed", Callable(self, "_on_text_changed"))
	_accept_snapshot()
	if enter_event:
		enter_event.released.connect(func(): text_accept.emit(text))
	set_process(true)

signal text_accept(text: String)

var prev_text = ""
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var shift_down = Input.is_action_pressed("shift")
	if Input.is_action_just_pressed("ui_shift_enter") or (shift_down and Input.is_action_just_pressed("ui_enter")):
		_insert_newline_at_caret()
		return

	if text and editable and Input.is_action_just_pressed("ui_enter") and not shift_down:
		text = prev_text
		text_accept.emit(text)
		if enter_event:
			enter_event.press(0.002)
		_clear_text_and_reset()
		return
	prev_text = text


func _on_text_changed() -> void:
	if _guard:
		return
	_guard = true

	var cur_line = get_caret_line()
	var cur_col = get_caret_column()
	var cur_vscroll = scroll_vertical
	var cur_hscroll = scroll_horizontal
	var cur_has_sel = has_selection()
	var cur_sel_from_line = get_selection_from_line() if cur_has_sel else 0
	var cur_sel_from_col = get_selection_from_column() if cur_has_sel else 0
	var cur_sel_to_line = get_selection_to_line() if cur_has_sel else 0
	var cur_sel_to_col = get_selection_to_column() if cur_has_sel else 0

	if text.length() > max_length:
		text = text.left(max_length)

	var lh = max(1, get_line_height())
	var allowed_rows = max(1, int(floor(float(max_size_y) / float(lh))))
	var visual_rows = _visual_rows()

	if visual_rows <= allowed_rows:
		_accept_snapshot()
		var content_h = visual_rows * lh
		custom_minimum_size.y = min(content_h, max_size_y)
	else:
		#("rest!")
		_restore_snapshot()

	var max_line = max(0, get_line_count() - 1)
	cur_line = clamp(cur_line, 0, max_line)
	cur_col = clamp(cur_col, 0, get_line(cur_line).length())
	set_caret_line(cur_line, true, true)
	set_caret_column(cur_col)

	scroll_vertical = cur_vscroll
	scroll_horizontal = cur_hscroll

	if cur_has_sel:
		var f_line = clamp(cur_sel_from_line, 0, max_line)
		var f_col = clamp(cur_sel_from_col, 0, get_line(f_line).length())
		var t_line = clamp(cur_sel_to_line, 0, max_line)
		var t_col = clamp(cur_sel_to_col, 0, get_line(t_line).length())
		select(f_line, f_col, t_line, t_col)
	else:
		deselect()

	_guard = false



func _visual_rows() -> int:
	var total = 0
	var lc = get_line_count()
	for i in lc:
		total += 1 + get_line_wrap_count(i)
	return total

func _accept_snapshot() -> void:
	_snap_text = text
	_snap_line = get_caret_line()
	_snap_col = get_caret_column()
	_snap_vscroll = scroll_vertical
	_snap_hscroll = scroll_horizontal
	_snap_has_sel = has_selection()
	if _snap_has_sel:
		_snap_sel_from_line = get_selection_from_line()
		_snap_sel_from_col = get_selection_from_column()
		_snap_sel_to_line = get_selection_to_line()
		_snap_sel_to_col = get_selection_to_column()
	else:
		_snap_sel_from_line = 0
		_snap_sel_from_col = 0
		_snap_sel_to_line = 0
		_snap_sel_to_col = 0


func _restore_snapshot() -> void:
	var cur_line = get_caret_line()
	var cur_col = get_caret_column()
	var cur_vscroll = scroll_vertical
	var cur_hscroll = scroll_horizontal

	text = _snap_text
	await get_tree().process_frame

	# clamp current caret position to new layout
	var max_line = max(0, get_line_count() - 1)
	var line = clamp(cur_line, 0, max_line)
	var col = clamp(cur_col, 0, get_line(line).length())

	set_caret_line(line, true, true)
	set_caret_column(col)
	scroll_vertical = cur_vscroll
	scroll_horizontal = cur_hscroll


func _insert_newline_at_caret() -> void:
	insert_text_at_caret("\n")

@export var base: float = 46

func _clear_text_and_reset() -> void:
	if _guard:
		return
	_guard = true

	text = ""
	deselect()
	set_caret_line(0, true, true)
	set_caret_column(0)
	scroll_vertical = 0.0
	scroll_horizontal = 0.0

	custom_minimum_size.y = 0
	custom_minimum_size.y = 46

	_accept_snapshot()

	_guard = false
