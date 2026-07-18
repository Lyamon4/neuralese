extends Node

const FullyLocalConfigScript := preload("res://scripts/fully_local_config.gd")
const FULLY_LOCAL_TRAINING := FullyLocalConfigScript.TRAINING
const FULLY_LOCAL_RUNTIME_ENTRY := "res://local_runtime/neuralese_local/train_entry.py"
const FULLY_LOCAL_EXPORT_ENTRY := "res://local_runtime/neuralese_local/export_yolk.py"
const FULLY_LOCAL_INFER_ENTRY := "res://local_runtime/neuralese_local/infer_once.py"
const FULLY_LOCAL_INFER_LOOP_ENTRY := "res://local_runtime/neuralese_local/infer_loop.py"
const FULLY_LOCAL_PYTHON_RES := "res://local_runtime/python/python.exe"
const FULLY_LOCAL_INFER_DEBUG := true
const FULLY_LOCAL_INFER_IDLE_TIMEOUT_S := 60 * 30
const FULLY_LOCAL_JOB_GC_TTL_S := 60 * 60 * 24
const FULLY_LOCAL_DATASET_NAMES := {
	"mnist": true,
	"iris": true,
	"titanic": true,
	"car_track": true,
}

class LocalInferChannel:
	extends RefCounted
	var model_path: String = ""
	var graph: Dictionary = {}
	var context_id: String = ""
	var output_node_id: String = ""
	var on_close: Callable = Callable()
	var closed: bool = false
	var index: int = 0
	var pid: int = -1
	var job_dir: String = ""
	var control_path: String = ""
	var request_path: String = ""
	var response_path: String = ""
	var stop_path: String = ""
	var last_response_index: int = -1
	var last_request_msec: int = 0
	var no_response_logged: bool = false
	var parse_fail_count: int = 0
	var request_in_flight: bool = false
	var pending_data = null

var inference_channel_leases := {}

func _infer_log(message: String, data: Dictionary = {}) -> void:
	if not FULLY_LOCAL_INFER_DEBUG:
		return
	var suffix := ""
	if not data.is_empty():
		suffix = " " + JSON.stringify(data)
	print("[FullyLocalInfer] " + message + suffix)

func _infer_input_tag(input: Graph) -> String:
	if not is_instance_valid(input):
		return "<invalid-input>"
	return "%s graph_id=%s context=%s" % [str(input.server_typename), str(input.graph_id), str(input.context_id)]


func _infer_channel_state_dict(sock) -> Dictionary:
	if sock is LocalInferChannel:
		return {
			"type": "local",
			"pid": sock.pid,
			"seq": sock.index,
			"closed": sock.closed,
			"request_in_flight": sock.request_in_flight,
			"has_pending_data": sock.pending_data is Dictionary,
			"last_response_index": sock.last_response_index,
			"job_dir": sock.job_dir,
			"request_path": sock.request_path,
			"response_path": sock.response_path,
		}
	return {
		"type": "remote_or_unknown",
		"valid": is_instance_valid(sock),
		"class": sock.get_class() if is_instance_valid(sock) else "<invalid>",
	}


func _infer_channel_lease_summary(input: Graph) -> Array:
	if not input in inference_channel_leases:
		return []
	var leases: Dictionary = inference_channel_leases[input]
	return leases.keys()


func infer_channel_lease_summary(input: Graph) -> Array:
	return _infer_channel_lease_summary(input)


func acquire_infer_channel_lease(input: Graph, owner: String) -> bool:
	if not is_instance_valid(input) or owner == "":
		return false
	var leases: Dictionary = inference_channel_leases.get(input, {})
	leases[owner] = true
	inference_channel_leases[input] = leases
	_infer_log("lease acquired", {
		"input": _infer_input_tag(input),
		"owner": owner,
		"leases": leases.keys(),
	})
	return true


func release_infer_channel_lease(input: Graph, owner: String) -> void:
	if owner == "":
		return
	if not input in inference_channel_leases:
		return
	var leases: Dictionary = inference_channel_leases[input]
	if owner in leases:
		leases.erase(owner)
	if leases.is_empty():
		inference_channel_leases.erase(input)
	else:
		inference_channel_leases[input] = leases
	_infer_log("lease released", {
		"input": _infer_input_tag(input) if is_instance_valid(input) else str(input),
		"owner": owner,
		"remaining_leases": leases.keys(),
	})


func infer_channel_has_external_lease(input: Graph) -> bool:
	if not input in inference_channel_leases:
		return false
	var leases: Dictionary = inference_channel_leases[input]
	return not leases.is_empty()


func close_auto_infer_channel(input: Graph) -> bool:
	if infer_channel_has_external_lease(input):
		_infer_log("auto close skipped: channel leased", {
			"input": _infer_input_tag(input),
			"leases": _infer_channel_lease_summary(input),
		})
		return false
	close_infer_channel(input)
	return true


func wait_infer_channel_idle(input: Graph, owner: String = "", timeout_s: float = 5.0) -> bool:
	var start_msec := Time.get_ticks_msec()
	while input in inference_sockets:
		var sock = inference_sockets[input]
		if !(sock is LocalInferChannel):
			return true
		if not sock.request_in_flight:
			return true
		if timeout_s >= 0.0 and float(Time.get_ticks_msec() - start_msec) / 1000.0 >= timeout_s:
			_infer_log("wait idle timed out", {
				"input": _infer_input_tag(input),
				"owner": owner,
				"channel": _infer_channel_state_dict(sock),
				"leases": _infer_channel_lease_summary(input),
			})
			return false
		await get_tree().process_frame
	return true


func delete_ctx(id):
	if FULLY_LOCAL_TRAINING:
		_delete_local_ctx(str(id))
	else:
		await web.POST("delete_ctx", {"user": cookies.user(), "pass": cookies.pwd(), "scene": str(glob.get_project_id()), "contexts": [str(id)]})


var local_training_jobs := {}
var _shutdown_cleanup_started := false
var _runtime_gc_accum := 0.0

func _ready() -> void:
	await local_runtime.ensure_ready()
	_gc_fully_local_runtime_dirs(true)
	await glob.wait(1, true)
	DisplayServer.window_set_title("Neuralese")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		close_all(true)
		if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
			get_tree().quit()

func _handle_train_state_dict(dict: Dictionary, additional: Callable, training_head: Graph = null):
	if not dict.has("phase"):
		return
	additional.call(dict)
	if dict["phase"] == "state":
		if dict["data"]["type"] == "complete":
			var head_to_stop = training_head if is_instance_valid(training_head) else graphs._training_head
			head_to_stop.train_stop()
			return
		var data = dict["data"]["data"]
		var acc = data["val_acc"]
		var head_to_update = training_head if is_instance_valid(training_head) else graphs._training_head
		if is_instance_valid(head_to_update):
			if head_to_update.has_method("push_acceptance"):
				head_to_update.push_acceptance(acc, 0.0)

