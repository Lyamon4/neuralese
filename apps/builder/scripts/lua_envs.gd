
extends Node

var processes: Dictionary = {}

func _log(message: String, data: Dictionary = {}) -> void:
	var suffix := ""
	if not data.is_empty():
		suffix = " " + JSON.stringify(data)
	print("[LuaEnv] " + message + suffix)


func _ready() -> void:
	pass

func create_process(name: String, code: String) -> LuaProcess:
	if processes.has(name):
		var existing: LuaProcess = processes[name]
		_log("create replacing existing process", {
			"name": name,
			"id": existing.get_instance_id(),
			"stopping": existing.stopping,
			"stopped": existing.stopped,
			"inside_tree": existing.is_inside_tree(),
			"queued_for_deletion": existing.is_queued_for_deletion(),
		})
	remove_process(name)
	var proc = LuaProcess.new(name, code)
	processes[name] = proc
	_log("created process", {
		"name": name,
		"id": proc.get_instance_id(),
		"code_len": code.length(),
	})
	proc.error_splashed.connect(func(): processes.erase(name))
	proc.execution_finished.connect(func(): processes.erase(name))
	return proc

func remove_process(name: String) -> void:
	if processes.has(name):
		var proc: LuaProcess = processes[name]
		_log("removing process", {
			"name": name,
			"id": proc.get_instance_id(),
			"stopping": proc.stopping,
			"stopped": proc.stopped,
			"inside_tree": proc.is_inside_tree(),
			"queued_for_deletion": proc.is_queued_for_deletion(),
		})
		proc.stop()
		processes.erase(name)

var _accum_time: float = 0.0
func _process(delta: float) -> void:
	_accum_time += delta
	var frame_step: float = 1 / 30.0
	while _accum_time >= frame_step:
		for p in processes.values():
			p.update(frame_step)
			p.queue_redraw()
		_accum_time -= frame_step
