extends Node

var lesson: LessonCode



func cache():
	lesson_cache = glob.get_var("lesson_cache", {}, "classroom.bin")
	for i in lesson_cache.keys():
		if _is_classroom_payload_wrapper(lesson_cache[i]):
			lesson_cache[i] = lesson_cache[i].classroom_data
		if not i:
			lesson_cache.erase(i)
	glob.set_var("lesson_cache", lesson_cache, "classroom.bin")

func ack_explain_next():
	if lesson:
		lesson.ack_explain_next()

func _enter_tree() -> void:
	
	cache()
	#(lesson_cache)

func active() -> bool: 
	return lesson_list().keys().find(current_lesson_key) != -1

func try_load_cached():
	var got = glob.get_var("lesson_cache", {}, "classroom.bin")
	lesson_cache = got

func dbg_load_lesson(path:String):
	var compiled = YAMLComp.new().compile_bundle(path, false)
	#(compiled)
	if compiled:
		load_classroom_data(compiled)

func _ready() -> void:
	#(dsl_reg)
	
	lesson_re_reg()

func lesson_re_reg():
	if lesson:
		lesson.queue_free()
		lesson = null
	await get_tree().process_frame
	lesson = LessonCode.new()
	add_child(lesson)

	lesson.step_started.connect(_on_step_started)
	lesson.step_completed.connect(_on_step_completed)
	lesson.invariant_broken.connect(_on_invariant_broken)
	graphs.node_added.connect(lesson.on_node_created)
	
	LessonRouter.register_lesson(lesson)


func stop_lesson():
	graphs.allow_deletion_all()
	if lesson:
		ui.quest.reset()
		ui.recreate_quest()
		current_lesson_key = null
		lesson.stop()
		ui.lesson_bar.dissapear()
		await get_tree().process_frame
		lesson_re_reg()
	graphs.set_fork_allow(false)

func _auth_headers() -> Dictionary:
	return cookies.get_bearer_auth_header()

func _account_id() -> String:
	return str(cookies.get_neuralese_profile().get("account_id", cookies.user()))

func join_classroom(id: String) -> Dictionary:
	var resp = await web.JPOST("classroom/join", {
		"classroom_id": id}, _auth_headers())
	if resp and resp.get("ok", false):
		cookies.set_profile("my_classroom", id)

		load_classroom_data(resp.data)
	return resp


func cache_classroom_data():
	if not cookies.profile("my_classroom"):
		return {}
	var resp = await web.JPOST("classroom/meta", {
		"classroom_id": cookies.profile("my_classroom")}, _auth_headers())
	#(resp.data)
	if resp and resp.get("ok", false):
		load_classroom_data(resp.data)
	return resp


func leave_classroom() -> bool:
	if cookies.profile("my_classroom"):
		var resp = await web.JPOST("classroom/leave", {
			"classroom_id": cookies.profile("my_classroom")}, _auth_headers())
	cookies.set_profile("my_classroom", "")
	return true



func is_lesson_open(who):
	if is_offline_lesson_key(who):
		return true
	var order = classroom_data.get("lesson_order", [])
	var idx = order.find(who)
	if idx == -1:
		return false
	return classroom_data.get("lesson_customs", {}).get(idx, {}).get("opened", false)

func create_classroom(name: String = "Untitled") -> String:
	var resp = await web.JPOST("classroom/create", {
		"meta": {"name": name}}, _auth_headers())
	print(resp)
	if not resp: return ""
	classroom_data = {}
	if resp and "classroom_id" in resp:
		cookies.set_profile("my_classroom", resp["classroom_id"])
		load_classroom_data(resp.data)
	#(classroom_data)
	return resp.get("classroom_id", "")


func classroom_stream():
	if not cookies.user(): return
	var h = web.GET_SSE(
		"classroom/events",
		{"classroom_id": cookies.profile("my_classroom")},
		_auth_headers()
	)
	
	return h

class EndSignal:
	signal end_signal

func wait_unblock():
	print("WAITING")
	if glob.DEBUG_RELOAD_LESSONS:
		print("TRU!!!!")
		return true
	if cookies.profile("teacher"):
		var f = func(): return glob.space_just_pressed
		while not f.call():
			await glob.tree.process_frame
	var h = classroom_stream()
	var end = EndSignal.new()
	var x = func(evt):
		#(JSON.stringify(evt, "\t"))
		if evt.get("event", "") != "snapshot": return
		evt = JSON.parse_string(evt.data)
		print(evt)
		if not evt.students.get(_account_id(), {}).get("awaiting", false):
			end.end_signal.emit()
		#if evt["end"]: end.end_signal.emit()
	h.on_sse.connect(x)
	await end.end_signal
	h.cancel()
	return true


