class_name TableCell
extends Control

var table: VirtualTable = null
@export var cell_type: StringName
@export var height: float = 67.0
@export var expensive: bool = false
@export var base_field: String = ""

signal changed

func _field_convert(who: String, data: String):
	pass

func _defaults() -> Dictionary:
	return {}

var cell_data: Dictionary = {}
func _ready() -> void:
	cell_data["type"] = cell_type
	_resized()

func get_data() -> Dictionary:
	return {}

func _height_key(info: Dictionary):
	return ""

func _modify(field: String, value):
	if glob.ds_processing(): 
		map_data.bind(cell_data.duplicate(true)).call_deferred()
		return
	#("a")
	table.dirtify(coord.x)
	cell_data[field] = value


func _resized():
	pass

func _mouse_enter():
	#(cell_data)
	pass

func _mouse_exit():
	pass

func _convert(data: Dictionary, dtype: String) -> Dictionary:
	return {}


func _dense_data():
	return 0

func _creating(row: int, col: int, data: Dictionary):
	pass


func _deleting(row: int, col: int, data: Dictionary):
	pass


@export var coord: Vector2i = Vector2i()
func map_data(data: Dictionary) -> void:
	if data["type"] != cell_type: return
	#if !table.data_map_allowed: return
	_map_data(data)

func _map_data(data: Dictionary) -> void:
	pass

func _estimate_height(data: Dictionary):
#	print(data)
	return height

func get_desired_size() -> Vector2:
	return size
