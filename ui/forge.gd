extends Control
## The spell forge, between runs: a dark wooden table seen from above, a big
## magic circle drawn on it in chalk. Each blank scroll is a small circle in it
## where a word of the spell is written; the words are sent to the forge
## (game/main.gd). Several spells can be forged at once: each job is a small
## circle at the top, its glyphs lighting up one after the other, all lit when
## the spell is forged; clicked, it comes to the foreground in the big circle,
## its words and glyphs there, the writing hidden. On the right, the spell to
## improve is chalked on the table, its name carved in the wood.

signal closed

const UITheme := preload("res://ui/theme.gd")
const HUD := preload("res://ui/hud.gd")  # its spell icon
const MAX_SHOWN := 8  # word circles drawn
const GLYPHS_N := 10  # glyphs lit around a job's circle while forging
const JOB := 64.0  # a job's circle
## Glyphs follow the forge's real progress (main.gd's job.progress); until the
## model answers, an expected curve creeps over its step (MODEL_STEP, server/forge.py).
const FORGE_SECONDS := 90.0
## PixelLab art (tools/make_forge.py); the chalk is white, tinted here.
const ROOM: Texture2D = preload("res://assets/forge/room.png")  # the study, its table seen at three quarters
## Its candles' flames, in ROOM pixels: a flickering light on each.
const FLAMES := [Vector2(68, 38), Vector2(358, 30), Vector2(36, 152), Vector2(390, 158)]
const TILT := 0.8  # the chalk on the table, seen at three quarters: squashed
const CIRCLE: Texture2D = preload("res://assets/forge/circle.png")
const SEAL: Texture2D = preload("res://assets/forge/seal.png")
const GLYPHS: Texture2D = preload("res://assets/forge/glyphs.png")  # 12 glyphs of 32 px
const CHALK := Color(0.95, 0.93, 0.87, 0.92)
const CHALK_DIM := Color(0.85, 0.8, 0.72, 0.72)
const CARVED := Color("#c9965f")  # carved in the wood: the fresh wood under the dark top
const GROOVE := Color("#0d0703")  # the groove's shaded upper wall
const EMBER := Color("#ffb347")  # chalk lit by the forge

