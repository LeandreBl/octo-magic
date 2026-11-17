extends CanvasLayer
## Every screen of the game, above the world: title menu, HUD, level-up choice,
## pause, options, end of run, shop, achievements, leaderboard, multiplayer.
## Solo, the world is paused whenever a screen other than the HUD is shown;
## in coop it only stops between runs.
## UI is drawn at screen resolution (not pixel-art scaled), scaled by the
## "UI size" option. Data comes from the Run and Profile autoloads.
## The multiplayer screen is the coop lobby (game/lobby.gd), the account
## screen game/account.gd (also the title screen while logged out).

const UITheme := preload("res://ui/theme.gd")

var main: Node  # game/main.gd
var root: Control  # scaled by the UI size option
var screens := {}  # name -> Control; "" is the HUD (in run)
var current := ""
var back_to := "title"  # where options, shop... return
var hud: Control
var sticks: Control
var _dim: ColorRect  # darkens the world behind menus


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
	_dim.color = Color(UITheme.INK, 0.75)
	add_screen(_dim)
	screens.title = add_screen(_title())
	screens.pause = add_screen(_menu("Pause", [
		["Resume", resume],
		["Options", open.bind("options")],
		["Abandon run", main.abandon_run]]))
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
	var shop := preload("res://ui/shop.gd").new()
	shop.main = main
	shop.closed.connect(back)
	screens.shop = add_screen(shop)
	screens.achievements = add_screen(_list_screen("Achievements", _achievements_text))
	screens.leaderboard = add_screen(_list_screen("Leaderboard", _scores_text))
	_level_box = HBoxContainer.new()
	_level_box.add_theme_constant_override("separation", 18)
	screens.levelup = add_screen(_menu("Level up!", [], _level_box))

	main.run_ended.connect(_on_run_ended)
	main.run_started.connect(show_screen.bind(""))  # also on peers when the host starts
	Run.leveled_up.connect(_show_level_up)
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_screen("title")
	Online.changed.connect(_on_session_changed)


## Logged out, the title menu is the account screen (no play without an account).
func _on_session_changed() -> void:
	var home := "title" if Online.logged_in() else "account"
	if current in ["title", "account"] and current != home:
		show_screen(home)


func _layout() -> void:
	var s: float = Settings.get_value("display", "ui_scale", 1.0)
	root.scale = Vector2(s, s)
	root.size = get_viewport().get_visible_rect().size / s


func add_screen(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.hide()
	root.add_child(c)
	return c


func show_screen(name: String) -> void:
	if name == "title" and not Online.logged_in():
		name = "account"
	current = name
	for k in screens:
		screens[k].visible = k == name
	sticks.visible = name == ""
	_dim.visible = name not in ["", "title"]
	get_tree().paused = not Run.active or (name != "" and main.solo())
	_appear(screens[name])
	if screens[name].has_meta("focus"):
		screens[name].get_meta("focus").grab_focus()
	elif get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()


## Screen transition: a fade, and the panel pops in (a slight overshoot).
func _appear(screen: Control) -> void:
	if screen == hud:
		return
	var tw := screen.create_tween().set_parallel()
	screen.modulate.a = 0.0
	tw.tween_property(screen, "modulate:a", 1.0, 0.12)
	var panel: Control = screen.get_child(0) if screen is CenterContainer and screen.get_child_count() else null
	if panel:
		panel.pivot_offset = panel.size / 2
		panel.scale = Vector2(0.9, 0.9)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Options and placeholders return to the screen that opened them.
func open(name: String) -> void:
	back_to = current
	show_screen(name)


func back() -> void:
	show_screen(back_to)


func open_pause() -> void:
	if current == "" and Run.active:
		show_screen("pause")


func resume() -> void:
	show_screen("")


func _unhandled_input(e: InputEvent) -> void:
	var pause := e.is_action_pressed("pause")
	if not pause and not (e.is_action_pressed("ui_cancel") and current != ""):
		return
	get_viewport().set_input_as_handled()
	match current:
		"": open_pause()
		"pause": resume()
		"title", "end", "levelup": pass
		_: back()


# --- screens -----------------------------------------------------------------

## A centered panel: header, then a column of [label, callable] buttons.
func _menu(title: String, buttons: Array, extra: Control = null) -> Control:
	var center := CenterContainer.new()
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = "Header"
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	if extra:
		box.add_child(extra)
	for b in buttons:
		var btn := _button(b[0], b[1])
		btn.custom_minimum_size.x = 320
		box.add_child(btn)
		if not center.has_meta("focus"):
			center.set_meta("focus", btn)
	return center


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _title() -> Control:
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var frame := PanelContainer.new()  # the icon has an opaque background: frame it
	frame.theme_type_variation = "Plate"
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(UITheme.icon_rect(preload("res://assets/icon.png"), 104))
	box.add_child(frame)
	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = "Octo Magic"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Write your spells, survive the waves."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(sub)
	box.add_child(Control.new())  # spacer
	var items := [["Play", _play], ["Multiplayer", open.bind("multiplayer")], ["Account", open.bind("account")],
		["Shop", open.bind("shop")], ["Achievements", open.bind("achievements")],
		["Leaderboard", open.bind("leaderboard")], ["Options", open.bind("options")]]
	if not OS.has_feature("web"):
		items.append(["Quit", get_tree().quit])
	# "Play" stands out; the rest in two columns, to fit a landscape phone.
	var play := _button(items[0][0], items[0][1])
	play.custom_minimum_size = Vector2(416, 64)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.add_theme_font_size_override("font_size", 30)
	play.add_theme_font_override("font", UITheme.PIXEL_BOLD)
	box.add_child(play)
	bg.set_meta("focus", play)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for it in items.slice(1):
		var b := _button(it[0], it[1])
		b.custom_minimum_size = Vector2(200, 0)
		grid.add_child(b)
	return bg


## A screen showing `text_fn.call()`, refreshed each time it is shown.
func _list_screen(title: String, text_fn: Callable) -> Control:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 18)
	var c := _menu(title, [["Back", back]], l)
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