func train_state_received(bytes: PackedByteArray, additional: Callable):
	var jsonified = bytes.get_string_from_utf8()
	var dict = JSON.parse_string(jsonified)
	if not dict: return
	if !(dict is Dictionary): return
	_handle_train_state_dict(dict, additional)



func request_save():
	for g in graphs._graphs:
		graphs._graphs[g].request_save()

func ws_ds_frames(train_input_origin: Graph, initial: Dictionary, ws: SocketConnection) -> void:
	if FULLY_LOCAL_TRAINING:
		push_warning("Skipping websocket dataset frames because FullyLocal training is enabled.")
		return
	var ds_name = train_input_origin.dataset_meta.get("name", "")
	if ds_name == "":
		push_warning("No dataset name found.")
		return
	if not glob.rle_cache.has(ds_name):
		push_warning("Dataset not yet compressed or cached.")
		return

	await glob.join_ds_processing()
	DsObjRLE.flush_now(ds_name, glob.dataset_datas[ds_name])
	#(DsObjProbe.probe_dataset(ds_name))

	var ds: Dictionary = glob.rle_cache[ds_name]
	var inputs: Array = ds["data"][0]
	var outputs: Array = ds["data"][1]
	var header: Dictionary = ds["header"]

	var block_hashes := {"inputs": [], "outputs": []}
	for col in inputs:
		block_hashes["inputs"].append(col.get("hashes", []))
	for col in outputs:
		block_hashes["outputs"].append(col.get("hashes", []))

	initial["session"] = cookies.user()
	initial["header"] = header
	initial["header"]["name"] = ds_name
	initial["block_hashes"] = block_hashes
	initial["hash_algo"] = "sha256"

	# --- send header ---
	var header_bytes = glob.compress_dict_zstd(initial)
	ws.send(header_bytes)
	#("[WS] Sent compressed header (%.2f KB)" % [float(header_bytes.size()) / 1024.0])

	var stats := {
		"total_bytes": 0.0,
		"total_blocks": 0,
		"side_bytes": {"inputs": 0.0, "outputs": 0.0}
	}

	### FIX: add dataset upload phase state flag
	var ds_phase_done := false

	var _on_packet: Callable
	_on_packet = func(data: PackedByteArray) -> void:
		# --- ignore if already done ---
		if ds_phase_done:
			return

		var text := data.get_string_from_utf8()
		if text == "__end__":
			return

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			# not JSON or not a dict — ignore
			return

		### FIX: only react to valid NEED payloads
		if not (parsed.has("inputs") or parsed.has("outputs")):
			return

		var need: Dictionary = parsed

		var _send_block = func(side: String, col_i: int, blk_i: int, blk_data: PackedByteArray) -> void:
			var meta := {"side": side, "col": col_i, "blk": blk_i}
			var meta_bytes := JSON.stringify(meta).to_utf8_buffer()

			var frame := PackedByteArray()
			frame.append((meta_bytes.size() >> 8) & 0xFF)
			frame.append(meta_bytes.size() & 0xFF)
			frame.append_array(meta_bytes)
			frame.append_array(blk_data)

			ws.send(frame)

			var bytes_sent = float(frame.size())
			stats["total_bytes"] += bytes_sent
			stats["total_blocks"] += 1
			stats["side_bytes"][side] += bytes_sent

			#if int(stats["total_blocks"]) % 50 == 0:
				#("[WS] Sent %d blocks (%.2f KB so far)" % [
				#	int(stats["total_blocks"]), stats["total_bytes"] / 1024.0
				#])

		# --- transmit all requested blocks ---
		for side in ["inputs", "outputs"]:
			if not need.has(side):
				continue
			var cols_arr := (inputs if side == "inputs" else outputs)
			for col_key in need[side].keys():
				var col_i := int(col_key)
				var missing: Array = need[side][col_key]
				if missing.is_empty():
					continue
				var col_data: Dictionary = cols_arr[col_i]
				var blocks: Array = col_data.get("blocks", [])
				for blk_i in missing:
					if blk_i >= 0 and blk_i < blocks.size():
						var blk_data: PackedByteArray = blocks[blk_i]
						_send_block.call(side, col_i, blk_i, blk_data)

		# --- end transmission ---
		ws.send("__end__".to_utf8_buffer())

		#("[WS] Sent all missing dataset blocks to server.")
		#("[WS] Blocks sent: %d  |  Total bytes: %.2f KB (%.2f MB)" %
		#	[int(stats["total_blocks"]), stats["total_bytes"] / 1024.0, stats["total_bytes"] / 1024.0 / 1024.0])
		#("[WS] Inputs: %.2f KB   Outputs: %.2f KB" %
		#	[stats["side_bytes"]["inputs"] / 1024.0, stats["side_bytes"]["outputs"] / 1024.0])

		### FIX: disconnect after sending once
		ds_phase_done = true
		if ws.packet.is_connected(_on_packet):
			ws.packet.disconnect(_on_packet)

	ws.packet.connect(_on_packet)







func try_print(train_input: Graph):
	var train_input_origin = graphs._reach_input(train_input, "TrainBegin")
	var execute_input_origin = null
	var _d = {}
	var cachify = func(from: Connection, to: Connection, branch_cache: Dictionary):
		if to.parent_graph.server_typename == "RunModel":
			assert(not _d.get("input"), "compile failed, run_model node >1 times banned")
			
			_d["input"] = graphs.get_input_graph_by_name(to.parent_graph.name_graph)
	#var all = 
	#(train_input_origin)
	graphs.reach(train_input_origin, cachify)
	execute_input_origin = _d["input"]
	if !is_instance_valid(train_input_origin) or !execute_input_origin: return false
	print({		"graph": graphs.get_syntax_tree(execute_input_origin),
			"train_graph": graphs.get_syntax_tree(train_input_origin),})


var training_sockets = {}
func _build_train_payload(train_input: Graph):
	if not check_valid(train_input, true): return false
	var train_input_origin = graphs._reach_input(train_input, "TrainBegin")
	var execute_input_origin = null
	var _d = {}
	var cachify = func(from: Connection, to: Connection, branch_cache: Dictionary):
		if to.parent_graph.server_typename == "RunModel":
			assert(not _d.get("input"), "compile failed, run_model node >1 times banned")
			
			_d["input"] = graphs.get_input_graph_by_name(to.parent_graph.name_graph)
	#var all = 
	#(train_input_origin)
	graphs.reach(train_input_origin, cachify)
	execute_input_origin = _d["input"]
	if !is_instance_valid(train_input_origin) or !execute_input_origin: return false
	if not train_input_origin.dataset_meta: return false
	if not train_input_origin.dataset_meta.get("name", ""): return false
	if not check_valid(execute_input_origin, false): return false
	request_save()
	var tdata = train_input_origin.get_training_data()
	var compressed = ({
		"session": "neriqward",
		"graph": graphs.get_syntax_tree(execute_input_origin),
		"train_graph": graphs.get_syntax_tree(train_input_origin),
		"scene_id": str(glob.get_project_id()),
		"context": str(execute_input_origin.context_id),
	}.merged(tdata))
	return {
		"train_input_origin": train_input_origin,
		"execute_input_origin": execute_input_origin,
		"tdata": tdata,
		"payload": compressed,
	}

