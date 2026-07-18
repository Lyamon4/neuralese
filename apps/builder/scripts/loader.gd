extends Control

@export var table: VirtualTable

func _ready() -> void:
	pass
	#var data := []
	#for r in 5000:
		#var row := []
		#for c in 2:
			#row.append({"type": "text", "text": "R%s C%s" % [r, c]})
		#data.append(row)
#
	#table.load_dataset(data, 2, 5000)
	#
	table.set_column_ratios(PackedFloat32Array([0.5, 0.5]))

func _process(delta: float) -> void:
	pass
	#if glob.space_just_pressed:
	#	var a = (table.get_row_at_position(table.get_local_mouse_position()))
	#	if a != -1:
	#		table.remove_row(a)
		#var t = Time.get_ticks_msec()
		#var row := []
		#row.append({"type": "text", "text": "0"})
		#for c in 2:
			#row.append({"type": "text", "text": "regegres"})
		#
		#table.add_row(row, 99990)
		#await get_tree().process_frame
		#(glob.get_process_delta_time())
		#t = Time.get_ticks_msec()
	#	table.scroll_to_row(49999, "center")
	#	print(Time.get_ticks_msec() - t)
			
