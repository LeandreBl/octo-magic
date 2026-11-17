extends PanelContainer
## Account screen, behind the menu's Account button (ui/ui.gd): log in or
## create an account (game/online.gd), log out.

signal closed

var info: Label
var mail: LineEdit
var password: LineEdit


func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)
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
	var row := HBoxContainer.new()
	box.add_child(row)
	for b in [["Log in", func(): _login(false)], ["Create an account", func(): _login(true)],
			["Log out", Online.logout], ["Back", closed.emit]]:
		var button := Button.new()
		button.text = b[0]
		button.pressed.connect(b[1])
		row.add_child(button)
	set_meta("focus", mail)
	Online.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	info.text = (tr("Logged in: %s") % Online.email if Online.logged_in() else tr("Offline: local profile only.")) \
		+ ("\n" + tr(Online.status) if Online.status else "")


func _login(create: bool) -> void:
	info.text = tr("Logging in…")
	var err := await Online.login(mail.text, password.text, create)
	password.text = ""
	_refresh()
	if err:
		info.text = tr("Failed: %s") % tr(err)
