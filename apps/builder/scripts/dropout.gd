extends BaseNeuronLayer

func _useful_properties() -> Dictionary:
	return {"config": {"p": cfg["p"], "type": "dropout"},
	"cache_tag": str(graph_id)}

@export var img_size: Vector2i = Vector2i(14,8)
var img: Image
var base_pxs = {}
var b_seed: int = randi_range(0,99999)
func get_noise():
	var p = float(cfg["p"])
	var rng = RandomNumberGenerator.new()
	if p > 1-0.01: b_seed = randi_range(0,99999)
	for x in img_size.x:
		for y in img_size.y:
			rng.seed = b_seed + (x << 16 | y)
			var pixel = rng.randf_range(0.2,0.8)
			pixel *= clamp((pixel - (p-0.2)) * 5, 0, 1)
			#base_pxs[Vector2i(x,y)] = pixel
			img.set_pixel(x,y,Color.WHITE * pixel)
	$TextureRect.texture = ImageTexture.create_from_image(img)
	
func _can_drag() -> bool:
	return not ui.is_focus($ColorRect/root/Label4/HSlider)

#func _proceed_hold() -> bool:
#	#(($ColorRect/root/Label4/HSlider).get_global_rect().has_point(get_global_mouse_position()))
#	return ($ColorRect/root/Label4/HSlider).get_global_rect().has_point(get_global_mouse_position())

func _config_field(field: StringName, value: Variant):
	if field == "p":
		$ColorRect/root/Label4/HSlider.value = lerp(0, 100, value)
		$ColorRect/root/Label4/n.text = str(glob.cap(value, 1))
		get_noise()

func _on_h_slider_value_changed(value: float) -> void:
	open_undo_redo()
	update_config({"p": value / 100})
	close_undo_redo()

func _ready() -> void:
	super()
	img = Image.create_empty(14,8,false,Image.FORMAT_L8)
	get_noise()
	$TextureRect.texture = ImageTexture.create_from_image(img)