func _is_fully_local_dataset(ds_name: String) -> bool:
	return FULLY_LOCAL_TRAINING and ds_name != "" and (FULLY_LOCAL_DATASET_NAMES.has(ds_name) or glob.dataset_datas.has(ds_name))

func _fully_local_dataset_error(ds_name: String) -> String:
	if ds_name == "":
		return "No dataset is selected."
	if FULLY_LOCAL_DATASET_NAMES.has(ds_name):
		return ""
	if glob.dataset_datas.has(ds_name):
		return ""
	return "FullyLocal training can use builtin datasets or datasets created in this project. Dataset '%s' is not available locally." % ds_name

func _ensure_local_runtime_ready() -> bool:
	if local_runtime.is_ready():
		return true
	ui.error("FullyLocal runtime is not ready: " + local_runtime.last_error())
	return false

func _local_runtime_root_abs() -> String:
	var root = await local_runtime.runtime_root_abs()
	return root if root != "" else ProjectSettings.globalize_path("res://local_runtime")

func _local_runtime_entry_abs() -> String:
	return await local_runtime.entry_path(FULLY_LOCAL_RUNTIME_ENTRY)

func _local_export_entry_abs() -> String:
	return await local_runtime.entry_path(FULLY_LOCAL_EXPORT_ENTRY)

func _local_infer_entry_abs() -> String:
	return await local_runtime.entry_path(FULLY_LOCAL_INFER_ENTRY)

func _local_infer_loop_entry_abs() -> String:
	return await local_runtime.entry_path(FULLY_LOCAL_INFER_LOOP_ENTRY)

func _local_checkpoint_root_abs() -> String:
	var root = ProjectSettings.globalize_path("user://fullylocal/checkpoints").path_join(str(glob.get_project_id()))
	DirAccess.make_dir_recursive_absolute(root)
	return root

func _local_context_dir_abs(context_id) -> String:
	return _local_checkpoint_root_abs().path_join(str(context_id))

func _local_inference_model_path(context_id) -> String:
	return _local_context_dir_abs(context_id).path_join("inference.onnx")

func _normalize_abs_path(path: String) -> String:
	return path.replace("\\", "/").rstrip("/")

func _path_is_under(path: String, root: String) -> bool:
	var normalized_path := _normalize_abs_path(path)
	var normalized_root := _normalize_abs_path(root)
	return normalized_path == normalized_root or normalized_path.begins_with(normalized_root + "/")

func _remove_dir_recursive_abs(path: String, allowed_roots: Array = []) -> bool:
	if allowed_roots.is_empty():
		allowed_roots = [_local_checkpoint_root_abs()]
	var allowed := false
	for root in allowed_roots:
		if _path_is_under(path, str(root)):
			allowed = true
			break
	if not allowed:
		push_warning("Refusing to remove local runtime directory outside allowed roots: " + path)
		return false
	if not DirAccess.dir_exists_absolute(path):
		return true
	var dir := DirAccess.open(path)
	if not dir:
		return false
	for file_name in dir.get_files():
		dir.remove(file_name)
	for dir_name in dir.get_directories():
		_remove_dir_recursive_abs(path.path_join(dir_name), allowed_roots)
	var parent := DirAccess.open(path.get_base_dir())
	if parent:
		parent.remove(path.get_file())
	return true

func _delete_local_ctx(context_id: String) -> void:
	_remove_dir_recursive_abs(_local_context_dir_abs(context_id))

func _fully_local_jobs_root_abs() -> String:
	var root = ProjectSettings.globalize_path("user://fullylocal/jobs")
	DirAccess.make_dir_recursive_absolute(root)
	return root

func _fully_local_infer_root_abs() -> String:
	var root = ProjectSettings.globalize_path("user://fullylocal/infer")
	DirAccess.make_dir_recursive_absolute(root)
	return root

func _fully_local_exports_root_abs() -> String:
	var root = ProjectSettings.globalize_path("user://fullylocal/exports")
	DirAccess.make_dir_recursive_absolute(root)
	return root

func _kill_pid(pid: int, reason: String = "") -> void:
	if pid <= 0:
		return
	var err = OS.kill(pid)
	if err != OK and err != ERR_DOES_NOT_EXIST:
		push_warning("Could not kill local runtime process %s (%s): %s" % [str(pid), reason, str(err)])

func _job_timestamp_from_name(name: String) -> float:
	var parts := name.split("_", false)
	if parts.is_empty():
		return 0.0
	return float(parts[0])

func _gc_fully_local_runtime_dirs(startup: bool = false) -> void:
	if not FULLY_LOCAL_TRAINING:
		return
	var infer_root := _fully_local_infer_root_abs()
	var jobs_root := _fully_local_jobs_root_abs()
	if startup:
		_remove_dir_recursive_abs(infer_root, [infer_root])
		DirAccess.make_dir_recursive_absolute(infer_root)
	var now := Time.get_unix_time_from_system()
	var jobs := DirAccess.open(jobs_root)
	if jobs:
		for dir_name in jobs.get_directories():
			var stamp := _job_timestamp_from_name(dir_name)
			if stamp <= 0.0 or now - stamp > FULLY_LOCAL_JOB_GC_TTL_S:
				_remove_dir_recursive_abs(jobs_root.path_join(dir_name), [jobs_root])

func _local_python_path() -> String:
	var bootstrap_python := await local_runtime.python_path()
	if bootstrap_python != "":
		return bootstrap_python
	var candidates := []
	candidates.append(ProjectSettings.globalize_path(FULLY_LOCAL_PYTHON_RES))
	candidates.append(ProjectSettings.globalize_path("res://local_runtime/python/Scripts/python.exe"))
	candidates.append(OS.get_executable_path().get_base_dir().path_join("local_runtime").path_join("python").path_join("python.exe"))
	candidates.append(OS.get_executable_path().get_base_dir().path_join("local_runtime").path_join("python").path_join("Scripts").path_join("python.exe"))
	candidates.append(OS.get_executable_path().get_base_dir().path_join("python").path_join("python.exe"))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return "python"

func _make_local_training_job_dir() -> String:
	var jobs_root = _fully_local_jobs_root_abs()
	var job_id = "%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]
	var job_dir = jobs_root.path_join(job_id)
	DirAccess.make_dir_recursive_absolute(job_dir)
	return job_dir

