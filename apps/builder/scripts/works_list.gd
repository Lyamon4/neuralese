@tool

extends BlockComponent

@onready var par = get_parent()


func _ready() -> void:
	if not Engine.is_editor_hint():
		super()

func _menu_handle_hovering(button: BlockComponent):
	glob.set_menu_type(self, &"delete_project")
	if glob.mouse_alt_just_pressed and not hint == "no_ctx":
		pass
		#("FJFJ")
		glob.menus[&"delete_project"].show_up(button.text, 
		(func():
			var a = await glob.delete_project(button.metadata["project_id"])
			show_up(glob.parsed_projects)
			))

func _process(delta: float) -> void:
	super(delta)
	glob.reset_menu_type(self, &"delete_project")
	#if not Engine.is_editor_hint():
	#	(_contained[-1].show())

func show_up(iter, node=null):
	#if visible: return=
	#menu_hide()
	#if is_instance_valid(timer):
	#	await timer.timeout
	glob.getref("works_unroll").unroll(iter)
	await get_tree().process_frame
	if not mouse_open:
		menu_show(position)
	state.holding = false
	unblock_input()
	tune()

@export var tune_mult = 2.2

func tune():

	for i in _contained:
		if i.metadata["project_id"] == glob.get_project_id():
			i.set_tuning(i.base_tuning * tune_mult)
	
	#menu_expand()
