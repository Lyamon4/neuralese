extends Loc

func _aux(text: String, lang: String):
	if lang != "en":
		_parent.text_offset.x = 4
	else:
		_parent.text_offset.x = 2