var _level_box: HBoxContainer


func _show_level_up(offers: Array) -> void:
	for c in _level_box.get_children():  # not free(): a pressed button is mid-signal
		_level_box.remove_child(c)
		c.queue_free()
	for i in offers.size():
		var o: Dictionary = offers[i]
		var u: Dictionary = Upgrades.LIST[o.id]
		var b := _button("", func():
			var more := Run.choose(i)
			main.send_loadout(false)
			if not more:
				show_screen(""))
		b.theme_type_variation = "Card"
		b.custom_minimum_size = Vector2(220, 250)
		var card := VBoxContainer.new()
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
		card.add_theme_constant_override("separation", 8)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		var pic := UITheme.icon_rect(UITheme.icon("up_" + o.id), 96)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_child(pic)
		for line in [[u.name, 26, UITheme.GOLD], [u.desc, 18, UITheme.TEXT],
				[tr("%s: %s") % [tr(Upgrades.SLOT_NAMES[o.slot]), Spell.label(Run.spells[o.slot])], 14, UITheme.TEXT_DIM]]:
			var l := Label.new()
			l.text = line[0]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.add_theme_font_size_override("font_size", line[1])
			l.add_theme_color_override("font_color", line[2])
			if line[1] == 26:
				l.add_theme_font_override("font", UITheme.PIXEL_BOLD)
			card.add_child(l)
		_level_box.add_child(b)
	screens.levelup.set_meta("focus", _level_box.get_child(0))
	show_screen("levelup")
	Sfx.play("level_up")


var _stats: Label


func _end_screen() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	_stats = Label.new()
	_stats.custom_minimum_size.x = 300
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	var plate := PanelContainer.new()
	plate.theme_type_variation = "Plate"
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plate.add_child(_stats)
	row.add_child(plate)
	var scroll := preload("res://ui/scroll_panel.gd").new()
	scroll.main = main
	row.add_child(scroll)
	return _menu("End of run", [["Play again", _play], ["Main menu", _to_title]], row)


func _on_run_ended() -> void:
	var r: Dictionary = main.last_run
	var text := tr("Wave reached: %d\nLevel: %d\nEnemies defeated: %d\nScore: %d\n\nGold earned: %d\nScrolls: %d") % [
		r.wave, r.level, r.kills, r.score, r.gold, r.scrolls]
	for id in r.reached:
		text += "\n" + tr("Achievement: %s!") % tr(Profile.ACHIEVEMENTS[id].name)
	for e in r.unlocked:
		text += "\n" + tr("Spell unlocked: %s.") % Spell.label(e.spell)
	_stats.text = text
	screens.end.get_meta("focus").disabled = not multiplayer.is_server()  # "Play again": the host restarts
	show_screen("end")


## The HUD shows on run_started (in coop only the host starts the run).
func _play() -> void:
	if not Online.logged_in():
		show_screen("account")
		return
	main.start_run()


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
