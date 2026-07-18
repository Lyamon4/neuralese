class_name LuaProcess
extends Node2D

const LUA_REQUIRED_LIBRARIES := ["base", "table", "string", "math", "coroutine", "debug"]
const LUA_VM_STARTUP_ATTEMPTS := 3

var lua: LuaAPI
var shapes: Array = []
var new_frame
var time := 0.0
var delta := 0.0

var methods = []
var physics_world: World2D
var _lua_coroutines: Array = []


class LuaFuture:
	var _done := false
	var _result = null
	func is_completed() -> bool: return _done
	func get_result() -> Variant: return _result
	func _complete(v: Variant) -> void:
		_done = true
		_result = v

var _accum_time: float = 0.0
var _frame_interval: float = 1.0 / 25.0 # 25 FPS

func _process(delta: float) -> void:
	# accumulate time and update Lua only every 0.04 sec
	_accum_time += delta
	if _accum_time < _frame_interval:
		return
	_accum_time -= _frame_interval
	if stopping or stopped:
		return

	# regular update tick
	update(_frame_interval)


func _register_future_helpers():
	lua.push_variant("future_is_completed", func(f): return f.is_completed())
	lua.push_variant("future_get_result", func(f): return f.get_result())

var _lua_step
var _lua_completed
var _lua_had_error
var _script_done := false
signal execution_finished
signal error_splashed

# -------------------------
# Auto-exposure helpers
# -------------------------
func _get_exposed_functions() -> Array[String]:
	var list: Array[String] = []
	for m in get_method_list():
		if m.name.begins_with("lua_") or m.name.begins_with("async_lua_"):
			list.append(m.name)
	return list

func _get_exposed_function_names() -> Array[String]:
	var list = _get_exposed_functions()
	for i in range(len(list)):
		list[i] = list[i].trim_prefix("lua_").trim_prefix("async_lua_")
	return list


func stepping() -> bool:
	return is_instance_valid(_lua_step)




func update(d: float):
	if not is_inside_tree() or lua == null:
		return
	if stopping or stopped:
		return
	#for i in model_qs:
	#	if i[1] != null and i[1] is not InferJob:
	#		pass
		#i = i[1]
		#var first = i.pop_front()
		#if first:
			#
	
	if _lua_step:
		#("Lua step valid:", _lua_step.is_valid(), " type:", typeof(_lua_step))

		var r = _lua_step.call()
		#(r)
		
		if r is LuaError:
			debug_printer.call(["[color=coral]" + r.message + "[/color]"])
			error_splashed.emit()
			execution_finished.emit()
			stop.call_deferred()
			_lua_step = null
			return

	if lua:
		var had_error = lua.do_string("return __had_error")
		if had_error == true:
			if not _script_done:
				_script_done = true
				error_splashed.emit()
				execution_finished.emit()
				stop.call_deferred()
				return

		var completed = lua.do_string("return __completed")
		if completed == true:
			if not _script_done:
				_script_done = true
				error_splashed.emit()
				execution_finished.emit()
				stop.call_deferred()
				return

	for i in range(_lua_coroutines.size() - 1, -1, -1):
		var c = _lua_coroutines[i]
		if c == null or (c.has_method("is_done") and c.is_done()):
			_lua_coroutines.remove_at(i)
		elif c.has_method("resume"):
			c.resume([])

	if stopped:
		return

	delta = d
	time += d

	if new_frame != null:
		var res = new_frame.call(d)
		if typeof(res) == TYPE_STRING and res != "":
			debug_printer.call(["[color=coral]" + res + "[/color]"])
			error_splashed.emit()
			execution_finished.emit()
			stop.call_deferred()
			return





func _physics_process(delta: float) -> void:
	for shape in shapes:
		if typeof(shape) != TYPE_DICTIONARY:
			continue
		if shape.get("physics_enabled", false) and shape.has("body"):
			var b = shape["body"]
			if not is_instance_valid(b):
				continue
			shape["x"] = b.position.x
			shape["y"] = b.position.y


