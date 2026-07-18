extends SplashMenu

func _ready() -> void:
	super()
	$ColorRect/Label.set_is_valid_call(func(input):
		#(input)
		return input and not input in glob.ds_dump and not "/" in input)
	if passed_data.has("txt"):
		$ColorRect/Label.set_line(passed_data["txt"])
		$ColorRect/Label.update_valid()
	if passed_data.has("path"):
		target_size.y = 175
		$ColorRect/Label/LabelAutoResize.text = passed_data["path"]
		$ColorRect/Label/LabelAutoResize.resize()
		$ColorRect/Label/LabelAutoResize.show()
		#(passed_data["path"])

func _process(delta: float) -> void:
	super(delta)

#func _resultate(data: Dictionary):
	#if "go_signup" in data:
		#can_go = false
		#go_away()
		#await quitting
		#queue_free()
		#ui.splash_and_get_result("signup", splashed_from, emitter, true)
	#else:
		#ui.hourglass_on()
		#var answer = await glob.login_req(data["user"], data["pass"])
		#if answer.ok:
			#var parsed = JSON.parse_string(answer.body.get_string_from_utf8())
			#if parsed.answer == "ok":
				#var prev = glob.logged_in()
				#glob.set_logged_in(data["user"], data["pass"])
				#emitter.res.emit(data)
				#go_away()
#
			#else:
				#ui.error("Username or password is wrong. :(")
		#else:
			#ui.error("Either your internet or the server itself is down. Sorry!")
		#
		#ui.hourglass_off()


func _resultate(data: Dictionary):
	if "go_path" in data:
		can_go = false
		go_away()
		await quitting
		queue_free()
		ui.splash_and_get_result("path_open", splashed_from, emitter, true, 
		{"from": self, "txt": $ColorRect/Label.text, "filter": ["csv"]})
	else:
		var rand_dataset_id: int = randi_range(0,999999)
		emitter.res.emit(data)
		if passed_data.has("path"):
			#(dsreader.parse_csv_dataset(passed_data["path"]))
			glob.ds_dump[data["text"]] = glob.create_dataset(rand_dataset_id, 
			data["text"],
			dsreader.parse_csv_dataset(passed_data["path"]))
			
			glob.cache_rle_compress(data["text"])
			await glob.join_ds_processing()
		else:
			glob.ds_dump[data["text"]] = glob.create_dataset(rand_dataset_id, data["text"])
		glob.tree_windows["ds"].reload_scenes()
		go_away()


func _on_trainn_released() -> void:
	$ColorRect/Label.update_valid()
	if $ColorRect/Label.is_valid:
		var result = {"text": $ColorRect/Label.text}
		if passed_data.has("path"):
			result["path"] = passed_data["path"]
		resultate(result)


func _on_load_released() -> void:
	#var a = await ui.splash_and_get_result("path_open", csv)
	resultate({"go_path": true})
	pass # Replace with function body.
