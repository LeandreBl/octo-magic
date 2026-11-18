extends Node2D
## The game scene. Game state lives in the autoloads: `Run` (the current run)
## and `Profile` (kept between runs, saved). This scene spawns waves and drops;
## every screen is in ui/ (ui/ui.gd), which follows the signals below. Runs
## play offline. Blank scrolls found in a run are kept; between runs the
## player, logged in (game/online.gd), writes words on them (one word per
## scroll, several at once) and the server's forge rewrites the main spell
## with them, cancelling meaningless words (their scrolls come back). If the
## forge does not answer, the scrolls stay for later.
##
## Coop (game/net.gd: WebRTC, game/lobby.gd): the host runs the waves, enemies,
## drops and damage, spawned through a MultiplayerSpawner; each peer steers
## its mage and keeps its own Run (level-ups, spells), sent to the host as a
## loadout. Kills and drops are shared. Solo is a host alone
## (OfflineMultiplayerPeer): one code path.

const POLL_SECONDS := 3.0
const SPAWN_EVERY := 0.5  # s between two monsters of a wave: it trickles in
const LEVEL_BLAST_RADIUS := 220.0  # px around the mage leveling up
const LEVEL_BLAST_FORCE := 900.0  # knock speed: about 270 px of slide (enemy knock decays 1500/s)
const GRIMOIRE_CHANCE := 0.04  # a kill drops a grimoire (red or blue); a boss always does
const Enemy := preload("res://game/enemy.gd")
const Pickup := preload("res://game/pickup.gd")
const Player := preload("res://game/player.gd")
const ALWAYS := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
const ON_CHANGE := SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE

signal run_started  # on every peer
signal run_ended  # last_run holds the result
signal net_error(message: String)  # host lost or room closed: back to solo
signal forge_started(job: Dictionary)  # the forge took the words: a job of forge_jobs
signal forged(job: Dictionary, ok: bool)  # a forge job ended: the spell came back, or the scrolls did

var spawner: MultiplayerSpawner
var net: Node  # game/net.gd
var spawned := 0  # names of spawned enemies and drops
var to_spawn := []  # the current wave's kinds not out yet (host)
var _spawn_in := 0.0  # s until the next one comes out
var map_name := "crypt"  # this run's map (its music), for players dropping in
## Scrolls being written, in parallel: {id, words (scrolls used), slot (of the
## improved spell, the forged one goes there), spell (the improved one), started}.
var forge_jobs: Array[Dictionary] = []
var _forge_posting := false  # words sent, not taken yet: their scrolls are not counted off
var forge_note := ""  # forge news, shown in the HUD and the forge (ui/forge.gd)
var forge_status := ""  # result of the last write attempt, for the forge
var last_run := {}  # Run.finish() + "reached" achievements + "unlocked" spells


