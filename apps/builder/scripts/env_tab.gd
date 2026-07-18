extends TabWindow

@onready var list = $Control/scenes/list
func _ready() -> void:
	#$CanvasLayer/ColorRect.color = $Control/console.get_theme_stylebox("normal").bg_color
	
	window_hide()
	await get_tree().process_frame
	glob.reset_menu_type(list, "list")
	$CanvasLayer.hide()
	glob.un_occupy(list, &"menu")
	glob.un_occupy(list, "menu_inside")
	border_rect_1 = ColorRect.new()
	border_rect_1.color.a = 0; border_rect_1.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	add_child(border_rect_1)
	border_rect_2 = ColorRect.new()
	border_rect_2.color.a = 0; border_rect_2.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	add_child(border_rect_2)
	border_console = ColorRect.new()
	border_console.color.a = 0
	border_console.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	add_child(border_console)
	
	repos()
	#border_console.position.y -= 3
	#$Control/console.position.y -= 3

var border_console: ColorRect
var _dragging_console: bool = false
var _drag_anchor_y_console: float = 0.0
var console_min_height: float = 50.0
var console_max_height: float = 500.0




func repos():
	border_rect_1.position = Vector2($Control/scenes.size.x - border_hit, 
	$Control/scenes.global_position.y)
	border_rect_1.size = Vector2(border_hit*1, $Control/scenes.size.y)
	border_rect_2.position = Vector2($Control/CodeEdit.size.x + $Control/CodeEdit.position.x, 
	$Control/scenes.global_position.y)
	border_rect_2.size = Vector2(border_hit, $Control/scenes.size.y)
	# vertical resize border for CodeEdit
	var code_pos = $Control/CodeEdit.global_position
	var console_node = $Control/console
	var top = console_node.global_position.y
	border_console.position = Vector2(console_node.global_position.x, top)
	border_console.size = Vector2(console_node.size.x - 10, border_hit)
	$Control/console.position.x = code_pos.x
	$Control/console.size.x = $Control/CodeEdit.size.x
	$Control/CodeEdit.size.y = $Control/scenes.size.y - $Control/console.size.y# - 3



var border_rect_1: ColorRect
var border_rect_2: ColorRect

func _window_hide():
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	glob.reset_menu_type(list, "list")
	$CanvasLayer.hide()
	glob.un_occupy(list, &"menu")
	glob.un_occupy(list, "menu_inside")
	var viewport = $Control/view/game
	viewport.render_target_clear_mode = viewport.CLEAR_MODE_ALWAYS
	if process != null and running_name in luas.processes:
		run_bt.get_node("TextureRect").texture = run_base_txt
		luas.remove_process(running_name); return
	
func reload_scenes():
	$Control/scenes/list.show_up(request_texts())
	if not current_lua_env:
		if not received_texts:
			match glob.get_lang():
				"kz":
					$Control/CodeEdit.text = "-- Әлемдер мәзірінде өз әлеміңізді жасаңыз."
				"ru":
					$Control/CodeEdit.text = "-- Создайте ваш мир в меню сцен слева."
				_:
					$Control/CodeEdit.text = "-- Create your world in the Scenes menu."
		else:
			match glob.get_lang():
				"kz":
					$Control/CodeEdit.text = "-- Әлемдер мәзірінен әлемді таңдаңыз."
				"ru":
					$Control/CodeEdit.text = "-- Выберите ваш мир в миров сцен слева."
				_:
					$Control/CodeEdit.text = "-- Select your scene from the Scenes menu."
	await get_tree().process_frame
	if !is_instance_valid(last_button):
		if last_hint in $Control/scenes/list.button_by_hint:
			_on_list_child_button_release($Control/scenes/list.button_by_hint[last_hint])
		elif received_texts and $Control/scenes/list._contained:
			_on_list_child_button_release($Control/scenes/list._contained[0])

@onready var base_size = $Control.size
func _window_show():
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
	if last_hint != null:
		if last_hint in $Control/scenes/list.button_by_hint:
			_on_list_child_button_release($Control/scenes/list.button_by_hint[last_hint])
	elif $Control/scenes/list._contained:
		_on_list_child_button_release($Control/scenes/list._contained[0])
	for i in 5:
		await get_tree().process_frame
	$Control/scenes/list.update_children_reveal()



func _process(_delta: float) -> void:
	tick()

	var console := $Control/console
	var vbar: VScrollBar = console.get_v_scroll_bar()
	var top := 0.0
	var bot := 0.0

	# Detect scroll state
	var top_now := vbar.value > 5.0
	var bot_now := vbar.value < vbar.max_value - vbar.page - 5.0

	# Apply shader extents (world coords as before)
	if bot_now:
		bot = console.get_global_rect().end.y
	if top_now:
		top = console.global_position.y + 32.0

	console.set_instance_shader_parameter("extents", Vector4(top, bot, 0, 0))

	# Handle the CodeEdit Y-size correction
	#var codeedit := $Control/CodeEdit