var main: Node
var _circle: Control  # the big magic circle, the words' circles in it
var _page: VBoxContainer  # the circle, the line to write on, the button, the status
var _rows: VBoxContainer  # the spell's stats, a name and a value per row
var _spell: Label  # the chosen spell's description
var _pick := ""  # id of the equipped spell to improve; empty: the main one
var _shown := ""  # id of the spell drawn in the picker, and of its character
var _icon: TextureRect
var _name: Label
var _element: Label
var _arrows: Array[Button] = []
var _words: Array = []  # one per blank scroll, written in its circle
var _blanks := 0  # blank scrolls owned
var _edit: LineEdit
var _write: Button
var _status: Label
var _counter: Label
var _jobs: HBoxContainer  # a small circle per forge job (_job_chip)
var _focus := ""  # id of the job in the foreground of the big circle; empty: writing
var _writing: Array[Control] = []  # hidden while a job is in the foreground
var _new: Button  # back to writing
var _gap: Control  # under _new, as tall as the hidden writing: the big circle stays put
var _glow := 0.0  # the big circle flares up when a spell is forged
var _drawn := 1.0  # the chalk being drawn on the table when shown, 0..1
var _time := 0.0
var _order := PackedInt32Array()  # which glyph goes at each place


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in GLYPHS_N:
		_order.append(rng.randi() % 12)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [["left", 32], ["right", 32], ["top", 20], ["bottom", 16]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	add_child(m)
	var box := _vbox(0)
	m.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var back := _chalk_button(Vector2(56, 56))
	back.icon = UITheme.glyph("back", Color.WHITE)
	back.tooltip_text = "Back"
	back.pressed.connect(closed.emit)
	head.add_child(back)
	var title := _carve(Label.new(), 44)
	title.text = "Spell forge"
	head.add_child(title)
	_jobs = HBoxContainer.new()
	_jobs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs.alignment = BoxContainer.ALIGNMENT_END
	_jobs.clip_contents = true
	_jobs.add_theme_constant_override("separation", 12)
	head.add_child(_jobs)
	head.add_child(UITheme.icon_rect(UITheme.icon("scroll"), 36))
	_counter = _chalk(Label.new(), 28)
	head.add_child(_counter)

	# The magic circle and the line to write on, on the left; the spell to
	# improve on the right.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 64)
	box.add_child(body)
	_page = _vbox(4)
	_page.custom_minimum_size.x = 500
	_page.size_flags_vertical = Control.SIZE_SHRINK_END  # the circle clear of the books at the back
	body.add_child(_page)
	_circle = Control.new()
	_circle.custom_minimum_size = Vector2(380, 380 * TILT)
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.draw.connect(_draw_circle)
	_page.add_child(_circle)

	# The words are chalked on a line under the circle.
	_edit = LineEdit.new()
	_edit.max_length = 200
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.add_theme_font_override("font", UITheme.PARCHMENT)
	_edit.add_theme_font_size_override("font_size", 26)
	_edit.add_theme_color_override("font_color", CHALK)
	_edit.add_theme_color_override("font_uneditable_color", CHALK_DIM)
	_edit.add_theme_color_override("font_placeholder_color", Color(CHALK_DIM, 0.45))
	_edit.add_theme_color_override("caret_color", EMBER)
	var line := UITheme.flat(Color(0, 0, 0, 0.18), Color.TRANSPARENT, 0, 10, 0)
	line.border_width_bottom = 3
	line.border_color = CHALK_DIM
	_edit.add_theme_stylebox_override("normal", line)
	var line_on := line.duplicate()
	line_on.border_color = EMBER
	_edit.add_theme_stylebox_override("focus", line_on)
	_edit.add_theme_stylebox_override("read_only", line)
	_edit.placeholder_text = "e.g. ignis, πῦρ, umbra"
	_edit.text_submitted.connect(func(_t): _on_write())
	_page.add_child(_edit)
	var rule := _chalk(Label.new(), 15, CHALK_DIM)
	rule.text = "Letters, ' and - only. A meaningless word gives its scroll back."
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(rule)

	_write = _chalk_button(Vector2(300, 56))
	_write.text = "Forge the spell"
	_write.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_write.add_theme_font_size_override("font_size", 26)
	_write.pressed.connect(_on_write)
	_page.add_child(_write)
	set_meta("focus", _edit)
	_status = _chalk(Label.new(), 16, CHALK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_status)
	_writing = [_edit, rule, _write]
	_new = _chalk_button(Vector2(300, 56))
	_new.text = "New scroll"
	_new.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_new.add_theme_font_size_override("font_size", 26)
	_new.pressed.connect(func(): _focus = "")
	_new.hide()
	_page.add_child(_new)
	_page.move_child(_new, _write.get_index() + 1)
	_gap = Control.new()
	_gap.hide()
	_page.add_child(_gap)
	_page.move_child(_gap, _new.get_index() + 1)

	# The spell to improve, picked among the equipped ones with the arrows: its
	# icon, its name carved in the wood, its description and stats in chalk.
	var view := _vbox(10)
	view.custom_minimum_size.x = 360
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(view)
	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 20)
	view.add_child(picker)
	_icon = UITheme.icon_rect(null, 96)
	for side in [["back", -1, "Previous spell"], ["next", 1, "Next spell"]]:
		var arrow := _chalk_button(Vector2(48, 48))
		arrow.icon = UITheme.glyph(side[0], Color.WHITE)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.tooltip_text = side[2]
		arrow.pressed.connect(func(): _pick = step(Profile.equipped_entries(), _chosen().id, side[1]))
		_arrows.append(arrow)
	picker.add_child(_arrows[0])
	picker.add_child(_icon)
	picker.add_child(_arrows[1])
	_name = _carve(Label.new(), 34)
	_element = _chalk(Label.new(), 16, CHALK_DIM)
	_spell = _chalk(Label.new(), 18)
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	for l in [_name, _element, _spell]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		view.add_child(l)
	_name.clip_text = true
	_rows = _vbox(2)
	view.add_child(_rows)

	main.forge_started.connect(_on_started)
	main.forged.connect(_on_forged)
	for job in main.forge_jobs:
		_jobs.add_child(_job_chip(job))
	visibility_changed.connect(_lay_down)


