extends Node
class_name Cookies

const cookie_file = "user://cookies.json"
const CLERK_ACCESS_TOKEN_COOKIE = "clerk_access_token"
const CLERK_REFRESH_TOKEN_COOKIE = "clerk_refresh_token"
const CLERK_USER_COOKIE = "clerk_user"
const NEURALESE_PROFILE_COOKIE = "neuralese_profile"
const CLERK_PROVIDER = "clerk"

signal clerk_login_started(payload: Dictionary)
signal clerk_login_completed(session: Dictionary)
signal clerk_login_failed(error: Dictionary)
signal user_profile_updated(profile: Dictionary)

var _cookies: Dictionary = {}
var clerk_auth_base_url: String = ""

func _ready() -> void:
	cookies.set_clerk_auth_base_url(glob.get_root_http().trim_suffix("/"))
	_load_cookies()
	
	#test tab: dont remove.
	#await glob.wait(0.9)
	#glob.go_window("net")
	
	#test_login()

func test_login():
	cookies.set_clerk_auth_base_url("http://127.0.0.1:8081")
	var result = await cookies.clerk_login(true)
	print(result)

func get_auth_header() -> Dictionary:
	if has_clerk_session():
		var compat = get_legacy_auth_pair()
		compat.merge({
			"Authorization": "Bearer %s" % get_clerk_access_token(),
			"X-Neuralese-Auth-Provider": CLERK_PROVIDER,
			"X-Neuralese-User": user(),
			"X-Neuralese-Clerk-User": get_clerk_user_id(),
		}, true)
		return compat
	return glob._logged_in

func get_bearer_auth_header() -> Dictionary:
	if not has_clerk_session():
		return {}
	return {"Authorization": "Bearer %s" % get_clerk_access_token()}

func refreshed_auth_headers(headers: Dictionary) -> Dictionary:
	var out := headers.duplicate(true)
	if has_clerk_session() and out.has("Authorization"):
		out["Authorization"] = "Bearer %s" % get_clerk_access_token()
	return out

func get_legacy_auth_pair() -> Dictionary:
	return {
		"user": user(),
		"pass": pwd(),
	}

func set_profile(field: String, val):
	var cfg = glob.remote_config if typeof(glob.remote_config) == TYPE_DICTIONARY else {}
	cfg[field] = val
	glob.set_remote_config(cfg)

	if has_clerk_session():
		var neuralese_profile = get_neuralese_profile()
		if typeof(neuralese_profile) != TYPE_DICTIONARY:
			neuralese_profile = {}
		neuralese_profile[field] = val
		set_cookie(NEURALESE_PROFILE_COOKIE, JSON.stringify(neuralese_profile))
		if typeof(glob._logged_in) == TYPE_DICTIONARY and glob._logged_in.get("auth_provider", "") == CLERK_PROVIDER:
			var session_profile = glob._logged_in.get("profile", {})
			if typeof(session_profile) != TYPE_DICTIONARY:
				session_profile = {}
			session_profile[field] = val
			glob._logged_in["profile"] = session_profile
			glob.set_var("credentials", glob._logged_in)

func profile(field: String):
	#if field == "my_classroom": return "111111"
	if has_clerk_session():
		var neuralese_profile = get_neuralese_profile()
		if field == "teacher":
			return str(neuralese_profile.get("type", "")).strip_edges().to_lower() == "teacher"
		if neuralese_profile.has(field):
			return neuralese_profile.get(field)
	return glob.remote_config.get(field)

var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)

func get_username() -> String:
	if has_clerk_session():
		return get_display_identity()
	return glob._logged_in.get("user", "")

func get_pass() -> String:
	return glob._logged_in.get("pass", "")

func user() -> String:
	if has_clerk_session():
		return get_display_identity()
	return glob._logged_in.get("user", "") if glob._logged_in else ""

func pwd() -> String:
	return glob._logged_in.get("pass", "") if glob._logged_in else ""

func set_clerk_auth_base_url(url: String) -> void:
	clerk_auth_base_url = url.strip_edges().trim_suffix("/")

