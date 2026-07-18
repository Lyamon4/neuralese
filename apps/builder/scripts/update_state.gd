extends Node
class_name UpdateManager

const LOCAL_VERSION := "1.0.7"

const OLD_EXE_NAME := "Neuralese_old.exe"
const SCRIPT_NAME  := "update.cmd"

var _exe_dir: String
var _new_exe_path: String
var _script_path: String
var _cur_exe_name: String


func _ready():
	var exe_path := OS.get_executable_path()
	_exe_dir = exe_path.get_base_dir()
	_cur_exe_name = exe_path.get_file()
	_script_path = _exe_dir.path_join(SCRIPT_NAME)


# ============================
# PUBLIC ENTRY POINT
# ============================
func check_update() -> void:
	if OS.has_feature("editor"):
		return

	var state = await _fetch_update_state()
	if not state:
		return

	if not state.get("d_req", false):
		return

	if state.get("version", "") == LOCAL_VERSION:
		return

	var ok = await _download_executable(state.get("exe_url", ""))
	if not ok:
		print("Update download failed")
		return

	if not _validate_download():
		print("Downloaded exe invalid")
		return

	_create_update_script()
	_run_update_script_and_exit()


# ============================
# STEP 1 — FETCH UPDATE STATE
# ============================
func _fetch_update_state() -> Dictionary:
	var sig = web.GET("check")
	var res = await sig
	if not res or not res.ok:
		return {}
	return JSON.parse_string(res.body.get_string_from_utf8())


# ============================
# STEP 2 — DOWNLOAD (NO RESUME)
# ============================
func _download_executable(url: String) -> bool:
	if url == "":
		return false

	_new_exe_path = _exe_dir.path_join("Neuralese_new.exe")

	if FileAccess.file_exists(_new_exe_path):
		DirAccess.remove_absolute(_new_exe_path)

	var file := FileAccess.open(_new_exe_path, FileAccess.WRITE)
	if not file:
		return false

	var handle = web.GET(url, {}, true) # bytes=true
	handle.on_chunk.connect(func(chunk: PackedByteArray):
		file.store_buffer(chunk)
	)

	var result = await handle.completed
	file.close()

	return result.ok


# ============================
# STEP 3 — BASIC VALIDATION
# ============================
func _validate_download() -> bool:
	if not FileAccess.file_exists(_new_exe_path):
		return false

	var f := FileAccess.open(_new_exe_path, FileAccess.READ)
	if not f:
		return false

	var size := f.get_length()
	f.close()

	return size > 10 * 1024 * 1024


# ============================
# STEP 4 — SCRIPT GENERATION
# ============================
func _create_update_script() -> void:
	var script := """@echo off
cd /d "%EXE_DIR%"

timeout /t 2 /nobreak >nul

if exist "%OLD_EXE%" del "%OLD_EXE%"
rename "%CUR_EXE%" "%OLD_EXE%"
rename "%NEW_EXE%" "%CUR_EXE%"

start "" "%CUR_EXE%"
del "%~f0"
"""

	script = script.replace("%EXE_DIR%", _exe_dir)
	script = script.replace("%CUR_EXE%", _cur_exe_name)
	script = script.replace("%NEW_EXE%", "Neuralese_new.exe")
	script = script.replace("%OLD_EXE%", OLD_EXE_NAME)

	var f := FileAccess.open(_script_path, FileAccess.WRITE)
	f.store_string(script)
	f.close()


# ============================
# STEP 5 — EXECUTE & EXIT
# ============================
func _run_update_script_and_exit() -> void:
	OS.create_process("cmd.exe", ["/c", _script_path])
	get_tree().quit()
