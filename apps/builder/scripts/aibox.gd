extends Control

func _enter_tree():
	ui.topr = self

func _process(delta: float) -> void:
	if not visible:
		
		ui.upd_topr_inside(self, false); return
	var o = global_position.y+10
	var i = global_position.y+$txt.size.y*scale.y - 20
	var maxval = $txt.get_v_scroll_bar().max_value - $txt.get_v_scroll_bar().page - 5
	glob.inst_uniform($txt, "extents", 
	Vector4(o if $txt.get_v_scroll_bar().value > 5 else 0, 
	i if $txt.get_v_scroll_bar().value < maxval else 0, 
	0, 0))
	if $txt/ColorRect.get_global_rect().has_point(get_global_mouse_position()):
		ui.upd_topr_inside(self, true)
		glob.set_menu_type(self, "o")
	else:
		ui.upd_topr_inside(self, false)
		glob.reset_menu_type(self, "i")
	#(ui.get_focus())
		#$txt.get_v_scroll_bar().grab_focus()

func show_text(txt: String):
	show()
	$txt.set_txt("")
	$txt.push_text(txt)


func _on_ai_released() -> void:
	hide()
