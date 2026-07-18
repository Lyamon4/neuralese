extends Control

@export var cust: bool = false
@export var base: Control = null

var _base = null
func _ready() -> void:
	_base = base.duplicate()
	base.queue_free()
	push_cfg({})
	
func push_cfg(cfg: Dictionary):
	#(cfg)
	$Label2.text = cfg.get("name", "")
	$Label3.text = glob.compact(cfg.get("size", 0)) if "size" in cfg else ""
	#(cfg)
	var who = $ScrollContainer/VBoxContainer
	for child in who.get_children():
		child.queue_free()
	for i in cfg.get("input_hints", []):
		var new_child = _base.duplicate()
		if cust:
			new_child.get_node("value").top = self
		new_child.get_node("name").text = i.name
		#new_child.get_node("name").simple = true
		#new_child.get_node("name").simple_letters = 8
		new_child.get_node("value").text = i.get("value", "")
		new_child.get_node("dtype").text = i.get("dtype", "")
		who.add_child(new_child)
		new_child.get_node("name").resize()
		if not cust:
			new_child.get_node("dtype").position.y = 7 - \
			(32-new_child.get_node("name").override) / 1.6









func re(pad: float):
	var who = $ScrollContainer/VBoxContainer
	#(pad)
	var i: int = 0
	for child in who.get_children():
		if child.get_node_or_null("name"):
			i += 1
			#(child)
			child.get_node("name").resize()
			child.get_node("dtype").position.y = 19 - \
			(32-child.get_node("name").override) / 1.6
			var val = child.get_node("value")
			var spl: PackedStringArray = val.text.split("\n")
			var maxl: int = 0
			for j in spl:
				maxl = max(len(j), maxl)
			var leng = maxl * 20 * val.scale.x
			#if i == 2:
			#	print(leng)
			var smpl = int((pad - leng - 30) / 16)
			child.get_node("name").simple_letters = smpl