func _write_json(path: String, data: Dictionary) -> bool:
	return _write_json_atomic(path, data)

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp_path := "%s.tmp.%s.%s" % [path, str(OS.get_process_id()), str(Time.get_ticks_usec())]
	var f = FileAccess.open(tmp_path, FileAccess.WRITE)
	if not f:
		ui.error("Could not write local runtime temp file: " + tmp_path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	for attempt in range(5):
		var rename_err := DirAccess.rename_absolute(tmp_path, path)
		if rename_err == OK:
			return true
		if FileAccess.file_exists(path):
			var remove_err := DirAccess.remove_absolute(path)
			if remove_err != OK and remove_err != ERR_DOES_NOT_EXIST:
				continue
			rename_err = DirAccess.rename_absolute(tmp_path, path)
			if rename_err == OK:
				return true
	push_warning("Could not publish local runtime file after retries: " + path)
	DirAccess.remove_absolute(tmp_path)
	return false

func local_export_extension(platform: String) -> String:
	match platform:
		"windows":
			return ".exe"
		"linux":
			return ""
		"onnx":
			return ".onnx"
		_:
			return ".bin"

func can_export_fully_local(input: Graph) -> bool:
	return FULLY_LOCAL_TRAINING and is_instance_valid(input) and FileAccess.file_exists(_local_inference_model_path(input.context_id))

func _copy_file_abs(from_path: String, to_path: String) -> Dictionary:
	var in_file = FileAccess.open(from_path, FileAccess.READ)
	if not in_file:
		return {"status": "error", "error": "Could not open source file: " + from_path}
	var bytes := in_file.get_buffer(in_file.get_length())
	in_file.close()
	var parent_dir := to_path.get_base_dir()
	if parent_dir != "":
		DirAccess.make_dir_recursive_absolute(parent_dir)
	var out_file = FileAccess.open(to_path, FileAccess.WRITE)
	if not out_file:
		return {"status": "error", "error": "Could not open output file: " + to_path}
	out_file.store_buffer(bytes)
	out_file.close()
	if not FileAccess.file_exists(to_path):
		return {"status": "error", "error": "Export did not create output file: " + to_path}
	var verify = FileAccess.open(to_path, FileAccess.READ)
	var written_size := verify.get_length() if verify else 0
	if verify:
		verify.close()
	if written_size <= 0:
		return {"status": "error", "error": "Export wrote an empty output file: " + to_path}
	return {"status": "ok", "platform": "onnx", "output_path": to_path, "bytes": written_size}

func _run_local_export_process(args: Array) -> Dictionary:
	var python_path: String = args[0]
	var entry_path: String = args[1]
	var request_path: String = args[2]
	var response_path: String = args[3]
	var output := []
	var exit_code := OS.execute(python_path, [entry_path, request_path], output, true, false)
	if exit_code != 0:
		var err_text := ""
		for line in output:
			err_text += str(line) + "\n"
		var parsed_err = JSON.parse_string(FileAccess.get_file_as_string(response_path)) if FileAccess.file_exists(response_path) else null
		if parsed_err is Dictionary:
			return parsed_err
		return {"status": "error", "error": "FullyLocal export failed: " + err_text}
	if not FileAccess.file_exists(response_path):
		return {"status": "error", "error": "FullyLocal export finished without response.json."}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(response_path))
	if parsed is Dictionary:
		return parsed
	return {"status": "error", "error": "FullyLocal export returned invalid response."}

func export_fully_local_model(input: Graph, platform: String, quant: String, output_path: String) -> Dictionary:
	if not FULLY_LOCAL_TRAINING:
		return {"status": "error", "error": "FullyLocal mode is disabled."}
	if not is_instance_valid(input):
		return {"status": "error", "error": "No model input graph selected."}
	if platform == "tensorrt":
		return {"status": "error", "error": "FullyLocal executable export supports onnx, windows, and linux only."}
	var model_path := _local_inference_model_path(input.context_id)
	if not FileAccess.file_exists(model_path):
		return {"status": "error", "error": "No local trained model found for this graph. Train it once before exporting."}
	if quant != "" and quant != "none":
		push_warning("FullyLocal executable export currently ignores quantization mode '" + quant + "' and exports the trained f32 ONNX model.")
	if platform == "onnx":
		return _copy_file_abs(model_path, output_path)
	if not await _ensure_local_runtime_ready():
		return {"status": "error", "error": local_runtime.last_error()}
	var entry_path := await _local_export_entry_abs()
	if not FileAccess.file_exists(entry_path):
		return {"status": "error", "error": "FullyLocal export runtime entry not found: " + entry_path}

	var job_id = "%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]
	var job_dir = _fully_local_exports_root_abs().path_join(job_id)
	DirAccess.make_dir_recursive_absolute(job_dir)
	var request_path := job_dir.path_join("request.json")
	var response_path := job_dir.path_join("response.json")
	var payload := {
		"model_path": model_path,
		"platform": platform,
		"output_path": output_path,
		"context": str(input.context_id),
		"scene_id": str(glob.get_project_id()),
		"graph_name": input.get_title() if input.has_method("get_title") else str(input.name),
	}
	if not _write_json(request_path, payload):
		return {"status": "error", "error": "Could not write FullyLocal export request."}

	var python_path := await _local_python_path()
	var thread := Thread.new()
	var start_err := thread.start(Callable(self, "_run_local_export_process").bind([python_path, entry_path, request_path, response_path]))
	if start_err != OK:
		return {"status": "error", "error": "Could not start FullyLocal export worker thread: " + str(start_err)}
	while thread.is_alive():
		await get_tree().process_frame
	return thread.wait_to_finish()

func _column_dtype_from_name(column_name: Variant) -> String:
	var parts := str(column_name).rsplit(":", true, 1)
	return parts[1] if parts.size() > 1 else "text"

func _cell_to_training_values(cell: Variant, dtype: String) -> Array:
	if not (cell is Dictionary):
		return [float(cell) if str(cell).is_valid_float() else 0.0]
	var c: Dictionary = cell
	var ctype := str(c.get("type", dtype))
	match ctype:
		"num":
			return [float(c.get("num", 0))]
		"float":
			return [float(c.get("val", 0.0))]
		"image":
			var tex = c.get("img", null)
			if tex == null or not (tex is Object) or not tex.has_method("get_image"):
				var x := int(c.get("x", 0))
				var y := int(c.get("y", 0))
				var count = max(0, x * y)
				var zeros: Array = []
				zeros.resize(count)
				zeros.fill(0.0)
				return zeros
			var img: Image = tex.get_image()
			if img == null:
				return []
			if img.get_format() != Image.FORMAT_L8:
				img.convert(Image.FORMAT_L8)
			var data := img.get_data()
			var out: Array = []
			out.resize(data.size())
			for i in data.size():
				out[i] = float(data[i]) / 255.0
			return out
		"text":
			var text := str(c.get("text", ""))
			return [float(text) if text.is_valid_float() else 0.0]
		_:
			if c.has("val"):
				return [float(c.get("val", 0.0))]
			if c.has("num"):
				return [float(c.get("num", 0))]
			return [0.0]

