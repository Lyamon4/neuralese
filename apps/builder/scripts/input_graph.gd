extends Graph


func _infer_debug(message: String, data: Dictionary = {}) -> void:
	var suffix: String = ""
	if not data.is_empty():
		suffix = " " + JSON.stringify(data)
	print("[Input2DInfer graph_id=%s context=%s] %s%s" % [str(graph_id), str(context_id), message, suffix])


func _auto_infer_enabled() -> bool:
	return bool(glob.AUTO_INPUT_INFERENCE_ENABLED)


func _auto_infer_diag(message: String, data: Dictionary = {}) -> void:
	if not bool(glob.AUTO_INPUT_INFERENCE_DIAGNOSTICS):
		return
	_infer_debug(message, data)


func _auto_infer_payload_diag(payload: Dictionary) -> Dictionary:
	var raw_values = payload.get("raw_values", [])
	return {
		"enabled": _auto_infer_enabled(),
		"has_channel": nn.is_infer_channel(self),
		"has_external_lease": nn.infer_channel_has_external_lease(self),
		"opening": _auto_infer_opening,
		"pending": _auto_infer_pending_payload is Dictionary,
		"raw_len": raw_values.size() if raw_values is Array else -1,
		"shape": payload.get("shape", null),
	}


func _can_drag() -> bool:
	return !$TextureRect.mouse_inside and not run.is_mouse_inside()


func get_raw_values():
	var width: int = $TextureRect.image.get_width()
	var height: int = $TextureRect.image.get_height()
	var res = []

	for y in height:
		for x in width:
			res.append($TextureRect.get_pixel(Vector2(x, y)).r)

	return res


func get_netname():
	return null


func _bind_as_default_model_input(force: bool = false) -> void:
	var current = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)

	if is_instance_valid(current) and current != self and not force:
		return

	if is_instance_valid(current) and current != self and force:
		graphs.forget_input_graph(current)

	graphs.add_input_graph_name(self, glob.DEFAULT_MODEL_NAME)
	graphs.model_updated.emit(glob.DEFAULT_MODEL_NAME)


func _exit_tree() -> void:
	super()
	graphs.forget_input_graph(self)

func _just_connected(who: Connection, to: Connection):
	_bind_as_default_model_input(true)
	graphs.push_2d(28, 28, to.parent_graph)


@onready var run = $run


func _just_disconnected(who: Connection, to: Connection):
	graphs.forget_input_graph(self)


func graph_updated():
	_bind_as_default_model_input()

	if nn.is_infer_channel(self):
		_infer_debug("graph_updated: sending full_graph")
		nn.send_inference_data(self, {"full_graph": graphs.get_syntax_tree(self)})


func _useful_properties() -> Dictionary:
	return {
		"raw_values": get_raw_values(),
		"config": {
			"rows": 28,
			"columns": 28,
			"subname": "Input2D"
		},
		"shape": 28 * 28
	}


func repr():
	var tensorified: PackedStringArray = []
	tensorified.append(str(image_dims.x))
	tensorified.append(str(image_dims.y))
	return base_dt + "(" + "x".join(tensorified) + ")"


func validate(pack: Dictionary):
	return base_dt == pack.get("datatype", "") and pack.get("x", 0) == image_dims.x and pack.get("y", 0) == image_dims.y


var running: bool = false
var cd: float = 0.0
var last_sent_hash = null
var _last_image_change_version: int = -1
const AUTO_INFER_IDLE_CLOSE_SECONDS := 10.0
var _auto_infer_last_activity_msec: int = 0
var _auto_infer_opening: bool = false
var _auto_infer_pending_payload = null


func _raw_values_hash(values: Array) -> int:
	return values.hash()
	#
	#var ctx = HashingContext.new()
	#ctx.start(HashingContext.HASH_MD5)
#
	#for value in values:
		#ctx.update(str(glob.cap(float(value), 4)).to_utf8_buffer())
		#ctx.update(",".to_utf8_buffer())
#
	#return ctx.finish().hex_encode().hash()


func _process(delta: float) -> void:
	super(delta)

	var image_change_version := int($TextureRect.change_version)
	if _last_image_change_version < 0:
		_last_image_change_version = image_change_version

	if image_change_version != _last_image_change_version and cd < 0.01:
		cd = 0.3
		_last_image_change_version = image_change_version

		var raw_values = get_raw_values()
		var raw_hash = _raw_values_hash(raw_values)

		if last_sent_hash == null or last_sent_hash != raw_hash:
			last_sent_hash = raw_hash
			_auto_infer_diag("auto drawing changed", {
				"drawing": $TextureRect.drawing,
				"raw_len": raw_values.size(),
				"hash": raw_hash,
				"enabled": _auto_infer_enabled(),
			})
			_auto_infer_touch(_useful_properties())

	if cd >= 0.0:
		cd -= delta
	else:
		cd = 0.0

	_auto_infer_close_if_idle()


func _auto_infer_touch(payload: Dictionary) -> void:
	if not _auto_infer_enabled():
		_auto_infer_diag("auto touch suppressed: disabled", _auto_infer_payload_diag(payload))
		return
	if nn.infer_channel_has_external_lease(self):
		_auto_infer_diag("auto touch suppressed: channel leased", _auto_infer_payload_diag(payload))
		return
	_auto_infer_last_activity_msec = Time.get_ticks_msec()
	if nn.is_infer_channel(self):
		_auto_infer_diag("auto touch sending on existing channel", _auto_infer_payload_diag(payload))
		running = true
		nn.send_inference_data(self, payload)
		return
	_auto_infer_pending_payload = payload
	if _auto_infer_opening:
		_auto_infer_diag("auto touch queued while opening", _auto_infer_payload_diag(payload))
		return
	_auto_infer_diag("auto touch scheduling open", _auto_infer_payload_diag(payload))
	_auto_infer_open_and_send.call_deferred(payload)