func _draw() -> void:
	if stopped: return
	for shape in shapes:
		if shape == null: continue
		var pos = Vector2(shape["x"], shape["y"])
		var rot = float(shape.get("rotation", 0.0))
		draw_set_transform(pos, rot, Vector2.ONE)
		if shape["type"] == "circle":
			draw_circle(Vector2.ZERO, shape["r"], shape["color"])
		elif shape["type"] == "rect":
			draw_rect(Rect2(-shape["w"]/2, -shape["h"]/2, shape["w"], shape["h"]), shape["color"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
# -------------------------
# Lua API: creation
# -------------------------
func lua_Circle(x: float, y: float, r: float) -> int:
	var id = shapes.size()
	var shape = {
		"type": "circle",
		"x": x, "y": y,
		"r": r,
		"rotation": 0.0,
		"color": Color(1,1,1),
		"physics_enabled": false
	}
	shapes.append(shape)
	return id

func lua_Rectangle(x: float, y: float, w: float, h: float) -> int:
	var id = shapes.size()
	var shape = {
		"type": "rect",
		"x": x, "y": y,
		"w": w, "h": h,
		"rotation": 0.0,
		"color": Color(1,1,1),
		"physics_enabled": false
	}
	shapes.append(shape)
	return id

# -------------------------
# Lua API: physics
# -------------------------
func lua_enable_physics(id: int, enabled: bool) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if enabled and not s.get("physics_enabled", false):
		var body := RigidBody2D.new()
		var collider := CollisionShape2D.new()
		if s["type"] == "circle":
			var shape2d := CircleShape2D.new()
			shape2d.radius = s["r"]
			collider.shape = shape2d
		else:
			var shape2d := RectangleShape2D.new()
			shape2d.extents = Vector2(s["w"]/2, s["h"]/2)
			collider.shape = shape2d
		body.position = Vector2(s["x"], s["y"])
		body.add_child(collider)
		add_child(body)
		s["body"] = body
		s["physics_enabled"] = true
	elif not enabled and s.get("physics_enabled", false):
		if s.has("body"):
			s["body"].queue_free()
		s.erase("body")
		s["physics_enabled"] = false

func lua_apply_force(id: int, fx: float, fy: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		s["body"].apply_central_force(Vector2(fx, fy))

func lua_set_velocity(id: int, vx: float, vy: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		s["body"].linear_velocity = Vector2(vx, vy)

# -------------------------
# Lua API: helpers
# -------------------------
func lua_raycast(x1: float, y1: float, x2: float, y2: float) -> Dictionary:
	ray_params.from =  Vector2(x1,y1); ray_params.to = Vector2(x2,y2)
	var res = space_state.intersect_ray(ray_params)
	if res.is_empty():
		return {}
	return {"position": res.position, "collider": res.collider}

var ray_params: PhysicsRayQueryParameters2D
var point_params: PhysicsPointQueryParameters2D
@onready var space_state = get_world_2d().direct_space_state

var _pending_name
var _pending_code
var _debug_name := ""

func _init(name: String = "", code: String = ""):
	_pending_name = name
	_pending_code = code
	_debug_name = name
	# Only collect method list in _init when there's no code
	if code == "":
		methods = _get_exposed_function_names()

var _armed
func _ready():
	print("[LuaProcess] ready ", JSON.stringify({
		"id": get_instance_id(),
		"name": _debug_name,
		"has_code": _pending_code != "",
	}))
	physics_world = get_world_2d()
	point_params = PhysicsPointQueryParameters2D.new()
	ray_params = PhysicsRayQueryParameters2D.new()
	space_state = get_world_2d().direct_space_state

	if _pending_code != "":
		_init_lua_vm(_pending_name, _pending_code)
		_armed = true


func _lua_runtime_state() -> Dictionary:
	if lua == null:
		return {"ok": false, "error": "lua_null"}
	var result = lua.do_string("""
local c = coroutine
local d = debug
local ctype = type(c)
local dtype = type(d)
return {
  ok = (
	ctype == 'table'
	and type(c.create) == 'function'
	and type(c.resume) == 'function'
	and type(c.status) == 'function'
	and type(c.yield) == 'function'
	and dtype == 'table'
	and type(d.traceback) == 'function'
	and type(load) == 'function'
	and type(xpcall) == 'function'
  ),
  coroutine_type = ctype,
  coroutine_create_type = ctype == 'table' and type(c.create) or 'missing_table',
  coroutine_resume_type = ctype == 'table' and type(c.resume) or 'missing_table',
  coroutine_status_type = ctype == 'table' and type(c.status) or 'missing_table',
  coroutine_yield_type = ctype == 'table' and type(c.yield) or 'missing_table',
  debug_type = dtype,
  debug_traceback_type = dtype == 'table' and type(d.traceback) or 'missing_table',
  load_type = type(load),
  xpcall_type = type(xpcall),
  table_type = type(table),
  string_type = type(string),
  math_type = type(math),
}
""")
	if result is LuaError:
		return {"ok": false, "error": result.message}
	if result is Dictionary:
		return result
	return {"ok": result == true, "value_type": typeof(result), "value": str(result)}


func _report_lua_startup_error(message: String) -> void:
	printerr(message)
	if debug_printer.is_valid():
		debug_printer.call(["[color=coral]" + message + "[/color]"])


func _create_lua_vm_with_required_libraries() -> bool:
	for attempt in range(1, LUA_VM_STARTUP_ATTEMPTS + 1):
		lua = LuaAPI.new()
		lua.bind_libraries(LUA_REQUIRED_LIBRARIES)
		var state := _lua_runtime_state()
		if state.get("ok", false) == true:
			if attempt > 1:
				print("[LuaProcess] Lua libraries recovered after retry ", JSON.stringify({
					"id": get_instance_id(),
					"name": _debug_name,
					"attempt": attempt,
					"state": state,
				}))
			return true
		printerr("[LuaProcess] Lua library bind incomplete ", JSON.stringify({
			"id": get_instance_id(),
			"name": _debug_name,
			"attempt": attempt,
			"state": state,
		}))
		lua = null
	return false


func _init_lua_vm(name: String, code: String) -> void:
	var prelude := """
-- ============================================================================
-- LuaProcess Prelude (Lua 5.1-safe)
-- ============================================================================

local unpack = unpack or table.unpack
local __user_chunk = nil
__last_error = nil
__had_error = false
__completed = false

-- safe call wrapper that works in Lua 5.1
local function __safe_call(fn, ...)
  local args = { ... }          -- capture varargs manually
  local function wrapped()      -- inner closure reads from 'args'
    return fn(unpack(args))
  end
  return xpcall(wrapped, debug.traceback)
end

function __set_user_src(code)
  local fn, err = load(code)
  if not fn then
    __had_error = true
    __last_error = tostring(err)
	print('[color=coral]' .. __last_error .. '[/color]')
    return __last_error
  end
  __user_chunk = fn
end

-- Coroutine lifecycle ---------------------------------------------------------
local __main = coroutine.create(function()
  if __user_chunk then __user_chunk() end
  local has_newframe = (type(newFrame) == 'function')
  if not has_newframe then
    __completed = true
  end
end)

function __step()
  if __had_error or __completed then return nil end
  if coroutine.status(__main) ~= 'dead' then
    local ok, err = coroutine.resume(__main)
    if not ok then
      __had_error = true
      __last_error = tostring(err)
	  --print('[lua runtime error]\\n' .. __last_error)
      return __last_error
    end
  end
  if coroutine.status(__main) == 'dead' and not (type(newFrame) == 'function') then
    __completed = true
  end
  return nil
end

-- protected newFrame
function __call_newFrame(dt)
  if __had_error or __completed then return __last_error end
  local nf = rawget(_G, 'newFrame')
  if type(nf) ~= 'function' then return nil end
  local ok, res = __safe_call(nf, dt)
  if not ok then
    __had_error = true
    __last_error = tostring(res)
	--print('[lua runtime error in newFrame]\\n' .. __last_error)
    return __last_error
  end
  return nil
end

function __call_createScene()
  local cs = rawget(_G, 'createScene')
  if type(cs) ~= 'function' then return nil end
  local ok, res = __safe_call(cs)
  if not ok then
    __had_error = true
    __last_error = tostring(res)
	--print('[lua runtime error in createScene]\\n' .. __last_error)
    return __last_error
  end
  return nil
end

"""



	if not _create_lua_vm_with_required_libraries():
		_report_lua_startup_error("[LuaProcess] Failed to initialize Lua VM with required libraries: " + JSON.stringify({
			"id": get_instance_id(),
			"name": name,
			"attempts": LUA_VM_STARTUP_ATTEMPTS,
		}))
		error_splashed.emit()
		execution_finished.emit()
		stop.call_deferred()
		return

	lua.push_variant("__gd_debug_print", func(...args): _debug_print(args))
	lua.do_string("function print(...) __gd_debug_print(...) end")

	_register_future_helpers()

	var err = lua.do_string(prelude)
	if err is LuaError:
		_report_lua_startup_error("[LuaProcess] Prelude error: " + err.message + " runtime_state=" + JSON.stringify(_lua_runtime_state()))
		error_splashed.emit()
		execution_finished.emit()
		stop.call_deferred()
		return

	_expose_gd_to_lua()

# 2) Load user code (syntax only)
	var err1 = lua.do_string("__set_user_src([[" + code + "]])")
	if err1 is LuaError:
		debug_printer.call(["[color=coral]" + err1.message + "[/color]"])
		error_splashed.emit(); execution_finished.emit()
		stop.call_deferred()
		return

	# 3) Pull __step and PRIME ONCE so the chunk defines globals
	_lua_step = lua.pull_variant("__step")
	if _lua_step != null and _lua_step.is_valid():
		var r = _lua_step.call()
		if r is LuaError:
			debug_printer.call(["[color=coral]" + r.message + "[/color]"])
			error_splashed.emit(); execution_finished.emit()
			stop.call_deferred()
			return

	var frame_fn = lua.pull_variant("__call_newFrame")
	var create_scene = lua.pull_variant("__call_createScene")

	new_frame = frame_fn if typeof(frame_fn) == TYPE_CALLABLE else null
	if create_scene != null and typeof(create_scene) == TYPE_CALLABLE:
		call_deferred("_call_lua_ready", create_scene)
	else:
		new_frame = frame_fn if typeof(frame_fn) == TYPE_CALLABLE else null

	_lua_step = lua.pull_variant("__step")

	lua.set_registry_value("__gd_call_bridge", func(reg_key: String, args: Array) -> Variant:
		var cb: Callable = lua.get_registry_value(reg_key)
		if cb == null or not cb.is_valid():
			printerr("[LuaBridge] invalid callable for ", reg_key)
			return {"_error":"bad_callable"}
		var out
		var ok := true
		# Guard callv
		if cb.is_valid():
			# Use a try-like pattern
			# (Godot doesn’t have try/catch in GDScript; rely on defensive checks)
			out = cb.callv(args)
		else:
			ok = false
		if not ok:
			return {"_error":"call_failed"}
		var guard := 0
		while typeof(out) == TYPE_CALLABLE and guard < 8:
			if not out.is_valid():
				return {"_error":"nested_callable_invalid"}
			out = out.call()
			guard += 1
		if typeof(out) == TYPE_CALLABLE:
			return {"_error":"callable_after_guard"}
		return out
	)


	var bridge_callable = lua.get_registry_value("__gd_call_bridge")
	lua.push_variant("__gd_call_bridge", bridge_callable)

	var err2 = lua.do_string("""
	function call_gd(reg_key, args)
		return __gd_call_bridge(reg_key, args)
	end
	""")
	if err2 is LuaError:
		printerr("Failed to define call_gd:", err.message)

	#_expose_gd_to_lua()

	call_deferred("_after_vm_ready")



func _after_vm_ready():
	pass

func _call_lua_ready(fn: Callable) -> void:
	if fn == null:
		return
	var result = fn.call([])
	if result is LuaError:
		debug_printer.call(["[color=coral]" + result.message + "[/color]"])
		error_splashed.emit()
		execution_finished.emit()
		stop()
		_lua_step = null



func _expose_gd_to_lua():
	for fn_name in _get_exposed_functions():
		if fn_name.begins_with("lua_"):
			lua.push_variant(fn_name.trim_prefix("lua_"), get(fn_name))
		elif fn_name.begins_with("async_lua_"):
			var clean_name := fn_name.trim_prefix("async_lua_")
			var callable_fn: Callable = get(fn_name)

			var reg_key := "__gd_callable_" + clean_name
			lua.set_registry_value(reg_key, callable_fn)

			var lua_stub := "function " + clean_name + "(...) " +\
				"\n local fut = call_gd('" + reg_key + "', {...}); " +\
				"\n if not fut then return {} end " +\
				"\n while not future_is_completed(fut) do coroutine.yield() end " +\
				"\n return future_get_result(fut) end"

			var err = lua.do_string(lua_stub)
			if err is LuaError:
				printerr("Failed to create Lua stub for " + clean_name + ": " + err.message)



func lua_overlap_point(x: float, y: float) -> bool:
	point_params.position = Vector2(x,y)
	var res = space_state.intersect_point(point_params)
	return res.size() > 0

func lua_move(id: int, dx: float, dy: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false):
		if s.has("body"):
			s["body"].position += Vector2(dx, dy)
	else:
		s["x"] += dx
		s["y"] += dy

func lua_set_pos(id: int, x: float, y: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false):
		if s.has("body"):
			s["body"].position = Vector2(x, y)
	else:
		s["x"] = x
		s["y"] = y

func lua_set_color(id: int, r: float, g: float, b: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	s["color"] = Color(r,g,b)

func lua_set_size(id: int, s: float) -> void:
	var sh = _get_shape(id)
	if sh.is_empty(): return
	if sh["type"] == "circle":
		sh["r"] = float(sh["r"]) * s
	else:
		sh["w"] = float(sh["w"]) * s
		sh["h"] = float(sh["h"]) * s

func lua_delete(id: int) -> void:
	if id < 0 or id >= shapes.size(): return
	var s = shapes[id]
	if typeof(s) == TYPE_DICTIONARY and s.get("physics_enabled", false) and s.has("body"):
		var b = s["body"]
		s["body"] = null
		if is_instance_valid(b): b.queue_free()
	shapes[id] = null


func lua_set_x(id: int, x: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		var pos = s["body"].position
		s["body"].position = Vector2(x, pos.y)
	else:
		s["x"] = x

func lua_set_y(id: int, y: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		var pos = s["body"].position
		s["body"].position = Vector2(pos.x, y)
	else:
		s["y"] = y


func lua_get_x(id: int) -> float:
	var s = _get_shape(id)
	return float(s["x"]) if not s.is_empty() else 0.0

func lua_get_y(id: int) -> float:
	var s = _get_shape(id)
	return float(s["y"]) if not s.is_empty() else 0.0

func lua_get_width(id: int) -> float:
	var s = _get_shape(id)
	if s.is_empty(): return 0.0
	return float(s["w"]) if s["type"] == "rect" else float(s["r"]) * 2.0

func lua_get_height(id: int) -> float:
	var s = _get_shape(id)
	if s.is_empty(): return 0.0
	return float(s["h"]) if s["type"] == "rect" else float(s["r"]) * 2.0

func lua_get_radius(id: int) -> float:
	var s = _get_shape(id)
	return float(s["r"]) if (not s.is_empty() and s.has("r")) else 0.0

func lua_get_color(id: int) -> Dictionary:
	var s = _get_shape(id)
	if s.is_empty(): return {"r":0,"g":0,"b":0}
	var c: Color = s["color"]
	return {"r": c.r, "g": c.g, "b": c.b}

func lua_get_key(keyname: String) -> bool:
	if InputMap.has_action(keyname):
		return Input.is_action_pressed(keyname)
	match keyname:
		"left": return Input.is_key_pressed(KEY_LEFT)
		"right": return Input.is_key_pressed(KEY_RIGHT)
		"up": return Input.is_key_pressed(KEY_UP)
		"down": return Input.is_key_pressed(KEY_DOWN)
		"space": return Input.is_key_pressed(KEY_SPACE)
		"mouse_left": return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		"mouse_right": return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		_: return false

func lua_get_mouse_pos() -> Dictionary:
	var p: Vector2 = glob.get_global_mouse_position()
	return {"x": p.x, "y": -p.y}


# -------------------------
# Inference
# -------------------------

var model_qs = {}
var _infer_channel_leases: Dictionary = {}

func _model_can_run_without_login(node: Graph) -> bool:
	return nn.validate_infer_channel(node)

func _missing_remote_login_for_model(node: Graph) -> bool:
	return not cookies.get_auth_header() and not _model_can_run_without_login(node)

func _wait_infer_open_ready(open_res) -> void:
	if open_res == null:
		return
	if open_res is bool and open_res == false:
		return
	if open_res is Object:
		if open_res.has_signal("ack"):
			await open_res.ack
			return
		if open_res.has_signal("connected"):
			await open_res.connected
			return
	await get_tree().process_frame


func _infer_lease_owner(name: String) -> String:
	return "lua:%s:%s" % [str(get_instance_id()), name]


func _acquire_lua_infer_channel(node: Graph, name: String) -> void:
	if not is_instance_valid(node):
		return
	var owner := _infer_lease_owner(name)
	if owner in _infer_channel_leases:
		return
	if nn.acquire_infer_channel_lease(node, owner):
		_infer_channel_leases[owner] = node
		print("[LuaProcess] inference lease acquired ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
			"owner": owner,
			"node": str(node),
		}))


func _release_lua_infer_channel_leases() -> void:
	for owner in _infer_channel_leases.keys():
		var node = _infer_channel_leases[owner]
		if is_instance_valid(node):
			nn.release_infer_channel_lease(node, str(owner))
	_infer_channel_leases.clear()


# --- add back the opener ---
func enq_open_model(node: Graph, name: String) -> void:
	print("[LuaProcess] deferred open_model requested ", JSON.stringify({
		"id": get_instance_id(),
		"process": _debug_name,
		"model": name,
		"node": str(node) if is_instance_valid(node) else "<invalid>",
		"already_open": nn.is_infer_channel(node) if is_instance_valid(node) else false,
	}))
	_acquire_lua_infer_channel(node, name)
	if not await nn.wait_infer_channel_idle(node, _infer_lease_owner(name)):
		print("[LuaProcess] deferred open_model failed: channel did not become idle ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
		}))
		return
	created_models[name] = true
	var open_res = await nn.open_infer_channel(node, node.close_runner)
	if not open_res:
		print("[LuaProcess] deferred open_model failed ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
		}))
		return
	await _wait_infer_open_ready(open_res)

	# ensure queue shape and mark idle
	var q = model_qs.get(name, null)
	if q == null:
		q = [node, null, false, false, null] # [node, slot, has_unread, in_flight, pending]
	else:
		q[0] = node
		while q.size() < 5: q.append(null)
		q[2] = false
		q[3] = false
	model_qs[name] = q

	# if Lua pushed something while we were opening — start it now
	if q[4] != null and not q[3]:
		var useful = node.useful_properties()
		useful["raw_values"] = q[4]
		q[4] = null
		var job := InferJob.new()
		q[1] = job
		q[2] = false
		q[3] = true
		model_qs[name] = q
		infer_job.call_deferred(name, node, useful, job)


func async_lua_open_model(name: String) -> LuaFuture:
	var f := LuaFuture.new()
	_open_model_task(name, f)
	return f

func _open_model_task(name: String, fut: LuaFuture) -> void:
	print("[LuaProcess] open_model requested ", JSON.stringify({
		"id": get_instance_id(),
		"process": _debug_name,
		"model": name,
	}))
	var node = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)
	if node == null:
		print("[LuaProcess] open_model failed: no default model node ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
		}))
		fut._complete({"ok": false, "_error":"no_node"})
		return
	_acquire_lua_infer_channel(node, name)
	if not await nn.wait_infer_channel_idle(node, _infer_lease_owner(name)):
		fut._complete({"ok": false, "_error":"channel_busy"})
		return

	# ensure q-shape [node, slot, has_unread, in_flight, pending, ready]
	var q = model_qs.get(name, null)
	if q == null:
		q = [node, null, false, false, null, false]
	else:
		q[0] = node
		while q.size() < 6: q.append(false) # index 5 = ready
	model_qs[name] = q

	# Already open & valid? Mark ready and return
	if nn.is_infer_channel(node) and nn.validate_infer_channel(node):
		print("[LuaProcess] open_model reused existing inference channel ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
			"node": str(node),
		}))
		q[5] = true
		model_qs[name] = q
		fut._complete({"ok": true})
		return

	# Open the channel and wait for whichever readiness primitive the backend exposes.
	# Remote websocket channels expose `ack`; FullyLocal channels are file-backed and do not.
	var open_res = await nn.open_infer_channel(node, node.close_runner)
	created_models[name] = true
	if not open_res:
		print("[LuaProcess] open_model failed: open_infer_channel returned false ", JSON.stringify({
			"id": get_instance_id(),
			"process": _debug_name,
			"model": name,
			"node": str(node),
		}))
		fut._complete({"ok": false, "_error":"invalid_graph"})
		return

	await _wait_infer_open_ready(open_res)

	# Small grace to avoid race on slow links (optional but robust)
	await glob.wait(0.1)

	q = model_qs.get(name, q)
	while q.size() < 6: q.append(false)
	q[5] = true  # ready
	model_qs[name] = q

	# If caller pushed something prematurely, do one ordered flush now
	if q[4] != null and not q[3]:
		var useful = q[0].useful_properties()
		useful["raw_values"] = q[4]
		q[4] = null
		var job := InferJob.new()
		q[1] = job
		q[2] = false
		q[3] = true
		model_qs[name] = q
		infer_job.call_deferred(name, q[0], useful, job)

	fut._complete({"ok": true})


		#var open_res = await nn.open_infer_channel(node, node.close_runner)


