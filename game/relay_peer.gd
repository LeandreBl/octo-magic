class_name RelayPeer
extends MultiplayerPeerExtension
## MultiplayerPeer over one WebSocket to the coop relay (relay/relay.py, see
## its protocol). Lets the high-level API (RPC, spawners, synchronizers) work
## on web and native without NAT traversal. The host is peer 1; clients only
## see the host, SceneMultiplayer relays between them (server relay).
## Everything is reliable and ordered: WebSocket has nothing else.

const MAX_PACKET := 65536 - 4  # relay.MAX_MESSAGE minus the peer id header

var code := ""  # room code, once hosting
var error := ""  # last relay error, for the lobby
var ws := WebSocketPeer.new()
var _hello := ""
var _id := 0
var _hosting := false
var _status := CONNECTION_DISCONNECTED
var _in: Array[PackedByteArray] = []  # [int32 sender id + payload]
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false


func host(url: String) -> Error:
	_hosting = true
	_id = 1
	return _open(url, {"op": "host"})


func join(url: String, room: String) -> Error:
	return _open(url, {"op": "join", "code": room.strip_edges().to_upper()})


func _open(url: String, hello: Dictionary) -> Error:
	_hello = JSON.stringify(hello)
	ws.inbound_buffer_size = 1 << 17
	ws.outbound_buffer_size = 1 << 17
	var err := ws.connect_to_url(url)
	if err == OK:
		_status = CONNECTION_CONNECTING
	else:
		error = "adresse invalide"
	return err


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello.is_empty():
		ws.send_text(_hello)
		_hello = ""
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if ws.was_string_packet():
			_control(JSON.parse_string(pkt.get_string_from_utf8()))
		elif pkt.size() >= 4 and _status == CONNECTION_CONNECTED:
			_in.append(pkt)
	if state == WebSocketPeer.STATE_CLOSED:
		if error.is_empty():
			error = "relais injoignable" if _status == CONNECTION_CONNECTING else "connexion perdue"
		_close()


func _control(msg: Variant) -> void:
	if not msg is Dictionary:
		return
	match msg.get("op"):
		"hosted":
			code = str(msg.get("code", ""))
			_status = CONNECTION_CONNECTED
		"joined":
			_id = int(msg.get("id", 0))
			_status = CONNECTION_CONNECTED
			peer_connected.emit(1)
		"peer":
			peer_connected.emit(int(msg.get("id", 0)))
		"left":
			peer_disconnected.emit(int(msg.get("id", 0)))
		"error":
			error = {"no such room": "code inconnu", "room full": "salon plein",
				"host left": "l'hôte est parti", "kicked": "exclu par l'hôte"}.get(msg.get("msg"), str(msg.get("msg")))


func _get_available_packet_count() -> int:
	return _in.size()


func _get_packet_peer() -> int:  # asked before _get_packet_script
	return _in[0].decode_s32(0) if _in else 0


func _get_packet_script() -> PackedByteArray:
	return _in.pop_front().slice(4) if _in else PackedByteArray()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, _target if _hosting else 1)
	out.append_array(buffer)
	return ws.send(out)


func _close() -> void:
	if _status != CONNECTION_DISCONNECTED:
		ws.close()
	_status = CONNECTION_DISCONNECTED
	_in.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _hosting:
		ws.send_text(JSON.stringify({"op": "kick", "id": peer}))


func _get_max_packet_size() -> int: return MAX_PACKET
func _get_packet_channel() -> int: return 0
func _get_packet_mode() -> TransferMode: return TRANSFER_MODE_RELIABLE
func _get_unique_id() -> int: return _id
func _is_server() -> bool: return _hosting
func _is_server_relay_supported() -> bool: return true
func _get_connection_status() -> ConnectionStatus: return _status
func _set_target_peer(peer: int) -> void: _target = peer
func _set_transfer_mode(mode: TransferMode) -> void: _mode = mode
func _get_transfer_mode() -> TransferMode: return _mode
func _set_transfer_channel(channel: int) -> void: _channel = channel
func _get_transfer_channel() -> int: return _channel
func _set_refuse_new_connections(enable: bool) -> void: _refusing = enable
func _is_refusing_new_connections() -> bool: return _refusing
