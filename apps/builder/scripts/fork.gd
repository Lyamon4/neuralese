extends Control
class_name SplineFork

func plot_hide():
	$plot.hide()

			

func plot_show():
	$plot.show()

func upd():
	pass
#	glob.inst_uniform($o2, "extents", Vector4(0,0,global_position.x-2,0))

func set_color(col: Color):
	$o.color = col
