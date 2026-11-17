extends PanelContainer
## Coop lobby, behind the menu's Multiplayer button (ui/ui.gd): host a room,
## join one by its code (logged in), see who is in, start the run.

signal closed

var main: Node  # game/main.gd
var info: Label
var code_edit: LineEdit
var players: Label
var start: Button


func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.theme_type_variation = "Header"
	title.text = "Multiplayer (coop)"
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "Create a room", func(): info.text = tr(await main.host_game()))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODE"
	code_edit.max_length = 4
	code_edit.custom_minimum_size.x = 80
	row.add_child(code_edit)
	_button(row, "Join", func(): info.text = tr(await main.join_game(code_edit.text)))
	main.net_error.connect(func(m): info.text = tr(m))
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	players = Label.new()
	box.add_child(players)
	row = HBoxContainer.new()
	box.add_child(row)
	start = _button(row, "Start the game", func(): main.start_run())
	_button(row, "Leave the room", func(): main.leave_game())
	_button(row, "Back", closed.emit)
	set_meta("focus", start)


func _button(row: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	row.add_child(b)
	return b


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var peer := multiplayer.multiplayer_peer
	start.disabled = not multiplayer.is_server()
	if not peer is WebRTCMultiplayerPeer:
		players.text = tr("Offline: solo game.")
		if main.net.waiting:
			info.text = tr("Connecting to the room…")
		elif main.net.error:
			info.text = tr(main.net.error)
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		info.text = tr("Connecting to the host…")
	elif multiplayer.is_server():
		info.text = tr("Room code: %s  (give it to the other players)") % main.net.code
	else:
		info.text = tr("Connected. The host starts the game.")
	var ids := Array(multiplayer.get_peers())
	ids.append(multiplayer.get_unique_id())
	ids.sort()
	players.text = tr("Players:") + "\n" + "\n".join(ids.map(func(id): return "  " + tr("Player %d") % id + "%s%s" % [
		" (%s)" % tr("host") if id == 1 else "", " (%s)" % tr("you") if id == multiplayer.get_unique_id() else ""]))