func _process(delta: float) -> void:
	pass


var lesson_cache = {}
var classroom_data = {}
const OFFLINE_TUTORIALS_DIR := "res://offline_tutorials"
const OFFLINE_KEY_PREFIX := "offline:"
var offline_tutorials := {
	"name": "Offline tutorials",
	"lesson_order": [],
	"lessons": {},
}

func _offline_key(bundle_name: String, lesson_key: String) -> String:
	return "%s%s/%s" % [OFFLINE_KEY_PREFIX, bundle_name, lesson_key]

func is_offline_lesson_key(lesson_key) -> bool:
	return str(lesson_key).begins_with(OFFLINE_KEY_PREFIX)

func _safe_resource_id(path: String) -> String:
	var out = path.replace("res://", "").replace("\\", "/").replace("/", "_").replace(".", "_")
	return out.strip_edges()

func _compile_offline_bundle(path: String, zip: bool = false) -> Dictionary:
	var compiled = YAMLComp.new().compile_bundle(path, zip)
	if not compiled:
		push_warning("Offline tutorial failed to compile: %s" % path)
	return compiled
var _offline_tutorials_scanned := false
func _scan_offline_tutorials(force: bool = false) -> void:
	#print(offline_tutorials.lessons.keys())
	if _offline_tutorials_scanned and not force:
		return

	var merged := {
		"name": "Offline tutorials",
		"lesson_order": [],
		"lessons": {},
	}

	var root := DirAccess.open(OFFLINE_TUTORIALS_DIR)
	if root == null:
		offline_tutorials = merged
		_offline_tutorials_scanned = true
		return

	var bundle_sources: Array[Dictionary] = []

	if root.file_exists("bundle.yaml"):
		bundle_sources.append({"path": OFFLINE_TUTORIALS_DIR, "zip": false})

	root.list_dir_begin()
	while true:
		var entry := root.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue

		if root.current_is_dir():
			var bundle_path := OFFLINE_TUTORIALS_DIR.path_join(entry)
			var bundle_dir := DirAccess.open(bundle_path)
			if bundle_dir != null and bundle_dir.file_exists("bundle.yaml"):
				bundle_sources.append({"path": bundle_path, "zip": false})
		else:
			var lower := entry.to_lower()
			if lower.ends_with(".zip") or lower.ends_with(".nls"):
				bundle_sources.append({"path": OFFLINE_TUTORIALS_DIR.path_join(entry), "zip": true})

	root.list_dir_end()

	bundle_sources.sort_custom(func(a, b): return str(a.path) < str(b.path))

	for source in bundle_sources:
		var bundle_path := str(source.path)
		var compiled = _compile_offline_bundle(bundle_path, bool(source.zip))
		if not compiled:
			continue

		var bundle_id := _safe_resource_id(bundle_path)
		var bundle_name := str(compiled.get("name", bundle_id))

		for lesson_key in compiled.get("lesson_order", []):
			var source_key := str(lesson_key)
			var source_lesson = compiled.get("lessons", {}).get(source_key, {})
			if not source_lesson:
				continue

			var key := _offline_key(bundle_id, source_key)
			var lesson_copy: Dictionary = source_lesson.duplicate(true)
			lesson_copy["offline"] = true
			lesson_copy["bundle_name"] = bundle_name
			lesson_copy["source_key"] = source_key

			merged.lesson_order.append(key)
			merged.lessons[key] = lesson_copy

	offline_tutorials = merged
	_offline_tutorials_scanned = true

func _classroom_lesson_list_from(profile: Dictionary) -> Dictionary:
	var output = {}
	if profile and profile.get("lesson_order"):
		for i in profile.lesson_order:
			output[i] = {"name": profile.lessons[i].lesson_title}
	return output

func classroom_lesson_list() -> Dictionary:
	return _classroom_lesson_list_from(lesson_cache.get(cookies.profile("my_classroom"), {}))

func lesson_list(include_offline: bool = true):
	_scan_offline_tutorials()
	var profile = lesson_cache.get(cookies.profile("my_classroom"), {})
	var output = {}

	if include_offline:
		for i in offline_tutorials.get("lesson_order", []):
			var lesson_data = offline_tutorials.lessons.get(i, {})
			var title = str(lesson_data.get("lesson_title", i))
			var bundle_name = str(lesson_data.get("bundle_name", "Offline tutorials"))
			output[i] = {
				"name": title,
				"offline": true,
				"bundle_name": bundle_name,
			}

	output.merge(_classroom_lesson_list_from(profile), true)
	return output


	#cookies.open_or_create("class.json", "C:/Users/Mike/Downloads/").store_string(JSON.stringify(lesson_cache["535706"], "\t"))


