extends TableCell
func _map_data(data: Dictionary) -> void:
	#(data)
	cell_data = data
	$Label.set_line(data["text"])
	#_on_label_changed.call_deferred()

func _height_key(info: Dictionary) :
	return 0

func _defaults() -> Dictionary:
	return {"text": ""}
func _field_convert(who: String, data: String):
	return data
func _convert(data: Dictionary, dtype: String) -> Dictionary:
	match dtype:
		"num":
			if data["text"].is_valid_int():
				return {"type": "num", "num": int(data["text"]), "ok": true}
			else:
				return {"type": "num", "num": 0, "ok": false}
		"float":
			if data["text"].is_valid_float():
				return {"type": "float", "val": float(data["text"]), "ok": true}
			else:
				return {"type": "float", "val": 0, "ok": false}
			
	return {}


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
	_modify("text", $Label.text)



func _on_label_changed() -> void:
	pass
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
