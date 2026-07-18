extends CanvasLayer

@onready var menu: BlockComponent = $debug_menu

func _ready() -> void:
	await get_tree().process_frame
	menu.unroll()
	menu.update_children_reveal()
