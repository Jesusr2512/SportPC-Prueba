class_name MobileBridgeServer
extends Node

signal telemetry_received(peer_id: int, data: Dictionary)
signal peer_disconnected(peer_id: int)

const DEFAULT_PORT := 8443
const WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const KEY_PATH := "user://sportpc_tls.key"
const CERT_PATH := "user://sportpc_tls.crt"

var active_port: int = 0
var is_running: bool = false

var _tcp_server := TCPServer.new()
var _crypto := Crypto.new()
var _private_key: CryptoKey
var _certificate: X509Certificate
var _tls_options: TLSOptions
var _html_bytes: PackedByteArray = PackedByteArray()

var _peers: Dictionary = {}
var _next_peer_id: int = 1


func _ready() -> void:
	_load_html()
	_ensure_certificates()
	_start_server()


func _load_html() -> void:
	var file := FileAccess.open("res://web/mobile_controller.html", FileAccess.READ)
	if file:
		_html_bytes = file.get_as_text().to_utf8_buffer()
	else:
		_html_bytes = "<html><body><h1>No se encontro mobile_controller.html</h1></body></html>".to_utf8_buffer()


func _ensure_certificates() -> void:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if FileAccess.file_exists(KEY_PATH) and FileAccess.file_exists(CERT_PATH):
		if key.load(KEY_PATH) == OK and cert.load(CERT_PATH) == OK:
			_private_key = key
			_certificate = cert
			_tls_options = TLSOptions.server(_private_key, _certificate)
			return

	_private_key = _crypto.generate_rsa(2048)
	_certificate = _crypto.generate_self_signed_certificate(
		_private_key,
		"CN=SportPC,O=SportPC,C=ES",
		"20250101000000",
		"20350101000000"
	)
	_private_key.save(KEY_PATH)
	_certificate.save(CERT_PATH)
	_tls_options = TLSOptions.server(_private_key, _certificate)


func _start_server() -> void:
	for offset in 8:
		var port := DEFAULT_PORT + offset
		if _tcp_server.listen(port, "0.0.0.0") == OK:
			active_port = port
			is_running = true
			return
	push_warning("MobileBridgeServer: no pudo abrir ningun puerto HTTPS en 8443..8450")


func get_primary_url() -> String:
	var urls := get_all_urls()
	if urls.is_empty():
		return "https://localhost:%d" % active_port
	return urls[0]


func get_all_urls() -> Array[String]:
	var scored: Array[Dictionary] = []
	for addr in IP.get_local_addresses():
		if not addr.contains(".") or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		var score := 0
		if addr.begins_with("192.168.56.") or addr.begins_with("192.168.99."):
			score = 1
		elif addr.begins_with("192.168."):
			score = 4
		elif addr.begins_with("10."):
			score = 3
		elif _is_rfc1918_172(addr):
			score = 2
		else:
			score = 1
		scored.append({"addr": addr, "score": score})

	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[String] = []
	for item in scored:
		out.append("https://%s:%d" % [item["addr"], active_port])
	return out


func _is_rfc1918_172(addr: String) -> bool:
	if not addr.begins_with("172."):
		return false
	var parts := addr.split(".")
	if parts.size() != 4:
		return false
	var oct := int(parts[1])
	return oct >= 16 and oct <= 31


