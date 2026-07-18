extends TableCell
func _map_data(data: Dictionary) -> void:
	#(data)
	cell_data = data
	setval(data["val"])
	#_on_label_changed.call_deferred()


func _input(event: InputEvent) -> void:
#	print(event)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP \
		or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Stop the slider from consuming this event.
		#	accept_event()
			if not $HSlider.get_global_rect().has_point(get_global_mouse_position()):
				return
			# Re-send it to the parent table.
			var p := get_parent()
			while p:
				p.propagate_call("_gui_input", [event], false)
				p = p.get_parent()
			return


func setval(who: float):
	who = clampf(who, 0, 1)
	$HSlider.set_value_no_signal(who * 100)
	$Label.set_line(str(who))

func _height_key(info: Dictionary) :
	return 0

func _convert(data: Dictionary, dtype: String) -> Dictionary:
	if dtype == "text":
		return {"type": "text", "text": str(data["val"]), "ok": true}
	return {}

func _field_convert(who: String, data: String):
	return clampf(float(data), 0, 1) if data.is_valid_float() else null

func _defaults() -> Dictionary:
	return {"val": 0.0}

var cache = {}
func _resized():
	#("AA")
	#cache = {}
	var slider_size: float = 95.0
	if size.x < 100:
		slider_size -= 100- size.x
	$HSlider.position = Vector2(max(6, size.x / 2 - slider_size / 2), size.y / 2 + 4)
	$HSlider.size.x = min(slider_size, size.x - $HSlider.position.x - 6)
	$Label.position = Vector2($HSlider.position.x, size.y / 3 - $Label.size.y * $Label.scale.y / 2)

	#$Label.size.x = min((size.x - 20) / $Label.scale.x, len(cell_data["text"]) * 30)
	#cache[cell_data["text"]] = Rect2($Label.position, $Label.size)
	var minimal = (size.x - 20)/$Label.scale.x 
	$Label.size.x = min(minimal, 
	max(len($Label.text),3) * 30 * $Label.scale.x)
	$Label.resize_after = int(minimal / 20)
	#($Label.resize_after)
	if not $Label.is_node_ready():
		await $Label.ready
	##$Label.set_line($Label.text, false, true)
	$Label._resize_monospace()
	##_on_label_changed()
	#if name == "ergergerg1":
		#($Label.override)
	#$Label.resize.call_deferred()
	#("fjfj")


		



func _on_label_changed() -> void:
	var new_text = $Label.text
	if new_text.is_valid_float():
		_modify("val", float(new_text))
		$HSlider.set_value_no_signal(float(new_text) * 100.0)
	#await get_tree().process_frame
##	print(cell_data["text"])
	#var minimal = (size.x - 40)/$Label.scale.x 
	#$Label.size.x = min(minimal, 
	#len($Label.text) * 30 * $Label.scale.x)
	#if $Label.size.x >= minimal-1:
	#$Label.resize_after = 18
	#else:
		#$Label.resize_after = 0
	##if cell_data.text == "egrergger":
	##	print($Label.base_font_size)
	##	print($Label.resize_after)
	#$Label._resize_monospace()
	#(glob.get_label_text_size($Label).x)



func _on_h_slider_value_changed(value: float) -> void:
	value /= 100.0
	_modify("val", value)
	var capped = str(glob.cap(value, 2))
	var exp = len(capped.split(".")[-1])
	if exp == 1: capped += "0"
	$Label.set_line(capped)
