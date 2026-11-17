extends Node2D
## Prototype loop: waves of enemies; after each cleared wave the player finds
## a blank scroll, writes a word on it, and the forge server rewrites the
## spell with that word.

const FORGE_URL := "http://localhost:8765/forge"
const SAVE_PATH := "user://spell.json"
const BOSS_EVERY := 5

var player: Node2D
var wave := 0
var hud: Label
var hud_icon: TextureRect
var scroll_panel: PanelContainer
var word_edit: LineEdit
var scroll_status: Label
var forge_http: HTTPRequest


func _ready() -> void:
	randomize()
	player = preload("res://game/player.gd").new()
	player.position = get_viewport_rect().size / 2.0
	player.died.connect(_on_died)
	player.set_spell(_load_spell())
	add_child(player)
	_build_ui()
	_next_wave()


func _load_spell() -> Dictionary:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		return Spell.sanitize(JSON.parse_string(f.get_as_text()))
	return Spell.base()


func _save_spell(s: Dictionary) -> void:
	FileAccess.open(SAVE_PATH, FileAccess.WRITE).store_string(JSON.stringify(s, "  "))


func _process(_delta: float) -> void:
	var s: Dictionary = player.spell
	hud_icon.texture = SpellArt.texture(s.icon, s.palette)
	hud.text = "Vague %d   PV %d   Mana %d   |   %s (%d mana)%s\n%s" % [
		wave, player.hp, player.mana, s.name, player.mana_cost,
		"  [" + " + ".join(s.words) + "]" if not s.words.is_empty() else "",
		s.description]
	if not get_tree().paused and get_tree().get_nodes_in_group("enemies").is_empty():
		_open_scroll()


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


func _on_died() -> void:
	# Permadeath: restart the run. The spell stays (gold will too).
	get_tree().reload_current_scene.call_deferred()


# --- scroll UI ---------------------------------------------------------------

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

	scroll_panel = PanelContainer.new()
	scroll_panel.set_anchors_preset(Control.PRESET_CENTER)
	scroll_panel.custom_minimum_size = Vector2(420, 0)
	scroll_panel.position = get_viewport_rect().size / 2.0 - Vector2(210, 80)
	scroll_panel.hide()
	layer.add_child(scroll_panel)
	var box := VBoxContainer.new()
	scroll_panel.add_child(box)
	var title := Label.new()
	title.text = "Tu trouves un parchemin vierge.\nÉcris un mot pour transformer ton sort :"
	box.add_child(title)
	word_edit = LineEdit.new()
	word_edit.max_length = 32
	word_edit.placeholder_text = "ex : tempête, vampire, miroir…"
	word_edit.text_submitted.connect(func(_t): _forge())
	box.add_child(word_edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	var write := Button.new()
	write.text = "Écrire"
	write.pressed.connect(_forge)
	row.add_child(write)
	var skip := Button.new()
	skip.text = "Garder mon sort"
	skip.pressed.connect(_close_scroll)
	row.add_child(skip)
	scroll_status = Label.new()
	scroll_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(scroll_status)

	forge_http = HTTPRequest.new()
	forge_http.timeout = 90.0
	forge_http.request_completed.connect(_on_forged)
	layer.add_child(forge_http)


func _open_scroll() -> void:
	get_tree().paused = true
	word_edit.text = ""
	scroll_status.text = ""
	scroll_panel.show()
	word_edit.grab_focus()


func _close_scroll() -> void:
	scroll_panel.hide()
	get_tree().paused = false
	_next_wave()


func _forge() -> void:
	var word := word_edit.text.strip_edges()
	if word.is_empty() or forge_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	scroll_status.text = "Le parchemin s'écrit…"
	var body := JSON.stringify({"spell": player.spell, "word": word})
	var err := forge_http.request(FORGE_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		scroll_status.text = "Impossible de joindre la forge (connexion requise)."


func _on_forged(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
	var reply: Variant = JSON.parse_string(data.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not reply is Dictionary:
		var msg: String = reply.get("error", "") if reply is Dictionary else ""
		scroll_status.text = "La forge a échoué (%s). Réessaie ou garde ton sort." % (msg if msg else str(code))
		return
	var s := Spell.sanitize(reply.get("spell"))
	_save_spell(s)
	player.set_spell(s)
	_close_scroll()
