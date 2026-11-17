extends Node2D
## The game scene. Game state lives in the autoloads: `Run` (the current run)
## and `Profile` (kept between runs, saved). This scene spawns waves and drops,
## and shows a minimal HUD, level-up choice and hub (the menus task replaces
## them). Runs are fully offline. Blank scrolls found in a run are kept; in the
## hub the player writes a word on one and the forge server rewrites the main
## spell with it. If the forge does not answer, the scroll stays for later.

const FORGE_URL := "http://localhost:8765/forge"
const POLL_SECONDS := 3.0
const Enemy := preload("res://game/enemy.gd")
const Pickup := preload("res://game/pickup.gd")

var player: Node2D
var hud: Label
var hud_icon: TextureRect
var level_panel: PanelContainer
var level_box: VBoxContainer
var hub: PanelContainer
var hub_box: VBoxContainer
var run_summary := "Bienvenue, mage."
var word_edit: LineEdit
var hub_status: Label
var forge_http: HTTPRequest
var forge_job := ""  # scroll being written on the forge
var forge_note := ""  # forge news, shown in the HUD and the hub


func _ready() -> void:
	randomize()
	player = preload("res://game/player.gd").new()
	player.run = Run
	player.died.connect(_end_run)
	add_child(player)
	_build_ui()
	Run.leveled_up.connect(_show_level_up)
	Profile.changed.connect(_refresh_hub)
	_show_hub()


func _process(_delta: float) -> void:
	if not Run.active:
		return
	var s: Dictionary = Run.spells.primary
	hud_icon.texture = SpellArt.sheet(s, s.icon_file) if s.icon_file else SpellArt.texture(s.icon, s.palette)
	var slots := []
	for slot in Upgrades.SLOTS:
		slots.append("%s (%d)" % [Run.spells[slot].name, Run.mana_cost(slot)])
	hud.text = "Vague %d   Niveau %d (%d/%d XP)   PV %d/%d   Mana %d   Or %d   Parchemins %d   Score %d\n%s\n%s" % [
		Run.wave, Run.level, Run.xp, Run.xp_to_next(Run.level), player.hp, player.max_hp, player.mana,
		Run.gold, Run.scrolls, Run.score(), "   |   ".join(slots), forge_note]
	if get_tree().get_nodes_in_group("enemies").is_empty():
		for p in get_tree().get_nodes_in_group("pickups"):
			p.magnet = INF  # wave cleared: the drops fly to the player
		_next_wave()


# --- run ---------------------------------------------------------------------

func _start_run() -> void:
	for n in get_children():
		if n != player and n is Node2D:
			n.free()
	var stats := Profile.total_stats()
	Run.start(Profile.equipped_spells(), stats)
	player.setup(stats)
	player.look = Profile.look.merged({"robe": Profile.ITEMS[Profile.equipped.robe].color,
		"staff": Profile.ITEMS[Profile.equipped.staff].color,
		"ring": Profile.ITEMS[Profile.equipped.ring].color}, true)
	player.position = get_viewport_rect().size / 2.0
	hub.hide()
	get_tree().paused = false
	_next_wave()


func _next_wave() -> void:
	Run.wave += 1
	Run.changed.emit()
	var size := get_viewport_rect().size
	for kind in Run.wave_plan(Run.wave):
		var e := Enemy.new()
		e.setup(kind, Run.enemy_stats(kind, Run.wave))
		e.target = player
		e.position = size / 2.0 + Vector2.from_angle(randf() * TAU) * size.length() * 0.55
		e.killed.connect(_on_killed)
		add_child(e)


