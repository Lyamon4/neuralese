extends Loc

func _aux(text: String, lang: String):
	if lang == "kz":
		get_parent().no_emit = true
		get_parent().resize_after = 5
		get_parent().set_txt_no_emit(get_parent().text)
		get_parent().no_emit = false
	else:
		get_parent().no_emit = true
		get_parent().resize_after = 4
		get_parent().set_txt_no_emit(get_parent().text)
		get_parent().no_emit = false
