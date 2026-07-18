class_name SyntaxParityRunner
extends SceneTree

const YAML_COMP := preload("res://compiler/yaml_comp.gd")

var input_path := ""
var report_path := ""
var fail_fast := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_args()
	if input_path.is_empty():
		push_error("Missing --input=<generated parity directory>")
		quit(2)
		return
	if report_path.is_empty():
		report_path = input_path.path_join("godot_compile_report.json")

	var cases := _discover_cases(input_path)
	var failures: Array[Dictionary] = []
	var passed := 0

	for test_case in cases:
		var case_id: String = test_case["id"]
		var case_path: String = test_case["path"]
		print("PARITY CASE START ", case_id)
		var compiled = YAML_COMP.compile_bundle(case_path, false)
		if typeof(compiled) == TYPE_DICTIONARY and not compiled.is_empty():
			passed += 1
			print("PARITY PASS ", case_id)
		else:
			failures.append({
				"id": case_id,
				"path": case_path,
				"error": "YAMLComp.compile_bundle returned an empty result; inspect godot-engine.log for the full trace.",
			})
			print("PARITY FAIL ", case_id)
			if fail_fast:
				break

	SyntaxParityRegistry.cleanup()
	var report := {
		"ok": not cases.is_empty() and failures.is_empty(),
		"total": cases.size(),
		"passed": passed,
		"failed": failures,
	}
	_write_report(report_path, report)
	print("Syntax parity: %d/%d cases passed" % [passed, cases.size()])
	print("Report: ", report_path)
	quit(0 if report["ok"] else 1)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):
			input_path = arg.trim_prefix("--input=")
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
		elif arg == "--fail-fast":
			fail_fast = true


func _discover_cases(root: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(root)
	if directory == null:
		push_error("Cannot open generated parity directory: %s" % root)
		return result

	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name.begins_with(".") or not directory.current_is_dir():
			continue
		var candidate := root.path_join(name)
		if FileAccess.file_exists(candidate.path_join("bundle.yaml")):
			result.append({ "id": name, "path": candidate })
	directory.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a["id"] < b["id"])

	if result.is_empty():
		push_error("No generated parity bundles found under: %s" % root)
	return result


func _write_report(path: String, report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write syntax-parity report: %s" % path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