func _ensure_qshape(name: String):
	if not (name in model_qs):
		return
	var q = model_qs[name]
	while q.size() < 5:
		q.append(null) # fill [3],[4]
	# normalize types
	if typeof(q[2]) != TYPE_BOOL: q[2] = false
	if typeof(q[3]) != TYPE_BOOL: q[3] = false
	model_qs[name] = q

func lua_push_model(name: String, input: Array):
	#(input)
	if not (name in model_qs): return {"_error":"model_not_started"}
	_ensure_qshape(name)
	var q = model_qs[name]
	var node = q[0]
	if node == null: return {"_error":"no_node"}
	if _missing_remote_login_for_model(node): return {"_error":"no_login", "type": -1, "repr": ""}

	if not nn.validate_infer_channel(node):
		if not nn.is_infer_channel(node):
			enq_open_model.call_deferred(node, name)
		q[4] = input
		model_qs[name] = q
		return {}

	if q[3]:
		q[4] = input
		model_qs[name] = q
		return {}

	# start new job immediately
	var useful = node.useful_properties()
	useful["raw_values"] = input
	var job := InferJob.new()
	q[1] = job
	q[2] = false
	q[3] = true
	q[4] = null
	model_qs[name] = q
	infer_job.call_deferred(name, node, useful, job)
	return {}

	#if not nn.is_infer_channel(node):