func _local_dataset_to_training_json(ds_name: String) -> Dictionary:
	if not glob.dataset_datas.has(ds_name):
		return {"ok": false, "error": "Dataset is not loaded locally: " + ds_name}
	var ds: Dictionary = glob.dataset_datas[ds_name]
	var rows: Array = ds.get("arr", [])
	if rows.is_empty():
		return {"ok": false, "error": "Dataset is empty: " + ds_name}
	var outputs_from := int(ds.get("outputs_from", 1))
	var col_names: Array = ds.get("col_names", [])
	var col_dtypes: Array = []
	for col_i in range(rows[0].size()):
		col_dtypes.append(_column_dtype_from_name(col_names[col_i]) if col_i < col_names.size() else "")
	var x_rows: Array = []
	var y_rows: Array = []
	for row in rows:
		if not (row is Array) or row.size() <= outputs_from:
			continue
		var x: Array = []
		var y: Array = []
		for col_i in range(row.size()):
			var vals := _cell_to_training_values(row[col_i], str(col_dtypes[col_i]) if col_i < col_dtypes.size() else "")
			if col_i < outputs_from:
				x.append_array(vals)
			else:
				y.append_array(vals)
		x_rows.append(x)
		y_rows.append(y[0] if y.size() == 1 else y)
	if x_rows.is_empty():
		return {"ok": false, "error": "Dataset has no trainable rows: " + ds_name}
	return {
		"ok": true,
		"name": ds_name,
		"x": x_rows,
		"y": y_rows,
		"meta": {
			"col_names": col_names,
			"outputs_from": outputs_from,
			"preview": DsObjRLE.get_preview(ds),
		},
	}

func _start_train_remote(train_input: Graph, prepared: Dictionary, additional_call: Callable, run_but: BlockComponent = null) -> bool:
	if not await glob.splash_login(run_but): return false
	var train_input_origin: Graph = prepared["train_input_origin"]
	var tdata: Dictionary = prepared["tdata"]
	var compressed: Dictionary = prepared["payload"]
	var a = sockets.connect_to("ws/train", train_state_received.bind(additional_call), cookies.get_auth_header())

	training_sockets[train_input] = a
	a.connected.connect(func():
		#if tdata.get("local"):
		#	var data = DsObjRLE.compress_and_send(train_input_origin.dataset_meta["name"]) if tdata.get("local") else {}
		#	a.send()
		#("send...")
		a.send(glob.compress_dict_zstd(compressed))
		#await a.packet
		if tdata["local"]:
			#("A")
			ws_ds_frames(train_input_origin, tdata, a)
		)
		#ws_ds_frames(train_input_origin, compressed, a))
	a.kill.connect(func(...x):
		#("AA")
		train_input_origin.train_stop(true))
	return true

func _start_train_fully_local(train_input: Graph, prepared: Dictionary, additional_call: Callable) -> bool:
	var train_input_origin: Graph = prepared["train_input_origin"]
	var payload: Dictionary = prepared["payload"].duplicate(true)
	var ds_name: String = train_input_origin.dataset_meta.get("name", "")
	if not _is_fully_local_dataset(ds_name):
		ui.error(_fully_local_dataset_error(ds_name))
		return false

	if not await _ensure_local_runtime_ready():
		return false
	var entry_path := await _local_runtime_entry_abs()
	if not FileAccess.file_exists(entry_path):
		ui.error("FullyLocal runtime entry not found: " + entry_path)
		return false

	var job_dir := _make_local_training_job_dir()
	if FULLY_LOCAL_DATASET_NAMES.has(ds_name):
		payload["dataset_ref"] = {"kind": "builtin_numpy", "name": ds_name}
	else:
		var dataset_payload := _local_dataset_to_training_json(ds_name)
		if not dataset_payload.get("ok", false):
			ui.error(str(dataset_payload.get("error", "Could not prepare local dataset.")))
			return false
		var dataset_path := job_dir.path_join("dataset.json")
		dataset_payload.erase("ok")
		if not _write_json(dataset_path, dataset_payload):
			ui.error("Could not write local dataset training payload.")
			return false
		payload["dataset_ref"] = {"kind": "godot_json", "name": ds_name, "path": dataset_path}
	payload["runtime_root"] = await _local_runtime_root_abs()
	payload["job_dir"] = job_dir
	payload["checkpoint_dir"] = _local_context_dir_abs(prepared["execute_input_origin"].context_id)
	payload["local_mode"] = "fullylocal_ort"
	payload["parent_pid"] = OS.get_process_id()
	payload.erase("local")

	if not _write_json(job_dir.path_join("request.json"), payload):
		return false

	var python_path := await _local_python_path()
	var pid := OS.create_process(python_path, [entry_path, job_dir])
	if pid == -1:
		ui.error("Could not start FullyLocal Python runtime. Tried executable: " + python_path)
		return false

	local_training_jobs[train_input] = {
		"pid": pid,
		"dir": job_dir,
		"progress_path": job_dir.path_join("progress.jsonl"),
		"stop_path": job_dir.path_join("stop"),
		"line_count": 0,
		"additional": additional_call,
		"train_input_origin": train_input_origin,
		"training_head": train_input,
	}
	return true


func start_train(train_input: Graph, additional_call: Callable = glob.def, run_but: BlockComponent = null) -> bool:
	try_print(train_input)
	var prepared = _build_train_payload(train_input)
	if !(prepared is Dictionary):
		return false
	var train_input_origin: Graph = prepared["train_input_origin"]
	var ds_name: String = train_input_origin.dataset_meta.get("name", "")
	if FULLY_LOCAL_TRAINING:
		await close_infer_channel(graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME))

		return await _start_train_fully_local(train_input, prepared, additional_call)
	return await _start_train_remote(train_input, prepared, additional_call, run_but)

func stop_train(train_input: Graph, force_process: bool = false):
	if train_input in local_training_jobs:
		var job: Dictionary = local_training_jobs[train_input]
		_stop_local_training_job(job, force_process)
		return
	if not train_input in training_sockets:
		#web.POST("end_train", {})
		return
	training_sockets[train_input].send(glob.compress_dict_zstd({"stop": "true"}))
	training_sockets.erase(train_input)

func _stop_local_training_job(job: Dictionary, force_process: bool = false) -> void:
	var stop_path: String = job.get("stop_path", "")
	if stop_path != "":
		var f = FileAccess.open(stop_path, FileAccess.WRITE)
		if f:
			f.store_string("stop")
			f.close()
	if force_process:
		_kill_pid(int(job.get("pid", -1)), "force stop local training")

