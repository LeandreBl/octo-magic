extends Node2D
## Prototype loop. A run is offline: waves of enemies; each cleared wave drops a
## blank scroll, kept for later. Between runs (after death, in the hub) the
## player writes a word on a scroll; the forge server rewrites the spell with
## it. Writing takes minutes: the player can start the next run meanwhile, and
## the new spell is equipped at the start of the run after it is ready.

const FORGE_URL := "http://localhost:8765/forge"
const SAVE_PATH := "user://spell.spell"  # bundle: manifest.json + PNGs
const POLL_SECONDS := 3.0
const BOSS_EVERY := 5

var player: Node2D
var wave := 0
var in_run := false
var blank_scrolls := 0
var hud: Label
var hud_icon: TextureRect
var hub: PanelContainer
var hub_title: Label
var word_edit: LineEdit
var write_button: Button
var hub_status: Label
var forge_http: HTTPRequest
var forge_job := ""  # scroll being written on the forge
var forge_note := ""  # forge news, shown in the HUD and the hub
var ready_spell := {}  # forged spell, equipped at the next run start


func _ready() -> void:
	randomize()
	player = preload("res://game/player.gd").new()
	player.died.connect(_end_run)
	player.set_spell(_load_spell())
	add_child(player)
	_build_ui()
	_start_run()


func _load_spell() -> Dictionary:
	var s := SpellArt.load_bundle(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else {}
	return s if not s.is_empty() else Spell.base()


func _process(_delta: float) -> void:
	var s: Dictionary = player.spell
	hud_icon.texture = SpellArt.sheet(s, s.icon_file) if s.icon_file else SpellArt.texture(s.icon, s.palette)
	hud.text = "Vague %d   PV %d   Mana %d   Parchemins vierges %d   |   %s (%d mana)%s\n%s\n%s" % [
		wave, player.hp, player.mana, blank_scrolls, s.name, player.mana_cost,
		"  [" + " + ".join(s.words) + "]" if not s.words.is_empty() else "",
		s.description, forge_note]
	if in_run and get_tree().get_nodes_in_group("enemies").is_empty():
		blank_scrolls += 1
		forge_note = "Parchemin vierge trouvé ! Tu pourras l'écrire à la fin de la run."
		_next_wave()


# --- run ---------------------------------------------------------------------

func _start_run() -> void:
	for n in get_children():
		if n is SpellBody or n.is_in_group("enemies"):
			n.free()
	if not ready_spell.is_empty():
		player.set_spell(ready_spell)
		forge_note = "Nouveau sort équipé : %s !" % ready_spell.name
		ready_spell = {}
	player.hp = player.MAX_HP
	player.mana = player.MAX_MANA
	player.position = get_viewport_rect().size / 2.0
	wave = 0
	in_run = true
	hub.hide()
	get_tree().paused = false
	_next_wave()


func _next_wave() -> void:
	wave += 1
	var size := get_viewport_rect().size
	var boss := wave % BOSS_EVERY == 0
	var count := 1 if boss else 4 + wave * 2
	for i in count:
		var e := preload("res://game/enemy.gd").new()
		e.target = player
		e.position = size / 2.0 + Vector2.from_angle(randf() * TAU) * size.length() * 0.55
		e.max_hp = (400.0 if boss else 20.0) * (1.0 + wave * 0.15)
		e.hp = e.max_hp
		e.speed = 50.0 if boss else randf_range(60.0, 100.0) + wave * 3.0
		e.radius = 36.0 if boss else 12.0
		e.touch_damage = 25.0 if boss else 10.0
		add_child(e)


## Permadeath: the run ends, scrolls (and later gold) are kept. Hub.
func _end_run() -> void:
	if not in_run:
		return
	in_run = false
	get_tree().paused = true
	hub_title.text = "Fin de la run : vague %d." % wave
	_refresh_hub()
	hub.show()
	word_edit.grab_focus()


func _refresh_hub() -> void:
	var can_write := blank_scrolls > 0 and forge_job.is_empty()
	word_edit.editable = can_write
	write_button.disabled = not can_write
	if not forge_job.is_empty():
		hub_status.text = "Un parchemin est en cours d'écriture."
	elif blank_scrolls == 0:
		hub_status.text = "Aucun parchemin vierge : trouve-en pendant la prochaine run."
	else:
		hub_status.text = "Tu as %d parchemin(s) vierge(s). Écris un mot pour transformer ton sort." % blank_scrolls


# --- hub UI ------------------------------------------------------------------

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

	hub = PanelContainer.new()
	hub.custom_minimum_size = Vector2(460, 0)
	hub.position = get_viewport_rect().size / 2.0 - Vector2(230, 90)
	hub.hide()
	layer.add_child(hub)
	var box := VBoxContainer.new()
	hub.add_child(box)
	hub_title = Label.new()
	box.add_child(hub_title)
	word_edit = LineEdit.new()
	word_edit.max_length = 32
	word_edit.placeholder_text = "ex : tempête, vampire, miroir…"
	word_edit.text_submitted.connect(func(_t): _forge())
	box.add_child(word_edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	write_button = Button.new()
	write_button.text = "Écrire le parchemin"
	write_button.pressed.connect(_forge)
	row.add_child(write_button)
	var again := Button.new()
	again.text = "Nouvelle run"
	again.pressed.connect(_start_run)
	row.add_child(again)
	hub_status = Label.new()
	hub_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hub_status)

	forge_http = HTTPRequest.new()
	forge_http.timeout = 30.0
	forge_http.request_completed.connect(_on_forge_reply)
	layer.add_child(forge_http)


# --- forge: POST the word, then poll the job until the bundle is ready -------

func _forge() -> void:
	var word := word_edit.text.strip_edges()
	if word.is_empty() or blank_scrolls == 0 or not forge_job.is_empty() \
			or forge_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	hub_status.text = "Envoi à la forge…"
	var body := JSON.stringify({"spell": player.spell, "word": word})
	if forge_http.request(FORGE_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		hub_status.text = "Impossible de joindre la forge (connexion requise)."


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
			hub_status.text = "La forge a échoué (%s). Ton parchemin est intact." % msg
		else:
			forge_job = ""
			blank_scrolls += 1  # the scroll was not used up
			forge_note = "La forge a échoué (%s). Ton parchemin t'est rendu." % msg
			_refresh_hub()
		return
	if reply.has("job"):
		forge_job = reply.job
		blank_scrolls -= 1
		forge_note = "Parchemin en cours d'écriture…"
		_refresh_hub()
	get_tree().create_timer(POLL_SECONDS, true).timeout.connect(_poll)


func _on_bundle(data: PackedByteArray) -> void:
	forge_job = ""
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var s := SpellArt.load_bundle(SAVE_PATH)
	if s.is_empty():
		forge_note = "Le parchemin est illisible."
		return
	if in_run:  # never swap spells mid-run
		ready_spell = s
		forge_note = "Parchemin écrit : %s sera équipé à la prochaine run." % s.name
	else:
		player.set_spell(s)
		forge_note = "Nouveau sort : %s !" % s.name
	_refresh_hub()
