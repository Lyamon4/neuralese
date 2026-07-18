extends Node2D

@export var hidden_cta: bool = false

var relative = Vector2(0,200)
@onready var input_offset = -input_cta._wrapped_in.size/2.0
func _ready() -> void:
	#relative = tutorial_cta._wrapped_in.global_position - input_cta._wrapped_in.global_position
	events.event_changed.connect(event_handle)
	
	tutorial_cta._wrapped_in.hide()
	if hidden_cta:
		input_cta._wrapped_in.hide()
	glob.lesson_opened.connect(func(who: String):
		input_cta._wrapped_in.hide()
		)
	glob.project_opened.connect(func(who: String):
		await glob.wait(1,true)
		if !hidden_cta and !is_instance_valid(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)):
			input_cta._wrapped_in.global_position = input_offset + glob.cam.get_target_position()

			input_cta._wrapped_in.show()
			#tutorial_cta._wrapped_in.global_position = input_cta._wrapped_in.global_position + relative
		await glob.wait(2,true))
	await glob.wait(6, true)
	input_cta._wrapped_in.global_position = glob.cam.get_target_position() + input_offset
	#if input_cta._wrapped_in.visible:
		#tutorial_cta._wrapped_in.global_position = input_cta._wrapped_in.global_position + relative
	
@export var input_cta: BlockComponent
@export var tutorial_cta: BlockComponent
func event_handle(name, meta, active):
	#print(active
	if name != "node": return
	if glob.project_id == -1:
		return
	if meta.who.is_input:
		if meta.who.is_train_graph:
			pass
			#if active:
				#$input.hide()
			#else:
				#$input.show()
		else:
			var center = meta.who.get_center_pos()
			await glob.wait(7,true)
			input_cta._wrapped_in.global_position = input_offset + glob.cam.get_target_position()
			#tutorial_cta._wrapped_in.global_position = input_cta._wrapped_in.global_position + relative

			#print((graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)))
			if is_instance_valid(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)):
				input_cta._wrapped_in.hide()
				#tutorial_cta._wrapped_in.hide()
				glob.un_occupy(input_cta, "block_button_inside") 
			elif !hidden_cta:
				input_cta._wrapped_in.global_position = center
				input_cta._wrapped_in.show()
				#tutorial_cta._wrapped_in.show()

var low = {"detatch": true, "edit_graph": true}
func _process(delta: float) -> void:
	#print(ui.splashed.keys()[0].typename)
	if !hidden_cta and input_cta._wrapped_in.visible and input_cta.is_mouse_inside():
		#if graphs.selected_nodes.size() <= 1:
		glob.set_menu_type(self, "select_node", low)
		
	else:
		glob.reset_menu_type(self, "select_node")

func _on_input_released() -> void:
	glob.menus["select_node"].show_nodes(["input", "input_1d"], get_global_mouse_position()) # Replace with function body.


func _on_tutorial_released() -> void:
	#print(ui.is_splashed("lessonlist"))
	ui.splash("lessonslist", tutorial_cta, null)
