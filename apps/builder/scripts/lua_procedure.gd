class_name LuaProcRunner
extends Node

signal execution_finished
signal error_splashed

var lua: LuaAPI = null
var debug_printer: Callable = func(x): print(" ".join(x))

var time: float = 0.0
var delta: float = 0.0

var stopped: bool = false
var stopping: bool = false
var _script_done: bool = false

var frame_hz: float = 25.0
var _frame_interval: float = 1.0 / 25.0
var _accum_time: float = 0.0

var _lua_step = null

var auto_queue_free: bool = true

class LuaFuture:
	var _done: bool = false
	var _result = null

	func is_completed() -> bool:
		return _done

	func get_result() -> Variant:
		return _result

	func _complete(v: Variant) -> void:
		_done = true
		_result = v


func _init(name: String = "", code: String = "") -> void:
	if code != "":
		_pending_name = name
		_pending_code = code


var _pending_name: String = ""
var _pending_code: String = ""


func _ready() -> void:
	_frame_interval = 1.0 / max(frame_hz, 1.0)
	if _pending_code != "":
		start(_pending_name, _pending_code)


func _process(d: float) -> void:
	_accum_time += d
	if _accum_time < _frame_interval:
		return
	_accum_time -= _frame_interval

	if stopping or stopped:
		return

	_tick(_frame_interval)


func start(name: String, code: String) -> void:
	if stopping or stopped:
		return
	_init_lua_vm(name, code)


func stop() -> void:
	if stopping or stopped:
		return
	stopping = true

	await get_tree().process_frame
	if stopped:
		return
	stopped = true

	_lua_step = null
	_script_done = true

	if lua:
		var tmp = lua
		lua = null
		tmp = null

	execution_finished.emit()



func _safe_free() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		queue_free()


func _exit_tree() -> void:
	_lua_step = null
	lua = null


func _tick(dt: float) -> void:
	if not is_inside_tree() or lua == null:
		return
	if stopping or stopped:
		return

	if _lua_step != null:
		var r = _lua_step.call()
		if r is LuaError:
			_on_lua_error(r.message)
			return
		if typeof(r) == TYPE_STRING and r != "":
			_on_lua_error(str(r))
			return

	var had_error = lua.do_string("return __had_error")
	if had_error == true:
		if not _script_done:
			_script_done = true
			var last_err = lua.do_string("return __last_error")
			_on_lua_error(str(last_err))
		return

	var completed = lua.do_string("return __completed")
	if completed == true:
		if not _script_done:
			_script_done = true
			execution_finished.emit()
			if auto_queue_free:
				call_deferred("_safe_free")
			else:
				stop.call_deferred()
		return

	delta = dt
	time += dt


func _on_lua_error(msg: String) -> void:
	print_rich(msg)
	if debug_printer.is_valid():
		debug_printer.call(["[color=coral]" + msg + "[/color]"])
	error_splashed.emit()
	execution_finished.emit()
	stop.call_deferred()


func _init_lua_vm(name: String, code: String) -> void:
	var prelude := """
-- ============================================================================
-- LuaProcRunner Prelude (Lua 5.1-safe)
-- Pure-procedural execution: run chunk once in a coroutine, resume on ticks.
-- ============================================================================
local unpack = unpack or table.unpack

__last_error = nil
__had_error = false
__completed = false

local __user_chunk = nil

local function __safe_call(fn, ...)
  local args = { ... }
  local function wrapped()
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

local __main = coroutine.create(function()
  if __user_chunk then
    __user_chunk()
  end
  __completed = true
end)

function __step()
  if __had_error or __completed then return nil end
  if coroutine.status(__main) ~= 'dead' then
    local ok, err = coroutine.resume(__main)
    if not ok then
      __had_error = true
      __last_error = tostring(err)
      return __last_error
    end
  end
  if coroutine.status(__main) == 'dead' then
    __completed = true
  end
  return nil
end
"""

	lua = LuaAPI.new()
	lua.bind_libraries(["base", "table", "string", "math", "coroutine", "debug"])

	lua.push_variant("__gd_debug_print", func(...args): _debug_print(args))
	lua.do_string("function print(...) __gd_debug_print(...) end")

	_register_future_helpers()

	var err = lua.do_string(prelude)
	if err is LuaError:
		_on_lua_error("Prelude error: " + err.message)
		return

	lua.set_registry_value("__gd_call_bridge",
	func(reg_key: String, args: Variant) -> Variant:
		var cb: Callable = lua.get_registry_value(reg_key)
		if cb == null or not cb.is_valid():
			push_error("call_gd: bad callable for " + reg_key)
			return null

		var argv: Array = []

		if args is Array:
			argv = args
		elif args is Dictionary:
			# Lua {...} comes as Dictionary — preserve order by numeric keys
			var keys = args.keys()
			keys.sort()
			for k in keys:
				argv.append(args[k])
		elif args != null:
			argv = [args]

		var out = cb.callv(argv)

		var guard := 0
		while typeof(out) == TYPE_CALLABLE and guard < 8:
			if not out.is_valid():
				return null
			out = out.call()
			guard += 1

		return out
)


	var bridge_callable = lua.get_registry_value("__gd_call_bridge")
	lua.push_variant("__gd_call_bridge", bridge_callable)

	var err_bridge = lua.do_string("""
	function call_gd(reg_key, args)

		return __gd_call_bridge(reg_key, args)
	end
	""")
	if err_bridge is LuaError:
		_on_lua_error("Failed to define call_gd: " + err_bridge.message)
		return

	_expose_gd_to_lua()

	var err1 = lua.do_string("__set_user_src([[" + code + "]])")
	if err1 is LuaError:
		_on_lua_error(err1.message)
		return
	_lua_step = lua.pull_variant("__step")
	if _lua_step != null and _lua_step.is_valid():
		var r = _lua_step.call()
		if r is LuaError:
			_on_lua_error(r.message)
			return
		if typeof(r) == TYPE_STRING and r != "":
			_on_lua_error(str(r))
			return


func _register_future_helpers() -> void:
	lua.push_variant("future_is_completed", func(f): return f.is_completed())
	lua.push_variant("future_get_result", func(f): return f.get_result())


func _debug_print(args) -> void:
	if debug_printer.is_valid():
		debug_printer.call(args)


func _get_exposed_functions() -> Array[String]:
	var list: Array[String] = []
	for m in get_method_list():
		if m.name.begins_with("lua_") or m.name.begins_with("async_lua_"):
			list.append(m.name)
	return list


func _expose_gd_to_lua() -> void:
	for fn_name in _get_exposed_functions():
		if fn_name.begins_with("lua_"):
			lua.push_variant(fn_name.trim_prefix("lua_"), get(fn_name))
		elif fn_name.begins_with("async_lua_"):
			var clean_name = fn_name.trim_prefix("async_lua_")
			var callable_fn: Callable = get(fn_name)

			var reg_key = "__gd_callable_" + clean_name
			lua.set_registry_value(reg_key, callable_fn)

			var lua_stub = "function " + clean_name + "(...) " +\
				"\n local fut = call_gd('" + reg_key + "', {...}); " +\
				"\n if not fut then return {} end " +\
				"\n while not future_is_completed(fut) do coroutine.yield() end " +\
				"\n return future_get_result(fut) end"

			var err = lua.do_string(lua_stub)
			if err is LuaError:
				_on_lua_error("Failed to create Lua stub for " + clean_name + ": " + err.message)


func lua_get_time() -> float:
	return time

func lua_get_delta() -> float:
	return delta
