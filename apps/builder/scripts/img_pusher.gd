@tool
extends Node
class_name SizePusher

@export var size: Vector2i = Vector2i():
	set(v):
		if Engine.is_editor_hint():
			size = v; re()
@export var rgb: bool = false

func _ready():
	if Engine.is_editor_hint():
		re()

func re():
	var img = Image.create_empty(size.x, size.y, false, Image.FORMAT_L8 if !rgb else Image.FORMAT_RG8)
	get_parent().texture = ImageTexture.create_from_image(img)
