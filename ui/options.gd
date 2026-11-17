extends CenterContainer
## Options, in two tabs: General (language, interface size, fullscreen,
## volumes) and Controls (key rebinding and the controls scheme). Every change
## applies at once; "Back" saves (ui/settings.gd).

signal closed
signal scale_changed

const UITheme := preload("res://ui/theme.gd")
const SCHEME := "Mouse: aim · left click: cast the spell · right click or Space: secondary spell\n" \
	+ "Gamepad: left stick move, right stick aim and cast, RT cast, RB secondary spell, Start pause\n" \
	+ "Menus with a gamepad: d-pad or left stick, A confirm, B back\n" \
	+ "Browser: press a gamepad button so it is detected\n" \
	+ "Touch: left half move, right half aim and cast, touch a slot to cast it"

var _waiting := ""  # action waiting for its new key
var _keys := {}  # action -> Button
var _pages := {}  # tab name -> Control


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 920
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 28)
	box.add_child(head)
	head.add_child(UITheme.label("Options", "Header"))
	var group := ButtonGroup.new()
	for t in ["General", "Controls"]:
		var tab := Button.new()
		tab.text = t
		tab.theme_type_variation = "Tab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = t == "General"
		tab.size_flags_vertical = Control.SIZE_SHRINK_END
		tab.pressed.connect(func():
			for k in _pages:
				_pages[k].visible = k == t)
		head.add_child(tab)
	box.add_child(_rule())

	# General: display on the left, sound on the right.
	var general := HBoxContainer.new()
	general.add_theme_constant_override("separation", 56)
	box.add_child(general)
	_pages.General = general
	var display := _column(general, "DISPLAY")
	var lang := OptionButton.new()
	lang.custom_minimum_size = Vector2(200, 44)
	for code in Settings.LANGUAGES:
		lang.add_item(Settings.LANGUAGES[code])
	lang.select(Settings.LANGUAGES.keys().find(Settings.language()))
	lang.item_selected.connect(func(i): Settings.set_language(Settings.LANGUAGES.keys()[i]))
	_row(display, "Language", lang)
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 0)
	var size_group := ButtonGroup.new()
	var scale: float = Settings.get_value("display", "ui_scale", 1.0)
	for f in Settings.UI_SCALES:
		var b := Button.new()
		b.text = "%d %%" % (f * 100)
		b.theme_type_variation = "SideTab"
		b.toggle_mode = true
		b.button_group = size_group
		b.button_pressed = is_equal_approx(f, scale)
		b.custom_minimum_size = Vector2(70, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			Settings.set_value("display", "ui_scale", f)
			scale_changed.emit())
		sizes.add_child(b)
	_row(display, "Interface size", sizes)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var full := CheckButton.new()
		full.button_pressed = Settings.get_value("display", "fullscreen", false)
		full.toggled.connect(func(on): Settings.set_value("display", "fullscreen", on))
		_row(display, "Fullscreen", full)
	var sound := _column(general, "SOUND")
	for bus in [["Master", "Master volume"], ["Music", "Music"], ["SFX", "Effects"], ["UI", "Interface"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var s := HSlider.new()
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size.x = 220
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value = Settings.get_value("audio", bus[0], 1.0)
		var value := UITheme.label("%d" % roundi(s.value * 100), "", 17, UITheme.TEXT_DIM)
		value.custom_minimum_size.x = 40
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.value_changed.connect(func(v):
			value.text = "%d" % roundi(v * 100)
			Settings.set_value("audio", bus[0], v))
		row.add_child(s)
		row.add_child(value)
		_row(sound, bus[1], row)

	# Controls: rebindable keys, and how each device plays.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 56)
	controls.hide()
	box.add_child(controls)
	_pages.Controls = controls
	var keys := _column(controls, "KEYS")
	for action in Settings.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size.x = 160
		b.pressed.connect(func():
			_waiting = action
			b.text = "Press a key…")
		_keys[action] = b
		_row(keys, Settings.REBINDABLE[action], b)
	_refresh_keys()
	var scheme := _column(controls, "DEVICES")
	var text := UITheme.label(SCHEME, "", 17)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size.x = 400
	scheme.add_child(text)

	box.add_child(_rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	box.add_child(foot)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.x = 200
	back.pressed.connect(_close)
	foot.add_child(back)
	var hint := UITheme.label("Every setting applies at once · Esc to go back", "Caption")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	set_meta("focus", lang)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UITheme.INK
	r.custom_minimum_size.y = 3
	return r


## A column with a small caps caption, holding rows.
func _column(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UITheme.label(title, "Caption", 15))
	parent.add_child(col)
	return col


## "Name ........ control", at least 52 px high.
func _row(col: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.custom_minimum_size.y = 52
	var l := UITheme.label(text, "", 19)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	col.add_child(row)


func _refresh_keys() -> void:
	for action in _keys:
		_keys[action].text = Settings.key_name(action)


## While waiting for a key, the next key press is the new binding (Escape or a
## gamepad button cancels). Otherwise Escape / B / Start close and save.
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _waiting.is_empty():
		if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_close()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode != KEY_ESCAPE:
			Settings.set_value("controls", _waiting, e.physical_keycode)
	elif not (e is InputEventJoypadButton and e.pressed):
		return
	get_viewport().set_input_as_handled()
	_waiting = ""
	_refresh_keys()


func _close() -> void:
	_waiting = ""
	_refresh_keys()
	Settings.save()
	closed.emit()
