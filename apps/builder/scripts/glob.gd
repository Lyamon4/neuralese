@tool
extends Node2D
const LOAD_LAST_PROJECT: bool = 1
const FullyLocalConfigScript := preload("res://scripts/fully_local_config.gd")
const DatasetCompressionDebugScript := preload("res://scripts/dataset_compression_debug.gd")
const DEBUG: bool = true
enum NetMode {Localhost, Remote, LAN}
var NET_MODE = NetMode.Localhost
const DUMMY_LOGIN: bool = 0
const DUMMY_PROJECTS: bool = 0
const WINDOW_DBG: bool = 0
const MENU_PLAY_AROUND: bool = false
const DEBUG_RELOAD_LESSONS: bool = 0
const IMPORT_LESSON_DIRS: bool = 0    
const NO_TRANSCRIBER_WARMUP: bool = true
const LocalSave: bool = 1
const LOCAL_PROJECT_DIR: String = "local_projects"
const LOCAL_PROJECT_INDEX: String = "local_projects/index.bin"

const BUILTIN_PROJECT_DIR: String = "built_in_projects"
const BUILTIN_PROJECTS_IMPORTED_FLAG: String = "builtin_projects_imported_v1"
const BUILTIN_DEFAULT_PROJECT: String = "Digits.scn" # Example: "Intro.scn". Empty = first sorted .scn

var default_spline = preload("res://scenes/default_spline.tscn")
var scroll_container = preload("res://scenes/vbox.tscn")

var dummy_string: String = """Lorem ipsum dolor sit amet, consectetur adipiscing elit."""

var dummy_string_long: String = """Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."""

var bg_trect: CanvasLayer

var undo_redo = UndoRedo.new()

var hide_menus: bool = false
var hovered_connection: Connection = null
var spline_connection: Connection = null
#var splines = {}

var menus: Dictionary[StringName, BlockComponent] = {}

var refs = {}
func ref(inst, name):
	refs[name] = inst

func flatten_array(arr: Array) -> Array:
	var result: Array = []
	var queue: Array = [arr]

	while not queue.is_empty():
		var current = queue.pop_front()
		for item in current:
			if item is Array:
				queue.push_back(item)
			else:
				result.append(item)
	return result


func getref(name):
	if name in refs:
		if is_instance_valid(refs[name]):
			return refs[name]
		else:
			refs.erase(name)
	return null


func get_spline(for_connection: Connection, keyword: StringName = &"default") -> Spline:
	var new = default_spline.instantiate()
	new.keyword = keyword
	splines_layer.add_child(new); new.z_index = 9
	return new

var splines_active = {}
func activate_spline(spline: Spline, add: bool = true):
	if add:
		splines_active[spline] = true
	if spline.get_parent() == top_splines_layer: return
	spline.reparent(top_splines_layer)

func deactivate_spline(spline: Spline):
	splines_active.erase(spline)
	if spline.get_parent() == splines_layer: return
	spline.reparent(splines_layer)

# Occupation (some node blocks input of others)
var occ_layers: Dictionary[StringName, Control] = {}


class GenArray:
	var _iterable = null; var _wrapper: Callable = Callable()
	func _init(iterable, wrapper: Callable):
		iterable = _iterable; _wrapper = wrapper

	func _iter_init(iter):
		iter[0] = 0
		return iter[0] < len(_iterable)

	func _iter_next(iter):
		iter[0] += 1
		return iter[0] < len(_iterable)

	func _iter_get(iter):
		return _wrapper.call(iter[0])


func gen(iterable, wrapper: Callable) -> GenArray:
	return GenArray.new(iterable, wrapper)

func is_occupied(node: Node, layer: StringName) -> bool: 
	var occupied = occ_layers.get(layer, null)
	return is_instance_valid(occupied) and occupied != node

func get_occupied(layer: StringName):
	var got = occ_layers.get(layer, null)
	return got if is_instance_valid(got) else null

var sib: Node
func loaded(string: String) -> int:
	if not sib: 
		sib = Node.new(); get_tree().get_root().add_child(sib)
		sib.get_parent().move_child(sib, base_node.get_index()+1)
		
	var inst = load(string).instantiate()
	inst.window_hide()
	sib.add_child(inst); return 0

var fg: ColorRect = null
var tree_windows: Dictionary[String, TabWindow] = {}
@onready var _load_window_scenes = {}
var curr_window = ""


func go_window(window_name: String):
	if curr_window == window_name: return
	for node in nn.infer_channels().duplicate():
		nn.close_infer_channel(node)
	ui.window_changed(window_name)
	if curr_window in tree_windows:
		tree_windows[curr_window].window_hide()
	if window_name in tree_windows:
		print("aa")
		tree_windows[window_name].window_show()
		curr_window = window_name
	



var base_node: Node2D = null

func cap(value: float, decimals: int) -> float:
	var factor = pow(10.0, decimals)
	return floor(value * factor) / factor

func is_occupator(node: Node, layer: StringName) -> bool:
	var occupied = occ_layers.get(layer, null)
	return is_instance_valid(occupied) and occupied == node

func occupy(node: Control, layer: StringName):
	var occupied = occ_layers.get_or_add(layer, null)
	if not is_instance_valid(occupied):
		occ_layers[layer] = node
func un_occupy(node: Control, layer: StringName):
	var occupied = occ_layers.get_or_add(layer, null)
	
	if is_instance_valid(occupied) and occupied == node:
		occ_layers[layer] = null

# Select menu type (add graph / edit graph / edit connection etc.)
var menu_type: StringName = &""
var _menu_type_occupator: Node = null
func is_my_menu(node: BlockComponent) -> bool:
	return menu_type == node.menu_name if menu_type else node.menu_name == &"add_graph"
var default = []
func set_menu_type(occ: Node, type: StringName, low_priority_types=null ):
	if !is_instance_valid(_menu_type_occupator) or (low_priority_types and menu_type in low_priority_types): 
		_menu_type_occupator = occ
		menu_type = type
func reset_menu_type(occ, type: StringName):
	#_stack()
	if is_instance_valid(_menu_type_occupator) and _menu_type_occupator == occ:
		#_stack()
		_menu_type_occupator = null
		menu_type = &""

func get_occupator():
	if not is_instance_valid(_menu_type_occupator):
		_menu_type_occupator = null
	return _menu_type_occupator

# Unique slot
var id: int = 0
func free_slot():
	id += 1; return id


func show_menu(name: StringName, at_pos: Vector2 = Vector2()):
	var menu = menus[name]
	menu.size.y = menu.base_size.y
	menu.menu_show(menu.pos_clamp(at_pos if at_pos else menu.get_global_mouse_position()))
	menu.state.holding = false

func hide_all_menus() -> void: hide_menus = true

func get_global_z_index(init_node: CanvasItem) -> int:
	var z: int = 0; var node: Node = init_node
	while node is CanvasItem:
		z += node.z_index
		if !node.z_as_relative: break
		node = node.get_parent()
	return z

var scroll_imp: Dictionary = {}

func set_scroll_possible(who: Control):
	scroll_imp.erase(who)

func set_scroll_impossible(who: Control):
	scroll_imp[who] = true

func is_scroll_possible() -> bool:
	return len(scroll_imp) == 0

func get_label_text_size_unscaled(lbl: Control, _unused: float = 1.0, auto_size: int = 0) -> Vector2:
	var font = lbl.get_theme_font("font")
	var size = auto_size
	if not auto_size:
		size = lbl.get_theme_font_size("font_size")
	return font.get_string_size(lbl.text, 0, -1, size)

func get_label_text_size(lbl: Control, use_scale: float = 1.0, cust_text = null) -> Vector2:
	# Measure label text size
	var font = lbl.get_theme_font("font")
	var size = lbl.get_theme_font_size("font_size") * use_scale
	return font.get_string_size(lbl.text if cust_text == null else cust_text, 0, -1, size)

func layer_to_global(layer: CanvasLayer, point: Vector2):
	return layer.transform * point

func global_to_layer(layer: CanvasLayer, point: Vector2):
	return layer.transform.affine_inverse() * point

func spring(from, to, t: float,
			frequency: float = 4.5,
			damping: float = 4.0,
			amplitude: float = 2.0
):
	var w = frequency * PI * 2.0
	var decay = exp(-damping * t)
	var osc = cos(w * t) + (damping / w) * sin(w * t)
	var amp_factor = lerp(1.0, amplitude, t)
	var factor = 1.0 - decay * osc * amp_factor
	return from + (to - from) * factor


var loaded_project_once: bool = false
class _Timer extends Object:
	var wait_time: float; var progress: float; var frames: bool 
	signal timeout
	func _init(wait_time: float, _frames: bool):
		self.wait_time = wait_time; self.progress = 0.0; frames = _frames

var timers: Dictionary[_Timer, bool] = {}

func timer(wait_time: float, frames: bool = false) -> _Timer:
	var timer = _Timer.new(wait_time, frames)
	timers[timer] = true; return timer

func wait(wait_time: float, frames: bool = false) -> Signal:
	var timer = _Timer.new(wait_time, frames)
	timers[timer] = true; return timer.timeout




func get_project_id() -> int:
	return project_id

func set_var(n: String, val: Variant, space = "memory.bin"):
	var got = get_stored(space)
	got[n] = val
	var op = cookies.open_or_create(space)
	op.store_var(got)

func get_var(n: String, deft = null, space = "memory.bin") -> Variant:
	return get_stored(space).get(n, deft)

func get_stored(space = "memory.bin") -> Dictionary:
	var op = cookies.open_or_create(space)
	if not op: return {}
	var res = op.get_var()
	return res if res else {}


func open_last_project():

	if LocalSave:
		var got = str(get_var("last_id", ""))
		var local_projects = await request_projects()
		if got and local_projects.has(got):
			load_scene(got)
		elif local_projects:
			load_scene(str(local_projects.keys()[0]))
		else:
			var i = await create_empty_project("", true)
			load_empty_scene(i, "")
		return 0

	if not _logged_in:
		return
	var got = get_var("last_id")
	if got:
		load_scene(str(got))
	else:
		var a = await request_projects()
		if a:
			load_scene(a.keys()[0])
		else:
			var i = await create_empty_project("", false)
			load_empty_scene(i, "")
	return 0


var parsed_projects = {}

func _local_project_blob_path(id: String) -> String:
	return "%s/%s.scn" % [LOCAL_PROJECT_DIR, id]

func _local_store_var(path: String, value: Variant) -> bool:
	var base_dir = path.get_base_dir()
	if base_dir:
		cookies.dir_or_create(base_dir)
	var file = FileAccess.open("user://" + path, FileAccess.WRITE_READ)
	if not file:
		push_error("Failed to write local project file: user://%s" % path)
		return false
	file.store_var(value)
	file.close()
	return true

func _local_read_var(path: String) -> Variant:
	if not FileAccess.file_exists("user://" + path):
		return null
	var file = FileAccess.open("user://" + path, FileAccess.READ)
	if not file:
		return null
	var value = file.get_var()
	file.close()
	return value

func _local_project_index() -> Dictionary:
	var value = _local_read_var(LOCAL_PROJECT_INDEX)
	return value if value is Dictionary else {}

func _local_store_project_index(index: Dictionary) -> bool:
	return _local_store_var(LOCAL_PROJECT_INDEX, index)

func _local_project_exists(id: String) -> bool:
	return FileAccess.file_exists("user://" + _local_project_blob_path(id))

func _local_request_projects() -> Dictionary:
	var index = _local_project_index()
	var changed = false
	for id in index.keys():
		if not _local_project_exists(str(id)):
			index.erase(id)
			changed = true
	if changed:
		_local_store_project_index(index)
	parsed_projects = index
	return parsed_projects

func _local_project_name(id: String) -> String:
	var index = _local_project_index()
	return str(index.get(id, {}).get("name", ""))

