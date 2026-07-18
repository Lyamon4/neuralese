extends Node

const INSTALL_DIR_NAME := "local_runtime"
const MANIFEST_NAME := ".neuralese_runtime_manifest.json"

var _ready := false
var _runtime_root := ""
var _last_error := ""


func is_ready() -> bool:
	return _ready


func _export_install_base_abs() -> String:
	return OS.get_executable_path().get_base_dir().path_join(INSTALL_DIR_NAME)


func _export_install_root_abs(platform: String) -> String:
	return _export_install_base_abs().path_join(platform)


func ensure_ready() -> bool:
	if _ready:
		return true

	_last_error = ""
	if OS.has_feature("editor"):
		_runtime_root = ProjectSettings.globalize_path("res://local_runtime")
		_ready = _runtime_has_python(_runtime_root)
		if not _ready:
			_last_error = "Editor local runtime is missing Python: " + _runtime_root
		return _ready

	var platform := platform_id()
	var install_root := _export_install_root_abs(platform)
	print("[LocalRuntime] Checking preinstalled runtime: ", install_root)
	if not _preinstalled_runtime_is_valid(install_root, platform):
		print(_last_error)
		return false

	_runtime_root = install_root
	_ready = true
	print("[LocalRuntime] Preinstalled runtime registered")
	return true


func runtime_root_abs() -> String:
	if not await ensure_ready():
		return ""
	return _runtime_root


func python_path() -> String:
	if not await ensure_ready():
		return ""
	return _python_executable_path(_runtime_root)


func entry_path(rel_path: String) -> String:
	if not await ensure_ready():
		return ""
	var clean := _runtime_relative_path(rel_path)
	if OS.has_feature("editor"):
		return _runtime_root.path_join(clean)
	if clean.ends_with(".py"):
		clean = clean.substr(0, clean.length() - 3) + ".pyc"
	return _runtime_root.path_join(clean)


func last_error() -> String:
	return _last_error


func platform_id() -> String:
	match OS.get_name():
		"Windows":
			return "windows-x64"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "linux-x64"
		_:
			return OS.get_name().to_lower() + "-x64"


func _runtime_relative_path(path: String) -> String:
	var clean := path.replace("\\", "/").strip_edges()
	if clean.begins_with("res://local_runtime/"):
		clean = clean.substr("res://local_runtime/".length())
	elif clean.begins_with("local_runtime/"):
		clean = clean.substr("local_runtime/".length())
	elif clean.begins_with("res://"):
		clean = clean.substr("res://".length())
	return clean.trim_prefix("/")


func _runtime_has_python(root: String) -> bool:
	return _python_executable_path(root) != ""


func _python_executable_path(root: String) -> String:
	var candidates := [
		root.path_join("python").path_join("python.exe"),
		root.path_join("python").path_join("Scripts").path_join("python.exe"),
		root.path_join("python").path_join("bin").path_join("python3"),
		root.path_join("python").path_join("bin").path_join("python"),
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _preinstalled_runtime_is_valid(root: String, platform: String) -> bool:
	if not _runtime_has_python(root):
		_last_error = "Preinstalled local runtime has no Python executable: " + root
		return false

	var manifest_path := root.path_join(MANIFEST_NAME)
	if not FileAccess.file_exists(manifest_path):
		_last_error = "Preinstalled local runtime manifest is missing: " + manifest_path
		return false

	var parsed = JSON.parse_string(_read_text(manifest_path))
	if not (parsed is Dictionary):
		_last_error = "Preinstalled local runtime manifest is invalid JSON: " + manifest_path
		return false

	var manifest_platform := str(parsed.get("platform", "")).strip_edges()
	if manifest_platform != "" and manifest_platform != platform:
		_last_error = "Preinstalled local runtime platform mismatch: expected %s, got %s" % [platform, manifest_platform]
		return false

	return true


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
