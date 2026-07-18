
extends TabWindow

@onready var list = $Control/scenes/list

var _last_edit_time: float = 0.0
var _flush_cooldown: float = 1.5   # seconds after last edit before flushing
var _pending_flush: bool = false
func flush_pending_changes() -> void:
	if not $Control/CodeEdit.dataset_obj: return
	var name = $Control/CodeEdit.dataset_obj["name"]

	var do_full_rebuild = pending_rebuild
	var do_inserts = pending_inserts.size() > 0
	var do_deletes = pending_deletes.size() > 0
	if not (do_full_rebuild or do_inserts or do_deletes):
		return

	if do_full_rebuild:
		pending_rebuild = false
		pending_inserts.clear()
		pending_deletes.clear()
		idxs.clear()
		glob.cache_rle_compress(name, null, "thread")
	else:
		var all_rows := (pending_inserts + pending_deletes)
		all_rows.sort()
		all_rows = all_rows.duplicate()
		pending_inserts.clear()
		pending_deletes.clear()

		if all_rows.size() > 0:
			var earliest := 1 << 30
			for row_i in all_rows:
				if row_i < earliest:
					earliest = row_i
			glob.cache_rle_compress(name, [earliest], "suffix")

	idxs.clear()







func _ready() -> void:
	#var vbar: VScrollBar = ($Control/console.get_v_scroll_bar())
	#vbar.position.x -= 5
	window_hide()
	await get_tree().process_frame
	glob.reset_menu_type(list, "list2")
	$CanvasLayer.hide()
	glob.un_occupy(list, &"menu")
	glob.un_occupy(list, "menu_inside")

	border_rect_1 = ColorRect.new()
	border_rect_1.color.a = 0
	border_rect_1.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	add_child(border_rect_1)

	border_rect_2 = ColorRect.new()
	border_rect_2.color.a = 0
	border_rect_2.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	add_child(border_rect_2)

	border_console = ColorRect.new()
	border_console.color.a = 0
	border_console.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	add_child(border_console)
	$Control/console.size.y = console_min_height
	repos()

	list.set_menu_size(
		($Control/scenes.size.x - list.position.x * 2 + 3) / list.scale.x,
		($Control/scenes.size.y - list.position.y - 10) / list.scale.y
	)

@export var console_bottom_offset: float = 41  # visual gap under console (only affects size/end)

func repos():
	border_rect_1.position = Vector2($Control/scenes.size.x - border_hit, $Control/scenes.global_position.y)
	border_rect_1.size = Vector2(border_hit * 2, $Control/scenes.size.y)
	border_rect_2.position = Vector2($Control/CodeEdit.size.x + $Control/CodeEdit.position.x, $Control/scenes.global_position.y)
	border_rect_2.size = Vector2(border_hit, $Control/scenes.size.y)

	var console_node = $Control/console
	var code_node = $Control/CodeEdit
	var scenes_node = $Control/scenes

	if code_hidden:
		console_node.position.x = code_node.position.x
		console_node.size.x = code_node.size.x
		console_node.position.y = scenes_node.position.y
		console_node.size.y = scenes_node.size.y - 42

	var top = console_node.global_position.y
	border_console.position = Vector2(console_node.global_position.x, top)
	border_console.size = Vector2(console_node.size.x - 10, border_hit)

	#$Control/console.position.x = code_pos.x - 1
	$Control/console.size.x = $Control/CodeEdit.size.x - 1

	var total_h = $Control/scenes.size.y
	if !code_hidden:
		var desired_codeedit_h = max(0.0, total_h - $Control/console.size.y - console_bottom_offset)
		$Control/CodeEdit.position.y = 0.0
		$Control/CodeEdit.size.y = desired_codeedit_h
		$Control/console.position.y = desired_codeedit_h
	console.position.x = $Control/scenes.size.x
	console.size.x = $Control/CodeEdit.size.x
	line_edit.global_position.y = $Control/console.get_global_rect().end.y
	line_edit.position.x = console.position.x + 10
	line_edit.size.x = $Control/CodeEdit.size.x / line_edit.scale.x - 34


