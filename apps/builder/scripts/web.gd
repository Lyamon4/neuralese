extends Node
class_name WebAPI

# "https://neriqward.360hub.ru/api/"
# "http://localhost:8000/"
var api_url: String = glob.get_root_http()

const _READ_CHUNK: int = 64 * 1024
const _CONNECT_TIMEOUT_S: float = 3.0
const _IO_YIELD_US: int = 500

var transcriber: Transcriber

func _ready() -> void:
	api_url = glob.get_root_http()
	transcriber = Transcriber.new()
	add_child(transcriber)


class RequestHandle:
	extends RefCounted

	signal completed(result: Dictionary)
	signal on_chunk(chunk: PackedByteArray)
	signal on_sse(event: Dictionary)

	var id: StringName = ""
	var is_sse: bool = false
	var cancelled: bool = false

	# Internal SSE buffer (string framing)
	var _sse_buffer: String = ""

	func cancel() -> void:
		cancelled = true


func POST(page: String, data, bytes: bool = false, obj: bool = false, headers: Dictionary = {}):
	return _request(_compose_url(page), data, HTTPClient.METHOD_POST, bytes, obj, false, headers)

func JPOST(page: String, data: Dictionary, headers: Dictionary = {}):
	var address = _compose_url(page)
	var req = await _request(address, data, HTTPClient.METHOD_POST, false, false, false, headers)
	var parsed = _parse_json_response(req, address)
	if _should_refresh_auth(parsed, req):
		var refreshed = await cookies.clerk_refresh_session()
		if refreshed.get("ok", false):
			var retry_headers = cookies.refreshed_auth_headers(headers)
			req = await _request(address, data, HTTPClient.METHOD_POST, false, false, false, retry_headers)
			parsed = _parse_json_response(req, address)
	return parsed

func _parse_json_response(req, address: String) -> Dictionary:
	if typeof(req) != TYPE_DICTIONARY:
		return {}
	var raw = ""
	if req.body:
		raw = req.body.get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			parsed["http_code"] = int(req.get("code", 0))
			parsed["address"] = address
			return parsed
	var code = int(req.get("code", 0))
	return {
		"ok": false,
		"http_code": code,
		"address": address,
		"raw": raw,
	}

func _should_refresh_auth(parsed: Dictionary, req) -> bool:
	if not cookies.has_clerk_session():
		return false
	var code = int(parsed.get("http_code", 0))
	if code != 401:
		return false
	var msg = str(parsed.get("error", parsed.get("raw", ""))).to_lower()
	return msg.find("expired") != -1 or msg.find("invalid token") != -1 or msg.find("signature") != -1

func HEALTH(page: String = "health"):
#	print(await GET("health"))
	var full_url = page
	var a = await _request(full_url, {}, HTTPClient.METHOD_GET, false, false, false)
#	print(a)
	print(a)
	if str(a.get("code", "")) == "200":
		return true
	return false

func GET(page: String, args: Dictionary = {}, obj: bool = false):
	var full_url = _compose_url(page)
	if not args.is_empty():
		full_url += "?" + _encode_query(args)
	return _request(full_url, {}, HTTPClient.METHOD_GET, false, obj, false)

func GET_SSE(
	page: String,
	args: Dictionary = {},
	headers: Dictionary = {}
) -> RequestHandle:
	var full_url = _compose_url(page)
	if not args.is_empty():
		full_url += "?" + _encode_query(args)

	return _request(
		full_url,
		{},
		HTTPClient.METHOD_GET,
		false,
		true,
		true,
		headers
	)


func _compose_url(page: String) -> String:
	var path = _canonical_rest_page(page)
	if path.begins_with("http://") or path.begins_with("https://"):
		return path
	var base = api_url.strip_edges()
	if base == "":
		base = glob.get_root_http()
	if not base.ends_with("/"):
		base += "/"
	path = path.trim_prefix("/")
	if base.ends_with("/api/") and path.begins_with("api/"):
		path = path.substr(4)
	return base + path


func _canonical_rest_page(page: String) -> String:
	var path = page.strip_edges().trim_prefix("/")
	var routes = {
		"save": "api/projects/save",
		"project": "api/projects/get",
		"delete_project": "api/projects/delete",
		"project_list": "api/projects/list",
		"get_chat": "api/projects/get-chat",
		"clear_chat": "api/projects/clear-chat",
		"reg_dataset": "api/projects/register-dataset",
		"datasets": "api/datasets",
		"ask_once": "api/axon/ask-once",
		"classroom/create": "api/classrooms/create",
		"classroom/join": "api/classrooms/join",
		"classroom/meta": "api/classrooms/meta",
		"classroom/leave": "api/classrooms/leave",
		"classroom/update_meta": "api/classrooms/update-meta",
		"classroom/update_lessons": "api/classrooms/update-lessons",
		"classroom/lesson_auto_project": "api/classrooms/lesson-auto-project",
		"classroom/update_state": "api/classrooms/update-state",
		"classroom/mark_explanation_made": "api/classrooms/mark-explanation-made",
		"classroom/get_state": "api/classrooms/get-state",
		"classroom/events": "api/classrooms/events",
	}
	return routes.get(path, path)