## Chalk written by hand on the table.
func _chalk(l: Label, size: int, color := CHALK) -> Label:
	l.add_theme_font_override("font", UITheme.PARCHMENT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## Carved in the wood: the fresh wood in the groove, its upper wall in shadow.
func _carve(l: Label, size: int) -> Label:
	_chalk(l, size, CARVED)
	l.add_theme_color_override("font_shadow_color", GROOVE)
	l.add_theme_constant_override("shadow_offset_x", -1)
	l.add_theme_constant_override("shadow_offset_y", -3)
	return l


## A button chalked on the table: a chalk outline, lit up when pointed at.
func _chalk_button(min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", UITheme.PARCHMENT)
	for st in [["normal", CHALK_DIM, 0.0], ["hover", CHALK, 0.1], ["pressed", EMBER, 0.15], ["focus", EMBER, 0.0],
			["disabled", Color(CHALK_DIM, 0.3), 0.0]]:
		var sb := UITheme.flat(Color(1, 1, 1, st[2]), st[1], 3, 8, 0)
		if st[0] == "focus":
			sb.draw_center = false
		b.add_theme_stylebox_override(st[0], sb)
	for c in ["font_color", "font_focus_color", "icon_normal_color", "icon_focus_color"]:
		b.add_theme_color_override(c, CHALK)
	for c in ["font_hover_color", "icon_hover_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	for c in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(c, EMBER)
	for c in ["font_disabled_color", "icon_disabled_color"]:
		b.add_theme_color_override(c, Color(CHALK_DIM, 0.3))
	return b


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


## Shown: the chalk is drawn on the table.
func _lay_down() -> void:
	if visible:
		_drawn = 0.0
		create_tween().tween_property(self, "_drawn", 1.0, 0.6).set_ease(Tween.EASE_OUT)


func _on_write() -> void:
	main.write_scroll(_edit.text, _chosen())


## The equipped spell to improve: the picked one, else the main one.
func _chosen() -> Dictionary:
	var equipped := Profile.equipped_entries()
	for e in equipped:
		if e.id == _pick:
			return e
	return equipped[0]


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


## The words were taken: the line is cleared for the next spell, and the new
## job comes to the foreground of the big circle, as if its chip was clicked.
func _on_started(job: Dictionary) -> void:
	_edit.text = ""
	_focus = job.id
	_jobs.add_child(_job_chip(job))


## A job: a small chalk circle, the improved spell's icon in it, its glyphs
## lighting up around it.
func _job_chip(job: Dictionary) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(JOB, JOB + 18)
	chip.tooltip_text = "%s · %s" % [job.get("who", ""), Spell.label(job.spell)]
	var who := _chalk(Label.new(), 13, CHALK_DIM)  # whose spell, under its circle
	who.text = job.get("who", "")
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	chip.add_child(who)
	chip.set_meta("job", job.id)
	chip.set_meta("glow", 0.0)  # its glyphs flare up once the spell is forged
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and chip.get_meta("job") != "":
			_focus = job.id)
	chip.draw.connect(_draw_job.bind(chip, job, HUD._icon(job.spell)))
	return chip


## The job ended: forged, its glyphs all light up, flare with the big circle,
## and it fades away; failed, it fades at once.
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
			tw.parallel().tween_property(self, "_glow", 1.0, 0.4)
			tw.tween_interval(1.0)
			tw.tween_property(self, "_glow", 0.0, 1.0)
		tw.parallel().tween_property(chip, "modulate:a", 0.0, 0.6)
		tw.tween_callback(chip.queue_free)


## Share of a job's glyphs lit after `seconds` of forging: fast at first, then
## slower, never all.
static func coverage(seconds: float) -> float:
	return 0.95 * (1.0 - exp(-seconds / FORGE_SECONDS))


func _process(delta: float) -> void:
	_time += delta
	if not is_visible_in_tree():
		return
	queue_redraw()
	_circle.queue_redraw()
	for chip in _jobs.get_children():
		chip.queue_redraw()
	var e := _chosen()
	if e.id + Online.character != _shown:  # the icon is built once per pick
		_shown = e.id + Online.character
		_icon.texture = HUD._icon(e.spell)
		_name.text = Spell.label(e.spell)
		var element := tr(str(e.spell.get("element", "")).capitalize())
		var who := Online.character_name()
		_element.text = tr("%s · equipped by %s") % [element, who] if who else element
		_spell.text = Spell.describe(e.spell)
		for c in _rows.get_children():
			c.queue_free()
		for r in stats(e.spell):
			var row := HBoxContainer.new()
			var n := _chalk(Label.new(), 18, CHALK_DIM)
			n.text = r[0]
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
			var v := _chalk(Label.new(), 18, Color("#9cc4ff") if r[0] == tr("Mana cost") else CHALK)
			v.text = r[1]
			row.add_child(v)
			_rows.add_child(row)
	var job := _focused()
	_focus = job.get("id", "")  # ended: back to writing
	for c in _writing:
		c.visible = job.is_empty()
	_new.visible = not job.is_empty()
	_gap.visible = _new.visible
	if _gap.visible:  # the writing's last laid out height (always shown before a job comes to the front)
		var h := 4.0 - _new.get_combined_minimum_size().y  # its 4 separations, against 3 here
		for c in _writing:
			h += c.size.y
		_gap.custom_minimum_size.y = maxf(h, 0.0)
	var can: bool = main.can_write()
	for a in _arrows:
		a.disabled = Profile.equipped_entries().size() < 2
	_edit.editable = can
	_write.disabled = not can
	_words = Array(str(job.get("text", "") if job else _edit.text).replace(",", " ").split(" ", false))
	_blanks = Profile.blank_scrolls
	_counter.text = str(_blanks)
	var state := tr("No blank scroll: bosses drop them.") if _blanks == 0 \
		else tr("The forge turns them into a new spell, equipped at your next run.")
	_status.text = state


## The job in the foreground, {} if none.
func _focused() -> Dictionary:
	for job in main.forge_jobs:
		if job.id == _focus:
			return job
	return {}


## The study and its table, covering the screen; the candles' light flickers.
func _draw() -> void:
	var k := maxf(size.x / ROOM.get_width(), size.y / ROOM.get_height())
	var at := (size - ROOM.get_size() * k) / 2
	draw_texture_rect(ROOM, Rect2(at, ROOM.get_size() * k), false, Color(0.78, 0.74, 0.72))  # dimmed: the chalk stands out
	for i in FLAMES.size():
		var flicker := 0.85 + 0.15 * sin(_time * 9.0 + i * 2.1) * sin(_time * 3.7 + i)
		for g in [[40.0, 0.05], [22.0, 0.08], [10.0, 0.12]]:
			draw_circle(at + FLAMES[i] * k, g[0] * k / 4 * flicker, Color(EMBER, g[1]))


## The big chalk circle, a small circle per blank scroll in it with its word,
## and the glyphs lit around it by the forge, the newest still hot.
func _draw_circle() -> void:
	var side := minf(_circle.size.x, _circle.size.y / TILT)
	var mid := _circle.size / 2
	var lit := maxf(_glow, 0.25 if not main.forge_jobs.is_empty() else 0.0)  # the forge at work
	if lit > 0:  # the forge's light on the table
		for g in [[0.62, 0.05], [0.5, 0.06], [0.3, 0.08]]:
			_circle.draw_circle(mid, side * g[0] * (0.97 + 0.03 * sin(_time * 7.0)), Color(EMBER, g[1] * lit))
	var chalk := CHALK.lerp(EMBER, lit)
	chalk.a *= _drawn
	var d := side * 1.0  # its rings span 0.84 of it
	var flat := Transform2D(0, Vector2(1, TILT), 0, mid)  # on the table, around the circle's middle
	_circle.draw_set_transform_matrix(flat)
	var job := _focused()
	var rings := chalk.lerp(Color(UITheme.GOLD, chalk.a), _progress(job)) if job else chalk  # gilded as its spell is forged
	_circle.draw_texture_rect(CIRCLE, Rect2(-Vector2(d, d) / 2, Vector2(d, d)), false, rings)

	if job:  # its glyphs lit around the big circle
		_glyphs(_circle, job, Vector2.ZERO, d * 0.47, d * 0.08, 0.0, false)
	var seals := _words.size() if job else _blanks  # a job: a circle per word written
	var n := clampi(seals, 1, MAX_SHOWN)
	var ring := 0.0 if n == 1 else side * 0.24
	var seal := minf(side * 0.27, 2.0 * ring * sin(PI / n) * 0.95) if n > 1 else side * 0.3
	var font: Font = UITheme.PARCHMENT
	for i in n:
		var at := Vector2.from_angle(-PI / 2 + TAU * i / n) * ring
		var word: String = _words[i] if i < _words.size() and i < seals else ""
		var tint := chalk if word else Color(chalk, chalk.a * (0.7 if i < seals else 0.25))
		var s := seal * (1.0 + 0.04 * sin(_time * 4.0 + i)) if word else seal  # written: it breathes
		_circle.draw_set_transform_matrix(flat)
		_circle.draw_texture_rect(SEAL, Rect2(at - Vector2(s, s) / 2, Vector2(s, s)), false, tint)
		_circle.draw_set_transform(Vector2.ZERO)  # the words stay upright, at their circle
		at = flat * at
		if word:
			var fs := 26
			while fs > 10 and font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > seal * 0.7:
				fs -= 1
			var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := at + Vector2(-w / 2, fs * 0.35)
			var gold := Color(UITheme.GOLD, _drawn)
			# a 1px gold rim (the outline size is its full width, both sides)
			_circle.draw_string_outline(font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, gold)
			_circle.draw_string(font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.from_hsv((hash(word) % 360) / 360.0, 0.85, 0.95, _drawn))  # a hue per word, from its letters


## A job's circle: the spell's icon in it, its glyphs lit one after the other,
## the newest still hot; all of them once the spell is forged.
func _draw_job(chip: Control, job: Dictionary, icon: Texture2D) -> void:
	var mid := Vector2(JOB, JOB) / 2  # the circle on top, the mage's name under it
	var done: bool = chip.get_meta("job") == ""
	var glow: float = chip.get_meta("glow")
	var front: bool = job.id == _focus  # in the foreground: its circle lit
	chip.draw_texture_rect(SEAL, Rect2(Vector2.ZERO, Vector2(JOB, JOB)), false, CHALK.lerp(EMBER, maxf(glow, 0.6 if front else 0.0)))
	var s := JOB * 0.4
	chip.draw_texture_rect(icon, Rect2(mid - Vector2(s, s) / 2, Vector2(s, s)), false)
	_glyphs(chip, job, mid, JOB * 0.36, JOB * 0.2, glow, done)


## A job's glyphs on `c`, around `mid` at `radius`, `g` wide: lit one after the
## other, the newest still hot; all of them once `done`.
func _glyphs(c: CanvasItem, job: Dictionary, mid: Vector2, radius: float, g: float, glow: float, done: bool) -> void:
	var shown: float = GLYPHS_N if done else _progress(job) * GLYPHS_N
	for i in mini(ceili(shown), GLYPHS_N):
		var at := mid + Vector2.from_angle(-PI / 2 + TAU * i / GLYPHS_N) * radius
		var hot := clampf(1.0 - (shown - i) / 3.0, 0.0, 1.0)  # the last ones are still hot
		var tint := CHALK.lerp(EMBER, maxf(hot, glow))
		tint.a = clampf(shown - i, 0.0, 1.0)  # the glyph being lit fades in
		c.draw_texture_rect_region(GLYPHS, Rect2(at - Vector2(g, g) / 2, Vector2(g, g)), Rect2(_order[i] * 32, 0, 32, 32), tint)


## A job's progress shown, 0..1: the forge's real one, an expected curve creeping
## until the model answers.
static func _progress(job: Dictionary) -> float:
	return maxf(job.get("progress", 0.0), 0.2 * coverage((Time.get_ticks_msec() - job.started) / 1000.0))
