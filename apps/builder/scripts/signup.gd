extends SplashMenu

func _ready() -> void:
	super()
	$ColorRect/Label3.set_is_valid_call(func(input):
		return input == $ColorRect/Label2.text and len(input)> 0)
	set_teacher(false)

@onready var switch = $ColorRect/switch

var is_teacher: bool = false
func set_teacher(on: bool):
	is_teacher = on
	if on:
		switch.base_modulate = Color(0.604, 0.929, 0.631) * 1.3
		switch.text = "I"
		$ColorRect/Label4.modulate = Color.WHITE
	else:
		switch.base_modulate = Color(0.47, 0.56, 0.478, 1.0) * 0.7
		$ColorRect/Label4.modulate = Color(0.412, 0.412, 0.412)
		switch.text = "O"

func _resultate(data: Dictionary):
	if "go_login" in data:
		can_go = false
		go_away()
		await quitting
		queue_free()
		ui.splash_and_get_result("login", splashed_from, emitter, true)
	else:
		ui.hourglass_on()
		var result = await glob.create_account(data["user"], data["pass"], {"teacher": is_teacher})
		ui.hourglass_off()

		if result.ok:
			emitter.res.emit(data)
			go_away()
		else:
			match result.error:
				"exists":
					ui.error("This username is already occupied. Choose a different one, please!")
				"network":
					ui.error("Either your internet or the server itself is down. Sorry!")
				_:
					ui.error("Unexpected server error.")


func _on_train_2_releaseda() -> void:
	resultate({"go_login": true})


func _on_label_2_text_changed(new_text: String) -> void:
	$ColorRect/Label3.update_valid()


func _on_train_releasedd() -> void:
	$ColorRect/Label2.update_valid()
	$ColorRect/Label.update_valid()
	$ColorRect/Label3.update_valid()
	if $ColorRect/Label2.is_valid and $ColorRect/Label.is_valid and $ColorRect/Label3.is_valid:
		resultate({"user": $ColorRect/Label.text, "pass": $ColorRect/Label2.text})


func _on_switch_released() -> void:
	set_teacher(!is_teacher)