func get_clerk_auth_base_url() -> String:
	if clerk_auth_base_url.strip_edges() != "":
		return clerk_auth_base_url.strip_edges().trim_suffix("/")
	return glob.get_root_http().trim_suffix("/")

func has_clerk_session() -> bool:
	return has_cookie(CLERK_ACCESS_TOKEN_COOKIE)

func get_clerk_access_token() -> String:
	return str(_cookies.get(CLERK_ACCESS_TOKEN_COOKIE, ""))

func get_clerk_refresh_token() -> String:
	return str(_cookies.get(CLERK_REFRESH_TOKEN_COOKIE, ""))

func get_clerk_user() -> Dictionary:
	var raw = str(_cookies.get(CLERK_USER_COOKIE, ""))
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func get_clerk_user_id() -> String:
	var user_info = get_clerk_user()
	return str(user_info.get("id", user_info.get("clerk_user_id", "")))

func get_clerk_display_name() -> String:
	var user_info = get_clerk_user()
	var display = str(user_info.get("display_name", "")).strip_edges()
	if display != "":
		return display
	var email = str(user_info.get("email", "")).strip_edges()
	if email != "":
		return email
	return get_clerk_user_id()

func get_neuralese_profile() -> Dictionary:
	var raw = str(_cookies.get(NEURALESE_PROFILE_COOKIE, ""))
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func get_profile_username() -> String:
	return str(get_neuralese_profile().get("username", "")).strip_edges()

func get_display_identity() -> String:
	var username = get_profile_username()
	if username != "":
		return username
	return get_clerk_display_name()

func restore_clerk_session(saved: Dictionary = {}) -> bool:
	var session = saved if not saved.is_empty() else {}
	if not session.get("access_token", ""):
		session = _session_from_clerk_cookies()
	if not session.get("access_token", ""):
		return false
	_apply_auth_session(session, true)
	return true

func restore_or_refresh_clerk_session(saved: Dictionary = {}) -> bool:
	if not restore_clerk_session(saved):
		return false
	var validation = await clerk_validate_session()
	if validation.get("ok", false):
		if validation.has("profile"):
			_apply_user_profile(validation.get("profile", {}), true)
		return true
	var refreshed = await clerk_refresh_session()
	if refreshed.get("ok", false):
		return true
	if _should_clear_clerk_session_for_error(refreshed):
		clear_clerk_session(false)
	return false

func clerk_login_cached_or_browser(open_browser: bool = true, ttl_seconds: int = 300, wait_timeout_seconds: int = 90) -> Dictionary:
	if await restore_or_refresh_clerk_session():
		var session = _session_from_clerk_cookies()
		clerk_login_completed.emit(session)
		return {
			"ok": true,
			"cached": true,
			"session": session,
		}
	return await clerk_login(open_browser, ttl_seconds, wait_timeout_seconds)

func clear_clerk_session(reset_glob: bool = true) -> void:
	delete_cookie(CLERK_ACCESS_TOKEN_COOKIE)
	delete_cookie(CLERK_REFRESH_TOKEN_COOKIE)
	delete_cookie(CLERK_USER_COOKIE)
	delete_cookie(NEURALESE_PROFILE_COOKIE)
	var cfg = glob.remote_config if typeof(glob.remote_config) == TYPE_DICTIONARY else {}
	cfg["teacher"] = false
	cfg["my_classroom"] = ""
	glob.set_remote_config(cfg)
	if reset_glob and glob._logged_in.get("auth_provider", "") == CLERK_PROVIDER:
		glob.reset_logged_in(true)

func clerk_start_login(ttl_seconds: int = 300) -> Dictionary:
	var body = {"ttl_seconds": ttl_seconds}
	var res = await _clerk_json_request(
		"POST",
		"/api/auth/device/start",
		body
	)
	if res.get("ok", false):
		clerk_login_started.emit(res)
	else:
		clerk_login_failed.emit(res)
	return res

func clerk_open_login_url(login_url: String) -> int:
	if login_url.strip_edges() == "":
		return ERR_INVALID_PARAMETER
	return OS.shell_open(login_url)