func _process(_delta: float) -> void:
	if not is_running:
		return

	while _tcp_server.is_connection_available():
		var tcp: StreamPeerTCP = _tcp_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var tls := StreamPeerTLS.new()
		if tls.accept_stream(tcp, _tls_options) != OK:
			continue
		var now_init := Time.get_ticks_msec()
		_peers[_next_peer_id] = {
			"tcp": tcp,
			"tls": tls,
			"mode": "http",
			"http_buf": PackedByteArray(),
			"ws_buf": PackedByteArray(),
			"frag_buf": PackedByteArray(),
			"frag_opcode": 0,
			"out_buf": PackedByteArray(),
			"cid": "",
			"remote_ip": tcp.get_connected_host(),
			"last_seen": now_init,
			"last_ping": now_init
		}
		_next_peer_id += 1

	var now := Time.get_ticks_msec()
	var to_remove: Array[int] = []

	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var tls: StreamPeerTLS = p["tls"]
		tls.poll()
		var status := tls.get_status()

		if status == StreamPeerTLS.STATUS_HANDSHAKING:
			if now - int(p["last_seen"]) > 6000:
				to_remove.append(id)
			continue
		elif status != StreamPeerTLS.STATUS_CONNECTED:
			to_remove.append(id)
			continue

		if not _flush_out_buf(p):
			to_remove.append(id)
			continue

		var got_data := false
		for _reads in 8:
			var avail := tls.get_available_bytes()
			if avail <= 0:
				break
			var res := tls.get_data(avail)
			if res[0] != OK:
				to_remove.append(id)
				break
			got_data = true
			p["last_seen"] = now
			var chunk: PackedByteArray = res[1]
			if p["mode"] == "http":
				if not _process_http(id, p, chunk):
					to_remove.append(id)
					break
			else:
				if not _process_ws(id, p, chunk):
					to_remove.append(id)
					break

		if id in to_remove:
			continue

		if not got_data:
			if p["mode"] == "ws":
				var idle := now - int(p["last_seen"])
				if idle > 6500:
					to_remove.append(id)
				elif idle > 2500 and now - int(p["last_ping"]) > 2500:
					p["last_ping"] = now
					_queue_ws_frame(p, 0x89, PackedByteArray())
			elif p["mode"] == "http" and now - int(p["last_seen"]) > 20000:
				to_remove.append(id)

	for id in to_remove:
		_disconnect_peer(id)


func _disconnect_peer(id: int) -> void:
	if not _peers.has(id):
		return
	var p: Dictionary = _peers[id]
	var was_ws: bool = str(p.get("mode", "")) == "ws"
	var tls: StreamPeerTLS = p["tls"]
	tls.disconnect_from_stream()
	_peers.erase(id)
	if was_ws:
		peer_disconnected.emit(id)


func get_peer_remote_ip(peer_id: int) -> String:
	if not _peers.has(peer_id):
		return ""
	return str(_peers[peer_id].get("remote_ip", ""))


func evict_client_id(cid: String, except_id: int = -1) -> void:
	if cid.is_empty():
		return
	var stale: Array[int] = []
	for id in _peers.keys():
		if int(id) == except_id:
			continue
		var p: Dictionary = _peers[id]
		if str(p.get("mode", "")) == "ws" and str(p.get("cid", "")) == cid:
			stale.append(int(id))
	for id in stale:
		_disconnect_peer(id)


