extends Control
## The spell forge, between runs: a parchment on a candle-lit table. The words
## written on it (one per blank scroll) are sent to the forge (game/main.gd);
## several can be written at once: each job's runes are engraved on its own strip
## at the top, the strip full when the spell is forged.

signal closed

const UITheme := preload("res://ui/theme.gd")
const HUD := preload("res://ui/hud.gd")  # its spell icon
const MAX_SHOWN := 8  # blank scrolls drawn
const CELL := 20.0  # a rune's square on a job's strip
## The forge gives no progress: runes follow an expected curve, slowing down
## (never full) until the spell comes back.
const FORGE_SECONDS := 90.0
const FLAME := Color("#ffb347")
const PX := 3  # screen pixels per art pixel
## PixelLab art (tools/make_forge.py).
const TABLE: Texture2D = preload("res://assets/forge/table.png")
const PARCHMENT: Texture2D = preload("res://assets/forge/parchment.png")
const CANDLE: Texture2D = preload("res://assets/forge/candle.png")  # 8 frames of 64 px
const QUILL: Texture2D = preload("res://assets/forge/quill.png")
const RUNES: Texture2D = preload("res://assets/forge/runes.png")  # glowing gold runes of 32 px
const CANDLE_GAP := 64 * PX + 24  # between the parchment and the view: a candle