func lua_can_pull_model(name: String):
#	print(model_qs)
	return name in model_qs and model_qs[name][1] != null and not model_qs[name][1] is InferJob

func lua_pull_model(name: String):
	var node
	if name in model_qs:
		node = model_qs[name][0]
	else:
		return {"_error":"model_not_started", "result": []}
	if node == null:
		return {"_error":"no_node"}
	if _missing_remote_login_for_model(node):
		return {"_error":"no_login", "type": -1, "repr": "", "result": []}
	if not nn.validate_infer_channel(node):
		return {"_error": "graph_invalid", "result": []}
	#(model_qs)
	if model_qs[name][1] != null and not model_qs[name][1] is InferJob:
		model_qs[name][2] = false
		#(model_qs[name][1])
		return {"result": model_qs[name][1]}
	return {"result": []}
	#if not nn.is_infer_channel(node):

class InferJob:
	signal finished

func infer_job(name, node, useful, job: InferJob):
	if not await nn.wait_infer_channel_idle(node, _infer_lease_owner(name)):
		var q_busy = model_qs.get(name, null)
		if q_busy != null:
			q_busy[1] = {"_error": "channel_busy", "result": []}
			q_busy[2] = true
			q_busy[3] = false
			model_qs[name] = q_busy
		job.finished.emit()
		return
	var result = await nn.send_inference_data(node, useful, true)
	#(result)
	var q = model_qs.get(name, null)
	if q == null:
		return

	# keep the original shape so Lua's: out.result.LabelGroup works
	if typeof(result) != TYPE_DICTIONARY:
		result = {"_error": "bad_type", "repr": str(result)}

	q[1] = result   # <-- RAW
	q[2] = true     # has_unread
	q[3] = false    # in_flight
	model_qs[name] = q
	#(model_qs)
	job.finished.emit()

	# if Lua pushed a newer input while we were running → run it now
	#if q[4] != null:
		#var next_input = q[4]
		#q[4] = null
		#var useful2 = node.useful_properties()
		#useful2["raw_values"] = next_input
		#var job2 := InferJob.new()
		#q[1] = job2
		#q[2] = false
		#q[3] = true
		#model_qs[name] = q
		#infer_job.call_deferred(name, node, useful2, job2)



