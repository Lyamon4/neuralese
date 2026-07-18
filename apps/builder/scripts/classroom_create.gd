extends SplashMenu

func _ready() -> void:
	super()
	$ColorRect/Label.set_is_valid_call(func(input):
		return len(input)> 0)

func _process(delta: float) -> void:
	super(delta)

func _resultate(data: Dictionary):
	emitter.res.emit(data)
	#glob.env_dump[data["text"]] = "-- Scene '%s'\nprint('Hello, world!')" % data["text"]
	#glob.tree_windows["env"].reload_scenes()
	go_away()


func _quit_request():
	can_go = false
	await quitting
	queue_free()
	ui.splash("settings", splashed_from, emitter, true)

func _on_trainn_released() -> void:
	$ColorRect/Label.update_valid()
	if $ColorRect/Label.is_valid:
		print("djkdk")
		var id: String = await learner.create_classroom($ColorRect/Label.text)
	#can_go = false
		print(id)
		go_away()
		await quitting
	#glob.load_scene(str(button.metadata["project_id"]))
	#queue_free()
		ui.splash("settings", splashed_from, emitter, true)
	
		#parsed[glob.random_project_id()] = {"name": "New Project"}
		#list.show_up(glob.parsed_projects)