func _on_killed(e: Node2D) -> void:
	Run.killed(e.kind)
	_drop("xp", e.xp, e.position)
	if e.kind == "boss" or randf() < 0.5:
		_drop("gold", e.gold, e.position + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
	if e.kind == "boss" or randf() < 0.01:
		_drop("scroll", 1, e.position + Vector2(0, 14))


func _drop(kind: String, value: int, pos: Vector2) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.value = value
	p.target = player
	p.position = pos
	p.add_to_group("pickups")
	p.collected.connect(func(k, v):
		Run.collect(k, v)
		if k == "scroll":
			forge_note = "Parchemin vierge trouvé ! Tu pourras l'écrire à la fin de la run.")
	add_child.call_deferred(p)


func _show_level_up(offers: Array) -> void:
	get_tree().paused = true
	for c in level_box.get_children():
		c.free()
	var title := Label.new()
	title.text = "Niveau %d ! Choisis une amélioration :" % Run.level
	level_box.add_child(title)
	for i in offers.size():
		var o: Dictionary = offers[i]
		var u: Dictionary = Upgrades.LIST[o.id]
		var b := Button.new()
		b.text = "%d. %s — %s (%s : %s)" % [i + 1, u.name, u.desc, Upgrades.SLOT_NAMES[o.slot], Run.spells[o.slot].name]
		b.pressed.connect(func():
			level_panel.hide()
			if not Run.choose(i):
				get_tree().paused = false)
		level_box.add_child(b)
	level_panel.show()
	level_box.get_child(1).grab_focus.call_deferred()


## Permadeath: the run is lost, its gold and scrolls are kept. Hub.
func _end_run() -> void:
	if not Run.active:
		return
	var r := Run.finish()
	var reached := Profile.record_run(r)
	level_panel.hide()
	run_summary = "Fin de la run : vague %d, niveau %d, %d ennemis, score %d. +%d or, +%d parchemin(s)." % [
		r.wave, r.level, r.kills, r.score, r.gold, r.scrolls]
	for id in reached:
		run_summary += "\nSuccès : %s !" % Profile.ACHIEVEMENTS[id].name
	for e in Profile.unlocked_by(reached):
		run_summary += "\nNouveau sort débloqué : %s." % e.spell.name
	_show_hub()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud_icon = TextureRect.new()
	hud_icon.position = Vector2(12, 8)
	hud_icon.stretch_mode = TextureRect.STRETCH_SCALE
	hud_icon.size = Vector2(48, 48)
	layer.add_child(hud_icon)
	hud = Label.new()
	hud.position = Vector2(68, 8)
	layer.add_child(hud)

	level_panel = PanelContainer.new()
	level_panel.position = Vector2(340, 240)
	level_panel.hide()
	layer.add_child(level_panel)
	level_box = VBoxContainer.new()
	level_panel.add_child(level_box)

	hub = PanelContainer.new()
	hub.position = Vector2(140, 40)
	hub.size = Vector2(1000, 640)
	hub.hide()
	layer.add_child(hub)
	var scroll := ScrollContainer.new()
	hub.add_child(scroll)
	hub_box = VBoxContainer.new()
	hub_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hub_box)
	word_edit = LineEdit.new()
	word_edit.max_length = 32
	word_edit.placeholder_text = "ex : tempête, vampire, miroir…"
	word_edit.text_submitted.connect(func(_t): _forge())
	hub_status = Label.new()
	hub_status.autowrap_mode = TextServer.AUTOWRAP_WORD

	forge_http = HTTPRequest.new()
	forge_http.timeout = 30.0
	forge_http.request_completed.connect(_on_forge_reply)
	layer.add_child(forge_http)


func _show_hub() -> void:
	get_tree().paused = true
	hud.text = ""
	_refresh_hub()
	hub.show()
	hub_box.get_child(1).grab_focus()


