extends PanelContainer
## Account screen (ui/ui.gd): log in or create an account (game/online.gd),
## log out. Logged out, it replaces the title menu: no play without an account.

signal closed

var info: Label
var mail: LineEdit
var password: LineEdit
var buttons := {}


func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.theme_type_variation = "Header"
	title.text = "Account"
	box.add_child(title)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	mail = LineEdit.new()
	mail.placeholder_text = "email"
	box.add_child(mail)
	password = LineEdit.new()
	password.placeholder_text = "password"
	password.secret = true
	password.text_submitted.connect(func(_t): _login(false))
	box.add_child(password)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	box.add_child(row)
	for b in [["Log in", func(): _login(false)], ["Create an account", func(): _login(true)],
			["Log in with Google", _google], ["Log out", Online.logout], ["Back", closed.emit]]:
		var button := Button.new()
		button.text = b[0]
		if b[0] == "Log in":
			button.theme_type_variation = "Primary"
		button.pressed.connect(b[1])
		row.add_child(button)
		buttons[b[0]] = button
	set_meta("focus", mail)
	Online.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var on := Online.logged_in()
	for k in buttons:
		buttons[k].visible = on == (k in ["Log out", "Back"])
	mail.visible = not on
	password.visible = not on
	info.text = (tr("Logged in: %s") % Online.email if on else tr("Log in or create an account to play.")) \
		+ ("\n" + tr(Online.status) if Online.status else "")


func _login(create: bool) -> void:
	info.text = tr("Logging in…")
	var err := await Online.login(mail.text, password.text, create)
	password.text = ""
	_refresh()
	if err:
		info.text = tr("Failed: %s") % tr(err)


func _google() -> void:
	info.text = tr("Log in with Google in the browser…")
	var err := await Online.login_google()
	_refresh()
	if err:
		info.text = tr("Failed: %s") % tr(err)