#
	#if top_now and not console_offset_applied:
		#codeedit.size.y -= CONSOLE_FIX_OFFSET
		##codeedit.position.y += CONSOLE_FIX_OFFSET
		#console_offset_applied = true
#
	#elif not top_now and console_offset_applied:
		#codeedit.size.y += CONSOLE_FIX_OFFSET
		##codeedit.position.y -= CONSOLE_FIX_OFFSET
		#console_offset_applied = false


var division_ratio: Array[float] = [0.2, 0.6]
var min_scenes_size: float = 150.0
var max_scenes_size: float = 300.0
var min_game_size: float = 150.0
var max_game_size: float = 500.0
var prev_win: Vector2 = Vector2()
var border_hit = 10.0
var _dragging: int = -1
var _drag_anchor: float = 0.0

var code_hidden: bool = false
var max_game_size_ncode: float = 1800.0

func set_code_hidden(hidden: bool) -> void:
	code_hidden = hidden
	$Control/CodeEdit.visible = not hidden
	$Control/console.visible = not hidden
	tick(true)
	ui.move_mouse(get_global_mouse_position())


var console_top_visible := false
var console_offset_applied := false
const CONSOLE_FIX_OFFSET := 3.0



func handle_top_drag() -> void:
	if not visible:
		return

	var ctrl = $Control
	var codeedit = ctrl.get_node("CodeEdit")
	var console = ctrl.get_node("console")
	if console == null or codeedit == null:
		return

	var mp = get_global_mouse_position()
	var border_y = console.global_position.y           # border between them

	# Start drag
	if glob.mouse_just_pressed and mp.y >= border_y+1 and mp.y < border_hit+border_y+1 and mp.x > console.global_position.x and mp.x < console.get_global_rect().end.x - 10:
		_dragging_console = true
		_drag_anchor_y_console = mp.y - border_y
	elif not glob.mouse_pressed and _dragging_console:
		_dragging_console = false

	# While dragging
	if _dragging_console and glob.mouse_pressed:
		var new_border_y = mp.y - _drag_anchor_y_console
		var local_y = new_border_y - ctrl.global_position.y

		# Total vertical span for both areas
		var total_height = ctrl.size.y
		var new_codeedit_height = clamp(local_y, 100.0, total_height - console_min_height)
		var new_console_height = clamp(total_height - new_codeedit_height, console_min_height, console_max_height)

		# Apply sizes and positions in parent's space
		codeedit.position.y = 0
		codeedit.size.y = new_codeedit_height

		console.position.y = new_codeedit_height
		console.size.y = new_console_height

		# Update visual drag bar
		border_console.position = Vector2(console.global_position.x, console.global_position.y)
		border_console.size = Vector2(console.size.x, border_hit)
		repos()
		#border_console.position.y -= 3
		#console.position.y -= 3





func tick(force: bool = false) -> void:
	
	if not visible:
		return
	handle_division_drag()
	handle_top_drag()

	var win: float = glob.window_size.x
	if get_global_mouse_position().x > border_rect_2.position.x:
		pass
		#$Control/CodeEdit.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		$Control/CodeEdit.process_mode = Node.PROCESS_MODE_INHERIT
	if get_global_mouse_position().x > border_rect_1.position.x:
	#	print("aa")
		$Control/scenes/list.block_input(true)
	else:
		$Control/scenes/list.unblock_input(true)
	if prev_win != glob.window_size or _dragging != -1 or force:
		$Control.position.y = glob.space_begin.y
		$Control.size.y = glob.window_size.y - $Control.position.y

		var scenes_w = clamp(win * division_ratio[0], min_scenes_size, max_scenes_size)

		var codeedit_target = min(win * division_ratio[1], glob.window_size.x - min_game_size - scenes_w)
		var codeedit_w = 0.0 if code_hidden else codeedit_target

		var game_w = win - scenes_w - codeedit_w
		game_w = clamp(game_w, min_game_size, max_game_size_ncode if code_hidden else max_game_size)

		if not code_hidden:
			if codeedit_w < 0.0:
				var deficit = -codeedit_w
				game_w = max(min_game_size, game_w - deficit)
				codeedit_w = max(0.0, win - scenes_w - game_w)
				if codeedit_w < 0.0:
					codeedit_w = 0.0
					game_w = max(0.0, win - scenes_w)

		$Control/scenes.size.x = scenes_w
		$Control/CodeEdit.position.x = scenes_w
		$Control/CodeEdit.size.x = codeedit_w

		$Control/view.position.x = scenes_w + codeedit_w
		$Control/view.size.x = game_w

		var rect = $Control/view/TextureRect
		var game_window = $Control/view
		if rect.size.x > 0.0:
			rect.scale = Vector2.ONE * ((game_w-4) / float(rect.size.x))
		else:
			rect.scale = Vector2.ONE
		var max_y = game_window.size.y - 0.2 * (glob.window_size.y + 60)
		var x = 2
		var y = 0
		if rect.size.y * rect.scale.y > max_y:
			rect.scale = Vector2.ONE * max_y / rect.size.y
			x += game_w / 2 - rect.scale.x * rect.size.x / 2
			y += 15
			y -= glob.window_size.y * 0.02
		y += 5
		rect.position = Vector2(x, game_window.size.y / 2 - rect.scale.y * rect.size.y / 2 + y)


		var scenes_size_y = $Control/scenes.size.y
		list.set_menu_size(
			($Control/scenes.size.x - list.position.x * 2 + 3) / list.scale.x,
			(scenes_size_y - list.position.y - 10) / list.scale.y
		)
		
		if code_hidden:
			$Control/scenes.size.x += 2
		prev_win = glob.window_size
		repos()
	
	$Control/view/Label.resize()






