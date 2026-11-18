extends VBoxContainer
## Coop lobby, behind the menu's Multiplayer button (ui/ui.gd): host a room
## (its code in big letters), join one by its code (logged in), see the seats
## taken, start the run.

signal closed

const UITheme := preload("res://ui/theme.gd")
const SEATS := 8

var main: Node  # game/main.gd
var info: Label
var code_edit: LineEdit
var start: Button
var _host: Button
var _code_row: HBoxContainer
var _copy: Button
var _count: Label
var _link: Label
var _seats: GridContainer


func _ready() -> void:
	custom_minimum_size = Vector2(1180, 600)
	add_theme_constant_override("separation", 22)
	var head := _hbox(16)
	add_child(head)
	var back := Button.new()
	back.icon = UITheme.glyph("back", UITheme.TEXT)
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(56, 56)
	back.tooltip_text = "Back"
	back.pressed.connect(closed.emit)
	head.add_child(back)
	head.add_child(UITheme.label("Coop", "Header"))
	var sub := UITheme.label("Up to 8 mages against the waves", "", 18, UITheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)

	var body := _hbox(28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := _vbox(20)
	left.custom_minimum_size.x = 400
	body.add_child(left)

	var room := _panel(left)
	var r_col := _vbox(14)
	room.add_child(r_col)
	r_col.add_child(UITheme.label("ROOM CODE", "Caption", 15))
	_host = _button(r_col, "Create a room", func(): info.text = tr(await main.host_game()))
	_code_row = _hbox(10)
	r_col.add_child(_code_row)
	for i in 4:
		var ch := PanelContainer.new()
		ch.add_theme_stylebox_override("panel", UITheme.flat(UITheme.INK, UITheme.GOLD, 4, 0, 0))
		ch.custom_minimum_size = Vector2(64, 76)
		var l := UITheme.label("", "", 44, UITheme.GOLD)
		l.add_theme_font_override("font", UITheme.BODY_BOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ch.add_child(l)
		_code_row.add_child(ch)
	info = UITheme.label("", "", 16, UITheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	r_col.add_child(info)
	_copy = _button(r_col, "Copy the code", func(): DisplayServer.clipboard_set(main.net.code))
	_copy.icon = UITheme.glyph("copy", UITheme.TEXT, 3)

	var join := _panel(left)
	var j_col := _vbox(12)
	join.add_child(j_col)
	j_col.add_child(UITheme.label("JOIN A ROOM", "Caption", 15))
	var j_row := _hbox(10)
	j_col.add_child(j_row)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODE"
	code_edit.max_length = 4
	code_edit.custom_minimum_size = Vector2(150, 52)
	code_edit.add_theme_font_size_override("font_size", 26)
	j_row.add_child(code_edit)
	_button(j_row, "Join", func(): info.text = tr(await main.join_game(code_edit.text)))
	main.net_error.connect(func(m): info.text = tr(m))

	var seats := _panel(body)
	seats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s_col := _vbox(16)
	seats.add_child(s_col)
	var s_head := _hbox(12)
	s_col.add_child(s_head)
	_count = UITheme.label("", "Subheader", 26)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_head.add_child(_count)
	_link = UITheme.label("", "", 15, UITheme.GOOD)
	s_head.add_child(_link)
	_seats = GridContainer.new()
	_seats.columns = 2
	_seats.add_theme_constant_override("h_separation", 12)
	_seats.add_theme_constant_override("v_separation", 12)
	s_col.add_child(_seats)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s_col.add_child(spacer)
	var buttons := _hbox(14)
	s_col.add_child(buttons)
	start = _button(buttons, "Start the game", func(): main.start_run())
	start.theme_type_variation = "Primary"
	start.custom_minimum_size.x = 280
	var leave := _button(buttons, "Leave the room", func(): main.leave_game())
	leave.theme_type_variation = "Danger"
	set_meta("focus", start)


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.frame({"rings": [[UITheme.OUTLINE, 4], [UITheme.RIM, 2]],
		"bg": UITheme.PANEL, "rivets": UITheme.GOLD, "drop": 6}, 20))
	parent.add_child(p)
	return p


func _button(row: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(on_press)
	row.add_child(b)
	return b


## A seat: the mage, "Player N", host/you tags; or a free seat.
func _seat(id: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 80)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == 0:
		p.add_theme_stylebox_override("panel", UITheme.flat(Color.TRANSPARENT, UITheme.RIM, 3, 10, 0))
		var l := UITheme.label("Free seat", "", 15, UITheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		return p
	var me := id == multiplayer.get_unique_id()
	p.add_theme_stylebox_override("panel", UITheme.flat(UITheme.INK, UITheme.GOLD if me else UITheme.OUTLINE, 3, 10, 0))
	var row := _hbox(12)
	p.add_child(row)
	var mage := UITheme.octo(56, false, null if me else "")  # the others' colors are not known here
	row.add_child(mage)
	var col := _vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(UITheme.label(tr("Player %d") % id, "", 19))
	var tags := _hbox(6)
	col.add_child(tags)
	if id == 1:
		tags.add_child(UITheme.tag(tr("host").to_upper(), true))
	if me:
		tags.add_child(UITheme.tag(tr("you").to_upper()))
	return p


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var peer := multiplayer.multiplayer_peer
	var online := peer is WebRTCMultiplayerPeer
	var hosting: bool = online and multiplayer.is_server() and main.net.code != ""
	start.disabled = not multiplayer.is_server()
	_host.visible = not online
	_code_row.visible = hosting
	_copy.visible = hosting
	if hosting:
		for i in 4:
			_code_row.get_child(i).get_child(0).text = main.net.code[i] if i < main.net.code.length() else ""
	var ids := [multiplayer.get_unique_id()]
	if not online:
		_link.text = ""
		if main.net.waiting:
			info.text = tr("Connecting to the room…")
		elif main.net.error:
			info.text = tr(main.net.error)
		elif info.text == "":
			info.text = tr("Offline: solo game.")
	else:
		ids = Array(multiplayer.get_peers())
		ids.append(multiplayer.get_unique_id())
		ids.sort()
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
			info.text = tr("Connecting to the host…")
			_link.text = ""
		else:
			info.text = tr("Give this code to the other players.") if multiplayer.is_server() \
				else tr("Connected. The host starts the game.")
			_link.text = tr("Connected")
	_count.text = "Mages · %d / %d" % [ids.size(), SEATS]
	var key := str(ids)
	if _seats.get_meta("ids", "") != key:
		_seats.set_meta("ids", key)
		for c in _seats.get_children():
			c.queue_free()
		for i in SEATS:
			_seats.add_child(_seat(ids[i] if i < ids.size() else 0))