func clerk_wait_login(attempt_id: String, device_secret: String, timeout_seconds: int = 90) -> Dictionary:
	var path = "/api/auth/device/wait?attempt_id=%s&timeout=%s" % [
		attempt_id.uri_encode(),
		str(timeout_seconds).uri_encode()
	]
	return await _clerk_json_request(
		"GET",
		path,
		{},
		{"Authorization": "Device %s" % device_secret}
	)

func clerk_cancel_login(attempt_id: String, device_secret: String) -> Dictionary:
	return await _clerk_json_request(
		"POST",
		"/api/auth/device/cancel",
		{"attempt_id": attempt_id},
		{"Authorization": "Device %s" % device_secret}
	)

func clerk_refresh_session() -> Dictionary:
	var refresh_token = get_clerk_refresh_token()
	if refresh_token == "":
		var missing = {"ok": false, "error": "missing refresh token"}
		clerk_login_failed.emit(missing)
		return missing
	var result = await _clerk_json_request(
		"POST",
		"/api/auth/refresh",
		{"refresh_token": refresh_token}
	)
	if not result.get("ok", false):
		if _should_clear_clerk_session_for_error(result):
			clear_clerk_session(false)
		clerk_login_failed.emit(result)
		return result
	var session = _session_from_clerk_result(result)
	if not session.get("access_token", ""):
		var invalid = {"ok": false, "error": "refresh response missing access token", "result": result}
		clerk_login_failed.emit(invalid)
		return invalid
	_apply_auth_session(session, true)
	clerk_login_completed.emit(session)
	return {"ok": true, "session": session, "result": result}

func _should_clear_clerk_session_for_error(result: Dictionary) -> bool:
	var http_code = int(result.get("http_code", 0))
	if http_code == 401 or http_code == 403:
		return true
	var error_text = str(result.get("error", result.get("message", ""))).to_lower()
	return (
		error_text.find("invalid token") != -1
		or error_text.find("signature") != -1
		or error_text.find("expired") != -1
		or error_text.find("revoked") != -1
		or error_text.find("refresh") != -1 and error_text.find("invalid") != -1
	)

func clerk_validate_session() -> Dictionary:
	if not has_clerk_session():
		return {"ok": false, "error": "missing session"}
	return await _clerk_json_request(
		"GET",
		"/api/auth/me",
		{},
		get_bearer_auth_header()
	)

func get_user_profile() -> Dictionary:
	if not has_clerk_session():
		return {"ok": false, "error": "missing session"}
	var result = await _clerk_json_request(
		"GET",
		"/api/users/me",
		{},
		get_bearer_auth_header()
	)
	if result.get("ok", false):
		_apply_user_profile(result.get("profile", {}), true)
	return result

func needs_username() -> bool:
	var profile = get_neuralese_profile()
	return profile.is_empty() or str(profile.get("username", "")) == ""

func check_username_available(username: String) -> Dictionary:
	if not has_clerk_session():
		return {"ok": false, "error": "missing session"}
	return await _clerk_json_request(
		"GET",
		"/api/users/username-available?username=%s" % username.uri_encode(),
		{},
		get_bearer_auth_header()
	)

func claim_username(username: String) -> Dictionary:
	if not has_clerk_session():
		return {"ok": false, "error": "missing session"}
	var result = await _clerk_json_request(
		"POST",
		"/api/users/claim-username",
		{"username": username},
		get_bearer_auth_header()
	)
	if result.get("ok", false):
		_apply_user_profile(result.get("profile", {}), true)
	return result

func clerk_apply_login_result(result: Dictionary, persist: bool = true) -> Dictionary:
	if not result.get("ok", false):
		var err = {"ok": false, "error": result.get("error", "login failed"), "result": result}
		clerk_login_failed.emit(err)
		return err

	var status = str(result.get("status", ""))
	if status not in ["complete", "completed"]:
		var pending = {"ok": false, "error": "login not complete", "status": status, "result": result}
		if status in ["cancelled", "expired", "error"]:
			clerk_login_failed.emit(pending)
		if status == "signed_out":
			clear_clerk_session(true)
			clerk_login_failed.emit(pending)
		return pending

	var session = _session_from_clerk_result(result)
	if not session.get("access_token", ""):
		var missing = {"ok": false, "error": "missing access token", "result": result}
		clerk_login_failed.emit(missing)
		return missing

	_apply_auth_session(session, persist)
	clerk_login_completed.emit(session)
	return {"ok": true, "session": session}