func _local_save_project_blob(id: String, bytes: PackedByteArray, name: String, contexts: Array = [], last_id: int = -1, chat_id: String = "0") -> Dictionary:
	if not _local_store_var(_local_project_blob_path(id), bytes):
		return {"status": "error", "local": true, "error": "Could not write local project blob."}
	_local_store_var("cached_projects/%s.scn" % id, bytes)
	var index = _local_project_index()
	index[id] = {
		"name": name,
		"scene": id,
		"local": true,
		"modified": Time.get_unix_time_from_system(),
		"last_id": last_id,
		"chat_id": chat_id,
		"contexts": contexts,
	}
	_local_store_project_index(index)
	parsed_projects = index
	set_var("last_id", int(id))
	return {"status": "ok", "local": true, "scene": id}

func _local_load_project_blob(id: String) -> Variant:
	var bytes = _local_read_var(_local_project_blob_path(id))
	if bytes == null:
		bytes = _local_read_var("cached_projects/%s.scn" % id)
	if bytes == null:
		return null
	return bytes_to_var(bytes)

func _local_delete_project(id: String) -> bool:
	var index = _local_project_index()
	index.erase(id)
	_local_store_project_index(index)
	parsed_projects = index
	var dir = DirAccess.open("user://" + LOCAL_PROJECT_DIR)
	var file_name = "%s.scn" % id
	if dir and dir.file_exists(file_name):
		dir.remove(file_name)
	var cache_dir = DirAccess.open("user://cached_projects")
	if cache_dir and cache_dir.file_exists(file_name):
		cache_dir.remove(file_name)
	return true

func create_empty_project(name: String, save: bool = true) -> int:
	if 1:
		learner.push_classroom_event({"on_lesson": -1})
		learner.stop_lesson()
	var id: int = random_project_id()
	while LocalSave and _local_project_exists(str(id)):
		id = random_project_id()
	parsed_projects[str(id)] = {"name": name}
	ui.hourglass_on()
	if save:
		var res = await save_empty(str(id), name)
	ui.hourglass_off()
	return id

func request_projects(lessons: bool = false):
	if LocalSave and not lessons:
		return _local_request_projects()
	if DUMMY_PROJECTS:
		var ddict = {}
		for i in range(10):
			ddict[hash(i)] = {"name": "Project %s" % i} if !lessons else {"name": "Lesson %s" % i}
		#(ddict)
		return ddict
	var a = await web.POST("project_list", {
	"user": cookies.user(), 
	"pass": cookies.pwd()
	})
	if a.body:
		#(a.body.get_string_from_utf8())
		var parsed = JSON.parse_string(a.body.get_string_from_utf8())
		if parsed.answer == "wrong": return {}
		a = parsed["list"]
		parsed_projects = a
		for i in a.keys():
			if a[i] == null: a.erase(i)
		return a
	return {}


func _read_var_abs(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var value = file.get_var()
	file.close()
	return value


func _install_builtin_projects_once() -> void:
	if not LocalSave:
		return
	print("local install start...")
	if OS.has_feature("editor"):
		return
	if bool(get_var(BUILTIN_PROJECTS_IMPORTED_FLAG, false)):
		return
	print("imported flag...")

	var dir = DirAccess.open("res://" + BUILTIN_PROJECT_DIR)
	if not dir:
		print("dir doesnt exist...")
		return

	var files: Array[String] = []

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".scn"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()

	var index = _local_project_index()
	var first_id := ""
	var default_id := ""

	for builtin_file in files:
		var bytes = _read_var_abs("res://%s/%s" % [BUILTIN_PROJECT_DIR, builtin_file])
		if not bytes is PackedByteArray:
			push_warning("Built-in project is not a local project blob: %s" % builtin_file)
			continue

		var id = str(random_project_id())
		while index.has(id) or _local_project_exists(id):
			id = str(random_project_id())

		if not _local_store_var(_local_project_blob_path(id), bytes):
			continue

		_local_store_var("cached_projects/%s.scn" % id, bytes)

		index[id] = {
			"name": builtin_file.get_basename(),
			"scene": id,
			"local": true,
			"builtin": true,
			"modified": Time.get_unix_time_from_system(),
			"last_id": -1,
			"chat_id": "0",
			"contexts": [],
		}

		if first_id.is_empty():
			first_id = id

		if BUILTIN_DEFAULT_PROJECT != "" and builtin_file == BUILTIN_DEFAULT_PROJECT:
			default_id = id

	_local_store_project_index(index)
	parsed_projects = index

	var open_id = default_id if not default_id.is_empty() else first_id
	if not open_id.is_empty():
		set_var("last_id", int(open_id))

	set_var(BUILTIN_PROJECTS_IMPORTED_FLAG, true)

func random_project_id() -> int:
	return randi_range(0,999999)

var project_id: int = random_project_id()

func _after_process(delta: float) -> void:
	hide_menus = false
	consumed_input.clear()
	hovered_connection_changed = false

	if space_just_pressed:
		pass
		#await save(str(get_project_id()))
		#load_scene("gr1")
	#prit(menu_type)

var opened_menu = null

var mouse_pressed: bool = false
var mouse_just_pressed: bool = false
var mouse_released: bool = false
var mouse_just_released: bool = false

var mouse_alt_pressed: bool = false
var mouse_alt_just_pressed: bool = false
var mouse_alt_released: bool = false
var mouse_alt_just_released: bool = false

var mouse_middle_pressed: bool = false
var mouse_middle_just_pressed: bool = false
var mouse_middle_released: bool = false
var mouse_middle_just_released: bool = false

var mouse_scroll: int = 0

var consumed_input: Dictionary[StringName, Control] = {}

var cam: Camera2D
var viewport: Viewport

const arrays: Dictionary[int, bool] = {
TYPE_ARRAY:true,
TYPE_PACKED_BYTE_ARRAY:true,
TYPE_PACKED_COLOR_ARRAY:true,
TYPE_PACKED_VECTOR2_ARRAY:true,
TYPE_PACKED_VECTOR3_ARRAY:true,
TYPE_PACKED_VECTOR4_ARRAY:true,
TYPE_PACKED_STRING_ARRAY:true,
TYPE_PACKED_FLOAT32_ARRAY:true,
TYPE_PACKED_FLOAT64_ARRAY:true,
TYPE_PACKED_INT32_ARRAY:true,
TYPE_PACKED_INT64_ARRAY:true
}

var units = [
	["T", 1_000_000_000_000],
	["B", 1_000_000_000],
	["M", 1_000_000],
	["K", 1_000]
]

func compact(n: int) -> String:
	if n < 1000:
		return str(n)

	for u in units:
		var suf: String = u[0]
		var val: int = u[1]
		if n >= val:
			var q: int = n / val
			var rem: int = n % val
			return str(q) + suf

	return str(n)


var iterables: Dictionary[int, bool] = arrays.merged({
TYPE_DICTIONARY:true,})

func to_set(arr, ...args) -> Dictionary:
	var a: Dictionary = {}
	if args != []:
		var old = arr
		arr = args
		arr.append(old)
	for i in arr:
		a[i] = true
	return a
func is_array(a) -> bool: return typeof(a) in arrays
func is_iterable(a) -> bool: return typeof(a) in iterables

func deep_map(root: Variant, mapper: Callable) -> Variant:
	var result = root.duplicate()
	var queue: Array = [result]

	while queue.size() > 0:
		var current = queue.pop_back()

		if current is Array:
			var size: int = current.size()
			for i in size:
				var v = current[i]
				if v is Array:
					var copy = v.duplicate()
					current[i] = copy
					queue.push_back(copy)
				elif v is Dictionary:
					var copy = v.duplicate()
					current[i] = copy
					queue.push_back(copy)
				else:
					current[i] = mapper.call(v)

		elif current is Dictionary:
			for k in current:
				var v = current[k]
				if v is Array:
					var copy = v.duplicate()
					current[k] = copy
					queue.push_back(copy)
				elif v is Dictionary:
					var copy = v.duplicate()
					current[k] = copy
					queue.push_back(copy)
				else:
					current[k] = mapper.call(k, v)

	return result

func list(type: int):
	var res = null
	match type:
		TYPE_ARRAY:res=[]
		TYPE_PACKED_BYTE_ARRAY:res=PackedByteArray()
		TYPE_PACKED_COLOR_ARRAY:res=PackedColorArray()
		TYPE_PACKED_VECTOR2_ARRAY:res=PackedVector2Array()
		TYPE_PACKED_VECTOR3_ARRAY:res=PackedVector3Array()
		TYPE_PACKED_VECTOR4_ARRAY:res=PackedVector4Array()
		TYPE_PACKED_STRING_ARRAY:res=PackedStringArray()
		TYPE_PACKED_FLOAT32_ARRAY:res=PackedFloat32Array()
		TYPE_PACKED_FLOAT64_ARRAY:res=PackedFloat64Array()
		TYPE_PACKED_INT32_ARRAY:res=PackedInt32Array()
		TYPE_PACKED_INT64_ARRAY:res=PackedInt64Array()
		TYPE_DICTIONARY:res={}
	return res

func consume_input(inst: Control, input: StringName):
	if not consumed_input.has(input) or consumed_input[input].z_index <= inst.z_index:
		consumed_input[input] = inst

func is_consumed(inst: Control, input: StringName):
	return consumed_input.has(input) and consumed_input[input] != inst

func get_consumed(input: StringName):
	return consumed_input.get(input, null)



func press_poll():
	mouse_just_pressed = Input.is_action_just_pressed("ui_mouse")
	mouse_pressed = Input.is_action_pressed("ui_mouse")
	mouse_just_released = Input.is_action_just_released("ui_mouse")
	mouse_released = not mouse_pressed

	mouse_alt_just_pressed = Input.is_action_just_pressed("ui_mouse_alt")
	mouse_alt_pressed = Input.is_action_pressed("ui_mouse_alt")
	mouse_alt_just_released = Input.is_action_just_released("ui_mouse_alt")
	mouse_alt_released = not mouse_alt_pressed

	mouse_middle_just_pressed = Input.is_action_just_pressed("ui_mouse_middle")
	mouse_middle_pressed = Input.is_action_pressed("ui_mouse_middle")
	mouse_middle_just_released = Input.is_action_just_released("ui_mouse_middle")
	mouse_middle_released = not mouse_alt_pressed
	
	if unpress_enq:
		glob.mouse_pressed = false
		glob.mouse_just_pressed = false
		glob.mouse_alt_pressed = false
		glob.mouse_alt_just_pressed = false
		unpress_enq = false
	
	if mouse_just_pressed:
		last_mouse_click_at = get_global_mouse_position()

var unpress_enq: bool = false

func reset_presses():
	unpress_enq = true

func cull(gp: Vector2, s: Vector2) -> bool:
	var p0: Vector2 = glob.world_to_screen(gp)
	var p1: Vector2 = glob.world_to_screen(gp + Vector2(s.x, 0.0))
	var p2: Vector2 = glob.world_to_screen(gp + Vector2(0.0, s.y))
	var p3: Vector2 = glob.world_to_screen(gp + s)

	var minx: float = min(p0.x, p1.x, p2.x, p3.x)
	var maxx: float  = max(p0.x, p1.x, p2.x, p3.x)
	var miny: float = min(p0.y, p1.y, p2.y, p3.y)
	var maxy: float = max(p0.y, p1.y, p2.y, p3.y)
	var rect_screen = Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))

	return rect_screen.intersects(window_rect)



func input_poll():
	press_poll()
	if Input.is_action_just_pressed("scroll_up"): mouse_scroll = -1
	elif Input.is_action_just_pressed("scroll_down"): mouse_scroll = 1
	else: mouse_scroll = 0


var ticks: int = 0

