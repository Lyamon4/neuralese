extends Loc

func _aux(text: String, lang: String):
	if lang != "en":
		get_parent().no_emit = true
		get_parent().resize_after = 7
		get_parent().set_txt_no_emit(get_parent().text)
		get_parent().no_emit = false
	else:
		get_parent().no_emit = true
		get_parent().resize_after = 8
		get_parent().set_txt_no_emit(get_parent().text)
		get_parent().no_emit = false
