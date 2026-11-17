extends Node2D
## The game scene. Game state lives in the autoloads: `Run` (the current run)
## and `Profile` (kept between runs, saved). This scene spawns waves and drops,
## and shows a minimal HUD, level-up choice and hub (the menus task replaces
## them). Runs are fully offline. Blank scrolls found in a run are kept; in the
## hub the player writes words on them (one word per scroll, several at once)
## and the forge server rewrites the main spell with them, cancelling
## meaningless words (their scrolls come back). If the forge does not answer,
## the scrolls stay for later.
##
## Coop (relay/relay.py, game/lobby.gd): the host runs the waves, enemies,
## drops and damage, spawned through a MultiplayerSpawner; each peer steers
## its mage and keeps its own Run (level-ups, spells), sent to the host as a
## loadout. Kills and drops are shared. Solo is a host alone
## (OfflineMultiplayerPeer): one code path.

const FORGE_URL := "http://localhost:8765/forge"
const POLL_SECONDS := 3.0
const Enemy := preload("res://game/enemy.gd")
const Pickup := preload("res://game/pickup.gd")
const Player := preload("res://game/player.gd")
const RELAY_URL := "ws://localhost:8770"
const ALWAYS := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
const ON_CHANGE := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE

var spawner: MultiplayerSpawner
var lobby: PanelContainer
var spawned := 0  # names of spawned enemies and drops
var map_info := ["crypt", 0]  # this run's map and seed, for players dropping in
var again_button: Button
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
var forge_job := ""  # scrolls being written on the forge
var forge_words := 0  # scrolls used by that job
var forge_note := ""  # forge news, shown in the HUD and the hub


