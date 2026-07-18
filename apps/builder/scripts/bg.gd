extends CanvasLayer


func _enter_tree():
	glob.bg_trect = self

@onready var base_bgcol =  ui.get_uni($SubViewport/bg/ColorRect, "bg_color")
@onready var base_grcol =  ui.get_uni($SubViewport/bg/ColorRect, "grid_color")

func set_screenshotting():
	ui.set_uni($SubViewport/bg/ColorRect, "bg_color", Color.GRAY)
	ui.set_uni($SubViewport/bg/ColorRect, "grid_color", Color.GRAY)
	
func set_not_screenshotting():
	ui.set_uni($SubViewport/bg/ColorRect, "bg_color", base_bgcol)
	ui.set_uni($SubViewport/bg/ColorRect, "grid_color", base_grcol)