func clerk_login(open_browser: bool = true, ttl_seconds: int = 300, wait_timeout_seconds: int = 90) -> Dictionary:
	var started = await clerk_start_login(ttl_seconds)
	if not started.get("ok", false):
		return started

	if open_browser:
		var open_err = clerk_open_login_url(str(started.get("login_url", "")))
		if open_err != OK:
			var err = {"ok": false, "error": "could not open browser", "code": open_err, "start": started}
			clerk_login_failed.emit(err)
			return err

	var waited = await clerk_wait_login_until_complete(
		str(started.get("attempt_id", "")),
		str(started.get("device_secret", "")),
		int(started.get("expires_in", ttl_seconds)),
		wait_timeout_seconds
	)
	if not waited.get("ok", false):
		clerk_login_failed.emit(waited)
		return waited

	var applied = clerk_apply_login_result(waited)
	if not applied.get("ok", false):
		return applied
	return {
		"ok": true,
		"start": started,
		"wait": waited,
		"session": applied.get("session", {})
	}

func clerk_wait_login_until_complete(attempt_id: String, device_secret: String, expires_in_seconds: int = 300, wait_timeout_seconds: int = 90) -> Dictionary:
	var deadline_msec = Time.get_ticks_msec() + max(30, expires_in_seconds) * 1000
	var wait_slice = min(max(10, wait_timeout_seconds), 45)
	var last_result: Dictionary = {}

	while Time.get_ticks_msec() < deadline_msec:
		var waited = await clerk_wait_login(attempt_id, device_secret, wait_slice)
		last_result = waited
		if waited.get("ok", false):
			var status = str(waited.get("status", ""))
			if status == "complete" or status == "completed" or status == "signed_out" or status == "cancelled" or status == "expired" or status == "error":
				return waited
		var http_code = int(waited.get("http_code", 0))
		var error_text = str(waited.get("error", "")).to_lower()
		if http_code == 503 and error_text.find("timeout") != -1:
			continue
		if not waited.get("ok", false) and http_code != 503:
			return waited

	return {
		"ok": false,
		"error": "login attempt timed out",
		"status": "expired",
		"result": last_result,
	}

func open_or_create(path: String, path_from: String = "user://") -> FileAccess:
	if not path_from.ends_with("/"):
		path_from += "/"
	var full_path = path_from + path
	var dir_path = full_path.get_base_dir()
	#(full_path)

	var dir := DirAccess.open(path_from)
	if dir and not dir.dir_exists(dir_path):
		var err = dir.make_dir_recursive(dir_path)
		if err != OK:
			push_error("Failed to create directory: %s" % dir_path)
			return null
	var file = FileAccess.open(full_path, FileAccess.READ_WRITE)
	if file:
		return file
	file = FileAccess.open(full_path, FileAccess.WRITE_READ)
	if not file:
		push_error("Failed to open or create file: %s" % full_path)
		return null
	return file

signal sandbox_projects_page_started(payload: Dictionary)
signal sandbox_projects_page_loaded(payload: Dictionary)
signal sandbox_projects_page_failed(error: Dictionary)

var _sandbox_projects_cursor: int = 0
var _sandbox_projects_total: int = 0
var _sandbox_projects_loading: bool = false
var _sandbox_projects_source_mode: String = "generated"

func reset_sandbox_projects_feed(total_count: int = 1000, source_mode: String = "generated") -> void:
	_sandbox_projects_cursor = 0
	_sandbox_projects_total = max(0, total_count)
	_sandbox_projects_loading = false
	_sandbox_projects_source_mode = source_mode


func has_more_sandbox_projects() -> bool:
	return _sandbox_projects_cursor < _sandbox_projects_total


func is_sandbox_projects_loading() -> bool:
	return _sandbox_projects_loading