var border_rect_1: ColorRect
var border_rect_2: ColorRect

func _window_hide():
	flush_pending_changes()  # ensure all pending edits are saved
	glob.fg.hide_back()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	glob.reset_menu_type(list, "list2")
	$CanvasLayer.hide()
	glob.un_occupy(list, &"menu")
	glob.un_occupy(list, "menu_inside")
	$CanvasLayer2.hide()



@onready var base_size = $Control.size
func _window_show():
	glob.fg.show_back()
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Control.position.y = glob.space_begin.y
	$Control.size.y = glob.window_size.y - $Control.position.y
	$CanvasLayer.show()
	show()
	$Control/scenes/list.menu_show($Control/scenes/list.global_position)
	prev_win = Vector2()
	tick()
	reload_scenes()
	await get_tree().process_frame
	$Control/scenes/list.update_children_reveal()
	$CanvasLayer2.show()

@export var line_edit: Control
@export var console: RichTextLabel
var last_demand: float = -1
func _process(delta: float) -> void:
	var vbar: VScrollBar = ($Control/console.get_v_scroll_bar())
	#var now = Time.get_ticks_msec() / 1000.0
#
	#if _pending_flush and now - _last_edit_time > _flush_cooldown and not pending_lock:
		#pending_lock = true
		#flush_pending_changes()
		#pending_lock = false
		#_pending_flush = false

	#tick()

	#vbar.position.x = $Control/console.size.x - 10
	tick()
	#if get_global_mouse_position().x > border_rect_1.position.x:
	#	print("aa")
	#	$Control/scenes/list.block_input(true)
	#else:
	#$Control/scenes/list.unblock_input(true)
	var bot = 0
	var top = 0
	if vbar.value < vbar.max_value - vbar.page - 5:
		bot = $Control/console.get_global_rect().end.y - 5
	if vbar.value > 5:
		top = $Control/console.global_position.y+30
	$Control/console.set_instance_shader_parameter("extents", Vector4(top, bot, 0, 0))
	$Control/ColorRect.position = $Control/console.position - Vector2(50,0)
	$Control/ColorRect.size = $Control/console.size + Vector2(105,50)
	$Control/view/Control.size.x = ($Control/view.size.x - \
	$Control/view/Control.position.x) / $Control/view/Control.scale.x

# ---- division settings ----
var division_ratio: Array[float] = [0.2, 0.6]
var min_scenes_size: float = 160.0
var max_scenes_size: float = 300.0
var min_game_size: float = 150.0
var max_game_size: float = 300.0
var prev_win: Vector2 = Vector2()
var border_hit = 10.0
var _dragging: int = -1
var _drag_anchor: float = 0.0
var code_hidden: bool = false
var max_game_size_ncode: float = 1800.0

var _console_prev_pos: Vector2
var _console_prev_size: Vector2

func set_code_hidden(hidden: bool) -> void:
	code_hidden = hidden
	var console_node = $Control/console
	var code_node = $Control/CodeEdit
	var scenes_node = $Control/scenes

	if hidden:
		# --- Save original layout ---
		_console_prev_pos = console_node.position
		_console_prev_size = console_node.size

		# --- Expand console to fill CodeEdit slot horizontally, full Scenes height vertically ---
		console_node.position.x = code_node.position.x
		console_node.size.x = code_node.size.x
		console_node.position.y = scenes_node.position.y
		console_node.size.y = scenes_node.size.y

		code_node.visible = false
	else:
		# --- Restore original console geometry ---
		console_node.position = _console_prev_pos
		console_node.size = _console_prev_size
		code_node.visible = true

	tick(true)
	ui.move_mouse(get_global_mouse_position())

