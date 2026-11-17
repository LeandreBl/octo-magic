extends CanvasLayer
## Every screen of the game, above the world: title menu, HUD, level-up choice,
## pause, options, end of run, shop, achievements, leaderboard, multiplayer.
## Solo, the world is paused whenever a screen other than the HUD is shown;
## in coop it only stops between runs.
## UI is drawn at screen resolution (not pixel-art scaled), scaled by the
## "UI size" option. Data comes from the Run and Profile autoloads.
## The multiplayer screen is the coop lobby (game/lobby.gd), the account
## screen game/account.gd.

const UITheme := preload("res://ui/theme.gd")

var main: Node  # game/main.gd
var root: Control  # scaled by the UI size option
var screens := {}  # name -> Control; "" is the HUD (in run)
var current := ""
var back_to := "title"  # where options, shop... return
var hud: Control
var sticks: Control
var _dim: ColorRect  # darkens the world behind menus
var _prompt: Label  # gamepad button prompts, while a gamepad is in use


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
		["Reprendre", resume],
		["Options", open.bind("options")],
		["Abandonner la run", main.abandon_run]]))
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
	screens.achievements = add_screen(_list_screen("Succès", _achievements_text))
	screens.leaderboard = add_screen(_list_screen("Classement", _scores_text))
	_level_box = VBoxContainer.new()
	_level_box.add_theme_constant_override("separation", 10)
	screens.levelup = add_screen(_menu("Niveau supérieur !", [], _level_box))

	main.run_ended.connect(_on_run_ended)
	main.run_started.connect(show_screen.bind(""))  # also on peers when the host starts
	Run.leveled_up.connect(_show_level_up)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y -= 30
	root.add_child(_prompt)
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_screen("title")


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
	current = name
	for k in screens:
		screens[k].visible = k == name
	sticks.visible = name == ""
	_dim.visible = name not in ["", "title"]
	get_tree().paused = not Run.active or (name != "" and main.solo())
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


func _update_prompt() -> void:
	_prompt.visible = Settings.pad and current != ""
	var ok := Settings.pad_button("A", "Croix") + " : valider"
	var cancel := "  ·  " + Settings.pad_button("B", "Rond") + " : retour"
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
	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = "Octo Magic"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Écris tes sorts, survis aux vagues."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(sub)
	box.add_child(Control.new())  # spacer
	var items := [["Jouer", _play], ["Multijoueur", open.bind("multiplayer")], ["Compte", open.bind("account")],
		["Boutique", open.bind("shop")], ["Succès", open.bind("achievements")],
		["Classement", open.bind("leaderboard")], ["Options", open.bind("options")]]
	if not OS.has_feature("web"):
		items.append(["Quitter", get_tree().quit])
	for it in items:
		var b := _button(it[0], it[1])
		b.custom_minimum_size = Vector2(320, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)
		if not bg.has_meta("focus"):
			bg.set_meta("focus", b)
	return bg


## A screen showing `text_fn.call()`, refreshed each time it is shown.
func _list_screen(title: String, text_fn: Callable) -> Control:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 18)
	var c := _menu(title, [["Retour", back]], l)
	c.visibility_changed.connect(func(): l.text = text_fn.call())
	return c


func _achievements_text() -> String:
	var lines := []
	for id in Profile.ACHIEVEMENTS:
		var a: Dictionary = Profile.ACHIEVEMENTS[id]
		var have: int = mini(Profile.stats.get(a.stat, 0), a.goal)
		lines.append("%s  %s · %s%s" % ["✔" if Profile.achievements.has(id) else "·", a.name, a.desc,
			"" if Profile.achievements.has(id) else "  (%d/%d)" % [have, a.goal]])
	return "\n".join(lines)


func _scores_text() -> String:
	var lines := []
	for i in Profile.scores.size():
		var r: Dictionary = Profile.scores[i]
		lines.append("%2d.  %6d pts   vague %d, niveau %d, %d ennemis   %s" % [i + 1, r.score, r.wave,
			r.level, r.kills, Time.get_date_string_from_unix_time(r.time)])
	return "\n".join(lines) if lines else "Aucun score : lance une run !"


var _level_box: VBoxContainer


func _show_level_up(offers: Array) -> void:
	for c in _level_box.get_children():  # not free(): a pressed button is mid-signal
		_level_box.remove_child(c)
		c.queue_free()
	for i in offers.size():
		var o: Dictionary = offers[i]
		var u: Dictionary = Upgrades.LIST[o.id]
		var b := _button("%s · %s\n%s : %s" % [u.name, u.desc, Upgrades.SLOT_NAMES[o.slot], Run.spells[o.slot].name],
			func():
				var more := Run.choose(i)
				main.send_loadout(false)
				if not more:
					show_screen(""))
		b.custom_minimum_size.x = 460
		_level_box.add_child(b)
	screens.levelup.set_meta("focus", _level_box.get_child(0))
	show_screen("levelup")


var _stats: Label


func _end_screen() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	_stats = Label.new()
	_stats.custom_minimum_size.x = 300
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(_stats)
	var scroll := preload("res://ui/scroll_panel.gd").new()
	scroll.main = main
	row.add_child(scroll)
	return _menu("Fin de la run", [["Rejouer", _play], ["Menu principal", _to_title]], row)


func _on_run_ended() -> void:
	var r: Dictionary = main.last_run
	var text := "Vague atteinte : %d\nNiveau : %d\nEnnemis vaincus : %d\nScore : %d\n\nOr gagné : %d\nParchemins : %d" % [
		r.wave, r.level, r.kills, r.score, r.gold, r.scrolls]
	for id in r.reached:
		text += "\nSuccès : %s !" % Profile.ACHIEVEMENTS[id].name
	for e in r.unlocked:
		text += "\nSort débloqué : %s." % e.spell.name
	_stats.text = text
	screens.end.get_meta("focus").disabled = not multiplayer.is_server()  # "Rejouer": the host restarts
	show_screen("end")


## The HUD shows on run_started (in coop only the host starts the run).
func _play() -> void:
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