func request_sandbox_projects_page(page_size: int = 24, cursor: String = "", simulated_delay_seconds: float = 0.12, filters: Dictionary = {}) -> Dictionary:
	if _sandbox_projects_loading:
		var busy_error = {
			"ok": false,
			"error": "sandbox projects request already in progress",
			"busy": true,
		}
		sandbox_projects_page_failed.emit(busy_error)
		return busy_error

	var safe_page_size = max(1, page_size)
	var resolved_cursor = _resolve_sandbox_projects_cursor(cursor)

	if resolved_cursor >= _sandbox_projects_total:
		var empty_payload = {
			"ok": true,
			"items": [],
			"cursor": str(resolved_cursor),
			"next_cursor": str(resolved_cursor),
			"has_more": false,
			"total": _sandbox_projects_total,
			"count": 0,
			"filters": filters,
			"source": _sandbox_projects_source_mode,
		}
		sandbox_projects_page_loaded.emit(empty_payload)
		return empty_payload

	_sandbox_projects_loading = true

	sandbox_projects_page_started.emit({
		"cursor": str(resolved_cursor),
		"requested_count": safe_page_size,
		"filters": filters,
		"source": _sandbox_projects_source_mode,
	})

	var result = await _download_sandbox_projects_page(
		resolved_cursor,
		safe_page_size,
		simulated_delay_seconds,
		filters
	)

	_sandbox_projects_loading = false

	if not result.get("ok", false):
		sandbox_projects_page_failed.emit(result)
		return result

	_sandbox_projects_cursor = int(result.get("next_cursor", _sandbox_projects_cursor))
	sandbox_projects_page_loaded.emit(result)

	return result


func _resolve_sandbox_projects_cursor(cursor: String) -> int:
	var clean_cursor = cursor.strip_edges()

	if clean_cursor == "":
		return _sandbox_projects_cursor

	if not clean_cursor.is_valid_int():
		return _sandbox_projects_cursor

	return clamp(int(clean_cursor), 0, _sandbox_projects_total)


func _download_sandbox_projects_page(start_cursor: int, page_size: int, simulated_delay_seconds: float, filters: Dictionary) -> Dictionary:
	# Later replace this function body with a real web._request().
	# Keep request_sandbox_projects_page() and its payload format unchanged.

	if simulated_delay_seconds > 0.0:
		await get_tree().create_timer(simulated_delay_seconds).timeout

	var end_cursor = min(start_cursor + page_size, _sandbox_projects_total)
	var items: Array = []

	for i in range(start_cursor, end_cursor):
		items.append(_generate_sandbox_project(i, filters))

	return {
		"ok": true,
		"items": items,
		"cursor": str(start_cursor),
		"next_cursor": str(end_cursor),
		"has_more": end_cursor < _sandbox_projects_total,
		"total": _sandbox_projects_total,
		"count": items.size(),
		"filters": filters,
		"source": _sandbox_projects_source_mode,
	}


func _generate_sandbox_project(index: int, filters: Dictionary = {}) -> Dictionary:
	var templates = [
		{
			"slug": "car_track_ai",
			"name": "Car Track AI",
			"short_description": "Train a tiny model to steer around a procedural racing track.",
			"tags": ["Cars", "Beginner", "Inference"],
		},
		{
			"slug": "mnist_lab",
			"name": "Digit Classifier Lab",
			"short_description": "Build and train a neural net to classify handwritten digits.",
			"tags": ["Vision", "Dataset", "Training"],
		},
		{
			"slug": "predator_prey_sim",
			"name": "Predator-Prey Sim",
			"short_description": "Experiment with agents, sensors, rewards, and survival behavior.",
			"tags": ["Agents", "RL", "Simulation"],
		},
		{
			"slug": "gesture_ai",
			"name": "Gesture AI",
			"short_description": "Classify simple hand gestures using a compact visual model.",
			"tags": ["Vision", "Classifier", "Interactive"],
		},
		{
			"slug": "maze_solver",
			"name": "Maze Solver",
			"short_description": "Teach a model to navigate mazes with limited sensor inputs.",
			"tags": ["Navigation", "Planning", "Sensors"],
		},
		{
			"slug": "sound_classifier",
			"name": "Sound Classifier",
			"short_description": "Build a small model that recognizes simple audio patterns.",
			"tags": ["Audio", "Signals", "Classifier"],
		},
	]

	var template: Dictionary = templates[index % templates.size()]
	var tags: Array = template.get("tags", []).duplicate(true)

	var feed = str(filters.get("feed", "community"))

	if feed == "featured":
		tags.append("Featured")
		tags.append("Neuralese Team")
	elif index % 7 == 0:
		tags.append("Featured")

	var owner = "Neuralese Team" if feed == "featured" or index % 5 == 0 else get_username()

	return {
		"id": "%s_%04d" % [str(template.get("slug", "sandbox")), index],
		"name": "%s #%d" % [str(template.get("name", "Sandbox")), index + 1],
		"short_description": str(template.get("short_description", "")),
		"tags": tags,
		"owner": owner,
		"feed": feed,
		"project_index": index,
	}





