extends Control
## The spell forge, between runs: a parchment on a candle-lit table. The words
## written on it (one per blank scroll) are sent to the forge (game/main.gd);
## while the forge works, runes are engraved on the parchment line after line:
## fully covered, the spell is forged.

signal closed

const UITheme := preload("res://ui/theme.gd")
const MAX_SHOWN := 8  # blank scrolls drawn
const CELL := 46.0  # a rune's square on the parchment
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
const RUNE_INK := Color(0.42, 0.2, 0.1)  # a cooled rune: the gold darkened to ink

var main: Node
var _parchment: PanelContainer
var _page: VBoxContainer  # what is written, dimmed under the runes (not the status)
var _runes: Control
var _spell: Label
var _blanks: HBoxContainer
var _count: Label
var _edit: LineEdit
var _write: Button
var _status: Label
var _counter: Label
var _progress := 0.0  # share of the parchment covered with runes
var _glow := 0.0  # the runes flare up gold once the spell is forged
var _fade := 0.0  # runes shown, 0..1
var _started := 0.0  # Time.get_ticks_msec() when the job started
var _busy := false  # a forge job runs
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
	var title := UITheme.label("Spell forge", "Header")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var plate := PanelContainer.new()
	plate.theme_type_variation = "Plate"
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p_row := HBoxContainer.new()
	plate.add_child(p_row)
	p_row.add_child(UITheme.icon_rect(UITheme.icon("scroll"), 32))
	_counter = UITheme.label("", "", 24)
	p_row.add_child(_counter)
	head.add_child(plate)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(center)
	_parchment = PanelContainer.new()
	_parchment.add_theme_stylebox_override("panel", _sheet())
	_parchment.custom_minimum_size = Vector2(900, 620)
	center.add_child(_parchment)
	_page = _vbox(14)
	_parchment.add_child(_page)
	_runes = Control.new()
	_runes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_runes.draw.connect(_draw_runes)
	_parchment.add_child(_runes)

	var heading := _ink(Label.new(), 34, UITheme.PARCH_RED)
	heading.text = "Write the words of the spell"
	heading.add_theme_font_override("font", UITheme.PARCHMENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(heading)
	_spell = _ink(Label.new(), 19, UITheme.PARCH_INK)
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spell.add_theme_font_override("font", UITheme.GREEK)
	_page.add_child(_spell)

	var blanks_row := HBoxContainer.new()
	blanks_row.alignment = BoxContainer.ALIGNMENT_CENTER
	blanks_row.add_theme_constant_override("separation", 10)
	_page.add_child(blanks_row)
	_blanks = HBoxContainer.new()
	_blanks.add_theme_constant_override("separation", 8)
	blanks_row.add_child(_blanks)
	for i in MAX_SHOWN:
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PARCH_LIGHT, UITheme.PARCH_BROWN, 3, 2, 0))
		blank.custom_minimum_size = Vector2(64, 64)
		var word := _ink(Label.new(), 14, UITheme.PARCH_RED)
		word.add_theme_font_override("font", UITheme.PARCHMENT)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word.clip_text = true
		blank.add_child(word)
		_blanks.add_child(blank)
	_count = _ink(Label.new(), 16, UITheme.PARCH_BROWN)
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

	main.forged.connect(_on_forged)
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
	main.write_scroll(_edit.text)


## The job ended: forged, the runes fill the parchment, flare up and fade away
## (the spell is written); failed, they fade at once.
func _on_forged(ok: bool) -> void:
	_busy = false
	var tw := create_tween()
	if ok:
		_edit.text = ""
		tw.tween_property(self, "_progress", 1.0, 0.6)
		tw.tween_callback(Sfx.play.bind("scroll"))
		tw.tween_property(self, "_glow", 1.0, 0.3)
		tw.tween_interval(0.8)
		tw.tween_property(self, "_fade", 0.0, 1.2)
		tw.parallel().tween_property(self, "_glow", 0.0, 1.2)
	else:
		tw.tween_property(self, "_fade", 0.0, 0.6)


## Share of the parchment covered after `seconds` of forging: fast at first,
## then slower, never full.
static func coverage(seconds: float) -> float:
	return 0.95 * (1.0 - exp(-seconds / FORGE_SECONDS))


func _process(delta: float) -> void:
	_time += delta
	if not _busy and not main.forge_job.is_empty():  # a job started
		_busy = true
		_started = Time.get_ticks_msec()
		_progress = 0.0
		_glow = 0.0
		_fade = 1.0
	if _busy:
		_progress = coverage((Time.get_ticks_msec() - _started) / 1000.0)
	if not is_visible_in_tree():
		return
	queue_redraw()
	_runes.queue_redraw()
	for c in _page.get_children():  # the forge's progress stays readable
		if c != _status:
			c.modulate.a = lerpf(1.0, 0.3, _fade)
	var s: Dictionary = Profile.equipped_spells().primary
	_spell.text = tr("Main spell: %s\n%s") % [Spell.label(s), Spell.describe(s)]
	var can: bool = main.can_write()
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
	var state := ""
	if _busy:
		state = tr("The forge is engraving the spell… %d%%") % roundi(_progress * 100)
	elif n == 0:
		state = tr("No blank scroll: bosses drop them.")
	else:
		state = tr("The forge turns them into a new spell, equipped at your next run.")
	_status.text = main.forge_status + "\n" + state if main.forge_status and not _busy else state


## The room: a dark wall, the wooden table, two candles beside the parchment.
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
	for x in [r.position.x - side - 8, r.end.x + 8]:
		var at := Vector2(x, minf(r.end.y, size.y - 16) - side)
		for g in [[170.0, 0.05], [100.0, 0.07], [50.0, 0.1]]:  # its light on the table
			draw_circle(at + Vector2(side / 2, side * 0.2), g[0] * flicker, Color(FLAME, g[1]))
		draw_texture_rect_region(CANDLE, Rect2(at, Vector2(side, side)), Rect2(frame * 64, 0, 64, 64))


## Runes engraved line by line, the newest glowing as if still hot.
func _draw_runes() -> void:
	if _fade <= 0:
		return
	var cols := maxi(1, int(_runes.size.x / CELL))
	var rows := maxi(1, int(_runes.size.y / CELL))
	var origin := (_runes.size - Vector2(cols, rows) * CELL) / 2
	var total := cols * rows
	var shown := _progress * total
	for i in mini(ceili(shown), total):
		var cell := origin + Vector2(i % cols, i / cols) * CELL
		var fresh := clampf(shown - i, 0.0, 1.0)  # the rune being engraved fades in
		var hot := clampf(1.0 - (shown - i) / 6.0, 0.0, 1.0)  # the last ones are still hot
		var tint := RUNE_INK.lerp(Color.WHITE, maxf(hot, _glow))
		tint.a = fresh * _fade
		_runes.draw_texture_rect_region(RUNES, Rect2(cell, Vector2(CELL, CELL)), Rect2(_order[i % _order.size()] * 32, 0, 32, 32), tint)
	if _busy and shown < total:  # the quill writing the next rune, its nib bottom left
		var at := origin + Vector2(int(shown) % cols + 0.5, int(shown) / cols + 0.5) * CELL
		at += Vector2(4 * sin(_time * 14.0), 3 * cos(_time * 9.0))
		_runes.draw_texture_rect(QUILL, Rect2(at - Vector2(8, 88), Vector2(96, 96)), false, Color(1, 1, 1, _fade))
