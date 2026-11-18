extends CanvasLayer
## Every screen of the game, above the world: title menu, HUD, level-up choice,
## pause, options, end of run, shop and spell forge (between runs), achievements,
## leaderboard, multiplayer.
## Solo, the world is paused whenever a screen other than the HUD is shown;
## in coop it only stops between runs.
## UI is drawn at screen resolution (not pixel-art scaled), scaled by the
## "UI size" option. Data comes from the Run and Profile autoloads.
## The multiplayer screen is the coop lobby (game/lobby.gd), the account
## screen game/account.gd (also the title screen while logged out), then the
## characters screen game/characters.gd (after login, or without a character).

const UITheme := preload("res://ui/theme.gd")

var main: Node  # game/main.gd
var root: Control  # scaled by the UI size option
var screens := {}  # name -> Control; "" is the HUD (in run)
var current := ""
var back_to := "title"  # where options, shop... return
var hud: Control
var sticks: Control
var _dim: ColorRect  # darkens the world behind menus
var _logged_in := false  # at the last Online.changed
var _prompt: Label  # gamepad button prompts, while a gamepad is in use
var _forge_from := "title"  # the screen the forge returns to (not back_to: options... keep theirs)
var _forge_corner: Button  # the way to the forge from every screen between runs
var _on_fullscreen: JavaScriptObject  # kept alive: the browser calls it on fullscreenchange
var _halo: TextureRect  # light bloom behind the level-up cards
var _time_tween: Tween  # time back to normal after a level-up


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	Settings.load_and_apply()
	sticks = TouchSticks.new()
	sticks.main = main
	add_child(sticks)
	root = Control.new()
	root.theme = UITheme.make()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	hud = preload("res://ui/hud.gd").new()
	hud.main = main
	hud.paused.connect(open_pause)
	add_screen(hud)
	screens[""] = hud
	_dim = ColorRect.new()
	_dim.color = Color(UITheme.INK, 0.82)
	add_screen(_dim)
	_halo = _make_halo()
	screens.title = add_screen(_title())
	screens.pause = add_screen(_pause_screen())
	Run.changed.connect(_refresh_pause)
	if OS.has_feature("web"):
		# Escape out of the site's fullscreen is eaten by the browser: pause on the exit instead.
		_on_fullscreen = JavaScriptBridge.create_callback(func(_a):
			if not JavaScriptBridge.eval("!!window.parent.document.fullscreenElement"):
				open_pause())
		JavaScriptBridge.get_interface("parent").document.addEventListener("fullscreenchange", _on_fullscreen)
	var options := preload("res://ui/options.gd").new()
	options.closed.connect(back)
	options.scale_changed.connect(_layout)
	screens.options = add_screen(options)
	screens.end = add_screen(_end_screen())
	var lobby := preload("res://game/lobby.gd").new()
	lobby.main = main
	lobby.closed.connect(back)
	var lobby_screen := CenterContainer.new()
	lobby_screen.add_child(lobby)
	screens.multiplayer = add_screen(lobby_screen)
	lobby_screen.set_meta("focus", lobby.get_meta("focus"))  # set in its _ready
	var account := preload("res://game/account.gd").new()
	account.closed.connect(back)
	var account_screen := CenterContainer.new()
	account_screen.add_child(account)
	screens.account = add_screen(account_screen)
	account_screen.set_meta("focus", account.get_meta("focus"))
	var chars := preload("res://game/characters.gd").new()
	chars.closed.connect(show_screen.bind("title"))
	var chars_screen := CenterContainer.new()
	chars_screen.add_child(chars)
	screens.characters = add_screen(chars_screen)
	chars_screen.set_meta("focus", chars.get_meta("focus"))
	var shop := preload("res://ui/shop.gd").new()
	shop.main = main
	shop.closed.connect(back)
	screens.shop = add_screen(shop)
	var forge := preload("res://ui/forge.gd").new()
	forge.main = main
	forge.closed.connect(func(): show_screen(_forge_from))
	screens.forge = add_screen(forge)
	screens.achievements = add_screen(_list_screen("Achievements", _achievements_text))
	screens.leaderboard = add_screen(_list_screen("Leaderboard", _scores_text))
	screens.levelup = add_screen(_levelup_screen())

	main.run_ended.connect(_on_run_ended)
	main.run_started.connect(show_screen.bind(""))  # also on peers when the host starts
	Run.offered.connect(_show_level_up)
	Run.changed.connect(func():  # a grimoire picked up while choosing
		_level_more.text = tr("+%d more grimoire(s) waiting") % (Run.pending.size() - 1) if Run.pending.size() > 1 else "")
	Profile.changed.connect(_refresh_title)
	_forge_corner = _forge_button()
	_forge_corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_forge_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_forge_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_forge_corner.offset_right = -32
	_forge_corner.offset_bottom = -28
	root.add_child(_forge_corner)
	_prompt = UITheme.label("", "Caption", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y -= 30
	root.add_child(_prompt)
	main.run_started.connect(_fade_in)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_logged_in = Online.logged_in()  # a session restored at launch: its last character
	show_screen("title")
	Online.changed.connect(_on_session_changed)


## Just logged in: the characters screen. Otherwise the title menu, or what
## replaces it (show_screen): a character picked, logged out...
func _on_session_changed() -> void:
	var login := Online.logged_in() and not _logged_in
	_logged_in = Online.logged_in()
	if login:
		show_screen("characters")
	elif current in ["title", "account", "characters"] and current != _home():
		show_screen("title")


## What the title menu is: the account screen logged out, the characters
## screen without a character (no play without either).
func _home() -> String:
	return "account" if not Online.logged_in() else "characters" if Online.character.is_empty() else "title"


## The UI size option, capped on menus to what their layout fits in: their
## minimum size, the whole design size (1280x720) for those laid out freely.
## The HUD's top bar (stats, wave, gold side by side) needs about 1000 wide.
func _layout() -> void:
	var s: float = Settings.get_value("display", "ui_scale", 1.0)
	var view := get_viewport().get_visible_rect().size
	if current in screens:
		var need: Vector2 = screens[current].get_combined_minimum_size()
		if current == "":
			need = Vector2(1000, 540)
		elif need == Vector2.ZERO:
			need = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
				ProjectSettings.get_setting("display/window/size/viewport_height"))
		s = minf(s, minf(view.x / need.x, view.y / need.y))
	root.scale = Vector2(s, s)
	root.size = view / s