var main: Node
var _parchment: PanelContainer
var _page: VBoxContainer
var _jobs: HBoxContainer  # a strip of runes per job (_job_chip)
var _view: PanelContainer  # the chosen spell: icon, name, description, stats
var _rows: VBoxContainer  # its stats, a name and a value per row
var _spell: Label  # the chosen spell's description
var _pick := ""  # id of the owned spell to improve; empty: the equipped main spell
var _shown := ""  # id of the spell drawn in the picker
var _icon: TextureRect
var _name: Label
var _element: Label
var _arrows: Array[Button] = []
var _blanks: HBoxContainer
var _count: Label
var _edit: LineEdit
var _write: Button
var _status: Label
var _counter: Label
var _time := 0.0
var _order := PackedInt32Array()  # which rune goes in each cell


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 512:
		_order.append(rng.randi() % 12)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [["left", 32], ["right", 32], ["top", 28], ["bottom", 28]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	add_child(m)
	var box := _vbox(16)
	m.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var back := Button.new()
	back.icon = UITheme.glyph("back", UITheme.TEXT)
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(56, 56)
	back.tooltip_text = "Back"
	back.pressed.connect(closed.emit)
	head.add_child(back)
	head.add_child(UITheme.label("Spell forge", "Header"))
	_jobs = HBoxContainer.new()
	_jobs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs.alignment = BoxContainer.ALIGNMENT_END
	_jobs.clip_contents = true
	_jobs.add_theme_constant_override("separation", 10)
	head.add_child(_jobs)
	var plate := PanelContainer.new()
	plate.theme_type_variation = "Plate"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p_row := HBoxContainer.new()
	plate.add_child(p_row)
	p_row.add_child(UITheme.icon_rect(UITheme.icon("scroll"), 32))
	_counter = UITheme.label("", "", 24)
	p_row.add_child(_counter)
	head.add_child(plate)

	# The parchment on the left, lifted off the screen's bottom edge; a candle,
	# then the view of the spell to improve on the right.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", CANDLE_GAP)
	box.add_child(body)
	_parchment = PanelContainer.new()
	_parchment.add_theme_stylebox_override("panel", _sheet())
	_parchment.custom_minimum_size.x = 600
	_parchment.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_parchment)
	_page = _vbox(14)
	_parchment.add_child(_page)

	var heading := _ink(Label.new(), 30, UITheme.PARCH_RED)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.text = "Write the words of the spell"
	heading.add_theme_font_override("font", UITheme.PARCHMENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(heading)

	# The spell to improve, picked among the owned ones with the arrows: its
	# icon, name, description and stats.
	_view = PanelContainer.new()
	_view.custom_minimum_size.x = 400
	_view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_view)
	var card := _vbox(12)
	_view.add_child(card)
	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 20)
	card.add_child(picker)
	_icon = UITheme.icon_rect(null, 96)
	for side in [["back", -1, "Previous spell"], ["next", 1, "Next spell"]]:
		var arrow := Button.new()
		arrow.icon = UITheme.glyph(side[0], UITheme.TEXT)
		arrow.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.custom_minimum_size = Vector2(48, 48)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.tooltip_text = side[2]
		arrow.pressed.connect(func(): _pick = step(Profile.owned_spells(), _chosen().id, side[1]))
		_arrows.append(arrow)
	picker.add_child(_arrows[0])
	picker.add_child(_icon)
	picker.add_child(_arrows[1])
	_name = UITheme.label("", "Header", 28, UITheme.GOLD)
	_element = UITheme.label("", "", 16, UITheme.TEXT_DIM)
	_spell = UITheme.label("", "", 17)
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	for l in [_name, _element, _spell]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(l)
	_name.clip_text = true
	_rows = _vbox(4)
	card.add_child(_rows)

	var blanks_row := _vbox(6)
	_page.add_child(blanks_row)
	_blanks = HBoxContainer.new()
	_blanks.alignment = BoxContainer.ALIGNMENT_CENTER
	_blanks.add_theme_constant_override("separation", 8)
	blanks_row.add_child(_blanks)
	for i in MAX_SHOWN:
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PARCH_LIGHT, UITheme.PARCH_BROWN, 3, 2, 0))
		blank.custom_minimum_size = Vector2(44, 44)
		var word := _ink(Label.new(), 14, UITheme.PARCH_RED)
		word.add_theme_font_override("font", UITheme.PARCHMENT)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word.clip_text = true
		blank.add_child(word)
		_blanks.add_child(blank)
	_count = _ink(Label.new(), 16, UITheme.PARCH_BROWN)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blanks_row.add_child(_count)

	# The words are inked on a line of the parchment.
	_edit = LineEdit.new()
	_edit.max_length = 200
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.add_theme_font_override("font", UITheme.PARCHMENT)
	_edit.add_theme_font_size_override("font_size", 30)
	_edit.add_theme_color_override("font_color", UITheme.PARCH_INK)
	_edit.add_theme_color_override("font_uneditable_color", UITheme.PARCH_BROWN)
	_edit.add_theme_color_override("font_placeholder_color", Color(UITheme.PARCH_BROWN, 0.7))
	_edit.add_theme_color_override("caret_color", UITheme.PARCH_RED)
	var line := UITheme.flat(Color(UITheme.PARCH_LIGHT, 0.35), Color.TRANSPARENT, 0, 14, 0)
	line.border_width_bottom = 3
	line.border_color = UITheme.PARCH_BROWN
	_edit.add_theme_stylebox_override("normal", line)
	var line_on := line.duplicate()
	line_on.border_color = UITheme.PARCH_RED
	_edit.add_theme_stylebox_override("focus", line_on)
	_edit.add_theme_stylebox_override("read_only", line)
	_edit.placeholder_text = "one word per scroll, in a dead language, e.g. ignis, πῦρ, umbra"
	_edit.text_submitted.connect(func(_t): _on_write())
	_page.add_child(_edit)
	var rule := _ink(Label.new(), 15, UITheme.PARCH_BROWN)
	rule.text = "Letters, ' and - only. A meaningless word gives its scroll back."
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(rule)

	_write = Button.new()
	_write.text = "Forge the spell"
	_write.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_write.custom_minimum_size = Vector2(300, 64)
	_write.add_theme_font_override("font", UITheme.BODY_BOLD)
	_write.add_theme_font_size_override("font_size", 26)
	var seal := {"rings": [[UITheme.OUTLINE, 4]], "bg": Color("#7a2f17"), "top": Color("#94401f"), "bottom": Color("#55200f"), "drop": 4}
	_write.add_theme_stylebox_override("normal", UITheme.frame(seal, 10))
	_write.add_theme_stylebox_override("hover", UITheme.frame(seal.merged({"bg": Color("#8e3a1d")}, true), 10))
	_write.add_theme_stylebox_override("pressed", UITheme.frame(seal.merged({"drop": 0, "top": Color("#55200f")}, true), 10, 4))
	_write.add_theme_stylebox_override("disabled", UITheme.frame(seal.merged({"bg": Color("#a78b6a"), "top": Color("#a78b6a"),
		"bottom": Color("#a78b6a"), "drop": 0}, true), 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_write.add_theme_color_override(c, UITheme.PARCH_LIGHT)
	_write.add_theme_color_override("font_disabled_color", UITheme.PARCH_LIGHT)
	_write.pressed.connect(_on_write)
	_page.add_child(_write)
	set_meta("focus", _edit)
	_status = _ink(Label.new(), 17, UITheme.PARCH_BROWN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_status)

	main.forge_started.connect(_on_started)
	main.forged.connect(_on_forged)
	for job in main.forge_jobs:
		_jobs.add_child(_job_chip(job))
	visibility_changed.connect(_lay_down)


## The parchment sheet, its rolled edges kept crisp at PX, the middle stretched.
func _sheet() -> StyleBoxTexture:
	var img := PARCHMENT.get_image()
	img.resize(img.get_width() * PX, img.get_height() * PX, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	for side in [[SIDE_LEFT, 24, 84], [SIDE_RIGHT, 24, 84], [SIDE_TOP, 18, 60], [SIDE_BOTTOM, 18, 56]]:
		sb.set_texture_margin(side[0], side[1] * PX)
		sb.set_content_margin(side[0], side[2])
	return sb


## Dark ink on the parchment: no light text shadow.
func _ink(l: Label, size: int, color: Color) -> Label:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


## Shown: the parchment is laid down on the table.
func _lay_down() -> void:
	if not visible:
		return
	_parchment.pivot_offset = _parchment.size / 2
	_parchment.rotation = -0.08
	_parchment.scale = Vector2(1.12, 1.12)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_parchment, "rotation", 0.0, 0.45)
	tw.tween_property(_parchment, "scale", Vector2.ONE, 0.45)


func _on_write() -> void:
	main.write_scroll(_edit.text, _chosen())


## The owned spell to improve: the picked one, else the equipped main spell.
func _chosen() -> Dictionary:
	var owned := Profile.owned_spells()
	for id in [_pick, Profile.spells.get("primary", "")]:
		for e in owned:
			if e.id == id:
				return e
	return owned[0]


## The id `by` spells after `id` in `owned`, wrapping around.
static func step(owned: Array, id: String, by: int) -> String:
	var i := owned.map(func(e): return e.id).find(id)
	return owned[posmod(i + by, owned.size())].id


## The spell's stats, a [name, value] per row (the base spell, before any
## bonus of the mage or the run).
func stats(s: Dictionary) -> Array:
	var b: Dictionary = s.emit.body
	var rows := [[tr("Mana cost"), Spell.cost_text(s, Spell.mana_cost(s))]]
	var dmg := 0.0
	var effects := []
	for f in b.on_hit + b.on_expire + b.on_tick:
		match f.type:
			"damage": dmg += f.amount
			"status": effects.append({"burn": tr("Burn"), "poison": tr("Poison"), "slow": tr("Slow"),
				"freeze": tr("Freeze"), "stun": tr("Stun")}[f.status])
			"knockback": effects.append(tr("Knockback"))
			"heal": effects.append(tr("Heal"))
			"cast": effects.append(tr("Splits"))
	if dmg > 0.0:
		rows.append([tr("Damage"), "%d × %d" % [roundi(dmg), s.emit.count] if s.emit.count > 1 else str(roundi(dmg))])
	if not b.on_tick.is_empty():
		rows.append([tr("Ticks"), tr("every %.1f s") % b.tick_interval])
	rows.append([tr("Cooldown"), "%.2f s" % s.cooldown])
	rows.append([tr("Shape"), {"bolt": tr("Bolt"), "zone": tr("Zone"), "beam": tr("Beam"), "cone": tr("Cone")}[b.shape]])
	if s.emit.count > 1:
		rows.append([tr("Projectiles"), str(s.emit.count)])
	if b.shape == "bolt" and b.speed > 0.0:
		rows.append([tr("Speed"), str(roundi(b.speed))])
	if b.pierce > 0:
		rows.append([tr("Pierce"), str(b.pierce)])
	if b.bounce > 0:
		rows.append([tr("Bounces"), str(b.bounce)])
	if not effects.is_empty():
		rows.append([tr("Effects"), ", ".join(effects)])
	return rows


## The words were taken: the line is cleared for the next spell.
func _on_started(job: Dictionary) -> void:
	_edit.text = ""
	_jobs.add_child(_job_chip(job))


## A job's plate: the improved spell's icon and name over its strip of runes.
func _job_chip(job: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "Plate"
	chip.set_meta("job", job.id)
	chip.set_meta("glow", 0.0)  # the runes flare up gold once the spell is forged
	var row := HBoxContainer.new()
	chip.add_child(row)
	row.add_child(UITheme.icon_rect(HUD._icon(job.spell), 32))
	var col := _vbox(2)
	row.add_child(col)
	var title := UITheme.label(Spell.label(job.spell), "", 14)
	title.clip_text = true
	title.custom_minimum_size.x = 8 * CELL
	col.add_child(title)
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(8 * CELL, CELL)
	strip.draw.connect(_draw_strip.bind(strip, chip, job))
	chip.set_meta("strip", strip)
	col.add_child(strip)
	return chip


## The job ended: forged, its strip fills, flares up and the plate fades away;
## failed, it fades at once.
func _on_forged(job: Dictionary, ok: bool) -> void:
	for chip in _jobs.get_children():
		if chip.get_meta("job") != job.id:
			continue
		chip.set_meta("job", "")  # ended
		var tw := chip.create_tween()
		if ok:
			_pick = ""  # the forged spell, equipped in the improved one's slot
			tw.tween_callback(Sfx.play.bind("scroll"))
			tw.tween_method(func(g): chip.set_meta("glow", g), 0.0, 1.0, 0.4)
			tw.tween_interval(1.2)
		tw.tween_property(chip, "modulate:a", 0.0, 0.6)
		tw.tween_callback(chip.queue_free)


## Share of the parchment covered after `seconds` of forging: fast at first,
## then slower, never full.
static func coverage(seconds: float) -> float:
	return 0.95 * (1.0 - exp(-seconds / FORGE_SECONDS))


func _process(delta: float) -> void:
	_time += delta
	if not is_visible_in_tree():
		return
	queue_redraw()
	for chip in _jobs.get_children():
		chip.get_meta("strip").queue_redraw()
	var e := _chosen()
	if e.id != _shown:  # the icon is built once per pick
		_shown = e.id
		_icon.texture = HUD._icon(e.spell)
		_name.text = Spell.label(e.spell)
		_element.text = tr("%s · spell %d of %d") % [tr(str(e.spell.get("element", "")).capitalize()),
			Profile.owned_spells().find(e) + 1, Profile.owned_spells().size()]
		_spell.text = Spell.describe(e.spell)
		for c in _rows.get_children():
			c.queue_free()
		for r in stats(e.spell):
			var row := HBoxContainer.new()
			var n := UITheme.label(r[0], "", 17, UITheme.TEXT_DIM)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
			row.add_child(UITheme.label(r[1], "", 17, UITheme.MANA if r[0] == tr("Mana cost") else UITheme.TEXT))
			_rows.add_child(row)
	var can: bool = main.can_write()
	for a in _arrows:
		a.disabled = Profile.owned_spells().size() < 2
	_edit.editable = can
	_write.disabled = not can
	var words := Array(_edit.text.replace(",", " ").split(" ", false))
	var n: int = Profile.blank_scrolls
	_counter.text = str(n)
	for i in MAX_SHOWN:
		var blank: Control = _blanks.get_child(i)
		blank.visible = i < maxi(n, 1)
		blank.modulate.a = 1.0 if i < n else 0.4
		var word: String = words[i] if i < words.size() and i < n else ""
		blank.get_child(0).text = word
		blank.scale = Vector2.ONE * (1.0 + 0.04 * sin(_time * 4.0 + i)) if word else Vector2.ONE  # inked: it breathes
		blank.pivot_offset = blank.size / 2
	_count.text = tr("%d blank · %d word(s)") % [n, mini(words.size(), n)] if n else ""
	var state := tr("No blank scroll: bosses drop them.") if n == 0 \
		else tr("The forge turns them into a new spell, equipped at your next run.")
	_status.text = main.forge_status + "\n" + state if main.forge_status else state


## The room: a dark wall, the wooden table, a candle beside the parchment.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.INK)
	var top := size.y * 0.38
	draw_set_transform(Vector2(0, top), 0, Vector2(PX, PX))
	draw_texture_rect(TABLE, Rect2(0, 0, size.x / PX, (size.y - top) / PX), true)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(0, top - 4, size.x, 8), Color(0, 0, 0, 0.5))  # the table's far edge
	var r := _parchment.get_global_rect()
	r.position -= global_position
	var flicker := 0.85 + 0.15 * sin(_time * 9.0) * sin(_time * 3.7)
	var frame := int(_time * 8.0) % 8
	var side := 64.0 * PX
	var at := Vector2(r.end.x + (CANDLE_GAP - side) / 2, r.end.y - side)
	for g in [[150.0, 0.05], [90.0, 0.07], [45.0, 0.1]]:  # its light on the table
		draw_circle(at + Vector2(side / 2, side * 0.2), g[0] * flicker, Color(FLAME, g[1]))
	draw_texture_rect_region(CANDLE, Rect2(at, Vector2(side, side)), Rect2(frame * 64, 0, 64, 64))


## A job's runes engraved one after the other, the newest glowing as if still
## hot, the quill writing the next one; all gold once the spell is forged.
func _draw_strip(strip: Control, chip: Control, job: Dictionary) -> void:
	var cols := maxi(1, int(strip.size.x / CELL))
	var done: bool = chip.get_meta("job") == ""
	var shown: float = cols if done else coverage((Time.get_ticks_msec() - job.started) / 1000.0) * cols
	var glow: float = chip.get_meta("glow")
	for i in mini(ceili(shown), cols):
		var fresh := clampf(shown - i, 0.0, 1.0)  # the rune being engraved fades in
		var hot := clampf(1.0 - (shown - i) / 3.0, 0.0, 1.0)  # the last ones are still hot
		var tint := Color(1, 1, 1, 0.35).lerp(Color.WHITE, maxf(hot, glow))
		tint.a *= fresh
		strip.draw_texture_rect_region(RUNES, Rect2(Vector2(i * CELL, 0), Vector2(CELL, CELL)),
			Rect2(_order[i % _order.size()] * 32, 0, 32, 32), tint)
	if not done:  # the quill writing the next rune, its nib bottom left
		var at := Vector2((int(shown) + 0.5) * CELL, CELL * 0.5) + Vector2(2 * sin(_time * 14.0), 1.5 * cos(_time * 9.0))
		strip.draw_texture_rect(QUILL, Rect2(at - Vector2(3, 34), Vector2(38, 38)), false)