func _queue_bytes(p: Dictionary, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var out: PackedByteArray = p["out_buf"]
	out.append_array(bytes)
	p["out_buf"] = out
	_flush_out_buf(p)


func _flush_out_buf(p: Dictionary) -> bool:
	var out: PackedByteArray = p["out_buf"]
	if out.is_empty():
		return true
	var tls: StreamPeerTLS = p["tls"]
	var sent := 0
	var total := out.size()
	for _attempt in 16:
		if sent >= total:
			break
		var res := tls.put_partial_data(out.slice(sent))
		if res[0] != OK:
			return false
		var written := int(res[1])
		if written <= 0:
			break
		sent += written
	if sent > 0:
		p["out_buf"] = out.slice(sent) if sent < total else PackedByteArray()
	tls.poll()
	return true


func _find_http_header_end(buf: PackedByteArray) -> int:
	var n := buf.size()
	for i in range(n - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _process_http(id: int, p: Dictionary, chunk: PackedByteArray) -> bool:
	var http_buf: PackedByteArray = p["http_buf"]
	http_buf.append_array(chunk)
	var header_end := _find_http_header_end(http_buf)
	if header_end == -1:
		p["http_buf"] = http_buf
		return http_buf.size() <= 16384

	var raw_headers: String = http_buf.slice(0, header_end).get_string_from_utf8()
	var rest_bytes: PackedByteArray = http_buf.slice(header_end + 4)
	p["http_buf"] = rest_bytes

	var ws_key := ""
	var is_ws := false
	for line in raw_headers.split("\r\n"):
		var lower := line.to_lower()
		if lower.begins_with("upgrade:") and lower.contains("websocket"):
			is_ws = true
		elif lower.begins_with("sec-websocket-key:"):
			ws_key = line.substr(line.find(":") + 1).strip_edges()

	if is_ws and not ws_key.is_empty():
		var accept := Marshalls.raw_to_base64((ws_key + WS_GUID).sha1_buffer())
		var reply := (
			"HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: %s\r\n\r\n" % accept
		)
		_queue_bytes(p, reply.to_utf8_buffer())
		p["mode"] = "ws"
		p["http_buf"] = PackedByteArray()
		if not rest_bytes.is_empty():
			return _process_ws(id, p, rest_bytes)
		return true

	if _html_bytes.is_empty():
		_load_html()
	var req_line := raw_headers.split("\r\n")[0]
	if req_line.begins_with("GET /favicon.ico"):
		_queue_bytes(p, "HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\nContent-Length: 0\r\n\r\n".to_utf8_buffer())
		return true

	var header := (
		"HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		("Content-Length: %d\r\n" % _html_bytes.size()) +
		"Cache-Control: no-store\r\n" +
		"Connection: keep-alive\r\n" +
		"Keep-Alive: timeout=15, max=100\r\n\r\n"
	).to_utf8_buffer()
	_queue_bytes(p, header)
	_queue_bytes(p, _html_bytes)
	return true


func _process_ws(id: int, p: Dictionary, chunk: PackedByteArray) -> bool:
	var buf: PackedByteArray = p["ws_buf"]
	buf.append_array(chunk)

	while buf.size() >= 2:
		var b0 := buf[0]
		var b1 := buf[1]
		var fin := (b0 & 0x80) != 0
		var opcode := b0 & 0x0F
		var masked := (b1 & 0x80) != 0
		var payload_len := b1 & 0x7F
		var offset := 2

		if payload_len == 126:
			if buf.size() < 4:
				break
			payload_len = (buf[2] << 8) | buf[3]
			offset = 4
		elif payload_len == 127:
			return false

		var mask_offset := offset
		if masked:
			offset += 4

		if buf.size() < offset + payload_len:
			break

		var payload := PackedByteArray()
		payload.resize(payload_len)
		if masked:
			for i in payload_len:
				payload[i] = buf[offset + i] ^ buf[mask_offset + (i % 4)]
		else:
			for i in payload_len:
				payload[i] = buf[offset + i]

		buf = buf.slice(offset + payload_len)

		if opcode == 0x8:
			_queue_ws_frame(p, 0x88, PackedByteArray())
			_flush_out_buf(p)
			p["ws_buf"] = buf
			return false
		elif opcode == 0x9:
			_queue_ws_frame(p, 0x8A, payload)
		elif opcode == 0xA:
			pass # Pong keepalive acknowledged via last_seen
		elif opcode == 0x1 or opcode == 0x2:
			if fin:
				_handle_ws_message(id, payload)
			else:
				p["frag_opcode"] = opcode
				p["frag_buf"] = payload
		elif opcode == 0x0:
			var fbuf: PackedByteArray = p["frag_buf"]
			fbuf.append_array(payload)
			if fbuf.size() > 65536:
				return false
			if fin:
				_handle_ws_message(id, fbuf)
				p["frag_buf"] = PackedByteArray()
				p["frag_opcode"] = 0
			else:
				p["frag_buf"] = fbuf

	p["ws_buf"] = buf
	return true


func _handle_ws_message(id: int, payload: PackedByteArray) -> void:
	var parsed = JSON.parse_string(payload.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("cid"):
			var cid := str(parsed["cid"]).strip_edges()
			if not cid.is_empty() and _peers.has(id):
				_peers[id]["cid"] = cid
				evict_client_id(cid, id)
		telemetry_received.emit(id, parsed)


func send_rumble(peer_id: int, duration_ms: int) -> void:
	send_feedback(peer_id, {"rumble": duration_ms})


func send_feedback(peer_id: int, payload: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var p: Dictionary = _peers[peer_id]
	if p.get("mode", "") != "ws":
		return
	var tls: StreamPeerTLS = p["tls"]
	if tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
		return
	var text := JSON.stringify(payload).to_utf8_buffer()
	_queue_ws_frame(p, 0x81, text)


func _queue_ws_frame(p: Dictionary, first_byte: int, payload: PackedByteArray) -> void:
	var frame := PackedByteArray()
	frame.append(first_byte)
	var size := payload.size()
	if size < 126:
		frame.append(size)
	elif size < 65536:
		frame.append(126)
		frame.append((size >> 8) & 0xFF)
		frame.append(size & 0xFF)
	else:
		return
	frame.append_array(payload)
	_queue_bytes(p, frame)
