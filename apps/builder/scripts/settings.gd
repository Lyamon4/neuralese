extends SplashMenu

@onready var list = $ColorRect/list
@onready var diff = $ColorRect.size.x - $ColorRect/Account.position.x
func _process(delta: float) -> void:
	var prev_s = $ColorRect.scale
	super(delta)
	#list_unroll.max_size = 50
	$ColorRect/Account.position.x = $ColorRect.size.x - diff

func usr_update():
	var prefix = "User: "
	match glob.curr_lang:
		"kz":
			prefix = "Адам: "
		"ru":
			prefix = "Юзер: "
	$ColorRect/Control/Label.text = prefix + cookies.user()


func _exit_tree() -> void:
	if stream:
		stream.cancel()

var stream = null

@onready var lock_button = $ColorRect/classroomstatus/lock
@onready var base_text = lock_button.get_node("t").texture
var open_text = preload("res://game_assets/icons/lock_open.png")
func hide_role_panels() -> void:
	$ColorRect/studentjoin.hide()
	$ColorRect/studentyes.hide()
	$ColorRect/classroomstatus.hide()
	$ColorRect/classroomcr.hide()

func open_lesson(idx: int):
	var list = learner.classroom_lesson_list()
	if idx < len(list) and idx >= 0:
		var lesson_key = list.keys()[idx]
		if learner.classroom_data.get("lesson_customs", {}):
			var me = learner.classroom_data.lesson_customs.get(idx, {})
			if !me.get("opened", false): lock_button.get_node("t").texture = base_text
			else: lock_button.get_node("t").texture = open_text
		lesson_index = idx
		curr_lesson = learner.get_lesson_data(lesson_key)
		if curr_lesson.is_empty():
			push_warning("Lesson data missing for key: %s" % str(lesson_key))
			return
		if last_snapshot:
			snapshot_receive(last_snapshot)
		$ColorRect/classroomstatus/Control2/Label.text = str(idx+1) + ". " + curr_lesson.lesson_title
		$ColorRect/classroomstatus/Control2/Label.resize()
			
var curr_lesson = null

var lesson_index: int = 0
var last_snapshot = null
func snapshot_receive(evt: Dictionary):
	if evt.get("event", "") != "snapshot": return
	last_snapshot = evt
	evt = JSON.parse_string(evt.data)
	var students = {}
	var ct: int = 0
	var unequal: int = 0
	for i in evt.students:
		if int(evt.students[i].get("on_lesson", -1)) != int(lesson_index):
			unequal += 1 
			students[i] = {"data": evt.students[i], "name": i, "other": true}
			continue
		if evt.students[i].awaiting:
			ct += 1
		students[i] = {"data": evt.students[i], "name": i, "other": false}
	reload_user_state(students)

	
	$ColorRect/classroomstatus/num.text = str(ct) + "/" + str(len(evt.students))
	if unequal == len(evt.students):
		$ColorRect/classroomstatus/num.show()
		$ColorRect/classroomstatus/num.self_modulate = Color(0.6,0.6,0.6,1)
	else:
		$ColorRect/classroomstatus/num.show()
		$ColorRect/classroomstatus/num.self_modulate = Color.WHITE
	if ct == len(evt.students) and ct:
		$ColorRect/classroomstatus/num.hide()
		cont.show()
	else:
		$ColorRect/classroomstatus/num.show()
		cont.hide()

@onready var cont = $ColorRect/classroomstatus/cont

var user_state = {}
func reload_user_state(usr: Dictionary):
	user_state = usr.duplicate()
	await unroll_do()

func increment_user_state(usr: Dictionary):
	user_state = usr.duplicate()
	for i in user_state:
		user_state[i].name = i
		update_single(links[i], user_state[i])
			

func update_single(who: BlockComponent, dict: Dictionary):
	
	var waiting = dict.data.get("awaiting", false)
	var user = str(dict.data.get("username", dict.name))
	if len(user) > 13:
		user = user.substr(0,13)
		user += ".."
	var footer = ""
	who.metadata["awaiting"] = waiting
	
	if dict.get("other", false):
		var on = int(dict.data.get("on_lesson", -1))
		who.freeze_input()
		footer = "[__] Not In Lesson" if on == -1 or on >= len(learner.classroom_lesson_list()) else "[--] In Lesson %s" % (on+1)
		match glob.curr_lang:
			"kz":
				footer = "[__] Сабақта емес" if on == -1 else "[--] %s-сабақта" % (on+1)
			"ru":
				footer = "[__] Не в уроке" if on == -1 else "[--] На уроке %s" % (on+1)
	else:
		
		footer = "(::) Working" if !waiting else "[**] Waiting"
		match glob.curr_lang:
			"kz":
				footer = "(::) Салады" if !waiting else "[**] Күтеді"
			"ru":
				footer = "(::) Работает" if !waiting else "[**] Ожидает"
		if int(dict.data.get("step", 0)):
			footer = str(int(dict.data.get("step", 0))) + "-" + footer
	var total_letters: int = (list_unroll.size.x - list_unroll.arrangement_padding.x * 2) / 12.7
	who.text = user + " ".repeat(total_letters - len(user) - len(footer) - 3) + footer
	if dict.get("other", false):
		who.modulate = Color(0.9,0.9,0.9,0.6)
	else:
		if waiting:
			who.self_modulate = Color(1.2,1.2,1.2,2)
		else:
			who.self_modulate = Color(1,1,1,0.8)
	who.hint = dict.name
	links[dict.name] = who

