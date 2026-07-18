extends DynamicGraph

func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("Label").text = kw["text"]
	if kw["features"]["type"] != "float" and kw["features"]["type"] != "sfloat":
		dup.get_node("Label").simple_letters = 9
		dup.get_node("Label").resize()
	else:
		dup.get_node("Label").simple_letters = 17
		dup.get_node("Label").resize()
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
#	dup.server_name = 
	if kw["features"]["type"] == "class":
		dup.get_node("loss").graph = dup
		dup.get_node("loss").auto_ready = true
	if kw["features"]["type"] == "bool":
		dup.get_node("bool").graph = dup
		dup.get_node("bool").auto_ready = true
	return dup


func _llm_map(pack: Dictionary):
	if not pack: return
	var result_features = []
	for i in pack.get("input_features", []):
		var dup = i.duplicate()
		dup.erase("text")
		dup["n"] = 0
		dup["on"] = false
		result_features.append({"text": i["text"], "features": dup})
	update_config({"input_features": result_features})



func class_unroll(frozen_duplicate: BlockComponent, args, kwargs):
	var output: Array[Node] = []
	var lines = []
	var i: int = 0
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = _i
		new.auto_ready = true
		new.hint = _i
		output.append(new)
	return output


var hsliders = {}
func _adding_unit(who: Control, kw: Dictionary):
	
	who.set_meta("kw", kw)
	var idx = who

	who.get_node("HSlider").hide()
	who.get_node("Label2").hide()
	who.get_node("val").hide()
	who.get_node("loss").hide()
	who.get_node("bool").hide()
	
	if kw["features"]["type"] != "class":
		who.get_node("loss").queue_free()
	if kw["features"]["type"] != "bool":
		who.get_node("bool").queue_free()
	
	match kw["features"].get("type"):
		"int":
			who.get_node("val").show()
			who.get_node("val").min_value = features.get_or_add("min", 0)
			who.get_node("val").max_value = features.get_or_add("max", 80)
			hsliders[idx] = who.get_node("val")
			who.get_node("val").tree_exiting.connect(func(): hsliders.erase(idx))
		#	who.get_node("ColorRect").size.y -= 5
		"float":
			var hslider = who.get_node("HSlider")
			hslider.value_changed.connect(hslider_val_changed.bind(hslider, kw))
			hslider.show()
			who.get_node("Label2").show()
			#(kw)
			hslider.tree_exiting.connect(func(): hsliders.erase(idx))
			hsliders[idx] = hslider
			#await get_tree().process_frame
			kw["min"] = 0.0
			kw["max"] = 1.0
			hslider_val_changed(0.0, hslider, kw)
		"sfloat":
			var hslider = who.get_node("HSlider")
			hslider.value_changed.connect(hslider_val_changed.bind(hslider, kw))
			hslider.show()
			who.get_node("Label2").show()
			#(kw)
			hslider.tree_exiting.connect(func(): hsliders.erase(idx))
			hsliders[idx] = hslider
			#await get_tree().process_frame
			kw["min"] = -1.0
			kw["max"] = 1.0
			hslider_val_changed(0.0, hslider, kw)
		"class":
			var got = who.get_node("loss")
			got.show()
			hsliders[idx] = who.get_node("loss")
			got.predelete.connect(func(): hsliders.erase(idx))
			who.get_node("loss").released.connect(set_class.bind(kw, who.get_node("loss")))
			await get_tree().process_frame
			kw["n"] = -1
			set_class(kw, got)
			#set_class(kw, got)
			#who.get_node("loss").predelete.connect(func(): hsliders.erase(idx))
		"bool":
			var got = who.get_node("bool")
			got.show()
			hsliders[idx] = who.get_node("bool")
			got.predelete.connect(func(): hsliders.erase(idx))
			who.get_node("bool").released.connect(set_weight_dec.bind(kw, who.get_node("bool")))
			await get_tree().process_frame
			set_weight_dec(kw, got)
			set_weight_dec(kw, got)
			#who.get_node("bool").predelete.connect(func(): hsliders.erase(idx))

	await get_tree().process_frame