func _ready() -> void:
	randomize()
	if OS.has_feature("web"):
		# The rune gate (web/godot-shell.html) opens its portal once this first frame is up.
		(func(): JavaScriptBridge.eval("window.octoGameReady && window.octoGameReady()")).call_deferred()
	spawner = MultiplayerSpawner.new()
	spawner.spawn_function = _spawn
	add_child(spawner)
	spawner.spawn_path = ^".."
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.server_disconnected.connect(_go_solo, CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(_go_solo, CONNECT_DEFERRED)
	net = preload("res://game/net.gd").new()
	net.process_mode = Node.PROCESS_MODE_ALWAYS
	net.joined.connect(_on_net_joined)
	net.lost.connect(_go_solo)
	add_child(net)
	Run.level_gained.connect(send_loadout.bind(false, true))
	Run.level_gained.connect(func(): _level_blast.rpc_id(1))
	Run.level_gained.connect(func(): Sfx.play("level_up"))
	_reset_world()
	var ui := preload("res://ui/ui.gd").new()
	ui.name = "UI"
	ui.main = self
	add_child(ui)


func local_player() -> Node2D:
	return get_node_or_null("P%d" % multiplayer.get_unique_id())


func solo() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _process(delta: float) -> void:
	if not Run.active or not local_player():
		return
	if not multiplayer.is_server():
		return
	if to_spawn:
		_spawn_in -= delta
		if _spawn_in <= 0.0:
			_spawn_in = SPAWN_EVERY
			_spawn_enemy(to_spawn.pop_front())
	elif get_tree().get_nodes_in_group("enemies").is_empty():
		_pull_drops()  # wave cleared
		_next_wave()


## Every drop on the map flies to the player (wave cleared, boss down).
func _pull_drops() -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		p.magnet = INF


# --- run (the host drives it, peers follow through RPCs) ----------------------

func start_run() -> void:
	if multiplayer.is_server():
		_run_started.rpc(Arena.MAPS.pick_random())
		_next_wave()


## Every peer starts its own Run (progression, spells) on the host's map.
@rpc("authority", "call_local", "reliable")
func _run_started(map: String) -> void:
	map_name = map
	Sfx.music(map)
	for n in get_children():
		if n is Node2D and not n.is_in_group("players"):
			n.free()
	Run.start(Profile.equipped_spells(), Profile.bonus_list(), Profile.slotted_augments())
	var p := local_player()
	if p:
		p.position = Arena.START
	add_child(Arena.new())
	forge_status = ""
	get_tree().paused = false
	send_loadout(true)
	run_started.emit()


## This peer's spells, stats and look, to the host (see Player.clean_loadout).
## `refill`: a level-up, +100 health and mana.
func send_loadout(fresh: bool, refill := false) -> void:
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_offer_loadout.rpc_id(1, JSON.stringify({"fresh": fresh, "refill": refill, "spells": Run.spells, "mult": Run.spells.keys().reduce(func(m, k): m[k] = Run.cost_mult(k); return m, {}), "passive": Run.passive,
		"stats": Run.stats, "look": Profile.look.merged({
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


## A mage levels up: the host pushes every enemy near it away, in a circle.
@rpc("any_peer", "call_local", "reliable")
func _level_blast() -> void:
	var from := multiplayer.get_remote_sender_id()
	var p := get_node_or_null("P%d" % (from if from else 1))
	if not multiplayer.is_server() or not p:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.position - p.position
		if to.length() < LEVEL_BLAST_RADIUS:
			e.push((to.normalized() if to else Vector2.RIGHT) * LEVEL_BLAST_FORCE)


## The wave's monsters come out one by one (_process), the first at once.
func _next_wave() -> void:
	_wave_started.rpc(Run.wave + 1)
	to_spawn = Run.wave_plan(Run.wave)
	_spawn_in = 0.0


## One monster of the wave, at a random spot off every mage's screen. A
## window wider or taller than this one shows more (stretch aspect
## "expand"): up to 21:9 and 4:3.
func _spawn_enemy(kind: String) -> void:
	var view := get_viewport_rect().size / Player.ZOOM
	view = Vector2(maxf(view.x, view.y * 21.0 / 9.0), maxf(view.y, view.x * 3.0 / 4.0))
	var seen := Arena.views(get_tree().get_nodes_in_group("players").map(func(p): return p.position), view)
	spawned += 1
	spawner.spawn({"kind": "enemy", "name": "E%d" % spawned, "type": kind,
		"stats": Run.enemy_stats(kind, Run.wave), "pos": Arena.spawn_point(seen)})


@rpc("authority", "call_local", "reliable")
func _wave_started(w: int) -> void:
	Run.wave = w
	Run.changed.emit()
	Sfx.play("boss" if Run.wave_plan(w).any(Run.is_boss) else "wave")


## An enemy's summon or split: `kind` at `pos`, at the current wave's stats.
func _on_summoned(kind: String, pos: Vector2) -> void:
	if multiplayer.is_server() and get_tree().get_nodes_in_group("enemies").size() < Enemy.CROWD:
		spawned += 1
		spawner.spawn.call_deferred({"kind": "enemy", "name": "E%d" % spawned, "type": kind,
			"stats": Run.enemy_stats(kind, Run.wave), "pos": pos.clamp(Arena.RECT.position, Arena.RECT.end)})


func _on_killed(e: Node2D) -> void:
	_killed.rpc(e.kind, e.xp, e.data.get("look", e.kind), e.position, e.radius, e._angle, e._flip)
	if Run.is_boss(e.kind) or randf() < 0.5:
		_drop("gold", e.gold, e.position + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
	if randf() < 0.04:
		_drop("mana", 1, e.position + Vector2(randf_range(-10, 10), -10))
	if randf() < 0.01:  # rarer than the rest
		_drop("life", 1, e.position + Vector2(randf_range(-10, 10), 10))
	if Run.is_boss(e.kind) or randf() < GRIMOIRE_CHANCE:
		_drop("grimoire_" + Upgrades.KINDS.pick_random(), 1, e.position + Vector2(randf_range(-12, 12), -16))
	if randf() < (0.05 if Run.is_boss(e.kind) else 0.0025):  # rare: ~1 boss in 20
		_drop("scroll", 1, e.position + Vector2(0, 14))
	if Run.is_boss(e.kind):
		_pull_drops.call_deferred()  # after its own drops' deferred spawns


## Kills and drops are shared: every peer counts them in its own Run.
@rpc("authority", "call_local", "reliable")
func _killed(kind: String, xp: int, look: String, pos: Vector2, radius: float, angle: float, flip: bool) -> void:
	Run.killed(kind)
	Run.collect("xp", xp)  # XP comes from the kill itself, no crystal to pick up
	if not Run.is_boss(kind):
		Sfx.play("die", pos)
		var c := Enemy.Corpse.new()
		c.look = look
		c.position = pos
		c.radius = radius
		c.angle = angle
		add_child(c)
		return
	var fx := BossDeath.new()  # sounds its own blasts
	fx.look = kind
	fx.position = pos
	fx.radius = radius
	fx.flip = flip
	add_child(fx)


@rpc("authority", "call_local", "reliable")
func _collected(kind: String, value: int) -> void:
	Run.collect(kind, value)
	Sfx.play("scroll" if kind.begins_with("grimoire") else kind)
	if kind == "scroll":
		forge_note = tr("Blank scroll found! You can write on it at the end of the run.")


func _drop(kind: String, value: int, pos: Vector2) -> void:
	if multiplayer.is_server():
		spawned += 1
		spawner.spawn.call_deferred({"kind": "pickup", "name": "D%d" % spawned, "type": kind, "value": value, "pos": pos})


## Permadeath: the run ends when every mage is down; its gold and scrolls are
## kept. Hub.
func _on_player_died() -> void:
	if Run.active and get_tree().get_nodes_in_group("players").all(func(p): return p.hp <= 0.0):
		_end_run.rpc()


@rpc("authority", "call_local", "reliable")
func _end_run() -> void:
	if not Run.active:
		return
	last_run = Run.finish()
	last_run.reached = Profile.record_run(last_run)
	last_run.unlocked = Profile.unlocked_by(last_run.reached)
	get_tree().paused = true
	Sfx.music("")
	Sfx.play("game_over")
	run_ended.emit()


## Abandon (pause menu): solo ends the run; in coop this mage drops out.
func abandon_run() -> void:
	if solo():
		_end_run()
	else:
		leave_game()


## Back to the title screen: the world is emptied.
func leave() -> void:
	if not solo():
		leave_game()
	_reset_world()
	get_tree().paused = true


# --- coop: spawning and connections -------------------------------------------

func _spawn(d: Dictionary) -> Node:
	var n: Node2D
	var sync := MultiplayerSynchronizer.new()
	if d.kind == "player":
		n = Player.new()
		n.peer_id = d.id
		n.died.connect(_on_player_died)
		sync.replication_config = _config({"hp": ON_CHANGE, "mana": ALWAYS, "shield": ON_CHANGE, "statuses": ALWAYS, "loadout_json": ON_CHANGE}, true)
		var own := MultiplayerSynchronizer.new()  # what the owner steers
		own.replication_config = _config({"position": ALWAYS, "aim": ALWAYS, "firing": ALWAYS}, false)
		own.set_multiplayer_authority(d.id)
		own.name = "Own"  # fixed names: peers resolve sync paths by name, auto names differ per peer
		n.add_child(own)
	elif d.kind == "enemy":
		n = Enemy.new()
		n.setup(d.type, d.stats)
		n.killed.connect(_on_killed)
		n.summoned.connect(_on_summoned)
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
	sync.name = "Sync"
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
	spawner.spawn({"kind": "player", "name": "P%d" % id, "id": id, "pos": Arena.START})


## Fresh world for a new session: the host (or solo) spawns its mage, a
## joining peer waits for the host's spawns.
func _reset_world() -> void:
	Sfx.music("")
	for n in get_children():
		if n is Node2D:
			n.free()
	if multiplayer.is_server():
		_spawn_player(1)


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		if Run.active:  # drop-in: the newcomer starts its run on this map
			_run_started.rpc_id(id, map_name)
			_wave_started.rpc_id(id, Run.wave)


func _on_peer_left(id: int) -> void:
	var p := get_node_or_null("P%d" % id)
	if multiplayer.is_server() and p:
		p.remove_from_group("players")
		p.queue_free()
		_on_player_died()  # the leaver may have been the last one standing


## Lobby: open a room (its code shows in the lobby once the server answers),
## or join one. Returns an error message, or "".
func host_game() -> String:
	_go_solo()
	return await net.start()


func join_game(code: String) -> String:
	_go_solo()
	return await net.start(code)


## The lobby gave this game its peer id: play through WebRTC.
func _on_net_joined() -> void:
	multiplayer.multiplayer_peer = net.rtc
	_reset_world()


func leave_game() -> void:
	net.close()
	_go_solo()


## Host lost, left the room or never reached it: back to solo.
func _go_solo() -> void:
	if not multiplayer.multiplayer_peer is WebRTCMultiplayerPeer:
		return
	net.close()
	net_error.emit(net.error)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_world()
	if Run.active:
		_end_run()


# --- forge: POST the words, then poll the job until the bundle is ready -------

func can_write() -> bool:
	return Profile.blank_scrolls > 0 and not _forge_posting


## A forge request on its own HTTPRequest (the jobs poll at once); `done` gets
## request_completed's arguments. False: not sent.
func _forge_request(path: String, headers: PackedStringArray, done: Callable,
		method := HTTPClient.METHOD_GET, body := "") -> bool:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(r, c, h, d): http.queue_free(); done.call(r, c, h, d))
	if http.request(Online.server + path, headers, method, body) != OK:
		http.queue_free()
		return false
	return true


## `words`: one word per scroll, separated by spaces or commas; `entry`: the
## owned spell to improve (Profile.owned_spells()), the result takes its slot.
func write_scroll(words: String, entry: Dictionary) -> void:
	var word := words.strip_edges()
	if word.is_empty() or not can_write():
		return
	_forge_posting = true
	var auth := await Online.auth_headers()
	if auth.is_empty():
		_forge_posting = false
		forge_status = tr("Log in (main menu → Account) to write the scrolls.")
		return
	forge_status = tr("Writing the scrolls…")
	var job := {"slot": entry.slot, "spell": entry.spell, "words": 0}
	var body := JSON.stringify({"spell": entry.spell, "words": word,
		"scrolls": Profile.blank_scrolls, "lang": TranslationServer.get_locale()})
	if not _forge_request("/api/forge", auth + PackedStringArray(["Content-Type: application/json"]),
			_on_forge_reply.bind(job), HTTPClient.METHOD_POST, body):
		_forge_posting = false
		forge_status = tr("The scrolls cannot be written right now. Your scrolls are kept.")


func _poll(job: Dictionary) -> void:
	var auth := await Online.auth_headers()  # a forge job can outlive the ID token
	if not _forge_request("/api/forge/" + job.id, auth, _on_forge_reply.bind(job)):
		get_tree().create_timer(POLL_SECONDS, true).timeout.connect(_poll.bind(job))


func _end_job(job: Dictionary, ok: bool) -> void:
	forge_jobs.erase(job)
	forged.emit(job, ok)


func _on_forge_reply(result: int, code: int, headers: PackedStringArray, data: PackedByteArray, job: Dictionary) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.slice(0, 2).get_string_from_ascii() == "PK":
		var applied: int = job.words
		for h in headers:
			if h.to_lower().begins_with("x-forge-applied:"):
				applied = h.get_slice(":", 1).strip_edges().to_int()
		_on_bundle(data, job, clampi(job.words - applied, 0, job.words))
		return
	var reply: Variant = JSON.parse_string(data.get_string_from_utf8())
	reply = reply if reply is Dictionary else {}
	if not job.has("id"):
		_forge_posting = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or reply.has("error"):
		var msg: String = tr(str(reply.get("error", tr("error %d") % code if result == HTTPRequest.RESULT_SUCCESS else tr("offline"))))
		if not job.has("id"):  # words refused or forge unreachable: scrolls kept
			forge_status = tr("The scrolls could not be written (%s). Your scrolls are kept.") % msg
		else:
			Profile.blank_scrolls += job.words  # the scrolls were not used up
			forge_note = tr("Writing the scrolls failed (%s). Your scrolls are given back.") % msg
			forge_status = forge_note
			Profile.save()
			_end_job(job, false)
		return
	if not job.has("id"):
		if not reply.has("job"):
			return
		job.id = reply.job
		job.words = maxi(1, reply.get("words", [1]).size())
		job.started = Time.get_ticks_msec()
		forge_jobs.append(job)
		Profile.blank_scrolls -= job.words
		Profile.save()
		forge_note = tr("%d scroll(s) being written…") % job.words
		forge_status = ""
		forge_started.emit(job)
	get_tree().create_timer(POLL_SECONDS, true).timeout.connect(_poll.bind(job))


## The forged spell is kept and equipped in the improved spell's slot: the run in
## progress keeps its spells, the next one starts with it.
## cancelled: words the forge found meaningless; their scrolls come back.
func _on_bundle(data: PackedByteArray, job: Dictionary, cancelled: int) -> void:
	var path := Profile.next_bundle_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var s := SpellArt.load_bundle(path)
	if s.is_empty():
		Profile.blank_scrolls += job.words
		Profile.save()
		forge_note = tr("The scroll is unreadable. Your scrolls are given back.")
		forge_status = forge_note
		_end_job(job, false)
		return
	Profile.blank_scrolls += cancelled
	Online.push_spell(Profile.add_forged(s, path, job.slot), path)
	forge_note = tr("Scroll written: %s will be your main spell in the next run.") % s.name
	if cancelled > 0:
		forge_note += " " + tr("%d word(s) cancelled (meaningless, not in a dead language or cheating), scroll(s) given back.") % cancelled
	forge_status = forge_note
	_end_job(job, true)
