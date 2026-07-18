extends Node2D
class_name TabWindow
const DUMMY_MENU_SCENE := preload("res://scenes/dummy_menu.tscn")

@export var window_name: String = ""
@export var camera: Camera2D

func _ready() -> void:
	if window_name == "graph" and glob.MENU_PLAY_AROUND and not has_node("dummy_menu"):
		add_child(DUMMY_MENU_SCENE.instantiate())

func _enter_tree() -> void:
	assert(!glob.tree_windows.has(window_name), "occupied")
	glob.tree_windows[window_name] = self
	camera.enabled = false

func _window_show():
	process_mode = Node.PROCESS_MODE_ALWAYS
	graphs.show()
	$menus.show()
	$follow_menus.show()
	$bg/TextureRect.show()
	show()
	if glob.cam is GraphViewport:
		glob.cam.reset()

func _window_hide():
	if glob.cam is GraphViewport:
		glob.cam.reset()
	process_mode = Node.PROCESS_MODE_DISABLED
	glob.hide_all_menus()
	graphs.hide()
	#(get_children())
	$menus.hide()
	$follow_menus.hide()
	$bg/TextureRect.hide()
	hide()

func window_hide():
	glob.cam = null
	camera.enabled = false
	_window_hide()
	glob.selector_box.hide()

func window_show():
	#glob.selector_box.clamp_rect = Rect2(0, glob.space_begin.y, 99999, 99999)
	glob.cam = camera
	print(window_name)
	camera.make_current()
	camera.enabled = true
	_window_show()

	#$GraphStorage.process_mode = Node.PROCESS_MODE_DISABLED
