extends TableCell
func _map_data(data: Dictionary) -> void:
	#if coord.y == 2:
	#	print(data)
	#	print_stack()
	var argpack = table.get_column_arg_pack(coord.y)
	#(coord.y, " ", argpack)
	if not argpack: return
	cell_data = data
	#if not table.data_map_allowed: return
	#(coord.y, " ", argpack, " ", data["num"])
	#if coord.y == 2:
	#	print(table.adapter_data)
	#	print_stack()
	if not argpack.has("min"): argpack["min"] = 0
	if not argpack.has("max"): argpack["max"] = 100
	data["num"] = clamp(data["num"], argpack.min, argpack.max)
	#("======", coord.y)
	$Label.min_value = argpack.min
	$Label.placeholder_text = str(argpack.min)
	$Label.max_value = argpack.max
	if int(data["num"]) == $Label.min_value:
		$Label.prev = data["num"]
		$Label.set_line("")
	else:
		$Label.prev = data["num"]
		$Label.set_line(str(data["num"]))
	$Label._revalidate_limits()
	#($Label.min_value, " ", $Label.max_value)
	#_on_label_changed.call_deferred()

func _height_key(info: Dictionary) :
	return 0

func _convert(data: Dictionary, dtype: String) -> Dictionary:
	match dtype:
		"text":
			return {"type": "text", "text": str(data["num"]), "ok": true}
		"float":
			return {"type": "float", "val": float(data["num"]), "ok": true}
	return {}

func _field_convert(who: String, data: String):
	return int(data) if data.is_valid_int() else null

func _defaults() -> Dictionary:
	return {"num": 0}

var cache = {}
func _resized():
	#("AA")
	#cache = {}
	
	$Label.position = Vector2(10, size.y / 2 - $Label.size.y * $Label.scale.y / 2)
	
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


func _on_label_line_enter() -> void:
	if $Label.is_valid:
		_modify("num", int($Label.get_value()))
		#(cell_data)
		#(table._get_cell(coord.x, coord.y))
		#(get_instance_id())
		#(cell_data)



func _on_label_changed() -> void:
	var argpack = table.get_column_arg_pack(coord.y)
	if argpack:
		$Label.min_value = argpack.min
		$Label.max_value = argpack.max
	#($Label.max_value, " ", coord.y, " ", table.get_column_arg_pack(coord.y))
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