func _ready() -> void:
	randomize()
	spawner = MultiplayerSpawner.new()
	spawner.spawn_function = _spawn
	add_child(spawner)
	spawner.spawn_path = ^".."
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.server_disconnected.connect(_go_solo, CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(_go_solo, CONNECT_DEFERRED)
	_build_ui()
	Run.leveled_up.connect(_show_level_up)
	Profile.changed.connect(_refresh_hub)
	_reset_world()
	_show_hub()


func local_player() -> Node2D:
	return get_node_or_null("P%d" % multiplayer.get_unique_id())


func _solo() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _process(_delta: float) -> void:
	var player := local_player()
	if not Run.active or not player:
		return
	var s: Dictionary = Run.spells.primary
	hud_icon.texture = SpellArt.sheet(s, s.icon_file) if s.icon_file else SpellArt.texture(s.icon, s.palette)
	var slots := []
	for slot in Upgrades.SLOTS:
		slots.append("%s (%d)" % [Run.spells[slot].name, Run.mana_cost(slot)])
	if player.skill:
		var k: Dictionary = Skills.LIST[player.skill]
		slots.append("%s (%d) %s" % [k.name, k.mana, "prêt" if player.skill_cooldown <= 0.0 else "%.0f s" % player.skill_cooldown])
	hud.text = "Vague %d   Niveau %d (%d/%d XP)   PV %d/%d   Mana %d   Or %d   Parchemins %d   Score %d\n%s\n%s" % [
		Run.wave, Run.level, Run.xp, Run.xp_to_next(Run.level), player.hp, player.max_hp, player.mana,
		Run.gold, Run.scrolls, Run.score(), "   |   ".join(slots), forge_note]
	if multiplayer.is_server() and get_tree().get_nodes_in_group("enemies").is_empty():
		for p in get_tree().get_nodes_in_group("pickups"):
			p.magnet = INF  # wave cleared: the drops fly to the player
		_next_wave()


# --- run (the host drives it, peers follow through RPCs) ----------------------

func _start_run() -> void:
	if multiplayer.is_server():
		_run_started.rpc(Decor.MAPS.keys().pick_random(), randi())
		_next_wave()


## Every peer starts its own Run (progression, spells) on the host's map.
@rpc("authority", "call_local", "reliable")
func _run_started(map: String, map_seed: int) -> void:
	map_info = [map, map_seed]
	for n in get_children():
		if n is Node2D and not n.is_in_group("players"):
			n.free()
	Run.start(Profile.equipped_spells(), Profile.total_stats())
	var p := local_player()
	if p:
		p.position = get_viewport_rect().size / 2.0
	var decor := Decor.new()  # one map per run, placed once
	decor.broken.connect(func(pos):
		_drop("gold", 3, pos)
		_drop("xp", 2, pos + Vector2(10, 0)))
	add_child(decor)
	decor.build(map, get_viewport_rect(), map_seed)
	hub.hide()
	lobby.hide()
	get_tree().paused = false
	_send_loadout(true)


## This peer's spells, stats and look, to the host (see Player.clean_loadout).
func _send_loadout(fresh: bool) -> void:
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_offer_loadout.rpc_id(1, JSON.stringify({"fresh": fresh, "spells": Run.spells, "mult": Run.mana_mult, "skill": Profile.skill,
		"stats": Profile.total_stats(), "look": Profile.look.merged({
			"robe": Profile.ITEMS[Profile.equipped.robe].color,
			"staff": Profile.ITEMS[Profile.equipped.staff].color,
			"ring": Profile.ITEMS[Profile.equipped.ring].color}, true)}))


## A player sends its loadout as JSON; the host cleans it and syncs it to all.
@rpc("any_peer", "call_local", "reliable")
func _offer_loadout(text: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	var p := get_node_or_null("P%d" % (from if from else 1))
	if multiplayer.is_server() and p:
		p.loadout_json = JSON.stringify(Player.clean_loadout(JSON.parse_string(text)))


func _next_wave() -> void:
	_wave_started.rpc(Run.wave + 1)
	var size := get_viewport_rect().size
	for kind in Run.wave_plan(Run.wave):
		spawned += 1
		spawner.spawn({"kind": "enemy", "name": "E%d" % spawned, "type": kind,
			"stats": Run.enemy_stats(kind, Run.wave),
			"pos": size / 2.0 + Vector2.from_angle(randf() * TAU) * size.length() * 0.55})


@rpc("authority", "call_local", "reliable")
func _wave_started(w: int) -> void:
	Run.wave = w
	Run.changed.emit()


func _on_killed(e: Node2D) -> void:
	_killed.rpc(e.kind)
	_drop("xp", e.xp, e.position)
	if e.kind == "boss" or randf() < 0.5:
		_drop("gold", e.gold, e.position + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
	if e.kind == "boss" or randf() < 0.01:
		_drop("scroll", 1, e.position + Vector2(0, 14))


## Kills and drops are shared: every peer counts them in its own Run.
@rpc("authority", "call_local", "reliable")
func _killed(kind: String) -> void:
	Run.killed(kind)


@rpc("authority", "call_local", "reliable")
func _collected(kind: String, value: int) -> void:
	Run.collect(kind, value)
	if kind == "scroll":
		forge_note = "Parchemin vierge trouvé ! Tu pourras l'écrire à la fin de la run."


func _drop(kind: String, value: int, pos: Vector2) -> void:
	if multiplayer.is_server():
		spawned += 1
		spawner.spawn.call_deferred({"kind": "pickup", "name": "D%d" % spawned, "type": kind, "value": value, "pos": pos})


func _show_level_up(offers: Array) -> void:
	get_tree().paused = _solo()  # coop: the others play on
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
			var more := Run.choose(i)
			_send_loadout(false)
			if not more:
				get_tree().paused = false)
		level_box.add_child(b)
	level_panel.show()
	level_box.get_child(1).grab_focus.call_deferred()


## Permadeath: the run ends when every mage is down; its gold and scrolls are
## kept. Hub.
func _on_player_died() -> void:
	if Run.active and get_tree().get_nodes_in_group("players").all(func(p): return p.hp <= 0.0):
		_end_run.rpc()


@rpc("authority", "call_local", "reliable")
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
	for n in Profile.unlocked_by(reached):
		run_summary += "\nDébloqué : %s." % n
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
	word_edit.max_length = 200
	word_edit.placeholder_text = "ex : tempête, vampire, miroir"
	word_edit.text_submitted.connect(func(_t): _forge())
	hub_status = Label.new()
	hub_status.autowrap_mode = TextServer.AUTOWRAP_WORD

	lobby = preload("res://game/lobby.gd").new()
	lobby.main = self
	lobby.hide()
	layer.add_child(lobby)

	forge_http = HTTPRequest.new()
	forge_http.timeout = 30.0
	forge_http.request_completed.connect(_on_forge_reply)
	layer.add_child(forge_http)


# --- coop: spawning and connections -------------------------------------------

func _spawn(d: Dictionary) -> Node:
	var n: Node2D
	var sync := MultiplayerSynchronizer.new()
	if d.kind == "player":
		n = Player.new()
		n.peer_id = d.id
		n.died.connect(_on_player_died)
		sync.replication_config = _config({"hp": ON_CHANGE, "mana": ALWAYS, "loadout_json": ON_CHANGE}, true)
		var own := MultiplayerSynchronizer.new()  # what the owner steers
		own.replication_config = _config({"position": ALWAYS, "aim": ALWAYS, "firing": ALWAYS}, false)
		own.set_multiplayer_authority(d.id)
		n.add_child(own)
	elif d.kind == "enemy":
		n = Enemy.new()
		n.setup(d.type, d.stats)
		n.killed.connect(_on_killed)
		sync.replication_config = _config({"position": ALWAYS, "hp": ON_CHANGE, "statuses": ALWAYS}, true)
	else:
		n = Pickup.new()
		n.kind = d.type
		n.value = d.value
		n.add_to_group("pickups")
		n.collected.connect(func(k, v): _collected.rpc(k, v))
		sync.replication_config = _config({"position": ALWAYS}, true)
	n.name = d.name
	n.position = d.pos
	n.add_child(sync)
	return n


static func _config(props: Dictionary, spawn: bool) -> SceneReplicationConfig:
	var c := SceneReplicationConfig.new()
	for p in props:
		var path := NodePath(".:" + p)
		c.add_property(path)
		c.property_set_spawn(path, spawn)
		c.property_set_replication_mode(path, props[p])
	return c


func _spawn_player(id: int) -> void:
	spawner.spawn({"kind": "player", "name": "P%d" % id, "id": id, "pos": get_viewport_rect().size / 2.0})


## Fresh world for a new session: the host (or solo) spawns its mage, a
## joining peer waits for the host's spawns.
func _reset_world() -> void:
	for n in get_children():
		if n is Node2D:
			n.free()
	if multiplayer.is_server():
		_spawn_player(1)


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		if Run.active:  # drop-in: the newcomer starts its run on this map
			_run_started.rpc_id(id, map_info[0], map_info[1])
			_wave_started.rpc_id(id, Run.wave)


func _on_peer_left(id: int) -> void:
	var p := get_node_or_null("P%d" % id)
	if multiplayer.is_server() and p:
		p.remove_from_group("players")
		p.queue_free()
		_on_player_died()  # the leaver may have been the last one standing


## Lobby: open a room (its code shows in the lobby once the relay answers),
## or join one. Returns an error message, or "".
func host_game(url: String) -> String:
	return _connect(url, "")


func join_game(url: String, code: String) -> String:
	return _connect(url, code)


func _connect(url: String, code: String) -> String:
	var peer := RelayPeer.new()
	if (peer.join(url, code) if code else peer.host(url)) != OK:
		return peer.error
	multiplayer.multiplayer_peer = peer
	_reset_world()
	_show_hub()
	return ""


func leave_game() -> void:
	multiplayer.multiplayer_peer.close()
	_go_solo()


## Relay lost, room closed or never joined: back to solo, in the hub.
func _go_solo() -> void:
	var peer := multiplayer.multiplayer_peer
	if not peer is RelayPeer:
		return
	lobby.info.text = peer.error
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_world()
	if Run.active:
		_end_run()
	else:
		_show_hub()


func _show_hub() -> void:
	get_tree().paused = true
	hud.text = ""
	_refresh_hub()
	hub.show()
	again_button.grab_focus()


## Rebuilds the hub from Profile: shop, bonuses, spells, look, forge, scores.
func _refresh_hub() -> void:
	if not hub or Run.active:
		return
	for c in hub_box.get_children():
		hub_box.remove_child(c)
		if c != word_edit and c != hub_status:
			c.queue_free()
	_label(run_summary)
	var row := _row()
	again_button = _button(row, "Nouvelle run" if multiplayer.is_server() else "L'hôte lance la run", _start_run)
	again_button.disabled = not multiplayer.is_server()
	_button(row, "Multijoueur", lobby.show)
	_label("\nOr : %d   Parchemins vierges : %d" % [Profile.gold, Profile.blank_scrolls])

	_label("\nÉquipement (acheter / équiper) :")
	row = _row()
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

	_label("\nSkill (clic droit / espace / RB / LB) :")
	row = _row()
	for id in Profile.available_skills():
		var k: Dictionary = Skills.LIST[id]
		var b := _button(row, k.name, func(): Profile.equip_skill(id))
		b.disabled = Profile.skill == id
		b.tooltip_text = "%s (%d mana, %d s)" % [k.desc, k.mana, k.cooldown]

	_label("\nChapeau :")
	row = _row()
	for c in Profile.COLORS:
		var b := _button(row, "  ", func(): Profile.set_look("hat", c))
		b.modulate = Color(c)
		b.disabled = Profile.look.hat == c

	_label("\nParchemin (forge, connexion requise) :")
	hub_box.add_child(word_edit)
	row = _row()
	var write := _button(row, "Écrire les parchemins", _forge)
	var can_write := Profile.blank_scrolls > 0 and forge_job.is_empty()
	word_edit.editable = can_write
	write.disabled = not can_write
	hub_box.add_child(hub_status)
	if not forge_job.is_empty():
		hub_status.text = "Un parchemin est en cours d'écriture. %s" % forge_note
	elif Profile.blank_scrolls == 0:
		hub_status.text = "Aucun parchemin vierge : les boss en laissent tomber. %s" % forge_note
	elif hub_status.text.is_empty():
		hub_status.text = "Écris un mot par parchemin (séparés par des espaces ou des virgules) pour transformer ton sort."

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


# --- forge: POST the words, then poll the job until the bundle is ready -------

func _forge() -> void:
	var word := word_edit.text.strip_edges()
	if word.is_empty() or Profile.blank_scrolls == 0 or not forge_job.is_empty() \
			or forge_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	hub_status.text = "Envoi à la forge…"
	var body := JSON.stringify({"spell": Profile.equipped_spells().primary, "words": word,
		"scrolls": Profile.blank_scrolls})
	if forge_http.request(FORGE_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		hub_status.text = "Impossible de joindre la forge (connexion requise). Tes parchemins sont gardés."


func _poll() -> void:
	if not forge_job.is_empty() and forge_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		forge_http.request(FORGE_URL + "/" + forge_job)


func _on_forge_reply(result: int, code: int, headers: PackedStringArray, data: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.slice(0, 2).get_string_from_ascii() == "PK":
		var applied := forge_words
		for h in headers:
			if h.to_lower().begins_with("x-forge-applied:"):
				applied = h.get_slice(":", 1).strip_edges().to_int()
		_on_bundle(data, clampi(forge_words - applied, 0, forge_words))
		return
	var reply: Variant = JSON.parse_string(data.get_string_from_utf8())
	reply = reply if reply is Dictionary else {}
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or reply.has("error"):
		var msg: String = reply.get("error", "erreur %d" % code if result == HTTPRequest.RESULT_SUCCESS else "hors ligne")
		if forge_job.is_empty():  # words refused or forge unreachable: scrolls kept
			hub_status.text = "La forge a refusé ou n'a pas répondu (%s). Tes parchemins sont gardés." % msg
		else:
			forge_job = ""
			Profile.blank_scrolls += forge_words  # the scrolls were not used up
			forge_note = "La forge a échoué (%s). Tes parchemins te sont rendus." % msg
			Profile.save()
			_refresh_hub()
		return
	if reply.has("job"):
		forge_job = reply.job
		forge_words = maxi(1, reply.get("words", [1]).size())
		Profile.blank_scrolls -= forge_words
		Profile.save()
		forge_note = "%d parchemin(s) en cours d'écriture…" % forge_words
		_refresh_hub()
	get_tree().create_timer(POLL_SECONDS, true).timeout.connect(_poll)


## The forged spell is kept and equipped as the main spell: the run in
## progress keeps its spells, the next one starts with it.
## cancelled: words the forge found meaningless; their scrolls come back.
func _on_bundle(data: PackedByteArray, cancelled: int) -> void:
	forge_job = ""
	var path := Profile.next_bundle_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var s := SpellArt.load_bundle(path)
	if s.is_empty():
		Profile.blank_scrolls += forge_words
		Profile.save()
		forge_note = "Le parchemin est illisible. Tes parchemins te sont rendus."
		_refresh_hub()
		return
	Profile.blank_scrolls += cancelled
	Profile.add_forged(s, path)
	forge_note = "Parchemin écrit : %s sera ton sort à la prochaine run." % s.name
	if cancelled > 0:
		forge_note += " %d mot(s) sans sens annulé(s), parchemin(s) rendu(s)." % cancelled
	_refresh_hub()
