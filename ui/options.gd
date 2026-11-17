extends CenterContainer
## Options: language, volumes, fullscreen, UI size, key rebinding and the
## controls scheme. Every change applies at once; "Back" saves (ui/settings.gd).

signal closed
signal scale_changed

const SCHEME := "Mouse: aim · left click: cast the spell\n" \
	+ "Gamepad: left stick move, right stick aim and cast, Start pause\n" \
	+ "Touch: left half move, right half aim and cast"

var _waiting := ""  # action waiting for its new key
var _keys := {}  # action -> Button


func _ready() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = "Header"
	head.text = "Options"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	box.add_child(cols)

	var general := _grid(cols)
	var lang := OptionButton.new()
	for code in Settings.LANGUAGES:
		lang.add_item(Settings.LANGUAGES[code])
	lang.select(Settings.LANGUAGES.keys().find(Settings.language()))
	lang.item_selected.connect(func(i): Settings.set_language(Settings.LANGUAGES.keys()[i]))
	_row(general, "Language", lang)
	for bus in [["Master", "Master volume"], ["Music", "Music"], ["SFX", "Effects"]]:
		var s := HSlider.new()
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size.x = 200
		s.value = Settings.get_value("audio", bus[0], 1.0)
		s.value_changed.connect(func(v): Settings.set_value("audio", bus[0], v))
		_row(general, bus[1], s)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var full := CheckButton.new()
		full.button_pressed = Settings.get_value("display", "fullscreen", false)
		full.toggled.connect(func(on): Settings.set_value("display", "fullscreen", on))
		_row(general, "Fullscreen", full)
	var ui_size := OptionButton.new()
	for f in Settings.UI_SCALES:
		ui_size.add_item("%d %%" % (f * 100))
	ui_size.select(maxi(0, Settings.UI_SCALES.find(Settings.get_value("display", "ui_scale", 1.0))))
	ui_size.item_selected.connect(func(i):
		Settings.set_value("display", "ui_scale", Settings.UI_SCALES[i])
		scale_changed.emit())
	_row(general, "Interface size", ui_size)

	var controls := _grid(cols)
	for action in Settings.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size.x = 160
		b.pressed.connect(func():
			_waiting = action
			b.text = "Press a key…")
		_keys[action] = b
		_row(controls, Settings.REBINDABLE[action], b)
	_refresh_keys()

	var scheme := Label.new()
	scheme.text = SCHEME
	scheme.add_theme_font_size_override("font_size", 16)
	box.add_child(scheme)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_close)
	box.add_child(back)
	set_meta("focus", general.get_child(1))


func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	parent.add_child(g)
	return g


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	grid.add_child(control)


func _refresh_keys() -> void:
	for action in _keys:
		_keys[action].text = Settings.key_name(action)


## While waiting for a key, the next key press is the new binding (Escape cancels).
func _input(e: InputEvent) -> void:
	if _waiting.is_empty() or not (e is InputEventKey and e.pressed and not e.echo):
		return
	get_viewport().set_input_as_handled()
	if e.physical_keycode != KEY_ESCAPE:
		Settings.set_value("controls", _waiting, e.physical_keycode)
	_waiting = ""
	_refresh_keys()


func _close() -> void:
	_waiting = ""
	_refresh_keys()
	Settings.save()
	closed.emit()
