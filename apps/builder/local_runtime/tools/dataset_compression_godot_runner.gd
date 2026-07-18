extends SceneTree

const Compressor := preload("res://ds_obj_serialize.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: --script dataset_compression_godot_runner.gd <fixture.json> <output.json>")
		quit(2)
		return
	var fixture_path := args[0]
	var output_path := args[1]
	var fixture := _read_json(fixture_path)
	if fixture.is_empty():
		quit(2)
		return

	fixture["outputs_from"] = int(fixture.get("outputs_from", 0))
	_materialize_images(fixture)
	var result: Dictionary = Compressor.compress_blocks(fixture)
	var canonical := _canonicalize_result(result)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open output: %s" % output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(canonical))
	file.close()
	quit(0)

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open fixture: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		push_error("Fixture is not a JSON object: %s" % path)
		return {}
	return parsed

func _materialize_images(dataset: Dictionary) -> void:
	for row_value in dataset.get("arr", []):
		var row: Array = row_value
		for cell_value in row:
			var cell: Dictionary = cell_value
			if cell.get("type", "") != "image":
				continue
			var raw: PackedByteArray = str(cell.get("image_bytes_hex", "")).hex_decode()
			var width := int(cell.get("image_width", 0))
			var height := int(cell.get("image_height", 0))
			var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, raw)
			cell["img"] = ImageTexture.create_from_image(image)

func _canonicalize_result(result: Dictionary) -> Dictionary:
	var canonical := {
		"header": result.get("header", {}).duplicate(true),
		"data": [[], []],
	}
	for side_index in range(2):
		var side: Array = result.get("data", [[], []])[side_index]
		for column_value in side:
			var column: Dictionary = column_value
			var blocks: Array = []
			for block_value in column.get("blocks", []):
				var block: PackedByteArray = block_value
				blocks.append(block.hex_encode())
			canonical["data"][side_index].append({
				"blocks": blocks,
				"hashes": column.get("hashes", []).duplicate(true),
				"rows_per_block": int(column.get("rows_per_block", 0)),
				"dtype": str(column.get("dtype", "")),
			})
	return canonical
