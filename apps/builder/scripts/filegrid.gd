# FileGrid.gd
extends GridVisualiser
class_name FileGrid

@export var file_icon: Texture2D
@export var dir_icon: Texture2D

var current_dir: String
var filter_extensions: Dictionary = {}
var scroll_cache: Dictionary = {}

var selected_path: String:
	get:
		return selected_key
	set(value):
		selected_key = value

var selected_is_dir: bool:
	get:
		return bool(selected_meta.get("is_dir", false))
	set(value):
		selected_meta["is_dir"] = value

signal file_selected(path: String)
signal directory_entered(path: String)
signal scan_finished
signal file_hovered(path: String, is_dir: bool)

var _scan_thread: Thread = null

func _ready() -> void:
	super._ready()
	#current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	#await _refresh()

func _refresh() -> void:
	if _scan_thread and _scan_thread.is_alive():
		return

	_vis_begin_refresh()

	_scan_thread = Thread.new()
	_scan_thread.start(_thread_scan_dir.bind(current_dir))
	await scan_finished

	_vis_end_refresh()

func _thread_scan_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return

	var dirs = dir.get_directories()
	var files = dir.get_files()

	if not filter_extensions.is_empty():
		var filtered = PackedStringArray()
		for f in files:
			var ext = f.get_extension().to_lower()
			if filter_extensions.has(ext):
				filtered.append(f)
		files = filtered

	dirs.sort()
	files.sort()
	_on_scan_finished.call_deferred(dirs, files)

func _on_scan_finished(dirs: PackedStringArray, files: PackedStringArray) -> void:
	await _create_entries_async(dirs, files)
	if _scan_thread:
		_scan_thread.wait_to_finish()
		_scan_thread = null
	scan_finished.emit()

func _create_entries_async(dirs: PackedStringArray, files: PackedStringArray) -> void:
	var counter = 0
	for fname in dirs:
		if fname.begins_with("."):
			continue
		_add_entry(fname, true)
		counter += 1
		if counter % batch_size == 0:
			await get_tree().process_frame

	for fname in files:
		_add_entry(fname, false)
		counter += 1
		if counter % batch_size == 0:
			await get_tree().process_frame

func _add_entry(file_name: String, is_dir: bool) -> void:
	var full_path = current_dir.path_join(file_name)
	add_item(
		full_path,
		file_name,
		dir_icon if is_dir else file_icon,
		file_name,
		{
			# keep old meta names so existing logic stays stable
			"path": full_path,
			"is_dir": is_dir,
		}
	)

func select_path(path: String, emit_signal_on_select: bool = false) -> void:
	if not has_item(path):
		push_warning("select_path(): Path not found in current view: %s" % path)
		return

	var tile: PanelContainer = get_tile(path)
	var is_dir = tile.get_meta("is_dir", false)

	_select_tile(tile, path, {"is_dir": is_dir})

	if emit_signal_on_select:
		if is_dir:
			current_dir = path
			await _refresh()
			directory_entered.emit(path)
		else:
			file_selected.emit(path)

func _on_item_selected(key: String, meta: Dictionary, tile: Control) -> void:
	var path = str(tile.get_meta("path", key))
	var is_dir = bool(tile.get_meta("is_dir", false))
	file_hovered.emit(path, is_dir)

func _on_item_activated(key: String, meta: Dictionary, tile: Control) -> void:
	var path = str(tile.get_meta("path", key))
	var is_dir = bool(tile.get_meta("is_dir", false))

	if is_dir:
		current_dir = path
		await _refresh()
		directory_entered.emit(path)
	else:
		file_selected.emit(path)

func go_up() -> void:
	var parent = current_dir.get_base_dir()
	if parent != current_dir:
		current_dir = parent
		await _refresh()
		directory_entered.emit(current_dir)

func refresh() -> void:
	await _refresh()
