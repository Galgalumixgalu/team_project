extends Node

signal joined
signal message_received(message: Dictionary)
signal status_changed(text: String)

var socket := WebSocketPeer.new()
var room_code := ""
var client_id := ""
var topic := ""
var joined_ok := false
var _join_ref := ""
var _join_sent := false
var _next_reference := 1
var _heartbeat_elapsed := 0.0
var _close_reported := false

func connect_room(project_url: String, public_key: String, code: String, local_client_id: String) -> bool:
	close_room()
	socket = WebSocketPeer.new()
	var clean_url := project_url.strip_edges().trim_suffix("/")
	if not clean_url.begins_with("https://"):
		status_changed.emit("Supabase 프로젝트 주소는 https:// 로 시작해야 합니다.")
		return false
	var host := clean_url.trim_prefix("https://").split("/")[0]
	if host.is_empty() or public_key.strip_edges().is_empty() or code.strip_edges().is_empty():
		status_changed.emit("프로젝트 주소, 공개 키, 방 코드를 확인해 주세요.")
		return false
	room_code = code.strip_edges().to_upper()
	client_id = local_client_id
	topic = "realtime:holdem_" + room_code.to_lower()
	joined_ok = false
	_join_sent = false
	_join_ref = ""
	_close_reported = false
	_heartbeat_elapsed = 0.0
	_next_reference = 1
	var url := "wss://%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [host, public_key.strip_edges().uri_encode()]
	status_changed.emit("Supabase에 연결하는 중…")
	var error := socket.connect_to_url(url)
	if error != OK:
		status_changed.emit("WebSocket 연결을 시작하지 못했습니다. 주소와 공개 키를 확인해 주세요.")
		return false
	return true

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _join_sent:
			_send_join()
		while socket.get_available_packet_count() > 0:
			var text := socket.get_packet().get_string_from_utf8()
			var decoded: Variant = JSON.parse_string(text)
			if typeof(decoded) == TYPE_DICTIONARY:
				_handle_server_message(decoded)
		if joined_ok:
			_heartbeat_elapsed += delta
			if _heartbeat_elapsed >= 20.0:
				_heartbeat_elapsed = 0.0
				_send_raw({"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": _new_ref()})
	elif state == WebSocketPeer.STATE_CLOSED and not _close_reported:
		_close_reported = true
		if not room_code.is_empty():
			joined_ok = false
			status_changed.emit("연결이 종료됐습니다. 다시 방에 접속해 주세요.")

func _send_join() -> void:
	_join_ref = _new_ref()
	_join_sent = true
	var payload := {
		"config": {
			"broadcast": {"ack": false, "self": false},
			"presence": {},
			"private": false
		}
	}
	_send_raw({"topic": topic, "event": "phx_join", "payload": payload, "ref": _join_ref, "join_ref": _join_ref})
	status_changed.emit("방 채널에 입장하는 중…")

func _handle_server_message(message: Dictionary) -> void:
	var event_name := str(message.get("event", ""))
	if event_name == "phx_reply":
		if str(message.get("ref", "")) != _join_ref:
			return
		var payload: Dictionary = message.get("payload", {})
		if str(payload.get("status", "")) == "ok":
			if not joined_ok:
				joined_ok = true
				status_changed.emit("방 채널에 연결됐습니다.")
				joined.emit()
		else:
			var response: Dictionary = payload.get("response", {})
			status_changed.emit("방 채널 입장 실패: " + str(response.get("reason", "설정과 방 코드를 확인해 주세요.")))
	elif event_name == "broadcast":
		var payload: Dictionary = message.get("payload", {})
		if str(payload.get("event", "")) != "holdem_message":
			return
		var body: Variant = payload.get("payload", {})
		if typeof(body) != TYPE_DICTIONARY:
			return
		if body.has("to") and str(body.get("to", "")) != client_id:
			return
		message_received.emit(body)
	elif event_name == "system":
		var payload: Dictionary = message.get("payload", {})
		if payload.has("message"):
			status_changed.emit(str(payload.get("message", "")))

func send_message(message: Dictionary) -> bool:
	if not joined_ok or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var payload := {"type": "broadcast", "event": "holdem_message", "payload": message}
	return _send_raw({"topic": topic, "event": "broadcast", "payload": payload, "ref": _new_ref(), "join_ref": _join_ref})

func close_room() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if joined_ok:
			_send_raw({"topic": topic, "event": "phx_leave", "payload": {}, "ref": _new_ref(), "join_ref": _join_ref})
		socket.close(1000, "Leaving room")
	joined_ok = false
	_join_sent = false
	room_code = ""
	topic = ""
	_close_reported = true

func _send_raw(message: Dictionary) -> bool:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return socket.send_text(JSON.stringify(message)) == OK

func _new_ref() -> String:
	var value := str(_next_reference)
	_next_reference += 1
	return value