func set_class(kw: Dictionary, switch):
	if not "n" in kw["features"]:
		kw["features"]["n"] = 0
	kw = kw["features"]
	switch.text = kw["classes"][kw["n"]]
	kw["n"] += 1
	if kw["n"] == len(kw["classes"]):
		kw["n"] = 0


func set_weight_dec(kw: Dictionary, switch):
	var on: bool = kw.get("on", true)
	if on:
		switch.base_modulate = Color(0.85, 0.85, 0.85, 1.0) * 1.3
		switch.text = "I"
	else:
		switch.base_modulate = Color(0.85, 0.85, 0.85, 1.0) * 0.7
		switch.text = "O"
	kw["on"] = !on


func to_tensor(cells: bool = false):
	var a = []
	for i in units:
		var features = i.get_meta("kw")["features"]
		match features.type:
			"float":
				a.append(i.get_value() if !cells else [i.get_value()])
			"sfloat":
				a.append(i.get_value() if !cells else [i.get_value()])
			"int":
				a.append(i.get_value() if !cells else [i.get_value()])
			"bool":
				if !cells:
					a.append(1.0 if features.get("on", false) else 0.0)
				else:
					a.append([1.0 if features.get("on", false) else 0.0])
			"class":
				var slices = []
				slices.resize(len(features["classes"]))
				slices.fill(0.0)
				slices[features["n"]-1] = 1.0
				if not cells:
					a.append_array(slices)
				else:
					a.append(slices)
	return a



func hslider_val_changed(val: float, slider: HSlider, kw: Dictionary):
	var k = lerp(kw["min"], kw["max"], (val / slider.max_value))
	var fit = k
	var capped = str(glob.cap(fit, 2))
	if len(capped.split(".")[-1]) == 1: capped += "0"
	slider.get_parent().get_node("Label2").text = capped


func _useful_properties() -> Dictionary:
	var input_features = []
	for i in units:
		input_features.append({"value": i.get_value(), "features": i.get_meta("kw").get("features", {})})
	#(to_tensor(d))
	return {
		"raw_values": to_tensor(),
		"config": {"input_features": input_features,
		"subname": "Input1D"}, "shape": len(to_tensor())
	}


var value_cache: Array = []
var manually: bool = false
func unit_set(unit, value, text):
	units[unit].set_weight(text)

func _config_field(field: StringName, value: Variant):
	#(cfg)
	if not manually and field == "input_features":
		for i in len(units):
			remove_unit(0)
		for i in len(value):
			if value[i] is Dictionary: pass
			else: continue
			add_unit(value[i])
		#	units[i].get_node("Label").text = value[i]
		push_values(value_cache, per)
	#if not upd and field == "title":
	#	$ColorRect/root/Label.set_line(value)
	#	ch()
func _just_connected(who: Connection, to: Connection):
	pass
	#if to.parent_graph.server_typename == "NeuronLayer":
	graphs.push_1d(len(to_tensor()), self)
	_bind_as_default_model_input(true)

func get_x():
	return len(to_tensor())

func something_focus() -> bool:
	if ui.is_focus($input/tabs/int/min): return true
	if ui.is_focus($input/tabs/int/max): return true
	return false

func _can_drag() -> bool:
	if features["type"] == "class" and ui.is_focus($input/tabs/class/Control/HFlowContainer.line_edit):
		return false
	if not super(): return false
	if something_focus(): return false
	if run_but.is_mouse_inside(): return false
	#(hsliders)
	for i in hsliders.values():
		if ui.is_focus(i):
			return false
		if i is BlockComponent and i.is_mouse_inside(): return false
	return true
#	return super() and not ui.is_focus($ColorRect/root/Label)

func _proceed_hold() -> bool:
	#if prev_adding_size:
	#	return true
	if running: return true
	if features["type"] == "class" and ui.is_focus($input/tabs/class/Control/HFlowContainer.line_edit):
		return true
	if something_focus(): return true
	for i in hsliders.values():
		if ui.is_focus(i):
			return true
		if i is BlockComponent and i.is_mouse_inside(): return true
	if not super(): return false
	return false
	#return ui.is_focus($ColorRect/root/Label)


func get_title() -> String:
	return $ColorRect/root/Label2.text

