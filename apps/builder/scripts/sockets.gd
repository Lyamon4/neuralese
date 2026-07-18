extends Node

var _conns: Dictionary = {}	# { SocketConnection: true }
#"wss://localhost:8000/"
var connection_prefix: String = glob.get_root_ws()#"wss://neriqward.360hub.ru/api/"

func _process(_dt: float) -> void:
	var to_del: Array = []

	for conn in _conns.keys():
		if conn == null:
			to_del.append(conn)
			continue
		conn._poll()
		if conn.is_closed():
			to_del.append(conn)

	for c in to_del:
		_conns.erase(c)



func connect_to(url: String, on_packet: Callable = Callable(), headers: Dictionary = {}) -> SocketConnection:
	var c = SocketConnection.new(_compose_ws_url(url), true, headers)
	_conns[c] = true
	if on_packet.is_valid():
		c.packet.connect(on_packet)
	return c


func _compose_ws_url(url: String) -> String:
	var path = _canonical_ws_page(url)
	if path.begins_with("ws://") or path.begins_with("wss://"):
		return path
	var base = connection_prefix.strip_edges()
	if base == "":
		base = glob.get_root_ws()
	if not base.ends_with("/"):
		base += "/"
	path = path.trim_prefix("/")
	return base + path


func _canonical_ws_page(url: String) -> String:
	var path = url.strip_edges().trim_prefix("/")
	var routes = {
		"ws/talk": "ws/axon/talk",
	}
	return routes.get(path, path)
