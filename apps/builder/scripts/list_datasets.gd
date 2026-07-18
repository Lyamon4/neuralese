@tool

extends BlockComponent

@onready var par = get_parent()


func _ready() -> void:
	if not Engine.is_editor_hint():
		super()

#func _menu_handle_hovering(button: BlockComponent):
	#glob.set_menu_type(self, &"delete_project")
	#if glob.mouse_alt_just_pressed:
		#pass
		##("FJFJ")
		#glob.menus[&"delete_project"].show_up(button.text, 
		#(func():
			#var a = await glob.delete_project(button.metadata["project_id"])
			#show_up(glob.parsed_projects)
			#))

func _process(delta: float) -> void:
	super(delta)
	#glob.reset_menu_type(self, &"delete_project")

var passed_who: String = ""
func show_up(iter, node=null):
	#if visible: return=
	#menu_hide()
	#if is_instance_valid(timer):
	#	await timer.timeout
	glob.getref("datasets").unroll(iter)
	await get_tree().process_frame
	if not mouse_open:
		menu_show(position)
	state.holding = false
	unblock_input()
	tune(passed_who)

func tune(with_who: String):
	if with_who:
		var wh = button_by_hint.get(with_who)
		if wh:
			wh.set_tuning(wh.base_tuning * 1.8)
			#(wh.base_tuning * 2.2)
	
	#menu_expand()
