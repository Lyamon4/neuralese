extends SplashMenu

var toppath_valid = ""
var lbl_valid = ""
func _ready() -> void:
	super()
	#('FJFJ')
	$ColorRect/toppath.set_is_valid_call(func(input):
		var has = DirAccess.dir_exists_absolute(input) or FileAccess.file_exists(input)
		if has:
			toppath_valid = input
		return has)
	$ColorRect/Label.set_is_valid_call(func(input):
		if not input: return true
		var dir = grid.current_dir
		if not input.begins_with("/"):
			dir += "/"
		dir += input
		#(dir)
		var exists = FileAccess.file_exists(dir)
		if "dirs" in passed_data:
			exists = exists or DirAccess.dir_exists_absolute(dir)
		#if exists:
		if exists:
			grid.select_path(dir, false)
			lbl_valid = input
		return exists)
var old_dir: String = ""
var prev_filter = null
func _just_splash():
	var got = passed_data.get("filter", [])
	var hs = got.hash()
	if !old_dir or (prev_filter == null or prev_filter != hs):
		grid.hide()
		await stable
		old_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	#("AA")
		prev_filter = hs
		grid.current_dir = old_dir
		#(old_dir)
		grid.filter_extensions = glob.to_set(got)
		grid.refresh()
		grid.show()

func _process(delta: float) -> void:
	super(delta)
	if $ColorRect/ScrollContainer.get_global_rect().has_point(get_global_mouse_position()):
		$ColorRect/list.block_input(true)
	#	print("fkfk")
	else:
		$ColorRect/list.unblock_input(true)


func _resultate(data: Dictionary):
	old_dir = grid.current_dir
	if "goto_splash" in passed_data:
		can_go = false
		go_away()
		await quitting
		hide()
		#queue_free()
		ui.splash_and_get_result(passed_data["goto_splash"], splashed_from, emitter, true, 
		{ "path": data["path"]})
	elif "from" in passed_data:
		can_go = false
		go_away()
		await quitting
		hide()
		#queue_free()
		ui.splash_and_get_result("dataset_create", splashed_from, emitter, true, 
		{"txt": passed_data.get("txt", ""), "path": data["path"]})
	elif "from_proj" in passed_data:
		glob.import_project_from_file(data["path"])
		emitter.res.emit(data)
		#glob.env_dump[data["text"]] = glob.get_default_script(data["text"])
		#glob.tree_windows["env"].reload_scenes()
		go_away()
		await quitting
		pass
		hide()
		ui.blur.self_modulate.a = 0.0
	else:
		emitter.res.emit(data)
		#glob.env_dump[data["text"]] = glob.get_default_script(data["text"])
		#glob.tree_windows["env"].reload_scenes()
		go_away()
		await quitting
		pass
		hide()
		ui.blur.self_modulate.a = 0.0


func _quit_request():
	grid._clear_selection()
	if "goto_splash" in passed_data:
		can_go = false
		go_away()
		await quitting
		hide()
		#queue_free()
		ui.splash_and_get_result(passed_data["goto_splash"], splashed_from, emitter, true, 
		{ })
	elif "from" in passed_data:
		can_go = false
		await quitting
		#queue_free()
		hide()
		ui.splash("dataset_create", splashed_from, emitter, true, 
		{"txt": passed_data.get("txt", "")})
	elif "from_proj" in passed_data:
		can_go = false
		await quitting
		#queue_free()
		hide()
		ui.splash("workslist", passed_data["from_proj"], emitter, true)
	else:
		can_go = true
		await quitting
		pass
		hide()
		ui.blur.self_modulate.a = 0.0

func _on_trainn_released() -> void:
	ress()
	
func ress():
	$ColorRect/Label.update_valid()
	if $ColorRect/Label.is_valid and $ColorRect/Label.text:
		resultate({"path": grid.selected_path})

@onready var grid = $ColorRect/ScrollContainer/GridContainer
@onready var list = $ColorRect/list
func _on_list_child_button_release(button: BlockComponent) -> void:
	button.block_input()
	var dir = -1
	await glob.wait(0.1)
	match button.hint:
		"desk":
			dir = OS.SYSTEM_DIR_DESKTOP
		"downloads":
			dir = OS.SYSTEM_DIR_DOWNLOADS
		"docs":
			dir = OS.SYSTEM_DIR_DOCUMENTS
		"pics":
			dir = OS.SYSTEM_DIR_PICTURES
	if dir != -1:
		grid.current_dir = OS.get_system_dir(dir)
	await grid.refresh()
	await glob.wait(0.1)
	button.unblock_input()
	lbl_valid = ""
	$ColorRect/Label.set_line("")


func _on_refresh_released() -> void:
	grid.refresh()
	lbl_valid = ""
	$ColorRect/Label.set_line("")


func quit(data: Dictionary = {}):
	if not visible: return
	quitting.emit()
	#(grid.current_dir)
	old_dir = grid.current_dir
	hide()
	if can_go:
		glob.mouse_just_pressed = false
		hide()
		ui.blur.self_modulate.a = 0
		emitter.res.emit(data)

func _on_undo_released() -> void:
	grid.go_up()


var prev_tuned = null
func _on_grid_container_refreshed() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	$ColorRect/toppath.set_line(grid.current_dir)
	if prev_tuned:
		prev_tuned.set_tuning(prev_tuned.base_tuning)
	for i in list.button_by_hint:
		var dir = -1
		match i:
			"desk":
				dir = OS.SYSTEM_DIR_DESKTOP
			"downloads":
				dir = OS.SYSTEM_DIR_DOWNLOADS
			"docs":
				dir = OS.SYSTEM_DIR_DOCUMENTS
			"pics":
				dir = OS.SYSTEM_DIR_PICTURES
		if dir != -1 and str(grid.current_dir).simplify_path() == OS.get_system_dir(dir):
			prev_tuned = list.button_by_hint[i]
			prev_tuned.set_tuning(prev_tuned.base_tuning * 2)
			break




func _on_grid_container_directory_entered(path: String) -> void:
	lbl_valid = ""
	$ColorRect/Label.set_line("")


func _on_grid_container_file_hovered(path: String, is_dir: bool) -> void:
	if not is_dir:
		$ColorRect/Label.set_line(path.split("/")[-1])
	elif is_dir and "dirs" in passed_data:
		$ColorRect/Label.set_line(path.split("/")[-1])


func _on_toppath_line_enter() -> void:
	await get_tree().process_frame
	if !$ColorRect/toppath.is_valid:
		$ColorRect/toppath.set_line(toppath_valid)
	elif grid.current_dir.simplify_path() != $ColorRect/toppath.text.simplify_path():
		grid.current_dir = $ColorRect/toppath.text
		var txt = grid.current_dir
		if !DirAccess.dir_exists_absolute(grid.current_dir):
			grid.current_dir = txt.get_base_dir()
		lbl_valid = ""
		$ColorRect/Label.set_line("")
		await grid.refresh()
		await get_tree().process_frame
		grid.select_path(txt)


func _on_label_line_enter() -> void:
	await get_tree().process_frame
	if !$ColorRect/Label.is_valid:
		$ColorRect/Label.set_line(lbl_valid)


func _on_grid_container_file_selected(path: String) -> void:
	pass
	#ress()