func async_lua_run_model(name: String, input: Array) -> LuaFuture:
	var f := LuaFuture.new()
	_call_inference(name, input, f)
	return f

var debug_printer: Callable = Callable()

func _debug_print(args) -> void:
	debug_printer.call(args)




func _call_inference(name: String, input: Array, fut: LuaFuture) -> void:
	_call_inference_task(name, input, fut)


func _exit_tree() -> void:
	_release_lua_infer_channel_leases()
	if lua:
		lua = null
	_lua_step = null
	new_frame = null
	_lua_coroutines.clear()


func _call_inference_task(name: String, input: Array, fut: LuaFuture) -> void:
	var node = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)
	if node == null:
		fut._complete({"_error":"no_node", "result": []})
		return
	_acquire_lua_infer_channel(node, name)
	if not await nn.wait_infer_channel_idle(node, _infer_lease_owner(name)):
		fut._complete({"_error":"channel_busy", "type": -1, "repr": "", "result": []})
		return

	var useful = node.useful_properties()
	useful["raw_values"] = input
	if _missing_remote_login_for_model(node):
		fut._complete({"_error":"no_login", "type": -1, "repr": "", "result": []})
		return

	if not nn.is_infer_channel(node):
		var open_res = await nn.open_infer_channel(node, node.close_runner)
		created_models[name] = true
		if not open_res:
			fut._complete({"_error":"invalid_graph", "type": -1, "repr": "", "result": []})
			return
		#await open_res.connected
		#while not open_res.is_listening():
		#	await get_tree().process_frame
		await _wait_infer_open_ready(open_res)
		await glob.wait(0.3)

	var result = await nn.send_inference_data(node, useful, true)

	if typeof(result) != TYPE_DICTIONARY:
		result = {"_error":"bad_type", "type": typeof(result), "repr": str(result), "result": []}
	else:
		result = {"result": result}
	fut._complete(result)