var per: bool = false
func push_values(values: Array, percent: bool = false):
	per = percent
	var minimal = values.min() if !percent else 0.0
	var maximal = values.max() if !percent else 1.0
	var add = "%" if percent else ""
	for unit in len(values):
		var value = (values[unit] - minimal) / float(maximal - minimal)
		var capped = glob.cap(values[unit], 2) if !percent else round(values[unit]*100.0)
		if unit >= len(units): continue
		if percent:
			unit_set(unit, value, str(capped)+"%")
		else:
			unit_set(unit, value, str(capped))
	for unit in range(len(values), len(units)):
		if percent:
			unit_set(unit, 0.0, "0%")
		else:
			unit_set(unit, 0.0, "0.0")

	if not undo_redo_opened and not glob.is_auto_action() and not manually:
		var res = []
		for i in units: 
			res.append(i.get_meta("kw"))
		open_undo_redo()
		manually = true
		update_config({"input_features": res})
		close_undo_redo()
		manually = false
		graphs.push_1d(len(to_tensor()), self)



func _unit_just_added() -> void:
	var ancestor = get_first_ancestors()
	if ancestor: 
		if ancestor[0].server_typename == "SoftmaxNode":
			push_values(value_cache, true)
		else:
			push_values(value_cache, false)
	else:
		push_values(value_cache, false)

func get_netname():
	return null




var res_meta: Dictionary = {}
func push_result_meta(meta: Dictionary):
	res_meta = meta
	ch()

func _infer_debug(message: String, data: Dictionary = {}) -> void:
	var suffix := ""
	if not data.is_empty():
		suffix = " " + JSON.stringify(data)
	print("[Input1DInfer graph_id=%s context=%s] %s%s" % [str(graph_id), str(context_id), message, suffix])


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


func repr():
	var tensorified: PackedStringArray = []
	#for i in to_tensor(true):
	#	tensorified.append(str(len(i)))
	return base_dt + "(" +str( len(to_tensor())) + ")"

func validate(pack: Dictionary):
	return base_dt == pack.get("datatype", "") and pack.get("x", 0) == len(to_tensor())



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



var target_tab: String = ""
func _after_process(delta: float):
#	print(adding_size_y)
	#if glob.space_just_pressed:
	#	print(graphs.get_syntax_tree(self))
	#(to_tensor())
	super(delta)
	if target_tab:
		for i in input.get_node("tabs").get_children():
			if i.name != target_tab:
				if 1:
					i.modulate.a = lerpf(i.modulate.a, 0.0, delta * 20.0)
					if i.modulate.a < 0.01:
						i.hide()
						
						adding_size_y = tg
			else:
				i.show()
				i.modulate.a = lerpf(i.modulate.a, 1.0, delta * 20.0)
	#(cfg)
	#push_values(range(len(units)), true)
	if cd < 0.001:
		cd = 0.3
		var new_sent = to_tensor()
		if last_sent == null:
			last_sent = new_sent
		elif last_sent.hash() != new_sent.hash():
			last_sent = new_sent
	#(new_sent)
		#	print(useful_properties())
			_auto_infer_diag("auto tensor changed", {
				"len": new_sent.size(),
				"hash": new_sent.hash(),
				"enabled": _auto_infer_enabled(),
			})
			_auto_infer_touch(useful_properties())
	cd -= delta
	if cd <= 0.0001:
		cd = 0.0
	#print("a")
	_auto_infer_close_if_idle()
	if features["type"] == "class":
		var hflow = $input/tabs/class/Control/HFlowContainer
		adding_size_y = 18 + max((hflow.size.y-18)*$input/tabs/class/Control.scale.y, 0)
	
	
	#($input/tabs/class/Control.custom_minimum_size.y)

var last_sent = null
var cd: float = 0.0
var prev_tensor
const AUTO_INFER_IDLE_CLOSE_SECONDS := 10.0
var _auto_infer_last_activity_msec: int = 0
var _auto_infer_opening: bool = false
var _auto_infer_pending_payload = null


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
	last_sent = null


