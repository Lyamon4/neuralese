@tool
extends TextureRect

var delay: float = 0.0
var prog: float = 0.0
var wanna_on: bool = false
var on_delay: float = 0.0
var since_last_on: float = 0.0
func _process(delta: float) -> void:
	on_delay += delta
	since_last_on += delta
	#if !Engine.is_editor_hint():
	#	print(modulate.a)
	if wanna_on:
		if on_delay < 0.5: delay = 0.0; prog = 0.0
		modulate.a = lerp(0.0, 1.0, clamp((on_delay-0.5)*1.0, 0.0, 1.0))
		if since_last_on > 3.0:
			off(true)
	else:
		modulate.a = lerp(modulate.a, 0.0, delta * 15.0)
	if delay > 0.3: delay = 0.0; prog = 0.0
	if delay: 
		delay += delta; return
	prog += delta * 1.5
	if prog > 1.0:
		rotation = PI
		delay += delta; return
	rotation = lerpf(PI, 0, glob.in_out_quad(prog))

var pending = 0
func on():
	show()
	pending += 1
	if not wanna_on:
		modulate.a = 0.0
		on_delay = 0.0
	since_last_on = 0.0
	wanna_on = true

func off(force: bool = false):
	if force:
		pending = 0
		wanna_on = false
		on_delay = 0.0; return
	if pending > 1:
		pending -= 1
	else:
		pending = 0
		wanna_on = false
		on_delay = 0.0