func add_screen(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.hide()
	root.add_child(c)
	return c


func show_screen(name: String) -> void:
	if name == "title":
		name = _home()
	current = name
	for k in screens:
		screens[k].visible = k == name
	sticks.visible = name == ""
	_dim.visible = name not in ["", "title", "shop", "forge", "end"]
	# Between runs, the forge is one click away (title and end of run have their own button).
	_forge_corner.visible = not Run.active and Online.logged_in() and not Online.character.is_empty() \
		and name not in ["", "pause", "levelup", "forge", "title", "end", "account", "characters"]
	_dim.color.a = 0.82 if Run.active else 1.0  # out of a run, only the idle mage would show: hide it
	if name == "levelup":
		_dim.color.a = 0.45  # the slowed world shows through
	get_tree().paused = not Run.active or (name not in ["", "levelup"] and main.solo())
	Sfx.pause_music(Run.active and name not in ["", "levelup"])  # pause menu and its options
	_slow_time(name)
	if name == "title":
		_refresh_title()
	elif name == "pause":
		_refresh_pause()
	_layout()
	_appear(screens[name])
	_focus_screen()
	_update_prompt()


## Keyboard/gamepad focus on the screen's "focus" control, else its first
## button; none in run.
func _focus_screen() -> void:
	var s: Control = screens[current]
	var first: Array = s.find_children("*", "Button", true, false).filter(
		func(b): return b.is_visible_in_tree() and b.focus_mode != Control.FOCUS_NONE)
	if current != "" and s.has_meta("focus"):
		s.get_meta("focus").grab_focus()
	elif current != "" and not first.is_empty():
		first[0].grab_focus()
	elif get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()


const RUN_FADE := 1.5  # seconds the screen takes to clear from black when a run starts


## A run starts on a black screen that slowly clears to show the map.
func _fade_in() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)  # last child of the layer: above every screen
	var tw := black.create_tween().set_ignore_time_scale()
	tw.tween_property(black, "modulate:a", 0.0, RUN_FADE)
	tw.tween_callback(black.queue_free)


## Screen transition: a fade, and the panel pops in (a slight overshoot).
func _appear(screen: Control) -> void:
	if screen == hud:
		return
	var tw := screen.create_tween().set_parallel().set_ignore_time_scale()  # level-up slow motion
	screen.modulate.a = 0.0
	tw.tween_property(screen, "modulate:a", 1.0, LEVEL_UP_FADE if screen == screens.get("levelup") else 0.12)
	var panel: Control = screen.get_child(0) if screen is CenterContainer and screen.get_child_count() else null
	if panel:
		panel.pivot_offset = panel.size / 2
		panel.scale = Vector2(0.9, 0.9)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_prompt() -> void:
	_prompt.visible = Settings.pad and current != ""
	var ok := tr("%s: confirm") % Settings.pad_button("A", tr("Cross"))
	var cancel := "  ·  " + tr("%s: back") % Settings.pad_button("B", tr("Circle"))
	_prompt.text = ok + ("" if current in ["title", "end", "levelup"] else cancel)