# Headers
func get_headers(json=true) -> PackedStringArray:
	var os_name = OS.get_name()
	var os_version = OS.get_version()
	var gvi = Engine.get_version_info()
	var project_name = ProjectSettings.get_setting("application/config/name", "UnnamedProject")
	var project_version = ProjectSettings.get_setting("application/config/version", "dev")

	var ua_string = "User-Agent: %s/%s Godot/%s.%s.%s-%s (%s %s)" % [
		project_name, project_version,
		gvi.major, gvi.minor, gvi.patch, gvi.status,
		os_name, os_version
	]

	var headers = PackedStringArray()
	headers.append(ua_string)
	if json:
		headers.append("Content-Type: application/json")
	headers.append("Accept: */*")

	var cookie_header = cookies.get_header()
	if cookie_header != "":
		headers.append(cookie_header)

	return headers


func _encode_query(params: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in params.keys():
		var key = String(k).uri_encode()
		var val = String(params[k]).uri_encode()
		parts.append("%s=%s" % [key, val])
	return "&".join(parts)

func _request(
	address: String,
	request_body,
	method: int,
	bytes: bool = false,
	obj: bool = false,
	sse: bool = false,
	extra_headers: Dictionary = {}
):

	var handle = RequestHandle.new()
	handle.id = "req_%s" % str(Time.get_ticks_usec())
	handle.is_sse = sse

	var thread = Thread.new()
	_threads.append(thread)

	var base_headers = get_headers()
	var merged_headers = _merge_headers(base_headers, extra_headers)

	var payload = {
		"address": address,
		"method": method,
		"body": request_body,
		"bytes": bytes,
		"headers": merged_headers,
		"handle": handle,
		"sse": sse,
	}

	thread.start(_http_thread.bind(payload, thread))

	if obj:
		return handle
	return handle.completed


func _merge_headers(base: PackedStringArray, extra: Dictionary) -> PackedStringArray:
	var out = PackedStringArray()
	out.append_array(base)

	for k in extra.keys():
		out.append("%s: %s" % [String(k), String(extra[k])])

	return out


static func _split_url(url: String) -> Dictionary:
	var ssl = false
	var rest = url
	if rest.begins_with("https://"):
		ssl = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		ssl = false
		rest = rest.substr(7)

	var slash = rest.find("/")
	var host_port = rest if slash == -1 else rest.substr(0, slash)
	var path = "/" if slash == -1 else rest.substr(slash)
	var host = host_port
	var port = 443 if ssl else 80
	var colon = host_port.find(":")
	if colon != -1:
		host = host_port.substr(0, colon)
		port = int(host_port.substr(colon + 1))
	return {"ssl": ssl, "host": host, "port": port, "path": path}

func _headers_without_content_type(hdrs: PackedStringArray) -> PackedStringArray:
	var out = PackedStringArray()
	for h in hdrs:
		if h.to_lower().begins_with("content-type:"):
			continue
		out.append(h)
	return out


var _threads: Array[Thread] = []

func _http_thread(p: Dictionary, thread: Thread) -> void:
	var handle: RequestHandle = p.handle
	var address: String = p.address
	var method: int = p.method
	var req_body = p.body
	var send_bytes: bool = p.bytes
	var hdrs: PackedStringArray = p.headers
	var is_sse: bool = p.sse

	var url = _split_url(address)
	var client = HTTPClient.new()
	client.blocking_mode_enabled = false

	# Ensure Host header
	var has_host = false
	for h in hdrs:
		if h.to_lower().begins_with("host:"):
			has_host = true
			break
	if not has_host:
		hdrs.append("Host: %s" % url.host)

	if is_sse:
		hdrs = _headers_without_content_type(hdrs)
		hdrs.append("Accept: text/event-stream")
		hdrs.append("Cache-Control: no-cache")
		hdrs.append("Connection: keep-alive")

	var body_data: PackedByteArray = PackedByteArray()
	if send_bytes:
		body_data = req_body
	else:
		body_data = (JSON.stringify(req_body, "", true, true)).to_utf8_buffer()

	var start = Time.get_ticks_msec()
	var tls_opts: TLSOptions = null
	if url.ssl:
		tls_opts = TLSOptions.client()

	var err = client.connect_to_host(url.host, url.port, tls_opts)
	if err != OK:
		call_deferred("_emit_http_done", handle, {
			"ok": false, "error": err, "code": 0, "body": PackedByteArray(),
			"address": address, "id": handle.id
		})
		call_deferred("_cleanup_thread", thread)
		return

	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		if float(Time.get_ticks_msec() - start) / 1000.0 > _CONNECT_TIMEOUT_S:
			call_deferred("_emit_http_done", handle, {
				"ok": false, "error": ERR_TIMEOUT, "code": 0, "body": PackedByteArray(),
				"address": address, "id": handle.id
			})
			call_deferred("_cleanup_thread", thread)
			return
		OS.delay_usec(_IO_YIELD_US)

	var is_get = method == HTTPClient.METHOD_GET

	if send_bytes:
		err = client.request_raw(method, url.path, hdrs, body_data if not is_get else PackedByteArray())
	else:
		err = client.request(method, url.path, hdrs, body_data.get_string_from_utf8() if not is_get else "")

	if err != OK:
		call_deferred("_emit_http_done", handle, {
			"ok": false, "error": err, "code": 0, "body": PackedByteArray(),
			"address": address, "id": handle.id
		})
		call_deferred("_cleanup_thread", thread)
		return

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_usec(_IO_YIELD_US)

	var response_code = client.get_response_code()
	var resp_headers: PackedStringArray = client.get_response_headers()
	call_deferred("_cookies_from_headers", resp_headers)

	# If SSE endpoint rejected us, finish like normal.
	if is_sse and not (response_code >= 200 and response_code < 300):
		call_deferred("_emit_http_done", handle, {
			"ok": false,
			"result": OK,
			"code": response_code,
			"headers": resp_headers,
			"body": PackedByteArray(),
			"address": address,
			"id": handle.id
		})
		call_deferred("_cleanup_thread", thread)
		return

	if is_sse:
		while true:
			if handle.cancelled:
				client.close()
				break

			client.poll()
			var st = client.get_status()

			if st == HTTPClient.STATUS_BODY:
				var chunk = client.read_response_body_chunk()
				if chunk.size() > 0:
					# Optional raw chunks for debugging/metrics
					call_deferred("_emit_http_chunk", handle, chunk)
					call_deferred("_emit_sse_chunk", handle, chunk)
				else:
					OS.delay_usec(_IO_YIELD_US)
			elif st in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
				OS.delay_usec(_IO_YIELD_US)
			else:
				# disconnected / error / closed by server
				break

		# Signal completion when the stream ends (or is cancelled)
		call_deferred("_emit_http_done", handle, {
			"ok": handle.cancelled,
			"result": OK,
			"code": response_code,
			"headers": resp_headers,
			"body": PackedByteArray(),
			"address": address,
			"id": handle.id,
			"cancelled": handle.cancelled
		})
		call_deferred("_cleanup_thread", thread)
		return

	var accum = PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk2 = client.read_response_body_chunk()
		if chunk2.size() > 0:
			call_deferred("_emit_http_chunk", handle, chunk2)
			accum.append_array(chunk2)
		else:
			OS.delay_usec(_IO_YIELD_US)

	call_deferred("_emit_http_done", handle, {
		"ok": response_code >= 200 and response_code < 300,
		"result": OK,
		"code": response_code,
		"headers": resp_headers,
		"body": accum,
		"address": address,
		"id": handle.id
	})
	call_deferred("_cleanup_thread", thread)


# Main-thread emitters and cleanup
func _emit_http_chunk(handle: RequestHandle, chunk: PackedByteArray) -> void:
	handle.emit_signal("on_chunk", chunk)

func _emit_http_done(handle: RequestHandle, payload: Dictionary) -> void:
	handle.emit_signal("completed", payload)

func _emit_sse_chunk(handle: RequestHandle, chunk: PackedByteArray) -> void:
	# Decode as UTF-8 text and normalize line endings.
	var text = chunk.get_string_from_utf8()
	if text.find("\r\n") != -1:
		text = text.replace("\r\n", "\n")
	if text.find("\r") != -1:
		text = text.replace("\r", "\n")

	handle._sse_buffer += text

	while true:
		# SSE frames end with a blank line
		var sep = handle._sse_buffer.find("\n\n")
		if sep == -1:
			break

		var raw = handle._sse_buffer.substr(0, sep)
		handle._sse_buffer = handle._sse_buffer.substr(sep + 2)

		if raw.strip_edges() == "":
			continue

		var evt = {
			"event": "message",
			"data": "",
			"id": ""
		}

		var data_lines: PackedStringArray = []
		for line in raw.split("\n", false):
			line = line.strip_edges()
			if line == "":
				continue
			if line.begins_with(":"):
				continue

			if line.begins_with("event:"):
				evt.event = line.substr(6).strip_edges()
			elif line.begins_with("data:"):
				data_lines.append(line.substr(5).strip_edges())
			elif line.begins_with("id:"):
				evt.id = line.substr(3).strip_edges()

		evt.data = "\n".join(data_lines).strip_edges()
		handle.emit_signal("on_sse", evt)

func _cookies_from_headers(headers: PackedStringArray) -> void:
	cookies.update_from_headers(headers)

func _cleanup_thread(thread: Thread) -> void:
	if thread == null:
		return
	# Always called via call_deferred() → main thread.
	if thread.is_started():
		thread.wait_to_finish()
	_threads.erase(thread)
