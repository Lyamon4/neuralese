@tool

extends BlockComponent

@export var naming = "list_unroll"
@export var auto: bool = false
@onready var par = get_parent()
@export var auto_names: Array[String] = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		super()
		if auto:
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var autos = {}
			for i in auto_names:
				var spl = i.split(":")
				autos[spl[0]] = spl[1]
			show_up(autos)

func _process(delta: float) -> void:
	super(delta)
	#if not Engine.is_editor_hint() and menu_name == "list_dirs":
	#	if in_splash:
	#		print(_contained)

func show_up(iter, node=null):
	#if visible: return=
	#menu_hide()
	#if is_instance_valid(timer):
	#	await timer.timeout
	glob.getref(naming).unroll(iter)
	await get_tree().process_frame
	if not mouse_open:
		menu_show(position)
	state.holding = false
	unblock_input()
	
	
	#menu_expand()