func _is_classroom_payload_wrapper(data: Dictionary) -> bool:
	return data.has("classroom_data") \
		and not data.has("lesson_customs") \
		and not data.has("lesson_order") \
		and not data.has("lessons") \
		and not data.has("teacher") \
		and not data.has("teacher_account_id")

func load_classroom_data(data: Dictionary):
	if _is_classroom_payload_wrapper(data):
		data = data.classroom_data
	#	print(data)
	var customs = {}
	for i in data.get("lesson_customs", {}):
		customs[int(i)] = data["lesson_customs"][i]
	data["lesson_customs"] = customs
	
	#	print_stack()
	classroom_data = data
	lesson_cache[cookies.profile("my_classroom")] = classroom_data
	glob.set_var("lesson_cache", lesson_cache, "classroom.bin")
	#(data)

func get_classroom_frontend():
	return lesson_cache.get(cookies.profile("my_classroom"), {})

func get_lesson_frontend(lesson_key):
	return offline_tutorials if is_offline_lesson_key(lesson_key) else get_classroom_frontend()

func get_lesson_data(lesson_key) -> Dictionary:
	var frontend = get_lesson_frontend(lesson_key)
	var lessons = frontend.get("lessons", {})
	var lesson_data = lessons.get(lesson_key, {})
	return lesson_data if typeof(lesson_data) == TYPE_DICTIONARY else {}

var current_lesson = {}; var current_lesson_key = null
func enter_lesson(lesson_key):
	#(lesson_cache.get(cookies.profile("my_classroom"), {}).\
	#get("lessons", {}))
	ui.quest.reset()
	ui.recreate_quest()
	lesson.stop()
	await lesson_re_reg()
	var from_offline := is_offline_lesson_key(lesson_key)
	var orch = get_lesson_data(lesson_key)
	if not orch: printerr("Lesson doesn't exist"); return
	current_lesson = orch; current_lesson_key = lesson_key
	var auto_project = orch.get("auto_project", {})
	if typeof(auto_project) == TYPE_DICTIONARY and not auto_project.is_empty():
		var blob := str(auto_project.get("blob", ""))
		if blob == "" and not from_offline:
			blob = await fetch_lesson_auto_project_blob(str(lesson_key))
		if blob != "":
			var project_name := str(auto_project.get("name", orch.get("lesson_title", lesson_key)))
			var ok = await glob.apply_lesson_project_blob(str(lesson_key), project_name, blob)
			if not ok:
				push_error("Failed to load lesson auto-project for %s" % str(lesson_key))
				return
	current_code = orch.code
	#(JSON.stringify(current_code, "\t"))
	lesson.load_code(orch.code)
	lesson.start()
	ui.lesson_bar.appear()
	if not from_offline:
		push_classroom_event({"on_lesson": get_classroom_frontend().lesson_order.find(lesson_key), "awaiting": false})
	graphs.set_fork_allow(true)
	
	
var current_code = {}

func push_classroom_event(event: Dictionary, target = null):
	if not cookies.user(): return
	var resp = await web.JPOST("classroom/update_state", {
	"target_account_id": target if target != null else _account_id(),
	"payload": event, "classroom_id": cookies.profile("my_classroom")}, _auth_headers())

	
	
func upload_classroom_meta(meta: Dictionary):
	var resp = await web.JPOST("classroom/update_meta", {
	"payload": meta, "classroom_id": cookies.profile("my_classroom")}, _auth_headers())
	if resp and resp.get("ok", false):
		load_classroom_data(meta)
	return resp


func upload_lesson_customs(lesson_id: int, meta: Dictionary):
	classroom_data.get_or_add("lesson_customs", {})[lesson_id] = meta
	var resp = await web.JPOST("classroom/update_lessons", {
	"payload": {lesson_id: meta}, "classroom_id": cookies.profile("my_classroom")}, _auth_headers())

func fetch_lesson_auto_project_blob(lesson_key: String) -> String:
	if not cookies.profile("my_classroom"):
		return ""
	var resp = await web.JPOST("classroom/lesson_auto_project", {
		"classroom_id": cookies.profile("my_classroom"),
		"lesson_key": lesson_key,
	}, _auth_headers())
	if resp and resp.get("ok", false):
		return str(resp.get("blob", ""))
	return ""