## Rebuilds the hub from Profile: shop, bonuses, spells, look, forge, scores.
func _refresh_hub() -> void:
	if not hub or Run.active:
		return
	for c in hub_box.get_children():
		hub_box.remove_child(c)
		if c != word_edit and c != hub_status:
			c.queue_free()
	_label(run_summary)
	_button(hub_box, "Nouvelle run", _start_run)
	_label("\nOr : %d   Parchemins vierges : %d" % [Profile.gold, Profile.blank_scrolls])

	_label("\nÉquipement (acheter / équiper) :")
	var row := _row()
	for id in Profile.ITEMS:
		var it: Dictionary = Profile.ITEMS[id]
		var on: bool = Profile.equipped[it.kind] == id
		var text: String = it.name + (" ✔" if on else "" if Profile.owned.has(id) else " (%d or)" % it.price)
		var b := _button(row, text, func():
			if not Profile.equip_item(id): Profile.buy_item(id))
		b.disabled = on or (not Profile.owned.has(id) and Profile.gold < it.price)
		b.tooltip_text = str(it.bonus)

	_label("\nBonus permanents :")
	row = _row()
	for id in Profile.BONUSES:
		var bo: Dictionary = Profile.BONUSES[id]
		var price := Profile.bonus_price(id)
		var b := _button(row, "%s %d/%d — %s%s" % [bo.name, Profile.bonuses.get(id, 0), bo.max, bo.desc,
			" (max)" if price < 0 else " (%d or)" % price], func(): Profile.buy_bonus(id))
		b.disabled = price < 0 or Profile.gold < price

	for slot in Upgrades.SLOTS:
		_label("\n%s :" % Upgrades.SLOT_NAMES[slot])
		row = _row()
		for e in Profile.available_spells(slot):
			var b := _button(row, e.spell.name, func(): Profile.equip_spell(slot, e.id))
			b.disabled = Profile.spells[slot] == e.id
			b.tooltip_text = "%s (%d mana)" % [e.spell.description, Spell.mana_cost(e.spell)]

	_label("\nChapeau :")
	row = _row()
	for c in Profile.COLORS:
		var b := _button(row, "  ", func(): Profile.set_look("hat", c))
		b.modulate = Color(c)
		b.disabled = Profile.look.hat == c

	_label("\nParchemin (forge, connexion requise) :")
	hub_box.add_child(word_edit)
	row = _row()
	var write := _button(row, "Écrire le parchemin", _forge)
	var can_write := Profile.blank_scrolls > 0 and forge_job.is_empty()
	word_edit.editable = can_write
	write.disabled = not can_write
	hub_box.add_child(hub_status)
	if not forge_job.is_empty():
		hub_status.text = "Un parchemin est en cours d'écriture. %s" % forge_note
	elif Profile.blank_scrolls == 0:
		hub_status.text = "Aucun parchemin vierge : les boss en laissent tomber. %s" % forge_note
	elif hub_status.text.is_empty():
		hub_status.text = "Écris un mot pour transformer ton sort principal."

	var done := Profile.ACHIEVEMENTS.keys().filter(func(id): return Profile.achievements.has(id))
	_label("\nSuccès %d/%d : %s" % [done.size(), Profile.ACHIEVEMENTS.size(),
		", ".join(done.map(func(id): return Profile.ACHIEVEMENTS[id].name))])
	var lines := []
	for i in Profile.scores.size():
		var s: Dictionary = Profile.scores[i]
		lines.append("%d. %d pts — vague %d, niveau %d" % [i + 1, s.score, s.wave, s.level])
	_label("\nMeilleurs scores :\n" + ("\n".join(lines) if lines else "aucun"))


func _label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	hub_box.add_child(l)


func _row() -> HFlowContainer:
	var r := HFlowContainer.new()
	hub_box.add_child(r)
	return r


func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


# --- forge: POST the word, then poll the job until the bundle is ready -------

func _forge() -> void:
	var word := word_edit.text.strip_edges()
	if word.is_empty() or Profile.blank_scrolls == 0 or not forge_job.is_empty() \
			or forge_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	hub_status.text = "Envoi à la forge…"
	var body := JSON.stringify({"spell": Profile.equipped_spells().primary, "word": word})
	if forge_http.request(FORGE_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		hub_status.text = "Impossible de joindre la forge (connexion requise). Ton parchemin est gardé."


func _poll() -> void:
	if not forge_job.is_empty() and forge_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		forge_http.request(FORGE_URL + "/" + forge_job)


func _on_forge_reply(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.slice(0, 2).get_string_from_ascii() == "PK":
		_on_bundle(data)
		return
	var reply: Variant = JSON.parse_string(data.get_string_from_utf8())
	reply = reply if reply is Dictionary else {}
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or reply.has("error"):
		var msg: String = reply.get("error", "erreur %d" % code if result == HTTPRequest.RESULT_SUCCESS else "hors ligne")
		if forge_job.is_empty():  # word refused or forge unreachable: scroll kept
			hub_status.text = "La forge n'a pas répondu (%s). Ton parchemin est gardé pour plus tard." % msg
		else:
			forge_job = ""
			Profile.blank_scrolls += 1  # the scroll was not used up
			forge_note = "La forge a échoué (%s). Ton parchemin t'est rendu." % msg
			Profile.save()
			_refresh_hub()
		return
	if reply.has("job"):
		forge_job = reply.job
		Profile.blank_scrolls -= 1
		Profile.save()
		forge_note = "Parchemin en cours d'écriture…"
		_refresh_hub()
	get_tree().create_timer(POLL_SECONDS, true).timeout.connect(_poll)


## The forged spell is kept and equipped as the main spell: the run in
## progress keeps its spells, the next one starts with it.
func _on_bundle(data: PackedByteArray) -> void:
	forge_job = ""
	var path := Profile.next_bundle_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var s := SpellArt.load_bundle(path)
	if s.is_empty():
		forge_note = "Le parchemin est illisible."
		_refresh_hub()
		return
	Profile.add_forged(s, path)
	forge_note = "Parchemin écrit : %s sera ton sort principal à la prochaine run." % s.name
	_refresh_hub()
