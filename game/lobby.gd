extends PanelContainer
## Coop lobby, behind the menu's Multijoueur button (ui/ui.gd): host a room,
## join one by its code, see who is in, start the run.

signal closed

var main: Node  # game/main.gd
var info: Label
var url_edit: LineEdit
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
	title.text = "Multijoueur (coop)"
	box.add_child(title)
	url_edit = LineEdit.new()
	url_edit.text = Online.relay_url
	Online.changed.connect(func(): url_edit.text = Online.relay_url)  # from the server's config
	url_edit.tooltip_text = "Adresse du relais"
	box.add_child(url_edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "Créer un salon", func(): info.text = main.host_game(url_edit.text.strip_edges()))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODE"
	code_edit.max_length = 4
	code_edit.custom_minimum_size.x = 80
	row.add_child(code_edit)
	_button(row, "Rejoindre", func(): info.text = main.join_game(url_edit.text.strip_edges(), code_edit.text))
	main.net_error.connect(func(m): info.text = m)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	players = Label.new()
	box.add_child(players)
	row = HBoxContainer.new()
	box.add_child(row)
	start = _button(row, "Lancer la partie", func(): main.start_run())
	_button(row, "Quitter le salon", func(): main.leave_game())
	_button(row, "Retour", closed.emit)
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
	var online := peer is RelayPeer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
	start.disabled = not multiplayer.is_server()
	if not online:
		players.text = "Hors ligne : partie solo."
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		info.text = "Connexion au relais…"
	elif multiplayer.is_server():
		info.text = "Code du salon : %s  (à donner aux autres joueurs)" % peer.code
	else:
		info.text = "Connecté. L'hôte lance la partie."
	var ids := Array(multiplayer.get_peers())
	ids.append(multiplayer.get_unique_id())
	ids.sort()
	players.text = "Joueurs :\n" + "\n".join(ids.map(func(id): return "  Joueur %d%s%s" % [
		id, " (hôte)" if id == 1 else "", " (toi)" if id == multiplayer.get_unique_id() else ""]))