func dir_or_create(path: String) -> DirAccess:
	var full_path = "user://" + path
	
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("Cannot open user://")
		return null
	
	if not dir.dir_exists(path):
		var err = dir.make_dir_recursive(path)
		if err != OK:
			push_error("Failed to create directory: %s" % full_path)
			return null
	
	return DirAccess.open(full_path)


func _save_cookies() -> void:
	var f = FileAccess.open(cookie_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_cookies, "", true, true))
		f.close()

func set_cookie(name: String, value: String) -> void:
	_cookies[name] = value
	_save_cookies()

func has_cookie(name: String) -> bool:
	return _cookies.has(name)

func delete_cookie(name: String) -> void:
	if _cookies.has(name):
		_cookies.erase(name)
		_save_cookies()

func _load_cookies() -> void:
	if not FileAccess.file_exists(cookie_file):
		return
	var f = FileAccess.open(cookie_file, FileAccess.READ)
	if f:
		var txt = f.get_as_text().strip_edges()
		f.close()
		if txt != "":
			var parsed = JSON.parse_string(txt)
			if typeof(parsed) == TYPE_DICTIONARY:
				_cookies = parsed

func update_from_headers(headers: PackedStringArray) -> void:
	for h in headers:
		var lower = h.to_lower()
		if lower.begins_with("set-cookie:"):
			var cookie_str = h.substr(12).strip_edges()
			_parse_cookie(cookie_str)
	_save_cookies()

func _parse_cookie(cookie_str: String) -> void:
	var parts = cookie_str.split(";")[0].split("=")
	if parts.size() == 2:
		var name = parts[0].strip_edges()
		var value = parts[1].strip_edges()
		_cookies[name] = value

func get_header() -> String:
	if _cookies.is_empty():
		return ""
	var list: Array[String] = []
	for n in _cookies.keys():
		list.append("%s=%s" % [n, _cookies[n]])
	return "Cookie: " + "; ".join(list)

func clear():
	_cookies.clear()
	if FileAccess.file_exists(cookie_file):
		DirAccess.open("user://").remove(cookie_file)

