extends ColorRect

var tg_visible: bool = false
func target_visible():
	tg_visible = true
	show()


func _enter_tree() -> void:
	ui.mist = self

func target_invisible():
	tg_visible = false

func _ready() -> void:
	target_invisible()
	hide()
	self_modulate.a = 0.0
	ui.axon_donut = self

func _process(delta: float) -> void:
	if not visible:
		return
	if tg_visible:
		self_modulate.a = lerpf(self_modulate.a, 1.0, delta * 5.0)
	else:
		self_modulate.a = lerpf(self_modulate.a, 0.0, delta * 5.0)
		if is_zero_approx(self_modulate.a):
			hide()
