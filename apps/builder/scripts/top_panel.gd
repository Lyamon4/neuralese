extends ColorRect
class_name TopBar

@export var menus: Dictionary[StringName, SubMenu] = {}

func _enter_tree() -> void:
	glob.fg = self

func show_back():
	material.set_shader_parameter("use_bg", true)
	$back.show()

func hide_back():
	material.set_shader_parameter("use_bg", false)
	$back.hide()

func _ready() -> void:
	glob.space_begin.y = size.y + position.y
	$Control3/dsbg.hide()
	$Control3/graphsbg.hide()
	$Control3/minigamesbg.show()
	name_resize()


func name_resize():
	$Label.size.x = clamp((glob.window_size.x - 700) * 0.6, 100, 189) / $Label.scale.x
	#savebut.global_position.x = $Label.get_global_rect().end.x + 10
	$Label.resize_after = $Label.size.x - 30
	$Label._resize_label.call_deferred()



func _process(delta: float) -> void:
	if size.x != glob.window_size.x-position.x*2:
		size.x = glob.window_size.x-position.x*2
		for m in menus:
			var menu = menus[m]
			menu.attachement_x = size.x - menu.size.x + 30
			#if glob.window_size.x < 50:
		name_resize()
	if (glob.window_size.x) < 899:
		#(1300-glob.window_size.x)
		if not in_small_mode:
			var idx: int = -1
			for i in buts:
				idx += 1; i.text = ""
				i.resize(Vector2(41, i.base_size.y))
			buts[1]._wrapped_in.position = buts[2]._wrapped_in.position - Vector2(48,0)
			buts[0]._wrapped_in.position = buts[1]._wrapped_in.position - Vector2(48,0)
			buts[0].get_node("i").position.x = 20.921
		in_small_mode = true
	else:
		if in_small_mode:
			buts[0].get_node("i").position.x = 22.921

			for i in len(buts):
				#i.resize_after = 20
				buts[i].text = b_texts[i]
				buts[i].resize(b_szs[i])
				buts[i]._wrapped_in.position = b_poss[i]
		in_small_mode = false
	var rect = get_global_rect()
	var k = 0.47 if glob.window_size.x < 1000 else 0.5
	if in_small_mode:
		k = 0.5
	$Control3.global_position.x = lerp(rect.position.x, rect.end.x, k)
	if in_small_mode:
		$Control3.global_position.x -= 22
	$Control3.global_position.x = max($Label.get_global_rect().end.x + 160, $Control3.global_position.x)
	#if Input.is_action_just_pressed("ui_accept"):
		#menus["a"].expand()
	#elif Input.is_action_just_pressed("down"):
		#menus["a"].close()
	#(glob.window_size.x)
var in_small_mode: bool = false
@onready var buts: Array[BlockComponent] = [$Control/ai, $Control/export, $Control/login]
@onready var b_texts = [buts[0].text, buts[1].text, buts[2].text]
@onready var b_szs = [buts[0].size, buts[1].size, buts[2].size]
@onready var b_poss = [buts[0].position, buts[1].position, buts[2].position]

func get_scene_name():
	return $Label.text

func set_scene_name(name: String):
	$Label.text = name


var game_icon = preload("res://game_assets/icons/game.png")
var build_icon = preload("res://game_assets/icons/splines.png")
@onready var play = $Control/play
func _on_play_released() -> void:
	if play.hint == "play_tab": 
	#	play.hint = "build_tab"
	#	play.text_offset = Vector2(7,0)
#		play.text = " Make"
		#play.get_node("i").texture = build_icon
		#play.get_node("i").offset.x = -3
		glob.go_window("env")
	else:
		go_into_graph()

func go_into_graph():
#	play.hint = "play_tab"
#	play.text_offset = Vector2(7,0)
#	play.text = " Test"
#	play.get_node("i").texture = game_icon
	glob.go_window("graph")
	set_def()

var logged_in: bool = false

func set_login_state(name: String):
	logged_in = len(name) > 0
	pass
	#if name:
	#	login_btn.text = name
	#else:
	#	login_btn.text = "Login"


@onready var login_btn = $Control/login
func _on_login_released() -> void:
	#if !ui.is_splashed("login"):
	#	login_btn.in_splash = true
	
	if !glob.logged_in():
		var a = await ui.splash_and_get_result("login", login_btn)
		if a:
			pass
			set_login_state("Works")
			ui.splash("settings", login_btn)
		else:
			set_login_state("")
		#if !glob.loaded_project_once:
		#	glob.open_last_project()
	else:
		ui.splash("settings", login_btn)
	#else:
	#	login_btn.in_splash = false
	#	ui.get_splash("login").go_away()

@onready var savebut = $"9"
func _on__released() -> void:
	if glob.LocalSave:
		ui.hourglass_on()
		await glob.save(str(glob.get_project_id()))
		ui.hourglass_off()
		return
	if !glob.logged_in():
		var a = await ui.splash_and_get_result("login", savebut)
		if a:
			ui.hourglass_on()
			await glob.save(str(glob.get_project_id()))
			ui.hourglass_off()
	else:
		ui.hourglass_on()
		await glob.save(str(glob.get_project_id()))
		ui.hourglass_off()

@onready var axon = $Control/ai
func _on_ai_released() -> void:
	if !glob.logged_in():
		var a = await ui.splash_and_get_result("login", axon)
		if a:
			set_login_state("Works")
			ui.splash("ai_help", axon)
		else:
			set_login_state("")
	else:
		ui.splash("ai_help", axon)


func _on_ds_released() -> void:
	pass # Replace with function body.


func _on_graphs_released() -> void:
	$Control3/dsbg.hide()
	$Control3/graphsbg.show()
	$Control3/minigamesbg.hide()
	glob.go_window("env")
func set_def():
	$Control3/dsbg.hide()
	$Control3/graphsbg.hide()
	$Control3/minigamesbg.show()

func _on_datasets_released() -> void:
	$Control3/dsbg.show()
	$Control3/graphsbg.hide()
	$Control3/minigamesbg.hide()
	glob.go_window("ds")


func _on_minigames_released() -> void:
	$Control3/dsbg.hide()
	$Control3/graphsbg.hide()
	$Control3/minigamesbg.show()
	go_into_graph()

@onready var export = $Control/export
func _on_export_released() -> void:
	var res = 1
	if nn.FULLY_LOCAL_TRAINING:

		var a = await ui.splash_and_get_result("model_export", export)
		return 
	if not cookies.get_auth_header():
		res = await ui.splash_and_get_result("login", export)
	if res:
		var a = await ui.splash_and_get_result("model_export", export)

@onready var workslist_but = $works
func _on_workslist() -> void:
	
	if glob.LocalSave:# and not learner.active():
		if ui.active_splashed(): 
			ui.hide_splash()
			return
		ui.splash("workslist", workslist_but)
		return
	if !glob.logged_in():
		var a = await ui.splash_and_get_result("login", workslist_but)
		if a:
			pass
			set_login_state("Works")
			ui.splash("workslist" if !learner.active() else "lessonslist", workslist_but)
		else:
			set_login_state("")
		#if !glob.loaded_project_once:
		#	glob.open_last_project()
	else:
		if ui.active_splashed(): 
			ui.hide_splash()
			return
		ui.splash("workslist"if !learner.active() else "lessonslist", workslist_but)