var links = {}

func unroll_do():
	$ColorRect/classroomstatus/list/ProceduralNodes.unroll()
	await get_tree().process_frame
	list_unroll.menu_show(list_unroll.position)
	list_unroll.state.holding = false
	list_unroll.unblock_input()



func unroll(dup, args, kwargs):
	var output: Array[Node] = []
	var arr_state = []
	for i in user_state:
		arr_state.append(user_state[i])
		user_state[i]["name"] = i
	arr_state.sort_custom(func(a, b):
		return a["name"].to_lower() < b["name"].to_lower()
	)
	for i in arr_state:
		var new: BlockComponent = dup.duplicate()
		new.placeholder = false
		new.show()
		i.hint = i.name
		new.self_modulate.a = 0.5
		update_single(new, i)
		output.append(new)
	#(output)
	return output


func set_teacher_layout(base: bool = true):
	if cookies.profile("my_classroom"):
		if base:
			set_base_size(Vector2(518,472.0))
		$ColorRect/studentjoin.hide()
		$ColorRect/studentyes.hide()
		$ColorRect/classroomstatus.show()
		$ColorRect/classroomcr.hide()
		var id: String = cookies.profile("my_classroom")
		$ColorRect/classroomstatus/Label2.text = id.substr(0,3) + "-" + id.substr(3,-1)
		unroll_do()
		$ColorRect/buts.position = Vector2(345.0, 45)
		$ColorRect/Account.hide()
		if learner.classroom_data.has("name"):
			$ColorRect/classroomstatus/Control/name.text = learner.classroom_data["name"]
			$ColorRect/classroomstatus/Control/name.resize()
		stream = learner.classroom_stream()
		stream.on_sse.connect(snapshot_receive)
		glob.language_changed.connect(func(): reload_user_state(user_state))
		if learner.classroom_lesson_list().is_empty():
			curr_lesson = {}
			lesson_index = -1
			lock_button.hide()
			cont.hide()
			$ColorRect/classroomstatus/Control2/Label.text = "No lessons uploaded"
			$ColorRect/classroomstatus/Control2/Label.resize()
		else:
			lock_button.show()
			open_lesson(0)
		#if cookies.profile("teacher"):
		#	print("teach!", evt)
	
	else:
		$ColorRect/studentjoin.hide()
		$ColorRect/studentyes.hide()
		$ColorRect/classroomstatus.hide()
		$ColorRect/classroomcr.show()

@export var loader: AnimSpin
func set_student_layout(base: bool = true):
	if cookies.profile("my_classroom"):
		if base:
			set_base_size(Vector2(462,230.0))
		$ColorRect/studentjoin.hide()
		$ColorRect/studentyes.show()
		$ColorRect/classroomstatus.hide()
		$ColorRect/classroomcr.hide()
		$ColorRect/buts.position = Vector2(32, 96)
		$ColorRect/Account.show()
		if learner.classroom_data:
			$ColorRect/studentyes/Control/name.text = learner.classroom_data["name"]
			$ColorRect/studentyes/Control/name.resize()
		glob.language_just_changed.connect(func(): 
			await get_tree().process_frame
			$ColorRect/studentyes/Control/name.global_position.x = \
			$ColorRect/studentyes/Control/Label.get_global_rect().end.x + 3)
		$ColorRect/studentyes/Control/name.global_position.x = \
			$ColorRect/studentyes/Control/Label.get_global_rect().end.x + 3
	else:
		if base:
			set_base_size(Vector2(462.0,259))
		$ColorRect/studentjoin.show()
		$ColorRect/studentyes.hide()
		$ColorRect/classroomstatus.hide()
		$ColorRect/classroomcr.hide()
		$ColorRect/buts.position = Vector2(32, 96)
		$ColorRect/Account.show()

var parsed = {}
@onready var up = $ColorRect/classroomstatus/upload
@onready var base_texture = up.get_node("TextureRect").texture
var good = preload("res://game_assets/icons/good.png")
func _ready() -> void:
	#("hey vey")