# -------------------------
# Timing + control
# -------------------------
func lua_get_time() -> float:
	return time

func lua_get_delta() -> float:
	return delta

func lua_clear() -> void:
	for s in shapes:
		if typeof(s) == TYPE_DICTIONARY and s.get("physics_enabled", false) and s.has("body"):
			var b = s["body"]
			s["body"] = null
			if is_instance_valid(b): b.queue_free()
	shapes.clear()

var stopped: bool = false

var created_models: Dictionary = {}
var stopping: bool = false

func stop() -> void:
	if stopping or stopped:
		print("[LuaProcess] duplicate stop ignored ", JSON.stringify({
			"id": get_instance_id(),
			"name": _debug_name,
			"stopping": stopping,
			"stopped": stopped,
		}))
		return
	stopping = true
	print("[LuaProcess] stop requested ", JSON.stringify({
		"id": get_instance_id(),
		"name": _debug_name,
		"created_models": created_models.keys(),
		"inference_channels": nn.infer_channels().size(),
		"inside_tree": is_inside_tree(),
	}))

	# stop logic is async-safe now
	await get_tree().process_frame

	if stopped:
		print("[LuaProcess] stop resumed after already stopped ", JSON.stringify({
			"id": get_instance_id(),
			"name": _debug_name,
		}))
		return
	stopped = true
	print("[LuaProcess] stop finalizing ", JSON.stringify({
		"id": get_instance_id(),
		"name": _debug_name,
		"created_models": created_models.keys(),
		"inference_channels": nn.infer_channels().size(),
	}))

	# --- freeze all further Lua steps ---
	if _lua_step:
		_lua_step = null
	if new_frame:
		new_frame = null

	# --- safely clear Lua VM ---
	if lua:
		var tmp = lua
		lua = null
		tmp = null

	# --- cancel any coroutines still hanging ---
	for c in _lua_coroutines:
		if c and c.has_method("close"):
			c.close()
	_lua_coroutines.clear()

	# --- close inference channels safely ---
	#print(created_models)
	#for node in nn.infer_channels().duplicate():
		#var node = graphs.get_input_graph_by_name(glob.DEFAULT_MODEL_NAME)
	#	nn.close_infer_channel(node)
	_release_lua_infer_channel_leases()
	created_models.clear()

	# --- clean up physics bodies ---
	for s in shapes:
		if typeof(s) == TYPE_DICTIONARY and s.get("physics_enabled", false):
			var b = s.get("body")
			if is_instance_valid(b):
				b.queue_free()
	shapes.clear()

	# --- final deferred self-free to prevent mid-call freeing ---
	call_deferred("_safe_free")


func _safe_free():
	# if UI or signal callbacks still reference this node, wait another frame
	await get_tree().process_frame
	if is_inside_tree():
		queue_free()


func lua_set_rotation(id: int, angle: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		s["body"].rotation = angle
	else:
		s["rotation"] = angle

func lua_get_rotation(id: int) -> float:
	var s = _get_shape(id)
	return float(s.get("rotation", 0.0)) if not s.is_empty() else 0.0

func lua_rotate(id: int, angle: float) -> void:
	var s = _get_shape(id)
	if s.is_empty(): return
	if s.get("physics_enabled", false) and s.has("body"):
		s["body"].rotation += angle
	else:
		s["rotation"] = float(s.get("rotation", 0.0)) + angle


# -------------------------
# Helpers
# -------------------------
func _get_shape(id: int) -> Dictionary:
	if id < 0 or id >= shapes.size(): return {}
	var s = shapes[id]
	if s == null: return {}
	return s
