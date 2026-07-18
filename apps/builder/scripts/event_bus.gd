extends Node
class_name NeuraleseEventBus

signal event_changed(event_name: StringName, event_meta: Dictionary, active: bool)

const _SIGNAL_CHARS: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

var events: Dictionary = {}

var _event_signal_cache: Dictionary = {}
var _signal_event_cache: Dictionary = {}
var _expression_cache: Dictionary = {}
var _bad_expression_cache: Dictionary = {}


func is_event(event_name: StringName, required_meta: Dictionary = {}) -> bool:
	if not events.has(event_name):
		return false

	if required_meta.is_empty():
		return true

	var event_meta: Dictionary = events[event_name]

	for key in required_meta:
		if not event_meta.has(key):
			return false

		if not _fits_meta_value(event_meta[key], required_meta[key]):
			return false

	return true

func event_ping(event_name: StringName, event_meta: Dictionary):
	event_true(event_name, event_meta)
	event_false(event_name)

func event_true(event_name: StringName, event_meta: Dictionary = {}) -> void:
	var signal_name: StringName = _ensure_event_signal(event_name)

	if not events.has(event_name):
		events[event_name] = event_meta.duplicate()
	else:
		var stored_meta: Dictionary = events[event_name]
		stored_meta.merge(event_meta, true)

	var final_meta: Dictionary = events[event_name]

	event_changed.emit(event_name, final_meta, true)
	emit_signal(signal_name, final_meta, true)


func set_event(event_name: StringName, event_meta: Dictionary = {}) -> void:
	event_true(event_name, event_meta)


func event_false(event_name: StringName) -> void:
	if not events.has(event_name):
		return

	var signal_name: StringName = _ensure_event_signal(event_name)
	var old_meta: Dictionary = events[event_name]

	events.erase(event_name)

	event_changed.emit(event_name, old_meta, false)
	emit_signal(signal_name, old_meta, false)


func get_event_signal(event_name: StringName) -> StringName:
	return _ensure_event_signal(event_name)


func connect_event(event_name: StringName, target: Callable, flags: int = 0) -> Error:
	var signal_name: StringName = _ensure_event_signal(event_name)

	if is_connected(signal_name, target):
		return OK

	return connect(signal_name, target, flags)


func disconnect_event(event_name: StringName, target: Callable) -> void:
	var signal_name: StringName = _ensure_event_signal(event_name)

	if is_connected(signal_name, target):
		disconnect(signal_name, target)


func _fits_meta_value(value: Variant, request: Variant) -> bool:
	if request is String or request is StringName:
		return _eval_meta_expression(value, String(request))

	if request is Callable:
		return bool(request.call(value))

	return value == request


func _eval_meta_expression(value: Variant, expression_text: String) -> bool:
	var expression: Expression = _get_expression(expression_text)

	if expression == null:
		return false

	var result: Variant = expression.execute([value], null, false, true)

	if expression.has_execute_failed():
		return false

	return bool(result)


func _get_expression(expression_text: String) -> Expression:
	if _expression_cache.has(expression_text):
		return _expression_cache[expression_text]

	if _bad_expression_cache.has(expression_text):
		return null

	var expression: Expression = Expression.new()
	var error = expression.parse(expression_text, PackedStringArray(["value"]))

	if error != OK:
		_bad_expression_cache[expression_text] = true
		push_warning("Invalid event meta expression '%s': %s" % [expression_text, expression.get_error_text()])
		return null

	_expression_cache[expression_text] = expression
	return expression


func _ensure_event_signal(event_name: StringName) -> StringName:
	if _event_signal_cache.has(event_name):
		return _event_signal_cache[event_name]

	var signal_name: StringName = _build_event_signal_name(event_name)

	if not has_user_signal(signal_name):
		add_user_signal(String(signal_name), [
			{"name": "event_meta", "type": TYPE_DICTIONARY},
			{"name": "active", "type": TYPE_BOOL}
		])

	_event_signal_cache[event_name] = signal_name
	_signal_event_cache[signal_name] = event_name

	return signal_name


func _build_event_signal_name(event_name: StringName) -> StringName:
	var base: String = "event_" + _to_signal_identifier(String(event_name))
	var signal_name: StringName = StringName(base)
	var index: int = 2

	while has_signal(signal_name) and not (_signal_event_cache.has(signal_name) and _signal_event_cache[signal_name] == event_name):
		signal_name = StringName(base + "_" + str(index))
		index += 1

	return signal_name


func _to_signal_identifier(text: String) -> String:
	var result: String = ""

	for i in range(text.length()):
		var ch: String = text.substr(i, 1)

		if _SIGNAL_CHARS.find(ch) != -1:
			result += ch.to_lower()
		else:
			result += "_"

	if result.replace("_", "").is_empty():
		return "event"

	return result