func handle_division_drag() -> void:
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
		if border1 - mp.x < border_hit and border1 - mp.x > 0:
			_dragging = 0
			_drag_anchor = border1 - mp.x
		elif mp.x - border2 <= border_hit and mp.x >= border2:
			_dragging = 1
			_drag_anchor = border2 - mp.x

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

	if not glob.mouse_pressed and _dragging != -1:
		_dragging = -1
		_drag_anchor = 0.0


func _on__released() -> void:
	set_code_hidden(!code_hidden)


func get_current_game_name() -> String:
	return "Lua_process_1"


func get_current_game_code() -> String:
	return $Control/CodeEdit.text


var received_texts = {}
func request_texts() -> Dictionary:
	var texts = glob.env_dump
	received_texts = texts
	$Control/CodeEdit.editable = len(texts) > 0
	return texts


func get_texts():
	return received_texts

var count: int = 0
func debug_print(args: Array):
#	$Control/console.append_text("[color=gray][" + str(count) + "][/color] ")
	$Control/console.append_text(" ".join(args))
	$Control/console.append_text("\n")
	count += 1

var process: LuaProcess = null; var running_name = null
@onready var run_bt = $Control/view/run
@onready var run_base_txt = $Control/view/run.get_node("TextureRect").texture
func _on_run_released() -> void:
	#if process:
	#	print(process.stepping())
	var viewport = $Control/view/game
	if process != null and running_name in luas.processes:
		run_bt.get_node("TextureRect").texture = run_base_txt
		viewport.render_target_clear_mode = viewport.CLEAR_MODE_NEVER
		luas.remove_process(running_name); return
	viewport.render_target_clear_mode = viewport.CLEAR_MODE_ALWAYS
	$Control/console.clear()
	run_bt.get_node("TextureRect").texture = glob.stop_icon
	
	count = 0
	running_name = get_current_game_name()
	process = luas.create_process(running_name, get_current_game_code())
	process.execution_finished.connect(func():
		#("AA")
		run_bt.get_node("TextureRect").texture = run_base_txt)
	process.debug_printer = debug_print
	viewport.add_child(process)
	process.position.y = 0

func reset():
	current_lua_env = null
	last_button = null
	last_hint = null
	cursors.clear()


var last_hint = null
var last_button: BlockComponent = null
var current_lua_env = null
var cursors: Dictionary[String, Vector2i] =  {}
func _on_list_child_button_release(button: BlockComponent) -> void:
	var viewport = $Control/view/game
	viewport.render_target_clear_mode = viewport.CLEAR_MODE_ALWAYS
	var code = $Control/CodeEdit
	if last_button:
		cursors[current_lua_env] = Vector2i(code.get_caret_column(), code.get_caret_line())
		last_button.set_tuning(last_button.base_tuning)
	button.set_tuning(button.base_tuning * 2)
	last_button = button
	current_lua_env = button.hint
	last_hint = button.hint
	$Control/view/Label.text = last_hint
	$Control/view/Label.resize()
	$Control/CodeEdit.text = received_texts[button.hint]
	if current_lua_env and current_lua_env in cursors:
		code.set_caret_column(cursors[current_lua_env].x)
		code.set_caret_line(cursors[current_lua_env].y)


func _on_code_edit_text_changed() -> void:
	await get_tree().process_frame
	if current_lua_env:
		received_texts[current_lua_env] = $Control/CodeEdit.text
		
		#$Control/scenes/list.button_by_hint[current_lua_env].metadata["content"] = $Control/CodeEdit.text
	

@onready var plus = $Control/scenes/plus
func _on_plus_released() -> void:
	var a = await ui.splash_and_get_result("scene_create", plus, null, false)
	if a and a.has("text"):
		await get_tree().process_frame
		await get_tree().process_frame
		var cont = ($Control/scenes/list._contained)
		for i in cont:
			if i.hint == a.text:
				_on_list_child_button_release(i)


func _on_train_2_released() -> void:
	$Control/console.clear()