func _session_from_clerk_result(result: Dictionary) -> Dictionary:
	var user_info = result.get("user", {})
	if typeof(user_info) != TYPE_DICTIONARY:
		user_info = {}
	var profile = result.get("profile", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = {}
	var username = str(profile.get("username", "")).strip_edges()
	var display_name = str(user_info.get("display_name", "")).strip_edges()
	if display_name == "":
		display_name = str(user_info.get("email", "")).strip_edges()
	if display_name == "":
		display_name = str(user_info.get("id", user_info.get("clerk_user_id", "")))
	var compat_user = username if username != "" else display_name
	return {
		"auth_provider": CLERK_PROVIDER,
		"user": compat_user,
		"pass": "",
		"access_token": str(result.get("access_token", "")),
		"refresh_token": str(result.get("refresh_token", "")),
		"user_info": user_info,
		"profile": profile,
	}

func _session_from_clerk_cookies() -> Dictionary:
	var user_info = get_clerk_user()
	var profile = get_neuralese_profile()
	var username = str(profile.get("username", "")).strip_edges()
	var display_name = str(user_info.get("display_name", "")).strip_edges()
	if display_name == "":
		display_name = str(user_info.get("email", "")).strip_edges()
	if display_name == "":
		display_name = str(user_info.get("id", user_info.get("clerk_user_id", "")))
	var compat_user = username if username != "" else display_name
	return {
		"auth_provider": CLERK_PROVIDER,
		"user": compat_user,
		"pass": "",
		"access_token": get_clerk_access_token(),
		"refresh_token": get_clerk_refresh_token(),
		"user_info": user_info,
		"profile": profile,
	}

func _apply_auth_session(session: Dictionary, persist: bool) -> void:
	var user_info = session.get("user_info", {})
	if typeof(user_info) != TYPE_DICTIONARY:
		user_info = {}
	var profile = session.get("profile", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = {}
	var profile_username = str(profile.get("username", "")).strip_edges()
	var compat_user = profile_username if profile_username != "" else str(session.get("user", "")).strip_edges()
	if compat_user == "" and typeof(user_info) == TYPE_DICTIONARY:
		compat_user = str(user_info.get("display_name", user_info.get("email", user_info.get("id", ""))))
	glob._logged_in = {
		"auth_provider": CLERK_PROVIDER,
		"user": compat_user,
		"pass": "",
		"user_info": user_info,
		"profile": profile,
	}
	_apply_profile_to_remote_config(profile)
	if persist:
		set_cookie(CLERK_ACCESS_TOKEN_COOKIE, str(session.get("access_token", "")))
		set_cookie(CLERK_REFRESH_TOKEN_COOKIE, str(session.get("refresh_token", "")))
		set_cookie(CLERK_USER_COOKIE, JSON.stringify(user_info))
		if not profile.is_empty():
			set_cookie(NEURALESE_PROFILE_COOKIE, JSON.stringify(profile))
		glob.set_var("credentials", glob._logged_in)

func _apply_user_profile(profile, persist: bool) -> void:
	if typeof(profile) != TYPE_DICTIONARY:
		return
	_apply_profile_to_remote_config(profile)
	if persist:
		set_cookie(NEURALESE_PROFILE_COOKIE, JSON.stringify(profile))
	var username = str(profile.get("username", "")).strip_edges()
	if username != "":
		if glob._logged_in.is_empty():
			glob._logged_in = {
				"auth_provider": CLERK_PROVIDER,
				"user": username,
				"pass": "",
				"user_info": get_clerk_user(),
				"profile": profile,
			}
		else:
			glob._logged_in["profile"] = profile
		glob._logged_in["user"] = username
		glob.set_var("credentials", glob._logged_in)
	user_profile_updated.emit(profile)

func _apply_profile_to_remote_config(profile: Dictionary) -> void:
	if typeof(profile) != TYPE_DICTIONARY:
		return
	var cfg = glob.remote_config if typeof(glob.remote_config) == TYPE_DICTIONARY else {}
	cfg["teacher"] = str(profile.get("type", "")).strip_edges().to_lower() == "teacher"
	if profile.has("my_classroom"):
		cfg["my_classroom"] = profile.get("my_classroom")
	glob.set_remote_config(cfg)

func _clerk_json_request(method: String, path: String, body: Dictionary = {}, headers: Dictionary = {}) -> Dictionary:
	var url = get_clerk_auth_base_url() + path
	var http_method = HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var req = await web._request(
		url,
		{} if method == "GET" else body,
		http_method,
		false,
		false,
		false,
		headers
	)
	if typeof(req) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid web response", "url": url}
	var result_code: int = int(req.get("result", OK))
	var response_code: int = int(req.get("code", 0))
	var response_body: PackedByteArray = req.get("body", PackedByteArray())
	var text = response_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		parsed = {"ok": false, "error": "invalid json", "raw": text}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		parsed["ok"] = false
		parsed["error"] = parsed.get("error", "network error")
	if response_code < 200 or response_code >= 300:
		parsed["ok"] = false
		parsed["error"] = parsed.get("error", "http %s" % response_code)
	parsed["http_code"] = response_code
	parsed["url"] = url
	return parsed
