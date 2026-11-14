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
		elif addr.begins_with("172."):
			score = 2
		scored.append({"addr": addr, "score": score})

	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[String] = []
	for item in scored:
		out.append("https://%s:%d" % [item["addr"], active_port])
	return out


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
		_peers[_next_peer_id] = {
			"tcp": tcp,
			"tls": tls,
			"mode": "http",
			"http_buf": "",
			"ws_buf": PackedByteArray(),
			"last_seen": Time.get_ticks_msec()
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
			if now - p["last_seen"] > 6000:
				to_remove.append(id)
			continue
		elif status != StreamPeerTLS.STATUS_CONNECTED:
			to_remove.append(id)
			continue

		if p["mode"] == "closing":
			var tcp: StreamPeerTCP = p["tcp"]
			tcp.poll()
			if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED or now >= int(p.get("close_at", 0)):
				to_remove.append(id)
			continue

		var avail := tls.get_available_bytes()
		if avail > 0:
			var res := tls.get_data(avail)
			if res[0] == OK:
				p["last_seen"] = now
				var chunk: PackedByteArray = res[1]
				if p["mode"] == "http":
					if not _process_http(id, p, chunk):
						to_remove.append(id)
				else:
					if not _process_ws(id, p, chunk):
						to_remove.append(id)
		elif p["mode"] == "ws" and now - p["last_seen"] > 12000:
			to_remove.append(id)
		elif p["mode"] == "http" and now - p["last_seen"] > 20000:
			to_remove.append(id)

	for id in to_remove:
		var p: Dictionary = _peers[id]
		var was_ws: bool = str(p.get("mode", "")) == "ws"
		var tls: StreamPeerTLS = p["tls"]
		tls.disconnect_from_stream()
		_peers.erase(id)
		if was_ws:
			peer_disconnected.emit(id)


func _process_http(id: int, p: Dictionary, chunk: PackedByteArray) -> bool:
	p["http_buf"] += chunk.get_string_from_utf8()
	var header_end: int = p["http_buf"].find("\r\n\r\n")
	if header_end == -1:
		if p["http_buf"].length() > 16384:
			return false
		return true

	var raw_headers: String = p["http_buf"].substr(0, header_end)
	var leftover_len: int = p["http_buf"].length() - (header_end + 4)
	var tls: StreamPeerTLS = p["tls"]

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
		tls.put_data(reply.to_utf8_buffer())
		p["mode"] = "ws"
		if leftover_len > 0:
			var http_str: String = str(p["http_buf"])
			var rest: PackedByteArray = http_str.substr(header_end + 4).to_utf8_buffer()
			p["http_buf"] = ""
			return _process_ws(id, p, rest)
		p["http_buf"] = ""
		return true

	var req_line := raw_headers.split("\r\n")[0]
	if req_line.begins_with("GET /favicon.ico"):
		_send_tls_bytes(tls, "HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\nContent-Length: 0\r\n\r\n".to_utf8_buffer())
		p["http_buf"] = ""
		return true

	var header := (
		"HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		("Content-Length: %d\r\n" % _html_bytes.size()) +
		"Cache-Control: no-store\r\n" +
		"Connection: keep-alive\r\n" +
		"Keep-Alive: timeout=15, max=100\r\n\r\n"
	).to_utf8_buffer()
	_send_tls_bytes(tls, header)
	_send_tls_bytes(tls, _html_bytes)
	p["http_buf"] = ""
	return true


func _send_tls_bytes(tls: StreamPeerTLS, bytes: PackedByteArray) -> void:
	var sent := 0
	var total := bytes.size()
	var attempts := 0
	while sent < total and attempts < 60:
		tls.poll()
		var slice := bytes.slice(sent)
		var res := tls.put_partial_data(slice)
		if res[0] != OK:
			break
		var written := int(res[1])
		if written > 0:
			sent += written
		else:
			attempts += 1
			OS.delay_msec(2)
	tls.poll()


func _process_ws(id: int, p: Dictionary, chunk: PackedByteArray) -> bool:
	var buf: PackedByteArray = p["ws_buf"]
	buf.append_array(chunk)
	var tls: StreamPeerTLS = p["tls"]

	while buf.size() >= 2:
		var b0 := buf[0]
		var b1 := buf[1]
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
			p["ws_buf"] = buf
			return false
		elif opcode == 0x9:
			_send_ws_frame(tls, 0x8A, payload)
		elif opcode == 0x1:
			var parsed = JSON.parse_string(payload.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				telemetry_received.emit(id, parsed)

	p["ws_buf"] = buf
	return true


func send_rumble(peer_id: int, duration_ms: int) -> void:
	if not _peers.has(peer_id):
		return
	var p: Dictionary = _peers[peer_id]
	if p.get("mode", "") != "ws":
		return
	var tls: StreamPeerTLS = p["tls"]
	if tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
		return
	var text := JSON.stringify({"rumble": duration_ms}).to_utf8_buffer()
	_send_ws_frame(tls, 0x81, text)


func _send_ws_frame(tls: StreamPeerTLS, first_byte: int, payload: PackedByteArray) -> void:
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
	tls.put_data(frame)
