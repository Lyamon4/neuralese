extends Loc

func _aux(text: String, lang: String):
	if lang == "en":
		_parent.position.x = 90
	if lang == "ru":
		_parent.position.x = 105
	if lang == "kz":
		_parent.position.x = 120