func _finalize_local_training_job(job: Dictionary) -> void:
	var job_dir: String = job.get("dir", "")
	if job_dir != "":
		_remove_dir_recursive_abs(job_dir, [_fully_local_jobs_root_abs()])



var inference_sockets := {}

func _infer_result_to_outputs(_dict: Dictionary, ws = null) -> Dictionary:
	var outs = {}
	if "ack" in _dict:
		if ws:
			#("ACK")
			ws.ack.emit()
	if "result" in _dict and _dict["result"] is Dictionary:
		for i in _dict["result"]:
			var node: Graph = graphs._graphs.get(int(i))
			if not node: continue
			for to_push in _dict["result"][i].values():
				if node.is_head:
					var flattened = glob.flatten_array(to_push)
					node.push_values(flattened, node.per)
					outs[node.get_title()] = flattened
	return outs

func _infer_state_received(bytes: PackedByteArray, ws: SocketConnection):
	var _dict = JSON.parse_string(bytes.get_string_from_utf8())
	if _dict and _dict is Dictionary:
		return _infer_result_to_outputs(_dict, ws)
	return {}
	#(_dict)


func infer_channels():
	return inference_sockets

func is_infer_channel(input: Graph) -> bool:
	if not input in inference_sockets:
		return false
	var sock = inference_sockets[input]
	return sock is LocalInferChannel or is_instance_valid(sock)

func check_valid(input: Graph, train: bool = false):
	if train:
		input = graphs._reach_input(input, "TrainBegin")
	var simple = graphs.simple_reach(input, true)
	var has_necc: bool = false; var in_nodes = {}
	if train: in_nodes = {"RunModel": 1, "OutputMap": 1, "ModelName": 1, "DatasetName": 1}
	else: in_nodes = {"ClassifierNode": 1}
	#(in_nodes)
	#(input.server_typename)
	for i in simple:
		if graphs.in_nodes(i, in_nodes): has_necc = true
		if not i.is_valid():
			return false
	return has_necc

func validate_infer_channel(input: Graph):
	#if input in inference_sockets and is_instance_valid(inference_sockets[input]):
	#	return false# already open
	if not check_valid(input): 
	#	print("fals")
		return false
	if FULLY_LOCAL_TRAINING:
		return FileAccess.file_exists(_local_inference_model_path(input.context_id))
	if not glob._logged_in:
		return false
	return true

func _find_local_output_node_id(graph: Dictionary) -> String:
	var pages: Dictionary = graph.get("pages", {})
	if pages.is_empty():
		return "0"
	var page_keys := pages.keys()
	page_keys.sort_custom(func(a, b): return int(a) < int(b) if str(a).is_valid_int() and str(b).is_valid_int() else str(a) < str(b))
	var ignored := {"TrainInput": true, "TrainBegin": true, "RunModel": true, "DatasetName": true, "ModelName": true}
	for pk_i in range(page_keys.size() - 1, -1, -1):
		var page: Dictionary = pages[page_keys[pk_i]]
		var node_keys := page.keys()
		for nk_i in range(node_keys.size() - 1, -1, -1):
			var nid = node_keys[nk_i]
			if not ignored.has(str(page[nid].get("type", ""))):
				return str(nid)
	return str(pages[page_keys[-1]].keys()[0])

func _open_infer_channel_fully_local(input: Graph, on_close: Callable = glob.def):
	var model_path := _local_inference_model_path(input.context_id)
	_infer_log("open requested", {
		"input": _infer_input_tag(input),
		"model_path": model_path,
	})
	if not FileAccess.file_exists(model_path):
		_infer_log("open failed: missing model", {"input": _infer_input_tag(input), "model_path": model_path})
		ui.error("No local trained model found for this graph. Train it once before running local inference.")
		return false
	var graph := graphs.get_syntax_tree(input)
	if not await _ensure_local_runtime_ready():
		return false
	var entry_path := await _local_infer_loop_entry_abs()
	if not FileAccess.file_exists(entry_path):
		_infer_log("open failed: missing loop entry", {"entry_path": entry_path})
		ui.error("FullyLocal inference runtime entry not found: " + entry_path)
		return false
	var channel := LocalInferChannel.new()
	channel.model_path = model_path
	channel.graph = graph
	channel.context_id = str(input.context_id)
	channel.output_node_id = _find_local_output_node_id(graph)
	channel.on_close = on_close
	channel.job_dir = _make_local_infer_job_dir(input.context_id)
	channel.control_path = channel.job_dir.path_join("control.json")
	channel.request_path = channel.job_dir.path_join("request.json")
	channel.response_path = channel.job_dir.path_join("response.json")
	channel.stop_path = channel.job_dir.path_join("stop")
	_infer_log("channel prepared", {
		"input": _infer_input_tag(input),
		"job_dir": channel.job_dir,
		"output_node_id": channel.output_node_id,
		"request_path": channel.request_path,
		"response_path": channel.response_path,
	})
	if FileAccess.file_exists(channel.stop_path):
		DirAccess.remove_absolute(channel.stop_path)
	if not _write_json(channel.control_path, {
		"model_path": channel.model_path,
		"graph": channel.graph,
		"context": channel.context_id,
		"output_node_id": channel.output_node_id,
		"parent_pid": OS.get_process_id(),
		"idle_timeout_s": FULLY_LOCAL_INFER_IDLE_TIMEOUT_S,
	}):
		_infer_log("open failed: could not write control", {"control_path": channel.control_path})
		return false
	var python_path := await _local_python_path()
	channel.pid = OS.create_process(python_path, [entry_path, channel.job_dir])
	if channel.pid == -1:
		_infer_log("open failed: process launch failed", {"python": python_path, "entry": entry_path})
		ui.error("Could not start FullyLocal inference process.")
		return false
	input.set_state_open()
	inference_sockets[input] = channel
	_infer_log("channel opened", {
		"input": _infer_input_tag(input),
		"pid": channel.pid,
		"python": python_path,
	})
	return channel