func _unit_removal(id: int):
	if not undo_redo_opened and not glob.is_auto_action() and not manually:
		var res = []
		for i in units: 
			res.append(i.get_meta("kw"))
		open_undo_redo()
		manually = true
		update_config({"input_features": res})
		close_undo_redo()
		manually = false
	await get_tree().process_frame

func _just_disconnected(who: Connection, from: Connection):
	graphs.forget_input_graph(self)


func _exit_tree() -> void:
	super()
	graphs.forget_input_graph(self)

func _bind_as_default_model_input(force: bool = false) -> void:
	var current = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)

	if is_instance_valid(current) and current != self and not force:
		return

	if is_instance_valid(current) and current != self and force:
		graphs.forget_input_graph(current)

	graphs.add_input_graph_name(self, glob.DEFAULT_MODEL_NAME)
	graphs.model_updated.emit(glob.DEFAULT_MODEL_NAME)

func ch():
	var target = graphs._reach_input(self)
	if !target:
		target = self

	var got = graphs.get_input_name_by_graph(target)
	if got:
		graphs.model_updated.emit(got)
	else:
		pass

func _on_color_rect_2_pressed() -> void:
	if features["type"] == "class":
		if not $input/tabs/class/Control/HFlowContainer.tags:
			return
	if line_edit.is_valid:
		await get_tree().process_frame
		#ui.click_screen(line_edit.global_position + Vector2(10,10))
		var maximal = float($input/tabs/int/max.text) if $input/tabs/int/max.text else 80
		var minimal = float($input/tabs/int/min.text) if $input/tabs/int/min.text else 0.0
		features["min"] = min(maximal, minimal)
		features["max"] = max(maximal, minimal)
	#	line_edit.grab_focus()
		if features["type"] == "class":
			features["classes"] = $input/tabs/class/Control/HFlowContainer.tags.duplicate()
			$input/tabs/class/Control/HFlowContainer.clear()
		add_unit({"text": line_edit.text, "features": features.duplicate()})
		line_edit.clear()


var upd = false
signal label_changed(text: String)
func _on_label_changed() -> void:
	ch()
	upd = true
	#update_config({"title": $ColorRect/root/Label.text})
	upd = false
	#var netname = target.get_netname()
	#if netname:
	#	netname.reload()
	#label_changed.emit($ColorRect/root/Label.text)


func _ready() -> void:
	super()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_bind_as_default_model_input(true)
	#	_on_type_child_button_release($input/type.button_by_hint["float"])

var features = {"type": "float"}

var tg: float = 0.0
func _on_type_child_button_release(button: BlockComponent) -> void:
	button.is_contained.text = button.text
	button.is_contained.menu_hide()
	target_tab = str(button.hint)
	#var other = input.get_node("tabs").get_node(NodePath(button.hint))
	#if other: other.show()
	if button.hint == "class":
		#features["classes"] = ["hello", "hi", "returtttn"]
		features["n"] = 0
	features["type"] = button.hint
	if button.hint == "class" or button.hint == "int":
		tg = 30.0
		adding_size_y = tg
	else:
		tg = 0.0

func graph_updated():
	if nn.is_infer_channel(self):
		_infer_debug("graph_updated: sending full_graph")
		nn.send_inference_data(self, {"full_graph": graphs.get_syntax_tree(self)})


@onready var run_but = $run
var running: bool = false
func _on_run_released() -> void:
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
		var opened = await nn.open_infer_channel(self, close_runner, run_but)
		#opened is bool and opened != false please keep it as this dont change this notation
		_infer_debug("open_infer_channel returned", {"opened": (opened is bool and opened != false) and opened != null})
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
		
	else:
		#run_but.text = "Run!"
		#run.text_offset.x = 2
		#running = false
		_infer_debug("run button closing active channel")
		nn.close_infer_channel(self)
	await glob.wait(2, true)
	hold_for_frame()

func close_runner():
	_infer_debug("close_runner called", {"text_before": run_but.text, "running_before": running})
	run_but.text_offset.x = 2
	run_but.text = "Run!"
	running = false
	_auto_infer_opening = false
	_auto_infer_pending_payload = null
	last_sent = null
	_infer_debug("close_runner finished", {"text_after": run_but.text, "running_after": running})
		
