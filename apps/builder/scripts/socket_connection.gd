extends Object
class_name SocketConnection

signal connected
signal closed(code: int, reason: String, clean: bool)
signal packet(data: PackedByteArray)
signal kill

var _ws: WebSocketPeer = WebSocketPeer.new()
var _url: String
var _last_state: int = WebSocketPeer.STATE_CLOSED
var _out_queue: Array[PackedByteArray] = []
var graceful: bool = false
var cache: Dictionary = {}

func _init(url: String, _graceful: bool = true, headers: Dictionary = {}):
	_url = url
	graceful = _graceful
	
	var _headers = []
	for key in headers:
		_headers.append(key + ": " + headers[key])
	_ws.handshake_headers = _headers

	var err = _ws.connect_to_url(url)
	if err != OK:
		push_error("socket connect_to_url failed: %s" % err)

func disconnect_all():
	for i in packet.get_connections():
		packet.disconnect(i.callable)

func _poll() -> void:
	_ws.poll()

	var state = _ws.get_ready_state()

	if state != _last_state:
		match state:
			WebSocketPeer.STATE_OPEN:
				for bytes in _out_queue:
					_ws.send(bytes)
				_out_queue.clear()
				connected.emit()

			WebSocketPeer.STATE_CLOSING:
				# Important: keep polling until STATE_CLOSED.
				pass

			WebSocketPeer.STATE_CLOSED:
				var code = _ws.get_close_code()
				var reason = _ws.get_close_reason()
				var clean = code != -1
				print("[ws] closed. code=", code, " reason=", reason, " clean=", clean)
				closed.emit(code, reason, clean)
				kill.emit()

		_last_state = state

	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CLOSING:
		while _ws.get_available_packet_count() > 0:
			var data: PackedByteArray = _ws.get_packet()
			packet.emit(data)

			if graceful:
				var parsed = JSON.parse_string(data.get_string_from_utf8())
				if parsed and parsed.has("_close_request"):
					var bytes = JSON.stringify({"_close_confirm": ""}).to_utf8_buffer()
					if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
						_ws.send(bytes)
						_ws.close(1000, "client confirmed close")

func send_json(json: Dictionary):
	send(JSON.stringify(json, "", true, true).to_utf8_buffer())

signal ack

func send(bytes: PackedByteArray) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send(bytes)
	else:
		_out_queue.append(bytes)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		kill.emit()

func close() -> void:
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN:
			_ws.close()
		_:
			pass

func is_listening():
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func is_closed() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED
