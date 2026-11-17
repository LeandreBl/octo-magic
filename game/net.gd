extends Node
## Coop over WebRTC (WebRTCMultiplayerPeer, built in on web, addons/webrtc_native
## on native). Game packets go peer to peer over UDP; the server's /play
## WebSocket only introduces the players (signaling, protocol in
## backend/src/lobby/lobby.service.ts). STUN finds a way through NATs; when there is none the
## TURN server relays. The host is peer 1, players connect to the host only
## and SceneMultiplayer relays between them (server relay).

signal joined  # a player got its peer id: its multiplayer peer is ready
signal lost  # the lobby closed the room (host gone, kicked...)

var rtc: WebRTCMultiplayerPeer
var code := ""  # room code, once hosting
var error := ""  # last lobby error, for the lobby panel
var ws := WebSocketPeer.new()
var _hello := ""
var waiting := false  # for the room: the lobby's answer, then the peer id
var _ice := []


## Opens a room (empty code) or joins one. Returns an error message, or "".
func start(room := "") -> String:
	close()
	var token := await Online.id_token()
	if token.is_empty():
		error = "log in first (Account button)"
		return error
	var hello := {"op": "join", "code": room.strip_edges().to_upper(), "token": token} if room else {"op": "host", "token": token}
	_hello = JSON.stringify(hello)
	error = ""
	if ws.connect_to_url(Online.server.replace("http", "ws") + "/play") != OK:
		error = "invalid server address"
	waiting = error.is_empty()
	return error


func close() -> void:
	waiting = false
	ws.close()
	if rtc:
		rtc.close()
	rtc = null
	code = ""


func _process(_delta: float) -> void:
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello.is_empty():
		ws.send_text(_hello)
		_hello = ""
	while ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_on_message(msg)
	if state == WebSocketPeer.STATE_CLOSED and waiting:
		waiting = false
		if error.is_empty():
			error = "server unreachable"


func _on_message(msg: Dictionary) -> void:
	match msg.get("op"):
		"hosted", "joined":
			waiting = false
			_ice = msg.get("ice", []) if msg.get("ice") is Array else []
			rtc = WebRTCMultiplayerPeer.new()
			if msg.op == "hosted":
				code = str(msg.get("code", ""))
				rtc.create_server()
			else:
				rtc.create_client(int(msg.get("id", 0)))
				_connection(1)  # the host sends the offer
			joined.emit()
		"peer":  # the host offers a connection to each newcomer
			_connection(int(msg.get("id", 0))).create_offer()
		"left":
			if rtc and rtc.has_peer(int(msg.get("id", 0))):
				rtc.remove_peer(int(msg.id))
		"signal":
			var from := int(msg.get("from", 0))
			var data: Variant = msg.get("data")
			if not rtc or not rtc.has_peer(from) or not data is Dictionary:
				return
			var pc: WebRTCPeerConnection = rtc.get_peer(from).connection
			if data.has("sdp"):
				pc.set_remote_description(str(data.get("type")), str(data.sdp))
			elif data.has("ice"):
				pc.add_ice_candidate(str(data.ice[0]), int(data.ice[1]), str(data.ice[2]))
		"error":
			lost.emit.call_deferred()
			error = {"no such room": "unknown code", "invalid token": "session expired, log in again"
				}.get(msg.get("msg"), str(msg.get("msg")))


func _connection(id: int) -> WebRTCPeerConnection:
	var pc := WebRTCPeerConnection.new()
	pc.initialize({"iceServers": _ice})
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_signal(id, {"type": type, "sdp": sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		_signal(id, {"ice": [media, index, cname]}))
	rtc.add_peer(pc, id)
	return pc


func _signal(to: int, data: Dictionary) -> void:
	ws.send_text(JSON.stringify({"op": "signal", "to": to, "data": data}))