func tick(force: bool = false) -> void:
	if not visible:
		return

	handle_division_drag()

	var win: float = glob.window_size.x
	$Control.position.y = glob.space_begin.y
	$Control.size.y = glob.window_size.y - $Control.position.y
	
	var scenes_w = clamp(win * division_ratio[0], min_scenes_size, max_scenes_size)


	# --- apply baseline layout (normal mode) ---
	$Control/scenes.size.x = scenes_w

	# --- modify only console when code is hidden ---
	if code_hidden:
		var console_node = $Control/console
		var code_node = $Control/CodeEdit
		var scenes_node = $Control/scenes

		# Horizontally: same slot as CodeEdit
		console_node.position.x = code_node.position.x
		console_node.size.x = code_node.size.x

		# Vertically: match full height of Scenes panel
		console_node.position.y = scenes_node.position.y
		#console_node.size.y = scenes_node.size.y

		code_node.visible = false
	else:
		$Control/CodeEdit.visible = true



	repos()
	if _dragging != -1 or _dragging_console:
		$Control/CodeEdit.addition_enabled = false
		#(_dragging)
		list.set_menu_size(
			($Control/scenes.size.x - list.position.x * 2 + 3) / list.scale.x,
			($Control/scenes.size.y - list.position.y - 10) / list.scale.y
		)
	else:
		$Control/CodeEdit.addition_enabled = true

	prev_win = glob.window_size
	#$Control/CodeEdit.size.x = glob.window_size.x - $Control/scenes.size.x - $Control/view.size.x
	$Control/console.size.x = $Control/CodeEdit.size.x
	if _dragging:
		$Control/view.position.x = $Control/scenes.size.x + $Control/CodeEdit.size.x
		$Control/view.size.x = glob.window_size.x - ($Control/scenes.size.x + $Control/CodeEdit.size.x)
	#var codeedit_w = 0.0 if code_hidden else codeedit_target
	#var game_w = win - scenes_w - codeedit_target  # always compute as if codeedit visible

	$Control/CodeEdit.position.x = $Control/scenes.size.x
	var codeedit_target = min(win * division_ratio[1], glob.window_size.x - min_game_size)
	$Control/CodeEdit.size.x = codeedit_target
	#repos()
	$Control/console.size.x = $Control/CodeEdit.size.x
	$Control/ColorRect.size.x = $Control/console.size.x
	#$Control/console.size.x = $Control/console.size.x
	repos()



	#if not current_lua_env:
	#	if not received_texts:
	#		$Control/CodeEdit.text = "-- Create your scene in the Scenes menu."
	#	else:
	#		$Control/CodeEdit.text = "-- Select your scene from the Scenes menu."
	#await get_tree().process_frame
	#if !is_instance_valid(last_button):
		#if last_hint in $Control/scenes/list.button_by_hint:
			#_on_list_child_button_release($Control/scenes/list.button_by_hint[last_hint])
		#elif received_texts and $Control/scenes/list._contained:
			#_on_list_child_button_release($Control/scenes/list._contained[0])

var border_console: ColorRect
var _dragging_console: bool = false
var _drag_anchor_y_console: float = 0.0
var console_min_height: float = 83.0
var console_max_height: float = 500.0




func handle_top_drag() -> void:
	if not visible:
		return
		

	var ctrl = $Control
	var codeedit = ctrl.get_node("CodeEdit")
	var console = ctrl.get_node("console")
	if console == null or codeedit == null:
		return

	var mp = get_global_mouse_position()
	var border_y = console.global_position.y

	# Start drag
	if not code_hidden and glob.mouse_just_pressed and mp.y >= border_y and mp.y - border_y <= border_hit and mp.x > console.global_position.x and mp.x < console.get_global_rect().end.x - 10:
		_dragging_console = true
		_drag_anchor_y_console = mp.y - border_y
	elif not glob.mouse_pressed and _dragging_console:
		_dragging_console = false

	# While dragging
	if _dragging_console and glob.mouse_pressed:
		var new_border_y = mp.y - _drag_anchor_y_console
		var local_y = new_border_y - ctrl.global_position.y

		var total_height = ctrl.size.y - console_bottom_offset
		var new_codeedit_height = clamp(local_y, 100.0, max(100.0, total_height - console_min_height))
		var new_console_height = clamp(total_height - new_codeedit_height, console_min_height, console_max_height)

		codeedit.position.y = 0
		codeedit.size.y = new_codeedit_height

		console.position.y = new_codeedit_height
		console.size.y = new_console_height

		border_console.position = Vector2(console.global_position.x, console.global_position.y)
		border_console.size = Vector2(console.size.x, border_hit)
		repos()

	#console.size.y = new_console_height - 20