func cast_variant(value: Variant, target_type: int) -> Variant:
	match target_type:
		TYPE_NIL:
			return null

		TYPE_BOOL:
			return bool(value)

		TYPE_INT:
			return int(value)

		TYPE_FLOAT:
			return float(value)

		TYPE_STRING:
			return str(value)

		TYPE_VECTOR2:
			if value is Vector2:
				return value
			elif value is Array and value.size() >= 2:
				return Vector2(value[0], value[1])
			return Vector2.ZERO

		TYPE_VECTOR3:
			if value is Vector3:
				return value
			elif value is Array and value.size() >= 3:
				return Vector3(value[0], value[1], value[2])
			return Vector3.ZERO

		TYPE_COLOR:
			if value is Color:
				return value
			elif value is String:
				return Color(value)
			elif value is Array and value.size() >= 3:
				return Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0)
			return Color.WHITE

		TYPE_VECTOR4:
			if value is Vector4:
				return value
			elif value is Array and value.size() >= 4:
				return Vector4(value[0], value[1], value[2], value[3])
			return Vector4.ZERO

		_:
			return value  # fallback, return as-is



var menu_canvas: CanvasLayer = null
func get_display_mouse_position():
	return menu_canvas.root.get_global_mouse_position()

func twine(a: float, b: float, factor: float):
	pass
	#return lerp(a, b, 1.0 - exp(-speed * delta))


var window_size: Vector2 = Vector2.ONE
var window_middle: Vector2 = Vector2.ONE

var UP: int = 0
var DOWN: int = 1
var LEFT: int = 2
var RIGHT: int = 3