## Tracks the device in use: prompts, and focus back on the screen when the
## gamepad takes over (a mouse click may have left none).
func _input(e: InputEvent) -> void:
	if not Settings.track_device(e):
		return
	_update_prompt()
	if Settings.pad and current != "" and not get_viewport().gui_get_focus_owner():
		_focus_screen()


## Options and placeholders return to the screen that opened them.
func open(name: String) -> void:
	back_to = current
	show_screen(name)


func open_forge() -> void:
	_forge_from = current
	show_screen("forge")


func back() -> void:
	show_screen(back_to)


func open_pause() -> void:
	if current == "" and Run.active:
		show_screen("pause")


func resume() -> void:
	show_screen("")


func _unhandled_input(e: InputEvent) -> void:
	# Level up: 1, 2, 3 pick a card.
	if current == "levelup" and _cards_ready and e is InputEventKey and e.pressed and not e.echo \
			and e.keycode >= KEY_1 and e.keycode < KEY_1 + _level_box.get_child_count():
		get_viewport().set_input_as_handled()
		_level_box.get_child(e.keycode - KEY_1).pressed.emit()
		return
	var pause := e.is_action_pressed("pause")
	if not pause and not (e.is_action_pressed("ui_cancel") and current != ""):
		return
	get_viewport().set_input_as_handled()
	match current:
		"": open_pause()
		"pause": resume()
		"title", "end", "levelup": pass
		"characters": show_screen("title")
		"forge": show_screen(_forge_from)
		_: back()


# --- building blocks ---------------------------------------------------------