func handle_division_drag() -> void:
	handle_top_drag()
	if not visible:
		return

	var win = glob.window_size.x
	if win <= 0.0:
		return

	var scenes_w = $Control/scenes.size.x
	var code_target = win * division_ratio[1]
	var game_w = clamp(win - scenes_w - code_target, min_game_size, max_game_size)
	var code_w = max(0.0, win - scenes_w - game_w)

	var border1 = scenes_w
	var border2 = scenes_w + code_w

	var mp = get_global_mouse_position()
	var ctrl = $Control
	var in_y = mp.y >= ctrl.position.y and mp.y <= (ctrl.position.y + ctrl.size.y)

	if glob.mouse_just_pressed and in_y:
		if abs(mp.x - border1) <= border_hit:
			_dragging = 0
			_drag_anchor = border1 - mp.x
		elif mp.x - border2 <= border_hit and mp.x >= border2:
			_dragging = 1
			_drag_anchor = border2 - mp.x
	#var new_xs = clamp(mp.x + _drag_anchor, 0.0, win)
	#var new_sceness = clamp(new_xs, min_scenes_size, max_scenes_size)
	#var desired_codes = max(0.0, border2 - new_sceness)
#
	var new_games = clamp(win - $Control/scenes.size.x - $Control/CodeEdit.size.x, min_game_size, max_game_size)
	var new_codes = max(0.0, win - $Control/scenes.size.x - new_games)
	division_ratio[1] = new_codes / win

	if glob.mouse_pressed and _dragging != -1:
		var new_x = clamp(mp.x + _drag_anchor, 0.0, win)

		if _dragging == 0:
			var new_scenes = clamp(new_x, min_scenes_size, max_scenes_size)
			var desired_code = max(0.0, border2 - new_scenes)

			var new_game = clamp(win - new_scenes - desired_code, min_game_size, max_game_size)
			var new_code = max(0.0, win - new_scenes - new_game)

			division_ratio[0] = new_scenes / win
			division_ratio[1] = new_code / win

		elif _dragging == 1:
			var desired_code = max(0.0, new_x - scenes_w)

			var new_game = clamp(win - scenes_w - desired_code, min_game_size, max_game_size)
			var new_code = max(0.0, win - scenes_w - new_game)

			division_ratio[0] = scenes_w / win
			division_ratio[1] = new_code / win
	
	if  _dragging != -1:
		$Control/view/Control.re($Control/view.size.x)
	
	if not glob.mouse_pressed and _dragging != -1:
		_dragging = -1
		_drag_anchor = 0.0
	
	#division_ratio[0] = $Control/scenes.size.x / win
	#division_ratio[1] = $Control/CodeEdit.size.x / win

	$Control/view/Label.resize()


func _on__released() -> void:
	set_code_hidden(!code_hidden)


@onready var plus = $Control/scenes/plus
func _on_plus_released() -> void:
	var plus_string = "dataset_create"
	plus.block_input()
	var a = await ui.splash_and_get_result(plus_string, plus, null, false)
	await get_tree().process_frame
	var m = func(): return glob.mouse_pressed
	while m.call():
		await get_tree().process_frame
	plus.unblock_input()
	if a:
		#(a)
		await get_tree().process_frame
		await get_tree().process_frame
		if list._contained:
			_on_list_child_button_release(list._contained[-1])

var received_texts = {}
func request_texts() -> Dictionary:
	var texts = glob.ds_dump
	received_texts = texts
	#$Control/CodeEdit.editable = len(texts) > 0
	return texts



