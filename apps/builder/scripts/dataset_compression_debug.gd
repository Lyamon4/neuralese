class_name DatasetCompressionDebug

const ENV_SWITCH := "NEURALESE_DATASET_COMPRESSION_COMPARE"
const PROJECT_SWITCH := "debug/neuralese/compare_dataset_compression"
const PYTHON_ENGINE := "res://local_runtime/tools/dataset_compression_engine.py"

static func enabled() -> bool:
	var env_value := OS.get_environment(ENV_SWITCH).strip_edges().to_lower()
	if env_value in ["1", "true", "yes", "on"]:
		return true
	return bool(ProjectSettings.get_setting(PROJECT_SWITCH, false))

static func compare_async(dataset_name: String, dataset: Dictionary, godot_result: Dictionary) -> void:
	if not enabled():
		return
	var canonical_dataset := canonicalize_dataset(dataset)
	var canonical_expected := canonicalize_result(godot_result)
	WorkerThreadPool.add_task(
		_run_compare.bind(dataset_name, canonical_dataset, canonical_expected),
		false,
		"dataset-compression-compare"
	)

static func canonicalize_dataset(dataset: Dictionary) -> Dictionary:
	var result := {
		"arr": [],
		"col_names": dataset.get("col_names", []).duplicate(true),
		"outputs_from": int(dataset.get("outputs_from", 0)),
		"col_args": dataset.get("col_args", []).duplicate(true),
	}
	for row_value in dataset.get("arr", []):
		var source_row: Array = row_value
		var row: Array = []
		for cell_value in source_row:
			var cell: Dictionary = cell_value
			var copied := cell.duplicate(true)
			if copied.get("type", "") == "image":
				copied["image_bytes_hex"] = _extract_image_bytes(cell).hex_encode()
				copied.erase("img")
			row.append(copied)
		result["arr"].append(row)
	return result

static func canonicalize_result(result: Dictionary) -> Dictionary:
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

static func _extract_image_bytes(cell: Dictionary) -> PackedByteArray:
	var texture = cell.get("img")
	if texture == null or texture is EncodedObjectAsID:
		return PackedByteArray()
	if texture is Object and texture.has_method("get_image"):
		var image: Image = texture.get_image()
		if image != null:
			return image.get_data()
	return PackedByteArray()

static func _run_compare(dataset_name: String, dataset: Dictionary, expected: Dictionary) -> void:
	var temp_dir := OS.get_cache_dir().path_join("neuralese_dataset_compression")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var token := "%s_%s_%s" % [dataset_name.sha256_text().substr(0, 12), Time.get_unix_time_from_system(), randi()]
	var input_path := temp_dir.path_join(token + "_input.json")
	var expected_path := temp_dir.path_join(token + "_expected.json")
	var output_path := temp_dir.path_join(token + "_python.json")
	if not _write_json(input_path, dataset) or not _write_json(expected_path, expected):
		push_error("[DatasetCompressionCompare] Could not write comparison fixture for '%s'." % dataset_name)
		return

	var python := _python_executable()
	var engine := ProjectSettings.globalize_path(PYTHON_ENGINE)
	var args := [engine, input_path, "--output", output_path, "--expected", expected_path]
	var output: Array = []
	var exit_code := OS.execute(python, args, output, true, true)
	if exit_code == 0:
		print("[DatasetCompressionCompare] MATCH dataset='%s'" % dataset_name)
	else:
		push_error("[DatasetCompressionCompare] MISMATCH dataset='%s' exit=%d\n%s" % [
			dataset_name,
			exit_code,
			"\n".join(output),
		])

	DirAccess.remove_absolute(input_path)
	DirAccess.remove_absolute(expected_path)
	DirAccess.remove_absolute(output_path)

static func _python_executable() -> String:
	var bundled := ProjectSettings.globalize_path("res://local_runtime/python/python.exe")
	if FileAccess.file_exists(bundled):
		return bundled
	return "python"

static func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	return true
