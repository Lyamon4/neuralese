extends TableCell

var none = preload("res://game_assets/icons/none.png")
func _map_data(data: Dictionary) -> void:
	#(data)
	cell_data = data
	#(data)
	var got = data.get("img", null)
	var img: bool = got is Object
	if img:
		$TextureRect.texture = data["img"]
		$TextureRect.self_modulate = Color.WHITE
		#$TextureRect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		#$TextureRect.anchor_bottom = -6
	else:
		$TextureRect.self_modulate = Color(0.5, 0.5, 0.5, 1)
		#$TextureRect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		$TextureRect.texture = none
		#$TextureRect.anchor_bottom = -6
	if img:
		var dims = get_dims()
		_modify("x", int(dims.x))
		_modify("y", int(dims.y))
	else:
		_modify("x", 0)
		_modify("y", 0)
	
	#_on_label_changed.call_deferred()


func _creating(row: int, col: int, data: Dictionary):
	var key: int = data["x"] << 16 | data["y"]
	var ccache = table.get_ccache(col)
	#(ccache)
	if not key in ccache:
		ccache[key] = {data["id"]: true}
	else:
		ccache[key][data["id"]] = true
	#(ccache)


func change_cache(row: int, col: int, old_dims: Vector2i, data: Dictionary):
	if old_dims.x == data["x"] and old_dims.y == data["y"]:
		return
	var key: int = old_dims.x << 16 | old_dims.y
	var ccache = table.get_ccache(col)
	#(ccache)
	if not key in ccache:
		pass
	else:
		ccache[key].erase(data["id"])
		if ccache[key].size() == 0:
			ccache.erase(key)
	key = data["x"] << 16 | data["y"]
	if not key in ccache:
		ccache[key] = {data["id"]: true}
	else:
		ccache[key][data["id"]] = true
	#(ccache)


func _deleting(row: int, col: int, data: Dictionary):
	var key: int = data["x"] << 16 | data["y"]
	var ccache = table.get_ccache(col)
	#(ccache)
	if not key in ccache:
		pass
	else:
		ccache[key].erase(data["id"])
		if ccache[key].size() == 0:
			ccache.erase(key)
	#(ccache)


func _height_key(info: Dictionary) :
	return 0

func _field_convert(who: String, data: String):
	if who == "img":
		return 0
	return null

func get_dims():
	return $TextureRect.texture.get_size()

func _defaults() -> Dictionary:
	return {"img": null, "x": 0, "y": 0, "id": randi_range(0,9999999)}

@onready var upload = $Label/train2

func _mouse_enter():
	upload.show()

func _mouse_exit():
	upload.hide()


func _convert(data: Dictionary, dtype: String) -> Dictionary:
	return {}


var cache = {}
var prev_size_x: int = size.x
func _resized():
	if size.x != prev_size_x:
		prev_size_x = size.x
		#("AA")
		$Label.resize.call_deferred()
	pass


func _on_label_line_enter() -> void:
	pass



func _on_label_changed() -> void:
	pass
	#await get_tree().process_frame
##	print(cell_data["text"])
	#var minimal = (size.x - 40)/$Label.scale.x 
	#$Label.size.x = min(minimal, 
	#len($Label.text) * 30 * $Label.scale.x)
	#if $Label.size.x >= minimal-1:
	#$Label.resize_after = 18
	#else:
		#$Label.resize_after = 0
	##if cell_data.text == "egrergger":
	##	print($Label.base_font_size)
	##	print($Label.resize_after)
	#$Label._resize_monospace()
	#(glob.get_label_text_size($Label).x)



func _on_train_2_released() -> void:
	var seti = ["png", "jpg", "jpeg"]
	var a = await ui.splash_and_get_result("path_open", upload, null, true, 
	{"filter": seti, "dirs": true})
	var setified = glob.to_set(seti)
	if a:
		var path = a["path"]
		var files = []
		var is_dir: bool = false
		if DirAccess.dir_exists_absolute(path):
			is_dir = true
			files = DirAccess.get_files_at(path)
		else:
			files = [path]
		#(files)
		var imgs = []
		for file in files:
			
			if file.rsplit(".", true, 1)[-1] in setified:
				pass
			else:
				continue
			if is_dir:
				file = path + "/"+ file
			var img = Image.load_from_file(file)
			#(img)
			var new = ImageTexture.create_from_image(img)
			#(new)
			imgs.append(new)
		table.push_textures(self, imgs)
		#if imgs:
		#	$TextureRect.texture = imgs[0]
		#(imgs)
