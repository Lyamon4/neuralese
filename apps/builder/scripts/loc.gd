extends Node
class_name Loc

@export var auto: bool = false
var lang: String = "en"


@export var localizations_ru: Dictionary[String, String] = {}
@export var localizations_kz: Dictionary[String, String] = {}

var _parent: Node
var _source_text: String = ""
var _base_text: String = ""
var _last_display: String = ""
var _translation_fn: Callable

var prev_txt = null

@export var defer_translate: bool = false

var readied_once: bool = false
func _ready() -> void:
	if readied_once: return
	if get_parent() is BlockComponent and get_parent().placeholder:
		return
#	if get_parent().text == ""
	
	readied_once = true
	await get_tree().process_frame
	lang = glob.get_lang()
	_parent = get_parent()
	if not _parent:
		push_warning("Localization node requires a parent control.")
		return

	if localizations_ru and localizations_ru.keys().size() == 1:
		var old = localizations_ru.keys()[0]
		var val = localizations_ru[old]
		localizations_ru.clear()
		localizations_ru[sanitize(_get_text())] = val
	if localizations_kz and localizations_kz.keys().size() == 1:
		var old = localizations_kz.keys()[0]
		var val = localizations_kz[old]
		localizations_kz.clear()
		localizations_kz[sanitize(_get_text())] = val

	_bind_signals()

	_source_text = _get_text()
	_base_text = _source_text
	_translate_now()

func _bind_signals() -> void:
	if _parent is LabelAutoResize or _parent is Label:
		_parent.draw.connect(func():
			var current = _parent.text
			if prev_txt == null or prev_txt != current:
				prev_txt = current
				_on_parent_text_changed())
	elif _parent is BlockComponent:
		_parent.text_changed.connect(_on_parent_text_changed)
	else:
		_handle_custom(_parent)

	glob.language_changed.connect(func():
		#(_source_text)
		lang = glob.get_lang()
		_translate_now())

func _on_parent_text_changed(arg = null) -> void:
	var new_text = _get_text() if arg == null else arg

	if new_text != _last_display:
		_source_text = new_text
		_base_text = new_text
		_translate_now.call_deferred()

func _get_text() -> String:
	if _parent is LabelAutoResize or _parent is BlockComponent or _parent is Label:
		return _parent.text
	elif _parent is LineEdit or _parent is ValidInput:
		return _parent.placeholder_text
	else:
		return ""

func _set_text(t: String) -> void:
	if _parent is LabelAutoResize:
		_parent.text = t
	elif _parent is BlockComponent:
		_parent.set_txt_no_emit(t)
	elif _parent is Label:
		_parent.text = t
	elif _parent is LineEdit:
		_parent.placeholder_text = t
	elif _parent is ValidInput:
		_parent.set_line(t)
	else:
		_handle_custom(_parent)

func translate():
	(func():
		var new = _translate_to(_get_text(), glob.curr_lang)
		_last_display = new
		_set_text(new)).call_deferred()

func _translate_now() -> void:
	if not _parent:
		return
	var base := _base_text if _base_text != "" else _source_text
	var new_text := _translate_to(base, lang)
	if new_text != _last_display:
		_last_display = new_text
		_set_text(new_text)

func _translate_to(text: String, lang: String) -> String:
	_aux(text, lang)
	
	#if get_parent() is BlockComponent:
	#	print(text)

	if auto:
		var key := sanitize(text)
		#if key == "teacher":
		#	print(localizations_ru)
		if lang == "kz":
			if key in localizations_kz:
				return localizations_kz[key]
			elif key in localizations_ru:
				return localizations_ru[key]
			else:
				return text
		elif lang == "ru":
			return localizations_ru.get(key, text)
	return text

var let_kz_last: int = ord("ұ")

func sanitize(src: String) -> String:
	var result := ""
	var prev_space := true
	var let_a := ord("a")
	var let_z := ord("z")
	var let_ru_first := ord("а")
	var let_ru_last := ord("я")
	var let_ru_yo := "ё"

	var kz_ext := {
		"ә": true, "ғ": true, "қ": true, "ң": true,
		"ө": true, "ұ": true, "ү": true, "һ": true, "і": true
	}

	for c in src.to_lower():
		var order = ord(c)
		var is_latin = order >= let_a and order <= let_z
		var is_digit = c.is_valid_int()
		var is_ru = (order >= let_ru_first and order <= let_ru_last) or (c == let_ru_yo)
		var is_kz = kz_ext.has(c)

		if is_digit or is_latin or is_ru or is_kz:
			result += c
			prev_space = false
		elif c == " ":
			if not prev_space:
				result += " "
				prev_space = true
	if result.ends_with(" "):
		result = result.substr(0, result.length() - 1)
	return result

func _aux(text: String, lang: String): pass
func _handle_custom(node: Node) -> void: pass
