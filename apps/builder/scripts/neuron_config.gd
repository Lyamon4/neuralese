extends Graph

@onready var dropout = $ColorRect2

func _after_ready():
	super()
	activ_show("none")

func _config_field(field: StringName, value: Variant):
	if field == "activ":
		selected_activation = value
		activ_show(selected_activation)
		if value in dropout.button_by_hint:
			dropout.text = dropout.button_by_hint[value].text

var selected_activation: StringName = &"none"

func activ_show(hint: String):
	match hint:
		"none":
			$plot/plot.load_dump(func(x): return x, Vector2(0.0, 80.0), 100)
		"relu":
			$plot/plot.load_dump(func(x): return max(x,0.0), Vector2(0.2, 80.0), 100)
		"sigmoid":
			$plot/plot.load_dump(
				func(x): return 1.0 / (1.0 + exp(-5.0 * x)),
				Vector2(0.2, 80.0),
				10
			)
		"tanh":
			$plot/plot.load_dump(
				func(x):
					var s = 1.0 / (1.0 + exp(-2.0 * x))
					return 2.0 * s - 1.0,
				Vector2(0.0, 60.0),
				10
			)

func _on_color_rect_2_child_button_release(button: BlockComponent) -> void:
	#button.is_contained.text = button.text
	open_undo_redo()
	update_config({"activ": button.hint})
	close_undo_redo()
	#selected_activation = button.hint
	button.is_contained.menu_hide()

@onready var list = $ColorRect2
func _proceed_hold() -> bool:
	return list.current_type == BlockComponent.ButtonType.CONTEXT_MENU