func mark_explanation_made(idx: int = -1):

	var resp = await web.JPOST("classroom/mark_explanation_made", {
	"lesson_idx": idx, "classroom_id": cookies.profile("my_classroom")}, _auth_headers())



func _exit_tree() -> void:
	LessonRouter.unregister_lesson(lesson)

func on_graph_deleted(who: Graph):
	pass

func _on_step_started(idx: int, step: Dictionary) -> void:
	#(current_code.keys())
	#(current_code.steps)
	print("STEP START:", step.get("title", step.get("id")), " ", idx)
	var from_offline := is_offline_lesson_key(current_lesson_key)
	if not from_offline:
		push_classroom_event({"step": idx+1})
	await get_tree().process_frame
	var lesson_frontend = offline_tutorials if from_offline else get_classroom_frontend()
	ui.lesson_bar.update_data({
	classroom_name = current_lesson.get("bundle_name", "Offline tutorials") if from_offline else classroom_data["name"],
	step_index = lesson.get_main_step_index() + 1,
	step_shorthand = step.get("title", ""),
	lesson_index = lesson_frontend.get("lesson_order", []).find(current_lesson_key) + 1,
	lesson_name = current_lesson.lesson_title,
	total_steps = lesson.get_main_total_steps()
}, idx == 0, idx != 0)


func estimate_read_time(text: String) -> float:
	# --- Base reading speed ---
	var WPM := 160.0
	var words := text.split(" ", false)
	var base_time := (words.size() / WPM) * 60.0

	# --- Punctuation pauses ---
	var punctuation_time := 0.0

	punctuation_time += text.count(",") * 0.15
	punctuation_time += text.count(".") * 0.35
	punctuation_time += text.count("?") * 0.45
	punctuation_time += text.count("!") * 0.45
	punctuation_time += (text.count(":") + text.count(";")) * 0.30
	punctuation_time += text.count("\n") * 0.50

	# --- Long word penalty ---
	var long_word_time := 0.0
	for word in words:
		if word.length() > 8:
			long_word_time += 0.04

	# --- Numbers slow reading ---
	var number_time := 0.0
	for c in text:
		if c.is_valid_int():
			number_time += 0.20

	# --- Final time ---
	var total_time := base_time + punctuation_time + long_word_time + number_time

	# Clamp to avoid absurd values
	return max(total_time, 0.5)


func _on_step_completed(idx: int, step: Dictionary) -> void:
	print("STEP DONE:", step.get("title", step.get("id")))


func _on_invariant_broken(idx: int, step: Dictionary, reason: String) -> void:
	print("INVARIANT BROKEN:", reason)

func _build_smoke_test() -> Dictionary:
	return {"total_steps": 7,
		"step_index": 0,
		"steps":[
		{
			"id": "create_input",
			"title": "Create input node",
			"bind_on_create": {
				"type": "input_1d",
				"bind": "x"
			},
			"requires": [
				{
					"type": "node",
					"node": { "bind": "x" }
				}
			]
		},
		{
			"id": "create_dense_a",
			"title": "Create first dense layer",
			"bind_on_create": {
				"type": "layer",
				"bind": "dense_a"
			},
			"requires": [
				{
					"type": "node",
					"node": { "bind": "dense_a" }
				}
			]
		},
		{
			"id": "create_dense_b",
			"title": "Create second dense layer",
			"bind_on_create": {
				"type": "layer",
				"bind": "dense_b"
			},
			"requires": [
				{
					"type": "node",
					"node": { "bind": "dense_b" }
				}
			]
		},
		{
			"id": "connect_input_dense",
			"title": "Connect input to first dense",
			"requires": [
				{
					"type": "connection",
					"from": { "bind": "x" },
					"to":   { "bind": "dense_a" }
				}
			],
			"persistent": true
		},
		{
			"id": "connect_dense_dense",
			"title": "Connect dense to dense",
			"requires": [
				{
					"type": "connection",
					"from": { "bind": "dense_a" },
					"to":   { "bind": "dense_b" }
				}
			],
			"persistent": true
		},
		{
			"id": "config_dense",
			"title": "Configure dense units",
			"requires": [
				{
					"type": "config",
					"node": { "bind": "dense_a" },
					"exprs": {
						"neuron_count": "neuron_count >= 4"
					}
				}
			],
			"persistent": true
		},
		{
			"id": "finish",
			"title": "Lesson finished"
		}
	]}



	

func notify_update():
	LessonRouter.notify_graph_changed()