func open_infer_channel(input: Graph, on_close: Callable = glob.def, run_but: BlockComponent = null):

	if input in inference_sockets and is_instance_valid(inference_sockets[input]):
		_infer_log("open ignored: channel already exists", {
			"input": _infer_input_tag(input),
			"channel": _infer_channel_state_dict(inference_sockets[input]),
			"leases": _infer_channel_lease_summary(input),
		})
		return false# already open
	if not check_valid(input): 
	#	print("fals")
		_infer_log("open failed: graph invalid", {"input": _infer_input_tag(input)})
		return false
	if FULLY_LOCAL_TRAINING:
		return await _open_infer_channel_fully_local(input, on_close)
	if not await glob.splash_login(run_but):
		return false
	request_save()
	var init_payload = {
		"session": "neriqward",
		"graph": graphs.get_syntax_tree(input),
		"scene_id": str(glob.get_project_id()),
		"context": str(input.context_id),
	}
	input.set_state_open()
	var sock = sockets.connect_to("ws/infer", Callable(),
	 cookies.get_auth_header())
	sock.packet.connect((func(bytes: PackedByteArray):
		var outs = _infer_state_received(bytes, sock)
		infer_clear(input, outs)
		))
	inference_sockets[input] = sock
	sock.connected.connect(func() -> void:
		sock.send(glob.compress_dict_zstd(init_payload))
	)
	sock.kill.connect(func(...x) -> void:
		if input in inference_sockets:
			if inference_sockets[input] == sock:
				inference_sockets.erase(input)
		if input in inference_channel_leases:
			inference_channel_leases.erase(input)
		if on_close.is_valid():
			on_close.call()
	)
	#await sock.connected
	return sock

var inference_polling: Dictionary = {}

func infer_clear(who, outputs: Dictionary):
	_infer_log("outputs applied", {
		"input": _infer_input_tag(who) if who is Graph else str(who),
		"output_keys": outputs.keys(),
	})
	inference_polling[who] = outputs

func _make_local_infer_job_dir(context_id) -> String:
	var root = _fully_local_infer_root_abs().path_join(str(context_id))
	DirAccess.make_dir_recursive_absolute(root)
	var job_id = "%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]
	var job_dir = root.path_join(job_id)
	DirAccess.make_dir_recursive_absolute(job_dir)
	return job_dir

func _queue_local_inference_data(input: Graph, channel: LocalInferChannel, data: Dictionary, await_response: bool = false) -> bool:
	if "full_graph" in data:
		if not check_valid(input):
			_infer_log("queue rejected: graph invalid during full_graph update", {"input": _infer_input_tag(input)})
			return false
		channel.graph = data["full_graph"]
		channel.output_node_id = _find_local_output_node_id(channel.graph)
		_infer_log("full graph queued", {
			"input": _infer_input_tag(input),
			"output_node_id": channel.output_node_id,
		})
	if channel.request_in_flight and not await_response:
		channel.pending_data = data.duplicate(true)
		inference_sockets[input] = channel
		_infer_log("request coalesced", {
			"input": _infer_input_tag(input),
			"in_flight_seq": channel.index,
			"has_full_graph": data.has("full_graph"),
			"raw_len": data.get("raw_values", []).size() if data.has("raw_values") and data["raw_values"] is Array else -1,
		})
		return true
	if input in inference_polling:
		inference_polling.erase(input)
	inference_polling[input] = true
	channel.index += 1
	channel.last_request_msec = Time.get_ticks_msec()
	channel.no_response_logged = false
	channel.request_in_flight = true
	var request := {
		"seq": channel.index,
		"graph": channel.graph,
		"data": data,
		"context": channel.context_id,
		"output_node_id": channel.output_node_id,
		"index": channel.index,
	}
	_infer_log("request queued", {
		"input": _infer_input_tag(input),
		"seq": channel.index,
		"has_full_graph": data.has("full_graph"),
		"raw_len": data.get("raw_values", []).size() if data.has("raw_values") and data["raw_values"] is Array else -1,
		"request_path": channel.request_path,
	})
	if not _write_json(channel.request_path, request):
		_infer_log("request write failed", {"input": _infer_input_tag(input), "request_path": channel.request_path})
		channel.request_in_flight = false
		inference_sockets[input] = channel
		inference_polling.erase(input)
		return false
	inference_sockets[input] = channel
	return true

func _poll_local_inference_channels() -> void:
	for input in inference_sockets.keys():
		var channel = inference_sockets[input]
		if !(channel is LocalInferChannel):
			continue
		if not is_instance_valid(input):
			_close_local_infer_channel(input, channel, true, false)
			continue
		if channel.closed:
			continue
		if channel.response_path == "" or not FileAccess.file_exists(channel.response_path):
			if channel.last_request_msec > 0 and not channel.no_response_logged and Time.get_ticks_msec() - channel.last_request_msec > 1000:
				channel.no_response_logged = true
				inference_sockets[input] = channel
				_infer_log("waiting for response file", {
					"input": _infer_input_tag(input),
					"seq": channel.index,
					"response_path": channel.response_path,
				})
			continue
		var f := FileAccess.open(channel.response_path, FileAccess.READ)
		if not f:
			_infer_log("response open failed", {"input": _infer_input_tag(input), "response_path": channel.response_path})
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if !(parsed is Dictionary):
			channel.parse_fail_count += 1
			inference_sockets[input] = channel
			if channel.parse_fail_count <= 5 or channel.parse_fail_count % 30 == 0:
				_infer_log("response parse failed", {
					"input": _infer_input_tag(input),
					"count": channel.parse_fail_count,
					"response_path": channel.response_path,
				})
			continue
		channel.parse_fail_count = 0
		var response_index := int(parsed.get("index", -1))
		if response_index <= channel.last_response_index:
			continue
		channel.last_response_index = response_index
		inference_sockets[input] = channel
		_infer_log("response received", {
			"input": _infer_input_tag(input),
			"phase": parsed.get("phase", ""),
			"index": response_index,
			"last_request_seq": channel.index,
			"ok": parsed.get("ok", null),
		})
		if parsed.get("phase", "") == "ready":
			continue
		channel.request_in_flight = false
		var pending_data = channel.pending_data
		channel.pending_data = null
		inference_sockets[input] = channel
		var outs := {}
		if parsed.get("phase", "") == "inference":
			outs = _infer_result_to_outputs(parsed)
		elif parsed.get("phase", "") == "error":
			push_warning("Local inference failed: " + str(parsed.get("error", {})))
		elif parsed.get("phase", "") == "closed":
			if input in inference_polling:
				inference_polling.erase(input)
			inference_sockets.erase(input)
			_remove_dir_recursive_abs(channel.job_dir, [_fully_local_infer_root_abs()])
			if channel.on_close.is_valid():
				channel.on_close.call()
			continue
		infer_clear(input, outs)
		if pending_data is Dictionary and input in inference_sockets:
			_infer_log("flushing coalesced request", {
				"input": _infer_input_tag(input),
				"after_response_index": response_index,
			})
			_queue_local_inference_data(input, inference_sockets[input], pending_data, false)