#	print(learner.classroom_data)
	hide_role_panels()
	if passed_data.has("path"):
		var path: String = passed_data["path"]
		var compiled = YAMLComp.new().compile_bundle(path, path.ends_with(".zip"))
		print(JSON.stringify(compiled, "\t"))
		#(compiled)
		if compiled:
			await learner.upload_classroom_meta(compiled)
	elif cookies.profile("my_classroom"):
		await learner.cache_classroom_data()
	if !cookies.profile("teacher"):
		set_student_layout()

	else:
		set_teacher_layout()
	usr_update()
	glob.language_changed.connect(usr_update)
	$ColorRect/Control/Label.resize()
	update_lang()
	super() 
	if cookies.profile("teacher"):
		$ColorRect/Control/Label2.text = "Teacher"
	else:
		$ColorRect/Control/Label2.text = "Student"
	#await get_tree().process_frame
	$ColorRect/Control/Label2/Loc.translate()
	if learner.classroom_data.get("lessons", {}):
		up.get_node("TextureRect").texture = good
	else:
		up.get_node("TextureRect").texture = base_texture

	#list.tune()

@onready var list_unroll = $ColorRect/classroomstatus/list


func _on_logout() -> void:
	#("a")
	glob.reset_logged_in(true)
	can_go = true
	go_away()
	await quitting
	queue_free()


func _on_list_scroll_changed() -> void:
	glob.hide_all_menus()


@onready var lang_button = $ColorRect/buts/lang
func _on_lang_released() -> void:
	pass
	glob.switch_lang()
	#(glob.get_lang())
	update_lang()

func update_lang():
	match glob.get_lang():
		"en":
			lang_button.text = "ENG"
		"ru":
			lang_button.text = "RUS"
		"kz":
			lang_button.text = "KAZ"


func quit(data: Dictionary = {}):
	if not visible: return
	quitting.emit()
	#(grid.current_dir)
	hide()
	if can_go:
		hide()
		if can_tween_zero:
			ui.blur.self_modulate.a = 0
		emitter.res.emit(data)
		queue_free()


func _quit_request():
	can_go = true
	await quitting
	queue_free()
	hide()
	#ui.splash("works", passed_data["from_but"], emitter, true)


func _resultate(data: Dictionary):
	#if "go_path" in data:
		#can_go = false
		#go_away()
		#await quitting
		#queue_free()
		#ui.splash_and_get_result("path_open", splashed_from, emitter, true, 
		#{"filter": ["nls"], "from_proj": splashed_from})
	#else:
		##var rand_dataset_id: int = randi_range(0,999999)
	emitter.res.emit(data)
	pass
	go_away()



#
#func _on_trainn_released() -> void:
	#$ColorRect/Label.update_valid()
	#if $ColorRect/Label.is_valid:
		#var result = {"text": $ColorRect/Label.text}
		#if passed_data.has("path"):
			#result["path"] = passed_data["path"]
		#resultate(result)
#
#
#func _on_load_released() -> void:
	##var a = await ui.splash_and_get_result("path_open", csv)
	#resultate({"go_path": true})
	#pass # Replace with function body.

# 462.0 259
# 518.0.0 472.0
func _on_confirm_valid(input: String) -> void:
	
	#target_size = Vector2(462,230.0)
	#$ColorRect/studentjoin.hide()
	#$ColorRect/studentyes.show()
	loader.play()
	var a = await learner.join_classroom(input)
	#(cookies.profile("my_classroom"))
	if cookies.profile("my_classroom"):
		set_student_layout(false)
		target_size = Vector2(462,230.0)





func classroom_create() -> void:
	can_go = false
	go_away()
	await quitting
	queue_free()
	ui.splash("classroom_create", splashed_from, emitter, true)
	#ui.splash("classroom_create", splashed_from, emitter, )
	#var id: String = await learner.create_classroom()
	#if id:
		#target_size = Vector2(518,472.0)
		#set_teacher_layout(false)


func leave_press() -> void:
	var a: bool = await learner.leave_classroom()
	#if a:
	target_size = Vector2(462.0,259)
	set_student_layout(false)


func _on_right_released() -> void:
	open_lesson(lesson_index + 1)


func _on_left_released() -> void:
	open_lesson((lesson_index - 1))


func _on_upload_released() -> void:
	can_go = false
	go_away()
	await quitting
	queue_free()
	ui.splash_and_get_result("path_open", splashed_from, emitter, true, 
	{"filter": ["zip"], "goto_splash": "settings", "dirs": glob.IMPORT_LESSON_DIRS})
	
	#learner.upload_classroom_meta()


func _on_continue_released() -> void:
	learner.mark_explanation_made(lesson_index)


func _on_llist_released() -> void:
	inner = true
	go_away(false)
	can_tween_zero = false
	await quitting
	ui.splash("lessonslist", splashed_from, emitter, true)


func _on_lock_released() -> void:
	await learner.upload_lesson_customs(lesson_index, {"opened": 
		not learner.classroom_data.get("lesson_customs", {}).get(lesson_index, {}).get("opened", false)})
	open_lesson(lesson_index)


func _on_list_child_button_release(button: BlockComponent) -> void:
#	print(button.metadata.get("awaiting", false))
	if button.metadata.get("awaiting", false):
		learner.push_classroom_event({"awaiting": false}, button.hint)
	else:
		learner.push_classroom_event({"awaiting": true}, button.hint)
		