func reload_scenes():
	$Control/scenes/list.show_up(request_texts())
	#(current_ds)

			#$Control/CodeEdit.text = "-- Select your scene from the Scenes menu."
	await get_tree().process_frame
	if !is_instance_valid(last_button):
		if last_hint in $Control/scenes/list.button_by_hint:
			_on_list_child_button_release($Control/scenes/list.button_by_hint[last_hint])
		elif received_texts and $Control/scenes/list._contained:
			_on_list_child_button_release($Control/scenes/list._contained[0])
	if current_ds == null:
		if not received_texts:
			$Control/CodeEdit.load_empty_dataset(false)
			#$Control/CodeEdit.text = "-- Create your scene in the Scenes menu."
		else:
			$Control/CodeEdit.load_empty_dataset(false)
		$Control/CodeEdit.disabled = true
	else:
		
		$Control/CodeEdit.disabled = false

var last_hint = null
var last_button: BlockComponent = null
var current_ds = null
var histories = {}
func _on_list_child_button_release(button: BlockComponent) -> void:
	await glob.join_ds_save()
	if button.hint in histories:
		$Control/console.text = histories[button.hint]
	$Control/LineEdit/CodeEdit2
	histories[button.hint] = $Control/console.text
	var code = $Control/CodeEdit
	if last_button:
		last_button.set_tuning(last_button.base_tuning)
	button.set_tuning(button.base_tuning * 2)
	last_button = button
	current_ds = button.hint
	last_hint = button.hint
	#code.set_uniform_row_height(randi_range(50, 100))
	#code.load_empty_dataset()
	var ds = glob.get_dataset_at(button.metadata["content"]["name"])
	ds["name"] = button.metadata["content"]["name"]
	var got = ds["arr"]
	#(got)
	#(ds["col_names"])
	#(ds)
	code.dataset_obj = ds
	var cols = ds["col_names"]
	#code.disable()
	#code.data_map_allowed = false
	code.hide()
	code.set_column_arg_packs(ds["col_args"])
	code.load_dataset(got, len(cols), len(got))
	#(code._get_cell(0,1))
	#(code.get_column_arg_pack(1))
	#(ds["col_args"])
	code.set_column_names(cols)
	code.set_outputs_from(ds["outputs_from"])
	code.reindex_cache()
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().process_frame
	#code.data_map_allowed = true
	#code.active_remap()
	code.refresh_preview()
	await get_tree().process_frame
	code.show()
	#code.enable()
	#ds["col_names"] = cols
	$Control/LineEdit/CodeEdit2.connect_ds(got)


func _on_train_2_released() -> void:
	$Control/console.clear()

@onready var csv = $Control/view/Label/run
func _on_run_released() -> void:
	pass
	#var a = await ui.splash_and_get_result("path_open", csv)
	#(dsreader.parse_csv_dataset("user://test.csv"))
	#(a)