func _button(text: String, action: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	return b


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A "Label ...... value" row.
func _stat_row(name: String) -> Array:
	var row := _hbox(12)
	var l := UITheme.label(name, "", 18, UITheme.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := UITheme.label("", "", 18)
	row.add_child(v)
	return [row, v]


## A full-rect margin container holding a screen's content.
func _margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in [["left", left], ["top", top], ["right", right], ["bottom", bottom]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	return m


# --- title -------------------------------------------------------------------

var _title_gold: Label
var _title_play: Button  # "Play", or "Continue" a saved run (Profile.run)
var _title_scrolls: Label
var _title_glow: Panel  # a gold aura around the forge button while blank scrolls wait
var _title_spell: Label
var _title_name: Label
var _title_spell_icon: TextureRect


## Title menu: name, Play, the spell forge and the menu on the left, the mage
## on the right, the purse and account top right.
func _title() -> Control:
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	# The deep: stepped bands, lighter toward the bottom.
	var bands := _vbox(0)
	bands.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bands.offset_top = -360
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(bands)
	for c in ["#0d1628", "#0f1a2f", "#112036", "#13253e", "#152a46"]:
		var band := ColorRect.new()
		band.color = Color(c)
		band.size_flags_vertical = Control.SIZE_EXPAND_FILL
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bands.add_child(band)

	# The mage, right, in rings of light.
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	stage.offset_left = -560
	stage.offset_right = -80
	stage.offset_top = -240
	stage.offset_bottom = 300
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(stage)
	for ring in [[0, 480, 0.10], [64, 352, 0.16]]:
		var p := Panel.new()
		p.add_theme_stylebox_override("panel", UITheme.flat(Color.TRANSPARENT, Color(UITheme.MANA, ring[2]), 8, 0, 0))
		p.position = Vector2(ring[0], ring[0])
		p.size = Vector2(ring[1], ring[1])
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(p)
	# Above the mage: the active character's name.
	_title_name = UITheme.label("", "Header")
	_title_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a name, not a string to translate
	_title_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_name.position = Vector2(40, 64)
	_title_name.size = Vector2(400, 60)
	stage.add_child(_title_name)
	var mage := UITheme.octo(288)
	mage.position = Vector2(96, 130)
	mage.size = Vector2(288, 288)
	stage.add_child(mage)
	# Under the mage: the spell it starts the next run with.
	var spell_box := CenterContainer.new()
	spell_box.position = Vector2(0, 430)
	spell_box.size = Vector2(480, 64)
	spell_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(spell_box)
	var plate := PanelContainer.new()
	plate.theme_type_variation = "Plate"
	spell_box.add_child(plate)
	var s_row := _hbox(10)
	plate.add_child(s_row)
	_title_spell_icon = UITheme.icon_rect(null, 40)
	s_row.add_child(_title_spell_icon)
	_title_spell = UITheme.label("", "", 22, UITheme.GOLD)
	s_row.add_child(_title_spell)

	var m := _margin(72, 56, 32, 28)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(m)
	var left := _vbox(12)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.custom_minimum_size.x = 400
	m.add_child(left)
	left.add_child(UITheme.label("Octo Magic", "Title"))
	left.add_child(UITheme.label("Create your spells, combine them, survive the waves.", "", 22, UITheme.TEXT_DIM))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	left.add_child(gap)

	var play := _button("Play", _play, "Primary")
	play.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # _refresh_title translates it
	_title_play = play
	play.custom_minimum_size.y = 76
	play.add_theme_font_size_override("font_size", 32)
	play.icon = UITheme.glyph("play", UITheme.ON_GOLD)
	play.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play.add_theme_constant_override("h_separation", 0)
	left.add_child(play)
	bg.set_meta("focus", play)
	var forge := _forge_button()
	_title_scrolls = UITheme.label("", "", 18, UITheme.GOLD)  # the blank scrolls, right in the button
	_title_scrolls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_title_scrolls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_title_scrolls.offset_right = -20
	forge.add_child(_title_scrolls)
	_title_glow = Panel.new()
	var aura := StyleBoxFlat.new()
	aura.bg_color = UITheme.GOLD
	aura.set_corner_radius_all(12)
	aura.shadow_color = Color(UITheme.GOLD, 0.6)
	aura.shadow_size = 16
	_title_glow.add_theme_stylebox_override("panel", aura)
	_title_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_glow.show_behind_parent = true
	_title_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forge.add_child(_title_glow)
	var pulse := _title_glow.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_title_glow, "modulate:a", 0.35, 1.2)
	pulse.tween_property(_title_glow, "modulate:a", 1.0, 1.2)
	left.add_child(forge)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)
	var items := [["Multiplayer", open.bind("multiplayer")], ["Characters", open.bind("characters")], ["Shop", open.bind("shop")],
		["Achievements", open.bind("achievements")], ["Leaderboard", open.bind("leaderboard")],
		["Options", open.bind("options")]]
	if not OS.has_feature("web"):
		items.append(["Quit", get_tree().quit])
	for it in items:
		var b := _button(it[0], it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	left.add_child(_spacer())

	# Top right: the purse and the account.
	var corner := _hbox(12)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -32
	corner.offset_top = 28
	bg.add_child(corner)
	var purse := PanelContainer.new()
	purse.theme_type_variation = "Plate"
	var p_row := _hbox(8)
	purse.add_child(p_row)
	p_row.add_child(UITheme.icon_rect(UITheme.icon("gold"), 32))
	_title_gold = UITheme.label("", "", 22, UITheme.GOLD)
	p_row.add_child(_title_gold)
	corner.add_child(purse)
	var account := _button("Account", open.bind("account"))
	account.icon = UITheme.glyph("user", UITheme.TEXT_DIM)
	corner.add_child(account)
	return bg


## The way to the spell forge, the heart of the game: a big parchment-red button.
func _forge_button() -> Button:
	var b := _button("Spell forge", open_forge)
	b.custom_minimum_size.y = 64
	b.add_theme_font_override("font", UITheme.PARCHMENT)
	b.add_theme_font_size_override("font_size", 30)
	b.icon = UITheme.icon("scroll")
	b.expand_icon = false
	var seal := {"rings": [[UITheme.OUTLINE, 4], [UITheme.GOLD_DIM, 2]], "bg": Color("#7a2f17"), "top": Color("#94401f"),
		"bottom": Color("#55200f"), "drop": 5}
	b.add_theme_stylebox_override("normal", UITheme.frame(seal, 10))
	b.add_theme_stylebox_override("hover", UITheme.frame(seal.merged({"bg": Color("#8e3a1d")}, true), 10))
	b.add_theme_stylebox_override("pressed", UITheme.frame(seal.merged({"drop": 0, "top": Color("#55200f")}, true), 10, 5))
	for c in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(c, UITheme.PARCH_LIGHT)
	return b


func _refresh_title() -> void:
	if not _title_gold:
		return
	_title_gold.text = str(Profile.gold)
	var w := int(Profile.run.get("wave", -1)) + 1
	_title_play.text = tr("Continue · wave %d") % w if w > 0 else tr("Play")
	var spell: Dictionary = Profile.equipped_spells().primary
	_title_spell.text = Spell.label(spell)
	_title_name.text = Online.character_name()
	_title_spell_icon.texture = preload("res://ui/hud.gd")._icon(spell)
	var n: int = Profile.blank_scrolls
	_title_scrolls.text = tr("No blank scroll") if not n else (tr("%d blank scroll") if n == 1 else tr("%d blank scrolls")) % n
	_title_glow.visible = n > 0


# --- lists (achievements, leaderboard) ---------------------------------------

## A centered panel: header, then an extra control, then [label, callable] buttons.
func _menu(title: String, buttons: Array, extra: Control = null) -> Control:
	var center := CenterContainer.new()
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := _vbox(16)
	panel.add_child(box)
	var head := UITheme.label(title, "Header")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	if extra:
		box.add_child(extra)
	for b in buttons:
		var btn := _button(b[0], b[1])
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size.x = 320
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(btn)
		if not center.has_meta("focus"):
			center.set_meta("focus", btn)
	return center


## A screen showing `text_fn.call()` in a sunken box, refreshed each time it is shown.
func _list_screen(title: String, text_fn: Callable) -> Control:
	var well := PanelContainer.new()
	well.theme_type_variation = "Well"
	var l := UITheme.label("", "", 18)
	well.add_child(l)
	var c := _menu(title, [["Back", back]], well)
	c.visibility_changed.connect(func(): l.text = text_fn.call())
	return c


func _achievements_text() -> String:
	var lines := []
	for id in Profile.ACHIEVEMENTS:
		var a: Dictionary = Profile.ACHIEVEMENTS[id]
		var have: int = mini(Profile.stats.get(a.stat, 0), a.goal)
		lines.append("%s  %s · %s%s" % ["✔" if Profile.achievements.has(id) else "·", tr(a.name), tr(a.desc),
			"" if Profile.achievements.has(id) else "  (%d/%d)" % [have, a.goal]])
	return "\n".join(lines)


func _scores_text() -> String:
	var lines := []
	for i in Profile.scores.size():
		var r: Dictionary = Profile.scores[i]
		lines.append(tr("%2d.  %6d pts   wave %d, level %d, %d enemies   %s") % [i + 1, r.score, r.wave,
			r.level, r.kills, Time.get_date_string_from_unix_time(r.time)])
	return "\n".join(lines) if lines else tr("No score yet: start a run!")


# --- pause -------------------------------------------------------------------

var _pause_rows := {}  # "wave", "level", "kills", "gold", "scrolls" -> value Label
var _pause_note: Label  # forge news
var _pause_picks: HFlowContainer
var _pause_quit: Button  # solo only
var _pause_levels := {}  # Run.levels shown in _pause_picks


## Pause: menu and run summary (nothing is bought in a run: the shop is
## between runs).
func _pause_screen() -> Control:
	var center := CenterContainer.new()
	var panel := PanelContainer.new()
	center.add_child(panel)
	var left := _vbox(14)
	left.custom_minimum_size.x = 340
	panel.add_child(left)
	left.add_child(UITheme.label("Pause", "Header"))
	var resume_b := _button("Resume", resume, "Primary")
	left.add_child(resume_b)
	center.set_meta("focus", resume_b)
	left.add_child(_button("Options", open.bind("options")))
	_pause_quit = _button("Save and quit", _quit_run)
	left.add_child(_pause_quit)
	left.add_child(_button("Abandon run", main.abandon_run, "Danger"))
	var well := PanelContainer.new()
	well.theme_type_variation = "Well"
	var sum := _vbox(10)
	well.add_child(sum)
	for k in [["wave", "Wave"], ["level", "Level"], ["kills", "Enemies defeated"], ["gold", "Gold"], ["scrolls", "Scrolls found"]]:
		var r := _stat_row(k[1])
		sum.add_child(r[0])
		_pause_rows[k[0]] = r[1]
	_pause_note = UITheme.label("", "", 14, UITheme.TEXT_DIM)
	_pause_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	sum.add_child(_pause_note)
	sum.add_child(UITheme.label("Upgrades taken", "Caption"))
	_pause_picks = HFlowContainer.new()
	_pause_picks.add_theme_constant_override("h_separation", 6)
	_pause_picks.add_theme_constant_override("v_separation", 6)
	sum.add_child(_pause_picks)
	left.add_child(well)
	return center


func _refresh_pause() -> void:
	_pause_quit.visible = main.solo()
	_pause_rows.wave.text = str(Run.wave)
	_pause_rows.level.text = str(Run.level)
	_pause_rows.kills.text = str(Run.kills)
	_pause_rows.gold.text = str(Run.gold)
	_pause_rows.scrolls.text = str(Run.scrolls)
	_pause_note.text = main.forge_note
	_pause_note.visible = main.forge_note != ""
	if _pause_levels != Run.levels:  # Run.changed fires on every kill
		_pause_levels = Run.levels.duplicate()
		for c in _pause_picks.get_children():
			c.queue_free()
		_skill_icons(_pause_picks, 40)


## The run's skills in `box`, icons of `size` px, their name, level and
## effect as a tooltip.
func _skill_icons(box: Control, size: int) -> void:
	for id in Run.levels:
		var icon := UITheme.icon_box(UITheme.icon("up_" + id), size, UITheme.RIM)
		var u: Dictionary = Run.list[id]
		icon.tooltip_text = "%s\n%s" % [Upgrades.title(u, Run.levels[id]), Upgrades.describe(u)]
		icon.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # already translated
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(icon)


# --- level up ----------------------------------------------------------------

const LEVEL_UP_TIME_SCALE := 0.05  # solo: the world crawls while the player picks
const LEVEL_UP_RECOVER := 1.5  # seconds (real time) back to full speed after the pick
const LEVEL_UP_FADE := 0.5  # seconds (real time) the choice fades in, cards locked meanwhile
const GRIMOIRES := {"hero": ["Red grimoire", Color("#ff6b5a")], "spell": ["Blue grimoire", Color("#5aa8ff")]}

var _level_box: HBoxContainer
var _level_title: Label
var _level_more: Label
var _cards_ready := false  # the choice fully shown: a click meant for a spell can't pick a card
var _arm_tween: Tween


func _levelup_screen() -> Control:
	var c := CenterContainer.new()
	var box := _vbox(10)
	c.add_child(box)
	_level_title = UITheme.label("", "Header")
	_level_title.add_theme_font_size_override("font_size", 56)
	_level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_level_title)
	var sub := UITheme.label("Pick an upgrade for this run", "", 20, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	box.add_child(gap)
	_level_box = _hbox(28)
	_level_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_level_box)
	gap = Control.new()
	gap.custom_minimum_size.y = 22
	box.add_child(gap)
	var hints := _hbox(22)
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_child(UITheme.label("1 · 2 · 3 or click to pick", "Caption"))
	_level_more = UITheme.label("", "", 16, UITheme.GOLD)
	hints.add_child(_level_more)
	box.add_child(hints)
	return c


func _show_level_up(offers: Array) -> void:
	for c in _level_box.get_children():  # not free(): a pressed button is mid-signal
		_level_box.remove_child(c)
		c.queue_free()
	var g: Array = GRIMOIRES[Run.pending[0]]
	_level_title.text = tr(g[0])
	_level_title.add_theme_color_override("font_color", g[1])
	_cards_ready = false
	for i in offers.size():
		var o: Dictionary = offers[i]
		var u: Dictionary = Run.list[o.id]
		var b := _button("", func():
			if not _cards_ready:  # gamepad/keyboard accept on the focused card
				return
			var more := Run.choose(i)
			main.send_loadout(false)
			if not more:
				show_screen(""))
		b.theme_type_variation = "Card"
		b.custom_minimum_size = Vector2(264, 372)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # until _arm_cards: no press can start on it
		var glow := Panel.new()  # gold halo, lit by _arm_cards
		var gs := UITheme.flat(Color.TRANSPARENT, UITheme.GOLD, 3, 0, 0)
		gs.draw_center = false
		gs.set_corner_radius_all(10)
		gs.shadow_color = Color(UITheme.GOLD, 0.7)
		gs.shadow_size = 18
		gs.set_expand_margin_all(4)
		glow.add_theme_stylebox_override("panel", gs)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.show_behind_parent = true
		glow.modulate.a = 0.0
		glow.name = "Glow"
		b.add_child(glow)
		var m := _margin(20, 16, 20, 22)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var card := _vbox(12)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(card)
		var num := PanelContainer.new()
		num.add_theme_stylebox_override("panel", UITheme.flat(UITheme.OUTLINE, UITheme.OUTLINE, 0, 0, 0))
		num.custom_minimum_size = Vector2(30, 30)
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := UITheme.label(str(i + 1), "", 18, UITheme.TEXT_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_child(n)
		card.add_child(num)
		card.add_child(UITheme.icon_box(UITheme.icon("up_" + o.id), 112))
		b.self_modulate = g[1].lerp(Color.WHITE, 0.4)  # the card's frame takes the grimoire's hue
		var maxed: bool = o.level == u.max
		for line in [[Upgrades.title(u, o.level), 28, g[1].lerp(Color.WHITE, 0.3), true],
				[Upgrades.describe(u), 19, UITheme.TEXT, false],
				[tr("Max level") if maxed else tr("Level %d / %d") % [o.level, u.max], 14, UITheme.GOLD if maxed else UITheme.TEXT_DIM, false]]:
			var l := UITheme.label(line[0], "", line[1], line[2])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			if line[3]:
				l.add_theme_font_override("font", UITheme.BODY_BOLD)
			card.add_child(l)
		_level_box.add_child(b)
	screens.levelup.set_meta("focus", _level_box.get_child(0))
	show_screen("levelup")
	Sfx.play("level_up")
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween().set_ignore_time_scale()
	_arm_tween.tween_interval(LEVEL_UP_FADE)
	_arm_tween.tween_callback(_arm_cards)


## The choice is fully opaque: the cards take clicks and light their gold halo.
func _arm_cards() -> void:
	_cards_ready = true
	var tw := create_tween().set_ignore_time_scale().set_parallel()
	for b in _level_box.get_children():
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		tw.tween_property(b.get_node("Glow"), "modulate:a", 1.0, 0.25)


## Solo level-up: time almost stops while the halo blooms, then eases back to
## normal once the last upgrade is picked. Coop keeps the shared clock.
func _slow_time(name: String) -> void:
	if _time_tween:
		_time_tween.kill()
	if name not in ["", "levelup"] or (name == "" and not _halo.visible):
		Engine.time_scale = 1.0
		_halo.hide()
		return
	var tw := create_tween().set_ignore_time_scale().set_parallel()
	_time_tween = tw
	if name == "levelup":
		_halo.show()
		_halo.scale = Vector2(0.3, 0.3)
		_halo.modulate.a = 0.0
		tw.tween_property(_halo, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_halo, "modulate:a", 1.0, 0.3)
		if main.solo():
			tw.tween_property(Engine, "time_scale", LEVEL_UP_TIME_SCALE, 0.3).set_ease(Tween.EASE_OUT)
	else:  # the last pick made
		tw.tween_property(_halo, "modulate:a", 0.0, 0.4)
		tw.tween_property(Engine, "time_scale", 1.0, LEVEL_UP_RECOVER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(_halo.hide)


## A warm radial glow, centred on the screen (the camera follows the mage).
func _make_halo() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.9])
	g.colors = PackedColorArray([Color(UITheme.GOLD_LIGHT, 0.9), Color(UITheme.GOLD, 0.55), Color(UITheme.GOLD, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var h := TextureRect.new()
	h.texture = tex
	h.stretch_mode = TextureRect.STRETCH_SCALE
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	h.material = mat
	add_screen(h)
	h.resized.connect(func(): h.pivot_offset = h.size / 2)
	return h


# --- end of run --------------------------------------------------------------

var _end_sub: Label
var _end_tiles := {}  # "wave", "level", "kills", "score" -> value Label
var _end_score_name: Label
var _end_gold: Label
var _end_scrolls: Label
var _end_news: VBoxContainer
var _end_picks: HFlowContainer
var _end_again: Button


## End of run, full screen: what the run was worth, then the way back (again,
## the forge for the scrolls, the main menu).
func _end_screen() -> Control:
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	var m := _margin(64, 40, 64, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(m)
	var col := _vbox(18)
	m.add_child(col)
	var head := UITheme.label("End of run", "Header")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 56)
	col.add_child(head)
	_end_sub = UITheme.label("", "", 22, UITheme.TEXT_DIM)
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_end_sub)
	var tiles := _hbox(14)
	col.add_child(tiles)
	for k in [["wave", "Wave reached"], ["level", "Level"], ["kills", "Enemies defeated"], ["bosses", "Bosses defeated"], ["score", "Score"]]:
		var tile := PanelContainer.new()
		tile.theme_type_variation = "Tile"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _vbox(0)
		tile.add_child(v)
		var name := UITheme.label(k[1], "Caption")
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name)
		var value := UITheme.label("", "Big")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(value)
		_end_tiles[k[0]] = value
		if k[0] == "score":
			_end_score_name = name
		tiles.add_child(tile)
	var gains := PanelContainer.new()
	gains.theme_type_variation = "Tile"
	var g_row := _hbox(48)
	g_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gains.add_child(g_row)
	for g in [["gold", true], ["scroll", false]]:
		var r := _hbox(8)
		r.add_child(UITheme.icon_rect(UITheme.icon(g[0]), 32))
		var l := UITheme.label("", "", 22, UITheme.GOLD if g[1] else UITheme.TEXT)
		r.add_child(l)
		g_row.add_child(r)
		if g[1]:
			_end_gold = l
		else:
			_end_scrolls = l
	col.add_child(gains)
	var cap := UITheme.label("Upgrades taken", "Caption")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	_end_picks = HFlowContainer.new()
	_end_picks.alignment = FlowContainer.ALIGNMENT_CENTER
	_end_picks.add_theme_constant_override("h_separation", 6)
	_end_picks.add_theme_constant_override("v_separation", 6)
	col.add_child(_end_picks)
	_end_news = _vbox(8)
	_end_news.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_end_news)
	col.add_child(_spacer())
	var buttons := _hbox(24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_again = _button("Play again", _play, "Primary")
	buttons.add_child(_end_again)
	buttons.add_child(_forge_button())
	var menu := _button("Main menu", _to_title)
	buttons.add_child(menu)
	for b in [_end_again, menu]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size.x = 240
	col.add_child(buttons)
	bg.set_meta("focus", _end_again)
	return bg


func _news(color: Color, head: String, text: String) -> void:
	var row := _hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(UITheme.label(head, "", 18, color))
	row.add_child(UITheme.label(text, "", 18))
	_end_news.add_child(row)


func _on_run_ended() -> void:
	var r: Dictionary = main.last_run
	_end_sub.text = tr("The octo-mage fell at wave %d.") % r.wave
	_end_tiles.wave.text = str(r.wave)
	_end_tiles.level.text = str(r.level)
	_end_tiles.kills.text = str(r.kills)
	_end_tiles.bosses.text = str(r.bosses)
	_end_tiles.score.text = str(r.score)
	var best: bool = not Profile.scores.is_empty() and r.score > 0 and r.score >= Profile.scores[0].score
	_end_score_name.text = tr("Score · record!") if best else "Score"
	_end_tiles.score.add_theme_color_override("font_color", UITheme.GOLD if best else UITheme.TEXT)
	_end_gold.text = tr("+%d gold") % r.gold
	_end_scrolls.text = tr("+%d scroll(s)") % r.scrolls
	for c in _end_news.get_children():
		c.queue_free()
	for c in _end_picks.get_children():
		c.queue_free()
	_skill_icons(_end_picks, 48)
	for id in r.reached:
		_news(UITheme.GOLD, tr("Achievement:"), tr(Profile.ACHIEVEMENTS[id].name))
	for e in r.unlocked:
		_news(UITheme.MANA.lightened(0.3), tr("Spell unlocked:"), Spell.label(e.spell))
	if not multiplayer.is_server():
		_news(UITheme.TEXT_DIM, "", tr("In coop, only the host starts a new run."))
	_end_again.disabled = not multiplayer.is_server()  # "Play again": the host restarts
	show_screen("end")


## The HUD shows on run_started (in coop only the host starts the run).
func _play() -> void:
	if not Online.logged_in() or Online.character.is_empty():
		show_screen("title")
		return
	if Profile.run.is_empty():
		main.start_run()
	else:
		main.resume_run()


## Solo: the run is kept as it was at the start of the wave, Play continues it.
func _quit_run() -> void:
	main.quit_run()
	show_screen("title")


func _to_title() -> void:
	main.leave()
	show_screen("title")


## Twin-stick touch controls, drawn where the fingers are (game/player.gd reads
## the touches). Shown on touch screens only, in screen pixels.
class TouchSticks extends Control:
	var main: Node

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not DisplayServer.is_touchscreen_available():
			return
		var player: Node2D = main.local_player()
		if not player:
			return
		var r: float = player.STICK_RANGE
		for pair in [[player._touch_move, Vector2(0.15, 0.78)], [player._touch_aim, Vector2(0.85, 0.78)]]:
			var base: Vector2 = size * pair[1]
			var knob := base
			for k in pair[0]:
				base = pair[0][k][0]
				knob = base + (pair[0][k][1] - base).limit_length(r)
			draw_circle(base, r, Color(1, 1, 1, 0.08))
			draw_arc(base, r, 0.0, TAU, 48, Color(UITheme.GOLD, 0.5), 3.0, true)
			draw_circle(knob, r * 0.35, Color(UITheme.TEXT, 0.35))