func _auto_infer_open_and_send(payload: Dictionary) -> void:
	if not _auto_infer_enabled():
		_auto_infer_diag("auto open suppressed: disabled", _auto_infer_payload_diag(payload))
		_auto_infer_pending_payload = null
		return
	if nn.infer_channel_has_external_lease(self):
		_auto_infer_diag("auto open suppressed: channel leased", _auto_infer_payload_diag(payload))
		_auto_infer_pending_payload = null
		return
	if _auto_infer_opening:
		_auto_infer_diag("auto open skipped: already opening", _auto_infer_payload_diag(payload))
		return
	_auto_infer_opening = true
	_bind_as_default_model_input(true)
	cd = max(cd, 0.3)

	if not nn.validate_infer_channel(self):
		_auto_infer_diag("auto open rejected: channel invalid", _auto_infer_payload_diag(payload))
		_auto_infer_opening = false
		_auto_infer_pending_payload = null
		return

	_auto_infer_diag("auto open_infer_channel begin", _auto_infer_payload_diag(payload))
	var opened = await nn.open_infer_channel(self, _auto_infer_closed)
	_auto_infer_opening = false

	_auto_infer_diag("auto open_infer_channel returned", {
		"opened_truthy": (opened is bool and opened != false) or (opened != null),
		"opened_type": typeof(opened),
		"has_channel": nn.is_infer_channel(self),
	})

	if opened and nn.is_infer_channel(self):
		if _auto_infer_pending_payload is Dictionary:
			payload = _auto_infer_pending_payload
		_auto_infer_pending_payload = null
		running = true
		_auto_infer_diag("auto sending after open", _auto_infer_payload_diag(payload))
		nn.send_inference_data(self, payload)
	else:
		_auto_infer_diag("auto open produced no active channel", _auto_infer_payload_diag(payload))
		_auto_infer_pending_payload = null


func _auto_infer_close_if_idle() -> void:
	if not _auto_infer_enabled():
		return
	if _auto_infer_opening or not nn.is_infer_channel(self):
		return
	if nn.infer_channel_has_external_lease(self):
		_auto_infer_diag("auto idle close suppressed: channel leased", {
			"leases": nn.infer_channel_lease_summary(self),
		})
		return
	if _auto_infer_last_activity_msec <= 0:
		return
	var idle_sec := float(Time.get_ticks_msec() - _auto_infer_last_activity_msec) / 1000.0
	if idle_sec < AUTO_INFER_IDLE_CLOSE_SECONDS:
		return
	_auto_infer_diag("auto idle close", {
		"idle_sec": idle_sec,
		"threshold_sec": AUTO_INFER_IDLE_CLOSE_SECONDS,
	})
	nn.close_auto_infer_channel(self)


func _auto_infer_closed() -> void:
	_auto_infer_diag("auto infer closed", {
		"running_before": running,
		"enabled": _auto_infer_enabled(),
	})
	running = false
	_auto_infer_opening = false
	_auto_infer_pending_payload = null
	last_sent_hash = null


func _proceed_hold() -> bool:
	if running:
		return true
	return false


var image_dims = Vector2i(1, 1)


func _after_ready() -> void:
	super()
	graphs._input_origin_graph = self
	image_dims = Vector2i($TextureRect.image.get_width(), $TextureRect.image.get_height())

	await get_tree().process_frame
	_bind_as_default_model_input(true)

func set_state_open():
	_infer_debug("set_state_open")

	running = true
	run_but.text_offset.x = 0

	match glob.get_lang():
		"kz":
			run_but.text = "Тоқта"
		"ru":
			run_but.text = "Стоп"
		_:
			run_but.text = "Stop"


@onready var run_but = $run


func _on_run_released() -> void:
	_bind_as_default_model_input(true)

	_infer_debug("run button released", {
		"running": running,
		"is_channel": nn.is_infer_channel(self),
		"text": run_but.text,
	})
	await glob.wait(2, true)
	hold_for_frame()
	return

	if not nn.is_infer_channel(self):
		cd = 2.0
		last_sent_hash = null

		var opened = await nn.open_infer_channel(self, close_runner, run_but)

		_infer_debug("open_infer_channel returned", {
			"opened": (opened is bool and opened != false) or (opened != null)
		})

		if opened:
			running = true
			run_but.text_offset.x = 0

			match glob.get_lang():
				"kz":
					run_but.text = "Тоқта"
				"ru":
					run_but.text = "Стоп"
				_:
					run_but.text = "Stop"

			await glob.wait(0.2)
			nn.send_inference_data(self, _useful_properties())

	else:
		_infer_debug("run button closing active channel")
		nn.close_infer_channel(self)

	await glob.wait(2, true)
	hold_for_frame()


func close_runner():
	_infer_debug("close_runner called", {
		"text_before": run_but.text,
		"running_before": running
	})

	run_but.text_offset.x = 2
	run_but.text = "Run!"
	running = false
	_auto_infer_opening = false
	_auto_infer_pending_payload = null
	last_sent_hash = null

	_infer_debug("close_runner finished", {
		"text_after": run_but.text,
		"running_after": running
	})
