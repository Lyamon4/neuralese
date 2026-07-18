@tool
extends BlockComponent
#edit graph menu
@export var implement: bool = true

var menu_call: Callable
var menu_call_alt: Callable
func show_up(input: String, call: Callable):
	text = input if len(input) <= 9 else input.substr(0, 9) + ".."
	menu_call = call
	menu_show(pos_clamp(get_global_mouse_position()))

	state.holding = false

func set_txt(txt: String):
	match glob.get_lang():
		"en":
			txt = "Row " + txt
		"ru":
			txt = "Строка " + txt
		"kz":
			txt = "Сызық " + txt
	#(max(10 - len(text), 0))
	text = txt + " ".repeat(max(10 - len(txt), 0)) + " *"

var of_node: Graph = null
func _process(delta: float) -> void:
	super(delta)
var low = {"detatch": true, "edit_graph": true, "delete_i": 1}
func _menu_handle_release(button: BlockComponent):
	if implement:
		if button.hint == "copy":
			menu_call_alt.call()
			menu_hide()
		elif button.hint == "replace" and of_node.deletion_allowed:
			glob.set_menu_type(self, "select_node", low)
			menu_hide()
			glob.menus["select_node"].show_nodes(graphs.get_alt_nodes(of_node), position, 
			false, (func():
	
				#glob.open_action_batch(false)
				await menu_call.call()
				await glob.wait(3,true)
				), of_node.get_center_pos()) # Replace with function body.
				
			await glob.wait(0.1)
			glob.reset_menu_type(self, "select_node")
		elif button.hint == "info":
			glob.set_menu_type(self, "debug_info", low)
			menu_hide()
			var info_menu: BlockComponent = glob.menus["debug_info"]
			info_menu.menu_show(info_menu.pos_clamp(position))
			info_menu.state.holding = false
			info_menu.unblock_input(true)
			await glob.wait(0.1)
			glob.reset_menu_type(self, "debug_info")
		
		elif button.hint == "delete":
			await menu_call.call()
			menu_hide()