func world_to_screen(p_world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p_world

func screen_to_world(p_screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p_screen

var follow_menus: Node
var window_rect: Rect2 = Rect2()
var time: float = 0.0
var space_pressed: bool = false
var space_just_pressed: bool = false

var enter_just_pressed: bool = false

var _logged_in: Dictionary = {}
func try_auto_login():
		
	var got = get_var("credentials")
	if WINDOW_DBG:
		if OS.get_cmdline_args().has("teacher"):
			got = {"user": "teacher", "pass": "1"}
		else:
			got = {"user": "n", "pass": "1"}
	if DUMMY_LOGIN: 
		dummy_login()
		return true
	if cookies.has_clerk_session():
		if await cookies.restore_or_refresh_clerk_session(got if typeof(got) == TYPE_DICTIONARY else {}):
			return true
		reset_logged_in(true)
		return true
	if got:
		if str(got.get("auth_provider", "")) == "clerk":
			if not await cookies.restore_or_refresh_clerk_session(got):
				reset_logged_in(true)
			return true
		var a = await login(got["user"], got["pass"])
		
		if a.get("ok", false):
			set_logged_in(got["user"], got["pass"])
		else:
			reset_logged_in(true)
	return true

func login_req(user: String, passw: String):
	return await web.POST("login", {"user": user, "pass": passw})

func dummy_login():
	var data = {"user": "n", "pass": "1"}
	set_logged_in(data["user"], data["pass"])

func set_logged_in(user: String, passw: String):
	_logged_in = {"user": user, "pass": passw}
	set_var("credentials", _logged_in)

func reset_logged_in(pers: bool = false):
	if _logged_in.get("auth_provider", "") == "clerk" or cookies.has_clerk_session():
		cookies.clear_clerk_session(false)
	_logged_in = {}
	learner.stop_lesson()
	learner.classroom_data = {}
	nn.close_all()
	set_var("credentials", {})

func logged_in() -> bool:
	return _logged_in.size() > 0

var f2_just_pressed: bool = false
var f2_pressed: bool = false

func poll_events():

	if Input.is_action_pressed("ui_mouse_middle"):
		events.event_true("ui_mouse_middle")
	else:
		events.event_false("ui_mouse_middle")


func _process(delta: float) -> void:
	#print(menu_type)
	#if space_just_pressed:
	#(graphs.get_llm_summary())
	#((graphs.get_llm_summary()).hash())
	#(last_summary_hash)
	#(project_id)
		#(graphs.get_llm_summary())

	
	
	space_just_pressed = Input.is_action_just_pressed("ui_accept")
	space_pressed = Input.is_action_pressed("ui_accept")
	
	
	time += delta
	ticks += 1
	if Engine.is_editor_hint(): return
	poll_events()
	
	if Input.is_action_just_pressed("ctrl_s"):
		await save(str(get_project_id()))
	#(window_size)
	f2_just_pressed = Input.is_action_just_pressed("f2")
	f2_pressed = Input.is_action_pressed("f2")
	if glob.get_occupied("menu") and !glob.get_occupied("menu").is_visible_in_tree():
		glob.un_occupy(glob.get_occupied("menu"), "menu")
	#if _menu_type_occupator and _menu_type_occupator is Connection:
	#	print(_menu_type_occupator.parent_graph.process_mode == Node.PROCESS_MODE_DISABLED)
	
	for i in tweens.keys():
		i.poll(delta)
		if i.is_finished:
			tweens.erase(i)
	
	#if space_just_pressed:
	#	await save(str(get_project_id()))
	#if space_just_pressed:
	#	save_datasets()
	if curr_window == "graph" and not get_viewport().gui_get_focus_owner() is LineEdit:
		if not ui.active_splashed():
			if Input.is_action_just_pressed("ctrl_z"):
				#("A")
				undo_redo.undo()
			if Input.is_action_just_pressed("ctrl_y"):
				#("A")
				undo_redo.redo()
	enter_just_pressed = Input.is_action_just_pressed("ui_enter")
	if not is_instance_valid(_menu_type_occupator):
		menu_type = ""
		_menu_type_occupator = null
	if _menu_type_occupator is Connection and not _menu_type_occupator.is_mouse_inside():
		menu_type = ""
		_menu_type_occupator = null
	
	window_size = DisplayServer.window_get_size()
	window_rect = Rect2(Vector2(), window_size)
	window_middle = window_size / 2
	space_end = DisplayServer.window_get_size()

	_after_process.call_deferred(delta)
	
	var to_erase = []
	for timer in timers:
		timer.progress += delta if not timer.frames else 1
		if timer.progress > timer.wait_time: 
			timer.timeout.emit()
			to_erase.append(timer)
	for i in to_erase:
		timers.erase(i)
		i.free.call_deferred()
	input_poll()
	var occ = get_occupied("block_button_inside")
	if occ:
		occ.last_mouse_pos = occ.get_global_mouse_position()
		if occ.is_mouse_inside():
			un_occupy(occ, "block_button_inside")
	if not _menu_type_occupator or not _menu_type_occupator.is_visible_in_tree():
		reset_menu_type(_menu_type_occupator, menu_type)


var hovered_connection_changed: bool = false

func is_graph_inside() -> bool: return is_occupied(self, "graph")

func byte(x) -> PackedByteArray:
	if x is Dictionary:
		return JSON.stringify(x).to_utf8_buffer()
	return PackedByteArray()

func compress_dict_gzip(dict: Dictionary):
	var jsonified = JSON.new().stringify(dict, "", true, true)
	var bytes = jsonified.to_ascii_buffer()
	return bytes.compress(FileAccess.CompressionMode.COMPRESSION_GZIP)

func compress_dict_zstd(dict: Dictionary):
	var jsonified = JSON.new().stringify(dict, "", true, true)
	var bytes = jsonified.to_ascii_buffer()
	return bytes.compress(FileAccess.CompressionMode.COMPRESSION_ZSTD)


var buffer: BackBufferCopy
var splines_layer: CanvasLayer
var top_splines_layer: CanvasLayer

func is_vec_approx(a: Vector2, b: Vector2, eps: float = 0.01) -> bool:
	return abs(a.x-b.x) < eps and abs(a.y-b.y) < eps

func inst_uniform(who: CanvasItem, uniform: StringName, val):
	RenderingServer.canvas_item_set_instance_shader_parameter(who.get_canvas_item(), uniform, val)

func inst_uniform_read(who: CanvasItem, uniform: StringName):
	#(RenderingServer.canvas_item_get_instance_shader_parameter_list(who.get_canvas_item()))
	return RenderingServer.canvas_item_get_instance_shader_parameter(who.get_canvas_item(), uniform)


func in_out_quad(t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

func lerp_quad(a: float, b: float, k: float) -> float:
	return lerp(a, b, in_out_quad(k))

func in_expo(t: float) -> float: t = clamp(t, 0.0, 1.0); return 0.0 if t == 0.0 else pow(2.0, 10.0 * t - 10.0)
func lerp_expo_in(a: float, b: float, k: float) -> float: return lerp(a, b, in_expo(k))

func out_expo(t: float) -> float: t = clamp(t, 0.0, 1.0); return 1.0 if t == 1.0 else 1.0 - pow(2.0, -10.0 * t)
func lerp_expo_out(a: float, b: float, k: float) -> float: return lerp(a, b, out_expo(k))

func in_out_expo(t: float) -> float: t = clamp(t, 0.0, 1.0); return 0.0 if t == 0.0 else (1.0 if t == 1.0 else (pow(2.0, 20.0 * t - 10.0) / 2.0 if t < 0.5 else (2.0 - pow(2.0, -20.0 * t + 10.0)) / 2.0))
func lerp_expo(a: float, b: float, k: float) -> float: return lerp(a, b, in_out_expo(k))

func get_project_data(empty: bool = false) -> Dictionary:
	var data = {"graphs": {}, "lua": {}, "registry": {}}
	data["registry"]["subgraph_registry"] = {}
	if empty:
		return data
	for i in graphs._graphs:
		data["graphs"][i] = graphs._graphs[i].get_info()
	var texts = glob.tree_windows["env"].get_texts()
	for i in texts:
		data["lua"][i] = texts[i]
		
	data["camera"] = Vector3(cam.position.x, cam.position.y, cam.zoom.x)
	
	for sub_id in Graph._subgraph_registry:
		var ids = []
		for n in Graph._subgraph_registry[sub_id]:
			if is_instance_valid(n):
				ids.append(n.graph_id)
		data["registry"]["subgraph_registry"][sub_id] = ids
	return data



func init_scene(scene: String):
	tree_windows["env"].request_texts()


func delete_project(scene: int):
	if LocalSave:
		var scene_id = str(scene)
		_local_delete_project(scene_id)
		if project_id == scene:
			var i = await create_empty_project("")
			load_empty_scene(i, "")
		return true
	web.POST("delete_project", {"user": cookies.user(), "pass": cookies.pwd(), "scene": str(scene)})
	parsed_projects.erase(str(scene))
	if project_id == scene:
		var i = await create_empty_project("")
		load_empty_scene(i, "")
	return true

func def(...args) -> void:
	pass


"https://neriqward.360hub.ru/api/"
"http://localhost:8000/"

#"ws://localhost:8000/"
#var connection_prefix: String = glob.get_root_ws()#"wss://neriqward.360hub.ru/api/"

var base_lan_ip: String = ""
func get_root_ws():
	if NET_MODE == NetMode.Localhost:
		return "ws://127.0.0.1:8081/"
	else:
		if NET_MODE == NetMode.Remote:
			return "wss://neuralese.asia/"
		else:
			return "ws://" + base_lan_ip + ":8081/"

func get_root_http():
	if NET_MODE == NetMode.Localhost:
		return "http://127.0.0.1:8081/"
	else:
		if NET_MODE == NetMode.Remote:
			return "https://neuralese.asia/"
		else:
			return "http://" + base_lan_ip + ":8081/"


func message_chunk_received(data, sock: SocketConnection):
	var dt = data.get_string_from_utf8()
	var parsed = JSON.parse_string(dt)
	if not "text" in parsed:
		return
	var text_update = sock.get_meta("text_update")
	var text: String = parsed.text
	print(text)
	var changed = text
	var clean_text = parser.parse_stream_tags(sock, text)
	#(sock.cache)
	#clean_text = clean_text.replace("```json\n", "").replace("\n```", "").strip_edges()`
	#if clean_text.is_empty():
	#	return
	sock.cache.get_or_add("message", [""])[0] += clean_text
	#(sock.cache.actions)
	if text_update.is_valid():
		text_update.call([clean_text, sock.cache.actions])


var message_sockets: Dictionary[int, SocketConnection] = {}

var last_mouse_click_at: Vector2 = Vector2()

var llm_name_mapping = {
	activation = "neuron",
	dense_layer = "layer",
	conv2d_layer = "conv2d",
	maxpool_layer = "maxpool",
	softmax = "softmax",
	flatten = "flatten",
	reshape2d = "reshape2d",
	out_labels =  "classifier",
	input_image_small = "input",
	model_name = "model_name",
	run_model = "run_model",
	train_begin = "train_begin",
	train_step = "train_input",
	load_dataset = "dataset",
	augment_tune = "augment_tf",
	output_map = "output_map",
	input_1d = "input_1d",
	load_environment = "lua_env",
	train_rl = "train_rl",
	dropout = "dropout",
	concat = "concat",
}

var tag_types = {}
var tags_1d: Dictionary[String, Graph] = {}

func get_llm_tag(who: Graph) -> String:
	#(who.llm_tag)
	var g: String = who.get_meta("created_with")
	if not g in tag_types:
		tag_types[g] = {}
		tag_types[g]["__counter__"] = 0

	var counter: int = tag_types[g].get("__counter__", 0)
	tag_types[g]["__counter__"] = counter + 1

	var base: String = llm_name_unmapping.get(g, g)
	var res: String = "%s_%d" % [base, counter]

	tag_types[g][res] = true
	tags_1d[res] = who
	return res






var previewed = {}
func load_dataset(name: String) -> Dictionary:
	if name in dataset_datas:
		if not name in previewed:
			previewed[name] = DsObjRLE.get_preview(dataset_datas[name])
		return previewed.get(name)
	return _load.get(name, {})

const FULLY_LOCAL_BUILTIN_DATASETS := {
	"mnist": {
		"name": "mnist",
		"size": 70000,
		"inputs": {"x": 28, "y": 28, "datatype": "2d"},
		"outputs": [{"label": "digit", "x": 10, "datatype": "1d", "label_names": ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]}],
		"input_hints": [{"name": "image", "value": "28x28", "dtype": "image"}],
		"fully_local": true,
		"storage": "numpy",
	},
	"iris": {
		"name": "iris",
		"size": 150,
		"inputs": {"x": 4, "datatype": "1d(len:4)"},
		"outputs": [{"label": "species", "x": 3, "datatype": "1d", "label_names": ["setosa", "versicolor", "virginica"]}],
		"input_hints": [
			{"name": "sepal_length", "value": "float", "dtype": "float"},
			{"name": "sepal_width", "value": "float", "dtype": "float"},
			{"name": "petal_length", "value": "float", "dtype": "float"},
			{"name": "petal_width", "value": "float", "dtype": "float"},
		],
		"fully_local": true,
		"storage": "numpy",
	},
	"titanic": {
		"name": "titanic",
		"size": 891,
		"inputs": {"x": 8, "datatype": "1d(len:8)"},
		"outputs": [{"label": "survived", "x": 2, "datatype": "1d", "label_names": ["no", "yes"]}],
		"input_hints": [{"name": "passenger_features", "value": "len:8", "dtype": "float"}],
		"fully_local": true,
		"storage": "numpy",
	},
	"car_track": {
		"name": "car_track",
		"size": 5400,
		"inputs": {"x": 8, "datatype": "1d"},
		"outputs": [{"label": "control", "x": 2, "datatype": "1d", "label_names": ["steer", "throttle"]}],
		"input_hints": [
			{"name": "ray_0", "value": "0..1", "dtype": "float"},
			{"name": "ray_1", "value": "0..1", "dtype": "float"},
			{"name": "ray_2", "value": "0..1", "dtype": "float"},
			{"name": "ray_3", "value": "0..1", "dtype": "float"},
			{"name": "ray_4", "value": "0..1", "dtype": "float"},
			{"name": "ray_5", "value": "0..1", "dtype": "float"},
			{"name": "ray_6", "value": "0..1", "dtype": "float"},
			{"name": "ray_7", "value": "0..1", "dtype": "float"},
		],
		"description": "Synthetic 2D driving dataset with eight raycast sensor distances and two continuous control outputs: steering and throttle.",
		"fully_local": true,
		"storage": "numpy",
	},
}

var _load = {}

func _with_builtin_datasets(remote: Dictionary) -> Dictionary:
	var merged := remote.duplicate(true)
	for ds_name in FULLY_LOCAL_BUILTIN_DATASETS:
		if not merged.has(ds_name):
			merged[ds_name] = FULLY_LOCAL_BUILTIN_DATASETS[ds_name].duplicate(true)
	return merged

func get_loaded_datasets():
	if _load:
		return _load
	var remote := {}
	var response = await web.GET("datasets") if not LocalSave else {}
	var bytes := PackedByteArray()
	if response is Dictionary and response.has("body") and response["body"] is PackedByteArray:
		bytes = response["body"]
	var dict = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() > 0 else null
	if dict:
		remote = dict.get("results", {})
	else:
		remote = {}
	_load = _with_builtin_datasets(remote)
	return _load

func del_dataset_file(nm: String):
	var a = Thread.new()
	a.start(func(): 
		var f = DirAccess.open("user://")
		f.remove("datasets/"+nm+".ds"))

signal language_changed

var lang_wheel = ["en", "ru", "kz"]; var lang_idx: int = 0
func switch_lang():
	lang_idx += 1
	if lang_idx >= len(lang_wheel):
		lang_idx = 0
	change_lang(lang_wheel[lang_idx])

var curr_lang: String = "en"
func change_lang(lang: String):
	curr_lang = lang
	set_var("lang", lang)
	language_changed.emit()
	language_just_changed.emit()

signal language_just_changed
func get_lang():
	return curr_lang

func _enter_tree() -> void:
	curr_lang = get_var("lang", "en")
	lang_idx = lang_wheel.find(curr_lang)

class BitPacker:
	var data = PackedByteArray()
	var bit_pos = 0

	func push(value: int, bits: int) -> void:
		for i in range(bits):
			var bit = (value >> (bits - 1 - i)) & 1
			_set_bit(bit_pos, bit)
			bit_pos += 1

	func _set_bit(pos: int, bit: int) -> void:
		var byte_i = pos >> 3
		var bit_i  = 7 - (pos & 7)

		if byte_i >= data.size():
			data.append(0)

		if bit == 1:
			data[byte_i] |= (1 << bit_i)
		else:
			data[byte_i] &= ~(1 << bit_i)

	func to_bytes() -> PackedByteArray:
		return data



func set_llm_tag(who: Graph, val: String):
	#("=======")
	#(who.llm_tag)
	if who.llm_tag in tags_1d and tags_1d[who.llm_tag] == who:
		tags_1d.erase(who.llm_tag)
	var g = who.get_meta("created_with")
	if not g in tag_types: tag_types[g] = {}
	who.llm_tag = val
	tag_types[g][val] = true
	#(who.llm_tag)
	#(val)
	#if !who.llm_tag:
	#	print_stack()
	#	breakpoint
	tags_1d[who.llm_tag] = who
	#(len(tags_1d))
	#(tags_1d.size())

var llm_name_unmapping = (func():
	var dict = {}
	for i in llm_name_mapping:
		dict[llm_name_mapping[i]] = i
	return dict).call()


func test_place():
	var txt = "here it is"
	#glob.update_chat_cache(str(chat_id), {"role": "ai", "text": txt})
	#message_sockets.erase(chat_id)
	#on_close.call()
	var chunk = """
<thinking>The user wants to build an MNIST CNN. This is a clear command to construct a specific type of neural network. Since the canvas is currently empty, I can use the specialized `build_graph_digit_2_conv` function which creates a two-layer CNN suitable for digit classification. This function will build the complete model with all necessary layers and connections for an MNIST CNN. I will then inform the user that the model has been built.</thinking>Отлично! Я построил для вас MNIST CNN с двумя сверточными слоями. Теперь вы можете его обучать!
<change_nodes>
[
  {"tag": "model_mnist_cnn", "type": "model_name", "config": {"name": "mnist_cnn"}},
  {"tag": "input_image_small_0", "type": "input_image_small", "config": {}},
  {"tag": "activation_relu_1", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "conv2d_layer_1", "type": "conv2d_layer", "config": {"filters": 32, "window": 3, "stride": 1}},
  {"tag": "maxpool_layer_1", "type": "maxpool_layer", "config": {"group": 2}},
  {"tag": "activation_relu_2", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "conv2d_layer_2", "type": "conv2d_layer", "config": {"filters": 64, "window": 3, "stride": 1}},
  {"tag": "maxpool_layer_2", "type": "maxpool_layer", "config": {"group": 2}},
  {"tag": "flatten_1", "type": "flatten", "config": {}},
  {"tag": "activation_relu_3", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "dense_layer_128", "type": "dense_layer", "config": {"neuron_amount": 128}},
  {"tag": "dense_layer_10", "type": "dense_layer", "config": {"neuron_amount": 10}},
  {"tag": "softmax_1", "type": "softmax", "config": {}},
  {"tag": "out_labels_digits", "type": "out_labels", "config": {"label_names": ["0","1","2","3","4","5","6","7","8","9"], "title": "digits"}},
  {"tag": "load_dataset_mnist", "type": "load_dataset", "config": {"dataset_name": "mnist"}},
  {"tag": "train_begin_0", "type": "train_begin", "config": {}},
  {"tag": "run_model_0", "type": "run_model", "config": {"branches": {"digits": "cross_entropy"}, "mapped": {"digits": "digit"}}},
  {"tag": "output_map_0", "type": "output_map", "config": {}}, 
  {"tag": "train_step_0", "type": "train_step", "config": {"optimizer": "adam", "lr": 1, "momentum": 0.0, "weight_decay": 0}}
]
</change_nodes>


<connect_ports>
[
  {"from": {"tag": "model_mnist_cnn", "port": 0}, "to": {"tag": "input_image_small_0", "port": 0}},
  {"from": {"tag": "input_image_small_0", "port": 0}, "to": {"tag": "conv2d_layer_1", "port": 1}},
  {"from": {"tag": "activation_relu_1", "port": 0}, "to": {"tag": "conv2d_layer_1", "port": 0}},
  {"from": {"tag": "conv2d_layer_1", "port": 0}, "to": {"tag": "maxpool_layer_1", "port": 0}},
  {"from": {"tag": "maxpool_layer_1", "port": 0}, "to": {"tag": "conv2d_layer_2", "port": 1}},
  {"from": {"tag": "activation_relu_2", "port": 0}, "to": {"tag": "conv2d_layer_2", "port": 0}},
  {"from": {"tag": "conv2d_layer_2", "port": 0}, "to": {"tag": "maxpool_layer_2", "port": 0}},
  {"from": {"tag": "maxpool_layer_2", "port": 0}, "to": {"tag": "flatten_1", "port": 0}},
  {"from": {"tag": "flatten_1", "port": 0}, "to": {"tag": "dense_layer_128", "port": 1}},
  {"from": {"tag": "activation_relu_3", "port": 0}, "to": {"tag": "dense_layer_128", "port": 0}},
  {"from": {"tag": "dense_layer_128", "port": 0}, "to": {"tag": "dense_layer_10", "port": 1}},
  {"from": {"tag": "dense_layer_10", "port": 0}, "to": {"tag": "softmax_1", "port": 0}},
  {"from": {"tag": "softmax_1", "port": 0}, "to": {"tag": "out_labels_digits", "port": 0}},
  {"from": {"tag": "load_dataset_mnist", "port": 0}, "to": {"tag": "train_begin_0", "port": 0}},
  {"from": {"tag": "train_begin_0", "port": 0}, "to": {"tag": "run_model_0", "port": 0}},
  {"from": {"tag": "model_mnist_cnn", "port": 0}, "to": {"tag": "run_model_0", "port": 1}},
  {"from": {"tag": "run_model_0", "port": 0}, "to": {"tag": "output_map_0", "port": 0}},
  {"from": {"tag": "output_map_0", "port": 0}, "to": {"tag": "train_step_0", "port": 0}}
]
</connect_ports>

<delete_nodes>
[]
</delete_nodes>

<disconnect_ports>
[]
</disconnect_ports>
"""
	var sock = {"cache": {}}
	var acts = parser.parse_stream_tags(sock, chunk)
	
	#for action in acts:
	#	for el in len(acts[action]):
	#		acts[action][el] = JSON.parse_string(acts[action][el])
	#("text, ", txt)
	parser.model_changes_apply(sock.cache.actions, txt)
	#var a = cookies.open_or_create("debug_changes.bin").get_var()
	#parser.model_changes_apply(a, "hi")

var multi_input: bool = false

func set_multi_input(boolean: bool):
	multi_input = boolean

func sock_end_life(chat_id: int, on_close: Callable, sock: SocketConnection):
	#(message_sockets[chat_id].cache.get("message", [""])[0])
	var txt = message_sockets[chat_id].cache.get("message", [""])[0]
	glob.update_chat_cache(str(chat_id), {"role": "ai", "text": txt})
	message_sockets.erase(chat_id)
	on_close.call()
	var acts = sock.cache.get("actions", {})
	
	#for action in acts:
	#	for el in len(acts[action]):
	#		acts[action][el] = JSON.parse_string(acts[action][el])
	#("text, ", txt)
	await glob.wait(0.5)
	#(txt)
	parser.model_changes_apply(acts, txt)
		#()


var last_summary_hash = -1


func splash_login(run_but: BlockComponent = null) -> bool:
	var m = func(): return glob.mouse_pressed
	var wait = func():
		if run_but:
			while m.call():
				await get_tree().process_frame
			run_but.unblock_input()
	if run_but:
		run_but.block_input()
	if !logged_in():
		var a = await ui.splash_and_get_result("login", run_but)
		await wait.call()
		if a: return true
	else:
		await wait.call()
		return true
	await wait.call()
	return false



func stable_json(val: Variant) -> String:
	# sort keys for Dictionaries
	match typeof(val):
		TYPE_DICTIONARY:
			var keys = val.keys()
			keys.sort()
			var parts = []
			for k in keys:
				parts.append('"%s":%s' % [str(k).json_escape(), stable_json(val[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var arr = []
			for v in val: arr.append(stable_json(v))
			return "[%s]" % ",".join(arr)
		_:
			return JSON.stringify(val, "", false, true)  # primitives

var last_summary_hash_by_project: Dictionary = {}  # key: String(project_id) -> String (sha256 hex)

# Helpers (put once in the same script):
func _stable_json(val: Variant) -> String:
	# Deterministic JSON: sort dict keys, no whitespace, full precision
	match typeof(val):
		TYPE_DICTIONARY:
			var keys = val.keys()
			keys.sort()
			var parts: Array[String] = []
			for k in keys:
				parts.append('"%s":%s' % [str(k).json_escape(), _stable_json(val[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var arr: Array[String] = []
			for v in val:
				arr.append(_stable_json(v))
			return "[%s]" % ",".join(arr)
		_:
			return JSON.stringify(val, "", false, true)

func _sha256_text(s: String) -> String:
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.to_utf8_buffer())
	return h.finish().hex_encode()


func unzip_to_temp_dir(zip_path: String) -> DirAccess:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		print("Failed to open ZIP: %s" % zip_path)
		return null

	# Create unique temp directory
	var temp_root := "user://tmp_zip_%d" % Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(temp_root)

	var dir := DirAccess.open(temp_root)
	if dir == null:
		reader.close()
		print("Failed to open temp dir: %s" % temp_root)
		return null

	# Extract files
	for file_path in reader.get_files():
		if file_path.ends_with("/"):
			dir.make_dir_recursive(file_path)
			continue

		var abs_path := temp_root.path_join(file_path)
		dir.make_dir_recursive(abs_path.get_base_dir())

		var file := FileAccess.open(abs_path, FileAccess.WRITE)
		if file == null:
			reader.close()
			print("Failed to write file: %s" % abs_path)
			return null
		
		#(reader.read_file(file_path).get_string_from_utf8())
		file.store_buffer(reader.read_file(file_path))

	reader.close()
	return dir





func update_message_stream(
	input_text: String,
	chat_id: int,
	text_update: Callable = def,
	on_close: Callable = def,
	clear: bool = false,
	user_id: int = 0,
	ai_id: int = 0
) -> SocketConnection:
	if chat_id in message_sockets:
		return

	var sock = await sockets.connect_to("ws/talk", def, cookies.get_auth_header())

	print(sock.is_listening())
	
	# --- 1. compute deterministic hash of current graph ---
	var summary = graphs.get_llm_summary()
	var summary_json = _stable_json(summary)
	var summary_hash = _sha256_text(summary_json)

	# --- 2. build payload with only hash first ---
	var payload = {
		"user": cookies.user(),
		"pass": cookies.pwd(),
		"chat_id": str(chat_id),
		"text": input_text,
		"_clear": "",
		"user_id": user_id,
		"ai_id": ai_id,
		"scene": str(get_project_id()),
		"summary_hash": summary_hash  # only hash first
	}
	
	print(payload)
	sock.send_json(payload)

	var sent_full = false

	sock.packet.connect(func(pkt):
		var s = pkt.get_string_from_utf8()
		var j = JSON.parse_string(s)

		if not j:
			push_warning("[ws/talk] Non-JSON packet: " + s)
			return

		# --- explicit backend errors / control packets ---
		if j.has("status") or j.has("error"):
			push_warning("[ws/talk] backend control/error packet: " + s)
			return

		# --- graceful close request ---
		if j.has("_close_request"):
			print("[ws/talk] backend requested graceful close")
			return

		# --- handshake phase ---
		if j.has("server_hash") or j.has("need_summary") or j.has("updated"):
			if j.get("updated", false):
				last_summary_hash = summary_hash
				return

			if j.get("need_summary", false) and not sent_full:
				var resend = payload.duplicate(true)
				resend["summary"] = summary
				resend["summary_hash"] = summary_hash
				sock.send_json(resend)
				sent_full = true
				last_summary_hash = summary_hash
				return

			return

		# --- normal chat stream ---
		message_chunk_received(pkt, sock)
	)

	message_sockets[chat_id] = sock
	sock.set_meta("text_update", text_update)
	sock.kill.connect(sock_end_life.bind(chat_id, on_close, sock))
	return sock




var cbox = preload("res://scenes/cbox.tscn")


func ask_once(input_text: String) -> String:
	var payload = {
		"text": input_text
	}
	
	# Using your web singleton for the POST request
	var resp = await web.JPOST("ask_once", payload, cookies.get_auth_header())
	
	if resp and resp.get("answer") == "ok":
		return resp.get("text", "")
		
	push_error("AI Request failed: " + str(resp))
	return ""



func get_my_message_state(chat_id: int, text_update: Callable = def) -> Array:
	if chat_id in message_sockets:
		var got = message_sockets[chat_id]
		got.set_meta("text_update", text_update)
		return [got, got.cache.get("message", [""])[0]]
	return [null, ""]


func clear_all():
	
	undo_redo.clear_history()
	last_summary_hash = -1
	for i in ui.splashed:
		if i.typename == "ai_help":
			i.clear_all()
	for i: SocketConnection in sockets._conns.keys():
		i.close()
		sockets._conns.erase(i)
	#tag_types.clear()
	#tags_1d.clear()
	#cached_chats.clear()


func clear_chats():
	cached_chats.clear()
	if ai_help_menu:
		ai_help_menu.clear_all()
		#ai_help_menu.re_recv()
var ai_help_menu: AIHelpMenu


func canvas_to_world(p: Vector2) -> Vector2:
	var vp = get_viewport()
	var total = vp.get_final_transform() * vp.get_canvas_transform()
	return total.affine_inverse() * (p)


func world_to_canvas(p: Vector2) -> Vector2:
	var vp = get_viewport()
	var total = vp.get_final_transform() * vp.get_canvas_transform()
	return total * p


var main_cam: GraphViewport
var env_dump = {}
var cached_projects = {}

func _apply_project_data(from: String, project_name: String, dat: Dictionary, clear_lesson: bool = false):
	return await _apply_project_payload(from, project_name, dat, {
		"clear_lesson": clear_lesson,
		"stop_lesson": true,
		"set_project_id": true,
		"emit_project_opened": true,
	})

func _apply_project_payload(from: String, project_name: String, dat: Dictionary, options: Dictionary = {}):
	if bool(options.get("clear_lesson", false)):
		learner.push_classroom_event({"on_lesson": -1})
	if bool(options.get("set_project_id", true)):
		project_id = int(from)
	else:
		project_id = int(options.get("project_id", project_id))
	cached_chats.clear()
	last_summary_hash = -1
	clear_chats()
	clear_all()
	loaded_project_once = true
	if bool(options.get("stop_lesson", true)):
		learner.stop_lesson()
	fg.go_into_graph()
	await graphs.delete_all()
	tree_windows["env"].reset()
	
	fg.set_scene_name(project_name)
	open_action_batch(true)
	#set_var("last_id", 0)
	var registry = dat.get("registry", {})
	var r = await graphs.load_graph(dat.get("graphs", {}), registry.get("subgraph_registry", {}))
	env_dump = dat.get("lua", {})
	tree_windows["env"].request_texts()
	if "camera" in dat and dat["camera"]:
		var camera = dat["camera"]
		main_cam.target_zoom = camera.z
		main_cam.target_position = Vector2(camera.x, camera.y)
	#else:
		main_cam.zoom = Vector2(camera.z, camera.z)
		main_cam.position = Vector2(camera.x, camera.y)
	else:
		pass

	for i in 15:
		await get_tree().process_frame
	if ai_help_menu:
		ai_help_menu.re_recv()
	set_var("last_id", project_id)
	await glob.wait(0.5)
	
	if bool(options.get("emit_project_opened", true)):
		project_opened.emit(from)
	close_action_batch()
	return true

func apply_lesson_project_blob(lesson_key: String, project_name: String, blob_base64: String):
	var raw := Marshalls.base64_to_raw(blob_base64)
	if raw.is_empty():
		push_error("Lesson auto-project '%s' has an empty project blob" % lesson_key)
		return false
	var dat = bytes_to_var(raw)
	if typeof(dat) != TYPE_DICTIONARY:
		push_error("Lesson auto-project '%s' did not decode to project data" % lesson_key)
		return false
	return await _apply_project_payload(str(lesson_key), project_name, dat, {
		"stop_lesson": false,
		"set_project_id": false,
		"project_id": -1,
		"emit_project_opened": false,
	})

func load_scene(from: String, clear_lesson: bool = false):
	set_multi_input(false)
	
	if LocalSave:
		var local_dat = _local_load_project_blob(from)
		if local_dat == null:
			return false
		var project_name = _local_project_name(from)
		if not project_name:
			project_name = "Project %s" % from
		return await _apply_project_data(from, project_name, local_dat, clear_lesson)
	var answer = await web.POST("project", {"scene": from, 
	 "user": cookies.user(), 
	"pass": cookies.pwd()})
	if not "body" in answer: return
	var a = JSON.parse_string(answer["body"].get_string_from_utf8())
	if not a: return
	if not "scene" in a: return
	var remote_dat = bytes_to_var(Marshalls.base64_to_raw(a["scene"]))
	if remote_dat == null: return
	return await _apply_project_data(from, a["name"], remote_dat, clear_lesson)



signal project_opened(who: String)
signal lesson_opened(who: String)
func load_lesson(from: String):
	#project_id = int(from)
	set_multi_input(false)
	await graphs.delete_all()
	cached_chats.clear()
	last_summary_hash = -1
	clear_chats()
	clear_all()
	project_id = -1
	loaded_project_once = true
	fg.go_into_graph()
	lesson_opened.emit(from)
	await graphs.delete_all()
	learner.enter_lesson(from)


var cached_chats = {}
func update_chat_cache(chat_id: String, update: Dictionary):
	var got = cached_chats.get_or_add(chat_id, [])
	if 0:#got and (got[-1].get("user", true) == false or got[-1].get("role", "user") != "user"):
		pass#got[-1] = (update)
	else:
		got.append(update)

func change_chat_cache(chat_id: String, update: Dictionary):
	cached_chats.get_or_add(chat_id, [])[-1] = update
	
func rem_chat_cache(chat_id: String):
	cached_chats.get_or_add(chat_id, []).remove_at(-1)

func _project_header_dict() -> Dictionary:
	var base = get_project_data()
	# Explicitly do NOT inline datasets here
	base.erase("datasets")
	return {
		"version": 1,
		"project": base,
		"name": fg.get_scene_name(),
		# Optional: embed env_dump if you want to lock the export to current env texts
		"env": env_dump
	}

func get_packed_ds(name: String) -> Dictionary:
	# If dataset was saved this session and not re-dirtied, use cached packed bytes
	if ds_pack_cache.has(name) and not dirty_datasets.has(name):
		return ds_pack_cache[name]

	# If dirty, we must ensure it is saved so the packed blob reflects latest Dict
	if dirty_datasets.has(name):
		# Serialize and persist synchronously through the existing save path
		# (join saves if a previous save is in flight)
		save_godot_dataset(dataset_datas[name])
		while ds_processing():
			await get_tree().process_frame
		dirty_datasets.erase(name)

	# Now read packed bytes from disk (fast, no decompress)
	var from_disk = _read_packed_ds_from_disk(name)
	if from_disk:
		ds_pack_cache[name] = from_disk
	return ds_pack_cache.get(name, {})

func _read_packed_ds_from_disk(name: String) -> Dictionary:
	var fname = "datasets/%s.ds" % sha1(name)
	var fa = FileAccess.open("user://" + fname, FileAccess.READ)
	if not fa:
		push_warning("Missing dataset file: %s" % fname)
		return {}

	if fa.get_length() <= 0:
		push_warning("Empty dataset file: %s" % fname)
		return {}

	var length_val = 0
	var compressed_val: PackedByteArray = PackedByteArray()

	# first var (length)
	if fa.get_position() < fa.get_length():
		length_val = int(fa.get_var())
	else:
		push_warning("Corrupted dataset file (no length): %s" % fname)
		return {}

	# second var (compressed data)
	if fa.get_position() < fa.get_length():
		var val = fa.get_var(true)
		if val == null or typeof(val) != TYPE_PACKED_BYTE_ARRAY:
			push_warning("Corrupted dataset file (no compressed bytes): %s" % fname)
			return {}
		compressed_val = val
	else:
		push_warning("Corrupted dataset file (truncated): %s" % fname)
		return {}

	return {"len": length_val, "bytes": compressed_val}


func preprocess_import_project(bytes: PackedByteArray) -> Dictionary:
	var result = {
		"ok": false,
		"header": {},
		"datasets": [],
		"errors": []
	}

	if bytes.is_empty():
		result.errors.append("Empty input buffer")
		return result

	var peer := StreamPeerBuffer.new()
	peer.data_array = bytes  # this resets cursor in StreamPeerBuffer :contentReference[oaicite:1]{index=1}

	var header = peer.get_var()
	if typeof(header) != TYPE_DICTIONARY:
		result.errors.append("Invalid header section")
		return result

	if peer.get_available_bytes() <= 0:
		result.errors.append("Missing dataset index section")
		return result

	var index_arr = peer.get_var()
	if typeof(index_arr) != TYPE_ARRAY:
		result.errors.append("Invalid dataset index section")
		return result

	var datasets: Array = []
	for i in index_arr.size():
		if peer.get_available_bytes() < 4:
			result.errors.append("Truncated dataset payload before entry %d" % i)
			break

		var blob_len: int = peer.get_u32()
		if blob_len <= 0 or peer.get_available_bytes() < blob_len:
			result.errors.append("Invalid length for dataset %d" % i)
			break

		var got := peer.get_data(blob_len) # [err, PackedByteArray] :contentReference[oaicite:2]{index=2}
		var err: int = got[0]
		if err != OK:
			result.errors.append("Failed reading dataset %d bytes (err=%d)" % [i, err])
			break

		var blob_bytes: PackedByteArray = got[1]

		var meta: Dictionary = index_arr[i].duplicate(true)
		meta["bytes"] = blob_bytes
		datasets.append(meta)

	result.ok = result.errors.is_empty()
	result.header = header
	result.datasets = datasets
	return result






func import_project(bytes: PackedByteArray) -> bool:
	# === 1. Parse the binary container ===
	var parsed = preprocess_import_project(bytes)
	#(parsed)
	if not parsed.ok:
		push_error("Import failed: " + ", ".join(parsed.errors))
		return false

	var header: Dictionary = parsed.header
	var datasets: Array = parsed.datasets
	if not header.has("project"):
		push_error("Invalid project container (no 'project' field).")
		return false

	# === 2. Extract main sections ===
	var project_meta: Dictionary = header.project
	var lua_env: Dictionary = header.get("env", {})
	var version: int = int(header.get("version", 1))
	project_id = random_project_id()

	# === 3. Full runtime clear (identical to load_scene) ===
	cached_chats.clear()
	clear_chats()
	clear_all()
	last_summary_hash = -1
	loaded_project_once = true
	fg.go_into_graph()
	for i in 10:
		await get_tree().process_frame
	await graphs.delete_all()
	tree_windows["env"].reset()

	for i in 10:
		await get_tree().process_frame
	# === 4. Write datasets ===
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var ds_dir = cookies.dir_or_create("datasets")
	for ds in datasets:
		var name: String = ds.get("name", "")
		if name.is_empty():
			continue

		var len: int = ds.get("len", 0)
		var bytes_zstd: PackedByteArray = ds.get("bytes", PackedByteArray())

		# Persist compressed dataset to disk (same format as save_godot_dataset)
		var spb = StreamPeerBuffer.new()
		spb.put_var(len)
		spb.put_var(bytes_zstd)
		var file_path = "datasets/%s.ds" % sha1(name)
		var f = cookies.open_or_create(file_path)
		f.store_buffer(spb.data_array)
		f.close()

		# Decompress + restore in memory
		var decomp = bytes_zstd.decompress(len, FileAccess.COMPRESSION_ZSTD)
		if decomp.is_empty():
			continue
		var ds_dict = bytes_to_var_with_objects(decomp)
		if not ds_dict:
			continue

		ds_dict["name"] = name
		dataset_datas[name] = ds_dict
		virtualt.cached_once[name] = true
		ds_pack_cache[name] = {"len": len, "bytes": bytes_zstd, "mtime": Time.get_ticks_msec()}
		cache_rle_compress(name, null, "thread")

	# === 5. Load environment and graphs ===
	env_dump = lua_env
	tree_windows["env"].request_texts()
	await get_tree().process_frame
	await get_tree().process_frame

	var graphs_data = project_meta.get("graphs", {})
	var subgraphs = project_meta.get("registry", {}).get("subgraph_registry", {})

	fg.set_scene_name(header.name)
	open_action_batch(true)
	var ok_graph = await graphs.load_graph(graphs_data, subgraphs)
	close_action_batch()
	await get_tree().process_frame

	if not ok_graph:
		push_warning("Graphs failed to load from imported project.")

	# === 6. Restore camera ===
	if project_meta.has("camera"):
		var camv: Vector3 = project_meta.camera
		if camv:
			main_cam.target_zoom = camv.z
			main_cam.target_position = Vector2(camv.x, camv.y)

	# === 7. UI and state sync ===
	for i in 15:
		await get_tree().process_frame
	if ai_help_menu:
		ai_help_menu.re_recv()

	set_var("last_id", project_id)
	await glob.wait(0.5)

	push_warning("Project import completed successfully.")
	return true


func import_project_from_file(path: String):
	var opened = FileAccess.open(path, FileAccess.READ)
	import_project(opened.get_buffer(opened.get_length()))
	await wait(0.1)
	ui.hourglass_on()
	await glob.save(str(glob.get_project_id()))
	ui.hourglass_off()


func export_project(include_contexts: bool = false) -> PackedByteArray:
	if include_contexts and not logged_in():
		return PackedByteArray() 

	await save_datasets()
	while ds_processing():
		await get_tree().process_frame
	await get_tree().process_frame

	var dset_names: Array[String] = []
	for gid in graphs._graphs:
		var node = graphs._graphs[gid]
		if node.server_typename == "DatasetName":
			var nm: String = node.cfg.get("name", "")
			if nm != "" and not dset_names.has(nm):
				dset_names.append(nm)

	var index: Array = []
	var payloads: Array = []
	for nm in dset_names:
		var packed = await get_packed_ds(nm)
		if packed and packed.has("bytes"):
			index.append({"name": nm, "sha1": sha1(nm), "len": int(packed.len)})
			payloads.append(packed.bytes)

	var buf = StreamPeerBuffer.new()
	buf.put_var(_project_header_dict())
	buf.put_var(index)

	for b in payloads:
		buf.put_u32(b.size())
		buf.put_data(b)

	return buf.data_array



func get_world_visible_rect() -> Rect2:
	var cam: Camera2D = glob.cam
	var viewport_size: Vector2 = cam.get_viewport().get_visible_rect().size

	# The world-space half extent is scaled by the inverse zoom.
	var half_extent = viewport_size * 0.5 / cam.zoom
	var top_left = cam.global_position - half_extent
	var rect_size = viewport_size / cam.zoom

	return Rect2(top_left, rect_size)


var remote_config = {}
var default_cfg_dict = {"teacher": false, "my_classroom": ""}
func set_remote_config(cfg):
	remote_config = default_cfg_dict.duplicate(true)
	remote_config.merge(cfg, true)

func rem_cfg(field: String):
	return remote_config.get(field)

func login(user: String, passw: String) -> Dictionary:
	var res := {
		"ok": false,
		"error": ""
	}

	var answer = await web.POST("login", {
		"user": user,
		"pass": passw
	})

	if not answer.ok:
		res.error = "network"
		return res

	var parsed = JSON.parse_string(answer.body.get_string_from_utf8())
	if parsed == null or not parsed.has("answer"):
		res.error = "protocol"
		return res
	set_remote_config(parsed.get("config", {}))
	if parsed.get("classroom_data", {}):
		learner.load_classroom_data(parsed["classroom_data"])
	#(learner.classroom_data)
	
	match parsed.answer:
		"ok":
			set_logged_in(user, passw)
			res.ok = true
		_:
			res.error = "auth"
	
	if cookies.profile("my_classroom"):
		learner.push_classroom_event({"on_lesson": -1})
	return res

func create_account(user: String, passw: String, cfg: Dictionary) -> Dictionary:
	var res := {
		"ok": false,
		"error": ""
	}

	var answer = await web.POST("create_user", {
		"user": user,
		"pass": passw,
		"config": cfg
	})
	set_remote_config(cfg)

	if not answer.ok:
		res.error = "network"
		return res

	var parsed = JSON.parse_string(answer.body.get_string_from_utf8())
	if parsed == null or not parsed.has("answer"):
		res.error = "protocol"
		return res

	match parsed.answer:
		"ok":
			set_logged_in(user, passw)
			res.ok = true
		"exists":
			res.error = "exists"
		_:
			res.error = "unknown"

	return res


func clear_chat(chat_id: int, req=true):
	last_summary_hash = -1
	cached_chats.get(str(chat_id), []).clear()
	if req:
		web.POST("clear_chat", {
			"chat_id": str(chat_id), 
			"scene": str(get_project_id())}, false, false, cookies.get_auth_header())

func request_chat(chat_id: String):
	var posted =  null
	#(cached_chats)
	if chat_id in cached_chats:
		posted = cached_chats[chat_id]
	else:
		var received = await web.POST("get_chat", {
		"chat_id": chat_id, 
		"scene": str(get_project_id())}, false, false, cookies.get_auth_header())
		if received and received.body:
			var json = JSON.parse_string(received.body.get_string_from_utf8())
			#(json)
			if json.has("messages"):
				cached_chats[chat_id] = json.messages
				posted = json.messages
			else:
				cached_chats[chat_id] = []
				posted = []
		else:
			cached_chats[chat_id] = []
			posted = []
	return posted


func load_empty_scene(pr_id: int, name: String):
	if 1:
		learner.push_classroom_event({"on_lesson": -1})
		learner.stop_lesson()
	fg.go_into_graph()
	cached_chats.clear()
	clear_chats()
	project_id = pr_id
	clear_all()
	set_var("last_id", project_id)
	tree_windows["env"].reset()
	loaded_project_once = true
	await graphs.delete_all()
	
	fg.set_scene_name(name)
	env_dump = {}
	tree_windows["env"].request_texts()

#func pull_scene_locally(from: String):
	#var old_var = cookies.open_or_create("scene_cache/%s.bin" % from).get_var()
	#

func save(from: String):
	if learner.active():
		return
	from = str(glob.get_project_id())
	await save_datasets()
	nn.request_save()
	var bytes = var_to_bytes(get_project_data())
	var contexts = Graph.get_ctx_groups().keys()
	var project_name = fg.get_scene_name()
	var last_id = ai_help_menu.get_last_id() if ai_help_menu else -1
	var chat_id = str(ai_help_menu.chat_id) if ai_help_menu else "0"
	if LocalSave:
		return _local_save_project_blob(from, bytes, project_name, contexts, last_id, chat_id)
	var blob = Marshalls.raw_to_base64(bytes)
	var acc = cookies.open_or_create("cached_projects/%s.scn" % from)
	acc.store_var(bytes)
	#("save...")
	#(Graph.get_ctx_groups().keys())
	#(get_project_data())
	return await web.POST("save", {"scene": from, 
	"blob": blob,
	"name": project_name,
	 "user": cookies.user(), 
	"last_id": last_id,
	"chat_id": chat_id,
	"contexts": contexts,
	"pass": cookies.pwd()})

func save_empty(from: String, name: String):
	nn.request_save()
	var bytes = var_to_bytes(get_project_data(true))
	if LocalSave:
		return _local_save_project_blob(from, bytes, name, [], -1, "0")
	var blob = Marshalls.raw_to_base64(bytes)
	var acc = cookies.open_or_create("cached_projects/%s.scn" % from)
	acc.store_var(bytes)
	return await web.POST("save", {"scene": from, 
	"blob": blob,
	"contexts": [],
	"name": name,
	"last_id": -1,
	"chat_id": "0",
	 "user": cookies.user(), 
	"pass": cookies.pwd()})


var action_batch = []

var is_redoing: bool = false
var is_undoing: bool = false
var stop_icon = preload("res://game_assets/icons/stop.png")
func is_auto_action() -> bool:
	return is_redoing or is_undoing

#func config_action(who: Graph, field: String):
	#pass

var selector_box: Control = null

func get_default_script(script_name: String):
	return """-- '%s'

function createScene()
	-- Scene is initialized here.
	-- Here you can create your objects, etc.
	print("Hello, Neuralese!")
end

function newFrame(delta)
	-- Per-frame work is done here
	-- "delta" is time since the last frame
end""" % script_name

func bound(callable: Callable, pos: Vector2, cfg: Dictionary, select: bool = true, forced_graph_id: int = -1):
	var args = callable.get_bound_arguments().duplicate()

	if args.size() < 2:
		push_error("Not enough bound args")
		return null

	args[1] = Graph.Flags.NONE

	var base: Callable = Callable()
	if callable.get_method() != "":
		base = Callable(callable.get_object(), callable.get_method())

	if not base.is_valid():
		return null

	var a: Graph = base.callv(args)

	if not is_instance_valid(a):
		return null

	a.position = pos
	a.update_config(cfg)

	if forced_graph_id != -1:
		if graphs._graphs.has(a.graph_id) and graphs._graphs[a.graph_id] == a:
			graphs._graphs.erase(a.graph_id)

		if graphs._graphs.has(forced_graph_id):
			var existing = graphs._graphs[forced_graph_id]
			if is_instance_valid(existing) and existing != a:
				existing.queue_free()

		a.graph_id = forced_graph_id
		graphs._graphs[forced_graph_id] = a

	if select:
		a.select()

	return a


signal ds_saved
func _ds_save_finish(nm, length, compressed):
	ds_pack_cache[nm] = {"len": length, "bytes": compressed, "mtime": Time.get_ticks_msec()}

	saving_thread.wait_to_finish()
	ds_saved.emit()
	threading = false

var rle_compressing: Dictionary = {}
var rle_cache = {}

var dirty_blocks = {}

func local_training_disables_dataset_stream_cache() -> bool:
	return FullyLocalConfigScript.TRAINING

# global state
func _comp_thread(dict: Dictionary, who: String, changed_rows: Array):
	var t = Time.get_ticks_msec()
	var comped: Dictionary
	if changed_rows.is_empty():
		comped = DsObjRLE.compress_blocks(dict)
	else:
		comped = DsObjRLE.recompress_changed_blocks(dict, changed_rows)
	call_deferred("_comp_finish", comped, who)
	#("threaded compress:", who, "took", Time.get_ticks_msec() - t, "ms")

func _comp_finish(dict: Dictionary, who: String):
	rle_cache[who] = dict
	rle_compressing.erase(who)
	_debug_compare_dataset_compression(who, dict)
	#("[cache] updated:", who, "rows=", dict["header"]["rows"])

func _debug_compare_dataset_compression(who: String, compressed: Dictionary) -> void:
	if not DatasetCompressionDebugScript.enabled():
		return
	if not dataset_datas.has(who):
		push_warning("[DatasetCompressionCompare] Dataset '%s' is no longer loaded." % who)
		return
	DatasetCompressionDebugScript.compare_async(who, dataset_datas[who], compressed)

func cache_rle_compress(who: String, changed_rows: Variant = null, mode: Variant = null):
	if local_training_disables_dataset_stream_cache():
		return
	# mode: "thread" (full rebuild), "suffix" (insert/delete threaded), "delta" (sync)
	var rows_arr: Array = []
	if changed_rows != null:
		if changed_rows is Array:
			rows_arr = changed_rows
		else:
			rows_arr = [changed_rows]
	# skip if nothing
	if rows_arr.is_empty() and mode == null:
		return

	var mode_str = ""
	if mode is bool and mode == true:
		mode_str = "suffix"
	elif typeof(mode) == TYPE_STRING:
		mode_str = mode
	else:
		mode_str = "delta"

	# --- FULL REBUILD (threaded)
	if mode_str == "thread":
		if who in rle_compressing: return
		rle_compressing[who] = true
		var dupped = dataset_datas[who]
		var thread = Thread.new()
		thread.start(_comp_thread.bind(dupped, who, []))  # <-- pass empty Array
		return

	# --- SUFFIX REBUILD (insert/delete)
	if mode_str == "suffix":
		if who in rle_compressing: return
		rle_compressing[who] = true
		var dupped = dataset_datas[who]
		var thread = Thread.new()
		thread.start(_comp_thread.bind(dupped, who, rows_arr))
		return

	# --- DELTA (fast, synchronous)
	var dupped = dataset_datas[who]
	var comped: Dictionary = DsObjRLE.recompress_changed_blocks(dupped, rows_arr)
	rle_cache[who] = comped
	_debug_compare_dataset_compression(who, comped)

	

	#rle_cache[who] = DsObjRLE.compress_and_send(dataset_datas[who])

var tweens = {}

class TweenSimple:
	signal finished
	var who: Object; var prop: String; var from; var to; var t; var total
	var is_finished: bool = false
	func poll(delta: float):
		t += delta
		if t > total - 0.008 or q_finish:
			is_finished = true
			finished.emit()
		who.set(prop, lerp(from, to, t / total))
	func _init(_who: Object, _prop: String, _from, _to, _t: float):
		who = _who; prop = _prop
		from = _from; to = _to; total = _t; t = 0.0
	var q_finish = false
	func finish():
		q_finish = true

const eps: float = 0.008



class TweenCall:
	signal finished
	var callb: Callable; var data: Dictionary
	var is_finished: bool = false
	var q_finish = false
	func poll(delta: float):
		if not callb.is_valid() or q_finish or callb.call(data, delta):
			is_finished = true; finished.emit()
	func _init(dt: Dictionary, cb : Callable):
		data = dt; callb = cb
	func finish():
		q_finish = true

func tween(who: Object, prop: String, from: Variant, to: Variant, t: float) -> bool:
	var obj = TweenSimple.new(who, prop, from, to, t)
	tweens[obj] = true
	await obj.finished
	return true

func tween_call(data: Dictionary, callb: Callable) -> bool:
	var obj = TweenCall.new(data, callb)
	if "write_into" in data:
		data.write_into[0] = obj
	tweens[obj] = true
	await obj.finished
	return true


func tween_call_obj(data: Dictionary, callb: Callable) -> TweenCall:
	var obj = TweenCall.new(data, callb)
	if "write_into" in data:
		data.write_into[0] = obj
	tweens[obj] = true
	return obj

func join_ds_processing():
	await join_ds_save()
	while rle_compressing.size() > 0:
		await get_tree().process_frame

func ds_processing() -> bool:
	return threading or rle_compressing.size() > 0

var virtualt: VirtualTable

func load_datasets():
	for i in cookies.dir_or_create("datasets").get_files():
		#(i)
		var opened = cookies.open_or_create("datasets/" + i)#.decompress(FileAccess.COMPRESSION_ZSTD)
		if not opened: continue
		var length = opened.get_var()
		var got = opened.get_var(true)
		if not got: continue
		var decomp = got.decompress(length, FileAccess.COMPRESSION_ZSTD)
		var ds = bytes_to_var_with_objects(decomp)
		#(ds)
		#(decomp)
		if ds:
			#var rle_comp = ds.get("rle_cached", {})
			#rle_cache[ds["name"]] = rle_comp
			#ds.erase("rle_cached")
			ds_dump[ds["name"]] = create_dataset(randi_range(0,999999999), ds["name"])
			dataset_datas[ds["name"]] = ds
			virtualt.cached_once[ds["name"]] = true
			cache_rle_compress(ds["name"], null, "thread")
	
func _save_worker(path: String, ds_obj, pre_bytes: bool = false):
	# ds_obj is the dataset Dictionary (not bytes)
	var bytes_to_store: PackedByteArray = ds_obj if pre_bytes else var_to_bytes_with_objects(ds_obj)

	var length: int = bytes_to_store.size()
	var compressed: PackedByteArray = bytes_to_store.compress(FileAccess.COMPRESSION_ZSTD)

	# Persist to disk (same format as before)
	var peer = StreamPeerBuffer.new()
	peer.put_var(length)
	peer.put_var(compressed)

	var ds = cookies.open_or_create(path)
	ds.store_buffer(peer.data_array)
	ds.close()

	# ---- NEW: update in-memory pack cache for export reuse
	#if typeof(ds_obj) == TYPE_DICTIONARY and ds_obj.has("name"):
	#	var nm: String = ds_obj.name
	#	ds_pack_cache[nm] = {"len": length, "bytes": compressed, "mtime": Time.get_ticks_msec()}

	_ds_save_finish.call_deferred(ds_obj.name, length, compressed, )

# Pack cache: name -> {"len": int, "bytes": PackedByteArray, "mtime": int}
var ds_pack_cache: Dictionary = {}


func join_ds_save():
	if threading and saving_thread.is_alive():
		#("awaa")
		await ds_saved
		saving_thread.wait_to_finish()


var saving_thread = Thread.new()
var threading: bool = false
func save_godot_dataset(ds_obj: Dictionary):
	var a = (ds_obj)
#	a["rle_cached"] = rle_cache.get(ds_obj.name, {})
	#("begin...")
	if threading and saving_thread.is_alive() and saving_thread.is_started():
		#("awaa")
		#("wait 1...")
		await ds_saved
		#("wait 2...")
		saving_thread.wait_to_finish()
	#("create...")
	saving_thread = Thread.new()
	threading = true
	#("start...")
	
	saving_thread.start(
	_save_worker.bind("datasets/"+sha1(ds_obj.name)+".ds", (a)))


func sha1(who: String):
	var crypto: HashingContext = HashingContext.new()
	var hash_bytes = crypto.start(HashingContext.HASH_SHA1)
	crypto.update(who.to_utf8_buffer())
	return crypto.finish().hex_encode()

func md5(who: String):
	var crypto: HashingContext = HashingContext.new()
	var hash_bytes = crypto.start(HashingContext.HASH_MD5)
	crypto.update(who.to_utf8_buffer())
	return crypto.finish().hex_encode()

var dirty_datasets = {}

func save_datasets(filter=null):
	while ds_processing():
		await get_tree().process_frame
	#(dirty_datasets)
	var todel = []
	for i in dataset_datas:
		if not dirty_datasets.has(i): continue
		if filter == null or i in filter:
			#(i)
			save_godot_dataset(dataset_datas[i])
			while ds_processing():
				await get_tree().process_frame
			todel.append(i)
	for i in todel:
		dirty_datasets.erase(i)

var ds_dump = {}
var dataset_datas = {}


signal ds_invalid(who: String)
func invalidate_local_ds(who: String):
	ds_invalid.emit(who)

signal ds_change(who: String)
func change_local_ds(who: String):
	#("AAAA")
	ds_change.emit(who)

func default_dataset() -> Dictionary:
	return {"arr": [[{"type": "text", "text": "Hello"}, 
							{"type": "num", "num": 0}]], "col_names": ["Input:text", "Output:num"],
							"outputs_from": 1, "col_args": [], "cache": {}}

func get_dataset_at(id: String):
	if not id in dataset_datas:
		dataset_datas[id] = default_dataset()
	dataset_datas[id]["name"] = id
	return dataset_datas[id]
func create_dataset(id: int, name: String, data = null):
	if data:
		dataset_datas[name] = data
	dirtify_dataset(name)
	return {"id": id, "content": {}, "name": name}

func dirtify_dataset(name: String):
	dirty_datasets[name] = true

func add_action(undo: Callable, redo: Callable, ...args):
	if is_auto_action(): return
	if batch_permanent: 
		return
	#(batch_permanent)
	#_stack()

	var undo_callable = func():
		is_undoing = true
		#(undo)
		if undo.is_valid():
			if args:
				undo.callv(args)
			else:
				undo.call()
		call_deferred("_end_auto_action", "undo")   # ← defer flag reset to next idle frame

	var redo_callable = func():
		is_redoing = true
		if redo.is_valid():
			if args:
				redo.callv(args)
			else:
				redo.call()
		call_deferred("_end_auto_action", "redo")   # ← defer flag reset

	#_stack()
	if in_batch:
		action_batch.append([redo_callable, undo_callable])
	else:
		undo_redo.create_action("Action")
		undo_redo.add_do_method(redo_callable)
		undo_redo.add_undo_method(undo_callable)
		undo_redo.commit_action(false)


func delay_close():
	await get_tree().process_frame
	await get_tree().process_frame
	close_action_batch()

func _end_auto_action(kind: String):
	if kind == "undo":
		is_undoing = false
	elif kind == "redo":
		is_redoing = false



var action_batch_depth: int = 0
var action_batch_permanent_stack: Array = []

var in_batch: bool = false
var batch_permanent: bool = false


func _refresh_batch_permanent() -> void:
	batch_permanent = false

	for permanent in action_batch_permanent_stack:
		if permanent:
			batch_permanent = true
			return


func open_action_batch(permanent: bool = false) -> void:
	if action_batch_depth == 0:
		action_batch.clear()

	action_batch_depth += 1
	action_batch_permanent_stack.append(permanent)

	in_batch = true
	_refresh_batch_permanent()


func close_action_batch() -> void:
	if action_batch_depth <= 0:
		in_batch = false
		batch_permanent = false
		action_batch_permanent_stack.clear()
		return

	action_batch_depth -= 1

	if not action_batch_permanent_stack.is_empty():
		action_batch_permanent_stack.pop_back()

	_refresh_batch_permanent()

	if action_batch_depth > 0:
		return

	var batch: Array = action_batch.duplicate()

	action_batch.clear()
	action_batch_permanent_stack.clear()
	in_batch = false
	batch_permanent = false

	if batch.is_empty():
		return

	undo_redo.create_action("Action")

	undo_redo.add_do_method(func():
		for i in batch:
			i[0].call()
	)

	undo_redo.add_undo_method(func():
		for idx in range(batch.size() - 1, -1, -1):
			batch[idx][1].call()
	)

	undo_redo.commit_action(false)



func close_action(owner):
	#("clos")
	var batch = action_batch.duplicate()
	undo_redo.add_do_method(func():
		for i in batch:
			i[0].call())
	undo_redo.add_undo_method(func():
		#("AA")
		for i in batch:
			i[1].call())
	action_batch.clear()
	undo_redo.commit_action(false)



func rget_children(from_root: Node) -> Array:
	var result: Array = []
	var stack: Array = [from_root]

	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for child in node.get_children(true):
			result.append(child)
			stack.append(child)

	return result


func create_conns(conns):
	#(conns)
	await get_tree().process_frame
	for i in conns:
		var from: Graph = graphs._graphs.get(i.from_id); var to: Graph = graphs._graphs.get(i.to_id)
		if not (from and to): continue
		if from.output_keys.has(i.from_port) and to.input_keys.has(i.to_port):
			from.output_keys[i.from_port].connect_to(to.input_keys[i.to_port])

func destroy_conns(conns):
	for i in conns:
		var from: Graph = graphs._graphs.get(i.from_id); var to: Graph = graphs._graphs.get(i.to_id)
		if not (from and to): continue
		if from.output_keys.has(i.from_port) and to.input_keys.has(i.to_port):
			from.output_keys[i.from_port].disconnect_from(to.input_keys[i.to_port])



func _window_scenes() -> Dictionary:
	return {
	"graph": $"../base/WIN_GRAPH",
	"env": loaded("res://scenes/env_tab.tscn"),
	"net": loaded("res://scenes/net_tab.tscn"),
	"ds": loaded("res://scenes/dataset_tab.tscn"),
	}

func connect_action(from: Connection, to: Connection):
	if not(from.reg_actions and to.reg_actions):
		return

	var from_id = from.parent_graph.graph_id
	var to_id = to.parent_graph.graph_id
	var from_port = from.hint
	var to_port = to.hint

	add_action(
		func():
			var f = graphs._graphs.get(from_id)
			var t = graphs._graphs.get(to_id)
			if is_instance_valid(f) and is_instance_valid(t):
				if f.output_keys.has(from_port) and t.input_keys.has(to_port):
					f.output_keys[from_port].disconnect_from(t.input_keys[to_port], true),
		func():
			var f = graphs._graphs.get(from_id)
			var t = graphs._graphs.get(to_id)
			if is_instance_valid(f) and is_instance_valid(t):
				if f.output_keys.has(from_port) and t.input_keys.has(to_port):
					f.output_keys[from_port].connect_to(t.input_keys[to_port], true)
	)


func disconnect_action(from: Connection, to: Connection):
	if not(from.reg_actions and to.reg_actions):
		return
	
	var from_id = from.parent_graph.graph_id
	var to_id = to.parent_graph.graph_id
	var from_port = from.hint
	var to_port = to.hint

	add_action(
		func():
			var f = graphs._graphs.get(from_id)
			var t = graphs._graphs.get(to_id)
			if is_instance_valid(f) and is_instance_valid(t):
				if f.output_keys.has(from_port) and t.input_keys.has(to_port):
					f.output_keys[from_port].connect_to(t.input_keys[to_port], true),
		func():
			var f = graphs._graphs.get(from_id)
			var t = graphs._graphs.get(to_id)
			if is_instance_valid(f) and is_instance_valid(t):
				if f.output_keys.has(from_port) and t.input_keys.has(to_port):
					f.output_keys[from_port].disconnect_from(t.input_keys[to_port], true)
	)


func reset_mouse():
	#mouse_alt_pressed = false
	mouse_just_pressed = false
	mouse_just_released = false
	#mouse_pressed = false


var space_begin: Vector2 = Vector2()
var space_end: Vector2 = DisplayServer.window_get_size()
var tree: SceneTree

func download_update(url: String):
	var exe_dir = OS.get_executable_path().get_base_dir()
	var path = exe_dir.path_join("Neuralese_new.exe")

	var offset := 0
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			offset = f.get_length()
			f.close()

	var headers = {}
	if offset > 0:
		headers["Range"] = "bytes=%d-" % offset

	var handle = web.GET(url, {}, false)
	handle.on_chunk.connect(func(chunk):
		var f = FileAccess.open(path, FileAccess.WRITE_READ)
		f.seek_end()
		f.store_buffer(chunk)
		f.close()
	)

	var result = await handle.completed
	if not result.ok:
		print("Update download failed")
		return

	print("Update downloaded")

const DEFAULT_MODEL_NAME: String = "__default_model__"
const AUTO_INPUT_INFERENCE_ENABLED: bool = true
const AUTO_INPUT_INFERENCE_DIAGNOSTICS: bool = true
var lan_ip = null

class Nothing:
	func _init():
		pass

class AsyncProcess:
	signal async_finished
	var is_done: bool = false
	var output = Nothing.new()
	var thread
	
	func _init():
		pass

	func finished(arg):
		print("finished req")
		thread.wait_to_finish()
		print("finished")
		is_done = true
		output = arg
		async_finished.emit(arg)
	
	func run(process: Callable):
		thread = Thread.new()
		thread.start(run_impl.bind(process))
		if !is_done:
			await async_finished
		return output
		
	
	func run_impl(process: Callable):
		print(process)
		var output = process.call()
		print(output)
		finished.call_deferred(output)
		
	
func run_async(callable: Callable, ...args):
	print("running async...")
	print(args)
	return await AsyncProcess.new().run(callable.bindv(args))
	

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	tree = get_tree()
	
	set_remote_config({})
	DisplayServer.window_set_min_size(Vector2(670,360))
	if DUMMY_LOGIN:
		dummy_login()
	
	graphs.spline_connected.connect(connect_action)
	#graphs.spline_disconnected.connect(disconnect_action)

	OS.low_processor_usage_mode = true
	splines_layer = CanvasLayer.new()
	splines_layer.layer = -124
	splines_layer.follow_viewport_enabled = true

	top_splines_layer = CanvasLayer.new()
	top_splines_layer.layer = 4
	top_splines_layer.follow_viewport_enabled = true
	
	get_tree().get_root().get_node("base/WIN_GRAPH").add_child(splines_layer)
	get_tree().get_root().get_node("base/WIN_GRAPH").add_child(top_splines_layer)
	
	await get_tree().process_frame
	_load_window_scenes = _window_scenes()
	go_window("graph")
	init_scene("")
	if NET_MODE == NetMode.LAN:
		lan_ip = load("res://scenes/lanpop.tscn").instantiate()
		base_node.add_child(lan_ip)
		var ip = await lan_ip.ip_entered
		set_var("lan_ip", ip)
		base_lan_ip = ip
		web.api_url = get_root_http()
		sockets.connection_prefix = get_root_ws()
	var upd = UpdateManager.new()
	add_child(upd)
	upd.check_update()
	
	if !DEBUG_RELOAD_LESSONS:
		await try_auto_login()
	#if _logged_in:

	load_datasets()
	if !DEBUG_RELOAD_LESSONS:
		await get_loaded_datasets()
	#(_load)
	#(load_dataset("mnist"))
	if (await request_projects()).size() == 0:
		set_var(BUILTIN_PROJECTS_IMPORTED_FLAG, false)
	_install_builtin_projects_once()
	if !DEBUG_RELOAD_LESSONS and LOAD_LAST_PROJECT:

		await open_last_project()
	#await wait(1)
	#test_place()
	ui.splash("ai_help", null, null, false, {"away": true})
	if DEBUG_RELOAD_LESSONS:
		await get_tree().process_frame
		learner.try_load_cached()
		learner.dbg_load_lesson("C:/Users/Mike/Desktop/lesson_bundle")
		learner.enter_lesson("neuro")
	

var scale_fg: CanvasLayer
func disconnect_all(from_signal: Signal):
	for i in from_signal.get_connections():
		from_signal.disconnect(i.callable)