func send_inference_data(input: Graph, data: Dictionary, output: bool = false):
	# make sure channel is open
	if not (input in inference_sockets):
		push_warning("No inference channel open for this graph")
		_infer_log("send rejected: no channel", {"input": _infer_input_tag(input), "output": output})
		return
	#(data)
	if "full_graph" in data:
		if not check_valid(input):
			_infer_log("send rejected: invalid graph", {"input": _infer_input_tag(input)})
			
			return false
	var sock = inference_sockets[input]
	if sock is LocalInferChannel:
		_infer_log("send local", {
			"input": _infer_input_tag(input),
			"output": output,
			"has_full_graph": data.has("full_graph"),
			"channel": _infer_channel_state_dict(sock),
			"leases": _infer_channel_lease_summary(input),
		})
		if not _queue_local_inference_data(input, sock, data, output):
			return false
		if output:
			while input in inference_polling and inference_polling[input] is bool:
				await get_tree().process_frame
			if not input in inference_polling:
				return
			var local_out = inference_polling[input]
			inference_polling.erase(input)
			return local_out
		return true
	if not is_instance_valid(sock):
		push_warning("Socket instance is no longer valid")
		inference_sockets.erase(input)
		return
	if input in inference_polling: 
		inference_polling.erase(input)
	inference_polling[input] = true
	var do_update: bool = false
	var syntax = null

	var payload = {"data": data}
	var compressed = glob.compress_dict_zstd(payload)
	sock.send(compressed)
	if output:
		while input in inference_polling and inference_polling[input] is bool:
			await get_tree().process_frame
		if not input in inference_polling:
			return
		var out = inference_polling[input]
		inference_polling.erase(input)
		return out
	inference_polling.erase(input)
	return
	#(data)

func _poll_local_training_jobs() -> void:
	for train_input in local_training_jobs.keys():
		var job: Dictionary = local_training_jobs.get(train_input, {})
		if not is_instance_valid(train_input):
			_stop_local_training_job(job, true)
			local_training_jobs.erase(train_input)
			continue
		var progress_path: String = job.get("progress_path", "")
		if progress_path == "" or not FileAccess.file_exists(progress_path):
			continue
		var f = FileAccess.open(progress_path, FileAccess.READ)
		if not f:
			continue
		var text := f.get_as_text()
		#(text)
		f.close()
		var lines := text.split("\n", false)
		
		var complete_count := lines.size()
		if complete_count > 0 and not text.ends_with("\n"):
			complete_count -= 1
		var start_line := int(job.get("line_count", 0))
		var should_erase := false
		for i in range(start_line, complete_count):
			var line := String(lines[i]).strip_edges()
			if line == "":
				continue
			var packet = JSON.parse_string(line)
			if packet is Dictionary:
				_handle_train_state_dict(packet, job.get("additional", glob.def), job.get("training_head", null))
				if packet.get("phase", "") in ["done", "stopped", "error"]:
					should_erase = true
		job["line_count"] = complete_count
		local_training_jobs[train_input] = job
		if should_erase:
			_finalize_local_training_job(job)
			local_training_jobs.erase(train_input)

func _process(delta: float) -> void:
	_runtime_gc_accum += delta
	if _runtime_gc_accum > 10.0:
		_runtime_gc_accum = 0.0
		_gc_fully_local_runtime_dirs(false)
	_poll_local_training_jobs()
	_poll_local_inference_channels()
	#if glob.space_just_pressed:
	#	pass
	#	upl_dataset(null)

func upl_dataset(from: Graph):
	for graph in graphs._graphs.values():
		if graph.server_typename == "TrainBegin":
			
			var tdata = graph.get_training_data()
			var a = await sockets.connect_to("ws/ds_load", func(a): null, cookies.get_auth_header())

			ws_ds_frames(graph, tdata, a)

func close_all(force_processes: bool = false):
	if _shutdown_cleanup_started and force_processes:
		return
	if force_processes:
		_shutdown_cleanup_started = true
	_infer_log("close_all requested", {
		"inference_channels": inference_sockets.size(),
		"local_training_jobs": local_training_jobs.size(),
		"training_sockets": training_sockets.size(),
		"force_processes": force_processes,
	})
	for i in inference_sockets.keys():
		var sock = inference_sockets.get(i)
		if sock is LocalInferChannel:
			_close_local_infer_channel(i, sock, force_processes, is_instance_valid(i))
		elif is_instance_valid(i):
			close_infer_channel(i, force_processes)
	for i in local_training_jobs.keys():
		stop_train(i, force_processes)
		if force_processes:
			var job: Dictionary = local_training_jobs.get(i, {})
			_finalize_local_training_job(job)
	for i in training_sockets.keys():
		if not is_instance_valid(i):
			continue
		stop_train(i, force_processes)
	local_training_jobs.clear()
	training_sockets.clear()
	inference_sockets.clear()
	inference_channel_leases.clear()

func _close_local_infer_channel(input, sock: LocalInferChannel, force_process: bool = false, call_on_close: bool = true) -> void:
	_infer_log("close local requested", {
		"input": _infer_input_tag(input) if is_instance_valid(input) else str(input),
		"seq": sock.index,
		"pid": sock.pid,
		"job_dir": sock.job_dir,
		"stop_path": sock.stop_path,
		"force_process": force_process,
	})
	sock.closed = true
	sock.request_in_flight = false
	sock.pending_data = null
	if sock.stop_path != "":
		var f = FileAccess.open(sock.stop_path, FileAccess.WRITE)
		if f:
			f.store_string("stop")
			f.close()
			_infer_log("stop file written", {"input": _infer_input_tag(input) if is_instance_valid(input) else str(input), "stop_path": sock.stop_path})
		else:
			_infer_log("stop file write failed", {"input": _infer_input_tag(input) if is_instance_valid(input) else str(input), "stop_path": sock.stop_path})
	if force_process:
		_kill_pid(sock.pid, "force close local inference")
	if input in inference_sockets:
		inference_sockets.erase(input)
	if input in inference_polling:
		inference_polling.erase(input)
	if input in inference_channel_leases:
		_infer_log("leases cleared by channel close", {
			"input": _infer_input_tag(input) if is_instance_valid(input) else str(input),
			"leases": _infer_channel_lease_summary(input),
		})
		inference_channel_leases.erase(input)
	if force_process and sock.job_dir != "":
		_remove_dir_recursive_abs(sock.job_dir, [_fully_local_infer_root_abs()])
	if call_on_close and sock.on_close.is_valid():
		_infer_log("calling local on_close", {"input": _infer_input_tag(input) if is_instance_valid(input) else str(input)})
		sock.on_close.call()

func close_infer_channel(input: Graph, force_process: bool = false) -> void:
	if not (input in inference_sockets):
		_infer_log("close ignored: no channel", {"input": _infer_input_tag(input) if is_instance_valid(input) else str(input)})
		return
	var sock = inference_sockets[input]
	if sock is LocalInferChannel:
		_close_local_infer_channel(input, sock, force_process, true)
		return
	_infer_log("close remote requested", {"input": _infer_input_tag(input)})
	if input in inference_channel_leases:
		_infer_log("leases cleared by remote close", {
			"input": _infer_input_tag(input),
			"leases": _infer_channel_lease_summary(input),
		})
		inference_channel_leases.erase(input)
	sock.send(glob.compress_dict_zstd({"stop": "true"}))