#no_outputs no_1d_outs mix_2d bad_img
func _on_code_edit_preview_refreshed(pr: Dictionary) -> void:
	if not $Control/CodeEdit.dataset_obj or not $Control/CodeEdit.dataset_obj.has('name'): 
		$Control/view/warn.text = ""
		return
	#("AAAAAAAAAAAAAAH")
	glob.previewed[$Control/CodeEdit.dataset_obj.name] = pr

	var prev = pr.duplicate(true)
	var dt = "1d"# "\n".join(prev["outputs"][0]["label_names"])
	#(prev)
	$Control/view/warn.text = ""
	var lang = glob.get_lang()
	if "fatal" in prev: 
		glob.invalidate_local_ds($Control/CodeEdit.dataset_obj.name)
		$Control/view/warn.text = ""
		return
	if not "fail" in prev:
		var nm = $Control/CodeEdit.dataset_obj.name
		glob.change_local_ds(nm)
		if glob.get_lang() == "kz":
			nm = "Шығыс"
		if glob.get_lang() == "ru":
			nm = "Вывод"
		prev["input_hints"].append({"name": nm, "value": 
			"len:\n"+str(len(prev["outputs"][0]["label_names"])), 
		"dtype": "%s"%dt})
	else:
		glob.invalidate_local_ds($Control/CodeEdit.dataset_obj.name)
		var txt = ""
		match prev["fail"]:
			"no_outputs":
				match lang:
					"ru":
						txt = "Выходы не настроены должным образом"
					"kz":
						txt = "Шығыстар дұрыс бапталмаған"
					_:
						txt = "No outputs properly configured"
			"no_1d_outs":
				match lang:
					"ru":
						txt = "Выходы могут быть только одномерными (без изображений)"
					"kz":
						txt = "Шығыстар тек бір өлшемді болуы тиіс (кескіндерсіз)"
					_:
						txt = "Outputs can be only 1D (no images)"
			"mix_2d":
				match lang:
					"ru":
						txt = "1D и 2D входы не могут смешиваться"
					"kz":
						txt = "1D және 2D кірістерді араластыруға болмайды"
					_:
						txt = "1D and 2D mix in inputs is prohibited"
			"preprocess_txt":
				match lang:
					"ru":
						txt = "Необходимо провести препроцессинг текстовых полей (токенизация)"
					"kz":
						txt = "Мәтін өрістерін алдын ала өңдеу қажет (токенизация)"
					_:
						txt = "Tokenization is required before using text datasets"
			"bad_img":
				match lang:
					"ru":
						txt = "Изображения настроены неверно (разные размеры или пустые строки)"
					"kz":
						txt = "Кескін бағандары дұрыс бапталмаған (өлшемдері әртүрлі немесе бос жолдар)"
					_:
						txt = "Image columns aren't properly configured (different sizes or empty rows)"
		
		$Control/view/warn.text = txt
		$Control/view/warn.self_modulate = Color.CORAL
		prev = {"name": $Control/CodeEdit.dataset_obj.name}
	$Control/view/Control.push_cfg(prev)
	#await get_tree().process_frame
	$Control/view/Control.re($Control/view.size.x)
	$Control/view/Control.re($Control/view.size.x)


func _on_control_item_rect_changed() -> void:
	list.set_menu_size(
		($Control/scenes.size.x - list.position.x * 2 + 3) / list.scale.x,
		($Control/scenes.size.y - list.position.y - 10) / list.scale.y
	)
	$Control/view/Control.re($Control/view.size.x)
	$Control/view/Control.re($Control/view.size.x)

var demanded: Callable
var idxs = {}
var once_null = false
var pending_inserts: Array[int] = []
var pending_deletes: Array[int] = []
var pending_rebuild = false
var pending_lock = false
func _on_code_edit_dirtified(idx: Variant, is_insert: bool = false, is_delete: bool = false) -> void:
	if pending_lock:
		return

	var name = $Control/CodeEdit.dataset_obj["name"]
	#("a")

	# --- FULL REBUILD ---
	if idx == null:
		pending_rebuild = true
		pending_inserts.clear()
		pending_deletes.clear()
		idxs.clear()
		return

	# --- INSERT / DELETE (just queue, don't flush now) ---
	if is_insert:
		pending_inserts.append(idx)
		return
	elif is_delete:
		pending_deletes.append(idx)
		return

	# --- DELTA (flush immediately, safe and fast) ---
	idxs[idx] = true
	if not pending_lock:
		await get_tree().process_frame
		pending_lock = true
		glob.cache_rle_compress(name, idxs.keys(), "delta")
		#DsObjRLE.flush_now(name, $Control/CodeEdit.dataset_obj)  # <-- immediate flush
		idxs.clear()
		pending_lock = false


func _on_code_edit_deleted() -> void:
	$Control/scenes/list.show_up(request_texts())
	await get_tree().process_frame
	await get_tree().process_frame
	if list._contained:
		_on_list_child_button_release(list._contained[-1])
