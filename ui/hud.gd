extends Control
## In-run HUD: pause and score (top left; the wave and gold are in the
## pause menu); one gauge (no text) of HP, XP and mana, each as wide as its
## max and hollow when empty, with the bosses' health under it, in gothic iron
## frames with Diablo-like liquids (top center: the
## other enemies show none); the spell slots, primary then secondary, with
## cooldown (top right: touch a slot to cast it), then the
## passive (shield, time until it is back).

signal paused

const UITheme := preload("res://ui/theme.gd")
const LIQUID: Shader = preload("res://ui/liquid.gdshader")
# The gauges' frame (generated, hollow, 9-sliced) and the divider between
# the bars in one frame (its ruby, cut from the frame's end cap).
const FRAME: Texture2D = preload("res://assets/ui/gauge_frame.png")
const DIVIDER: Texture2D = preload("res://assets/ui/gauge_divider.png")
const CAP := 36  # the frame's end caps: the slot starts there
const RIM := 6  # the frame's rails, above and below the slot
const SLOT := 18  # the slot's height: the bars'
# Diablo's liquids: blood red, deep blue; the XP gold.
const HP_COLOR := Color("#b3141b")
const MANA_COLOR := Color("#2346c8")
const XP_COLOR := Color("#d9a520")
const SHARE := 1.0 / 3.0  # of the screen width the gauges take at base max HP and mana
const MAX_SHARE := 0.45  # their cap, however high the max HP and mana go
const MILESTONE := 5  # every this many waves, a message fades in and out

var main: Node
var _hp: ProgressBar
var _mana: ProgressBar
var _xp: ProgressBar
var _boss: VBoxContainer  # the bosses' names and health bar, hidden without one
var _boss_bar: ProgressBar
var _score: Label
var _passive: Control
var _shield: Label
var _shield_wait: ColorRect  # covers the passive while a broken shield comes back
var _slots := {}  # slot -> [icon, cooldown ColorRect, spell shown, unused, name Label, panel, seconds Label]
var _ready_box: StyleBox
var _busy_box: StyleBox
var _milestone: Label  # "Wave 10!", faded in and out every MILESTONE waves
var _wave_seen := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_box = UITheme.frame({"rings": [[UITheme.GOLD, 4]], "bg": UITheme.PANEL, "drop": 4}, 0)
	_busy_box = UITheme.frame({"rings": [[UITheme.OUTLINE, 4]], "bg": UITheme.PANEL, "drop": 4}, 0)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	# Top left: pause, the score.
	var left := _box(HBoxContainer.new(), 12)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(left)
	var pause := Button.new()
	pause.icon = UITheme.glyph("pause", UITheme.TEXT)
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.tooltip_text = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(56, 56)
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause.pressed.connect(paused.emit)
	left.add_child(pause)
	var score := _plate(left, Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	_score = UITheme.label("", "", 15, UITheme.TEXT_DIM)
	score.add_child(_score)

	# Top center: HP, XP and mana in one frame, sized by their max; under
	# them the bosses' health while one is up.
	var top := _box(VBoxContainer.new(), 8)
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top)
	_hp = _bar(HP_COLOR)
	_hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN  # empties from the left
	_xp = _bar(XP_COLOR)
	_mana = _bar(MANA_COLOR)
	_gauge(top, [_hp, _xp, _mana])
	_boss = _box(VBoxContainer.new(), 2)
	top.add_child(_boss)
	var b_name := UITheme.label("", "", 20, UITheme.TEXT)
	b_name.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	b_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.add_child(b_name)
	_boss_bar = _bar(HP_COLOR)
	_boss_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_gauge(_boss, [_boss_bar])

	# Top right: the primary spell, the secondary under it, then the passive.
	var right := _box(VBoxContainer.new(), 10)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(right)
	for slot in Spell.RUN_SLOTS:
		right.add_child(_slot(slot))
	_passive = _box(VBoxContainer.new(), 6)
	_passive.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var p_panel := Panel.new()
	p_panel.theme_type_variation = "Slot"
	p_panel.custom_minimum_size = Vector2(60, 60)
	p_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_panel.clip_contents = true
	var shield := UITheme.icon_rect(UITheme.glyph("shield", UITheme.MANA), 36)
	shield.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p_panel.add_child(shield)
	_shield_wait = ColorRect.new()
	_shield_wait.color = Color(UITheme.OUTLINE, 0.65)
	_shield_wait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_shield_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_panel.add_child(_shield_wait)
	_passive.add_child(p_panel)
	_shield = UITheme.label("", "", 14, UITheme.TEXT_DIM)
	_shield.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_passive.add_child(_shield)
	right.add_child(_passive)

	# Upper third: every MILESTONE waves, a message fades in and out (clicks go through).
	_milestone = UITheme.label("", "Header", 56, UITheme.GOLD)
	_milestone.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	_milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_milestone.anchor_top = 0.28
	_milestone.anchor_bottom = 0.28
	_milestone.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_milestone.modulate.a = 0.0
	add_child(_milestone)
	Run.changed.connect(_on_run_changed)


## Wave MILESTONE, 2 x MILESTONE... and the special waves (Run.wave_type): the message fades in, stays, fades out.
func _on_run_changed() -> void:
	if Run.wave == _wave_seen:
		return
	_wave_seen = Run.wave
	var special: String = {"elite": tr("Elite wave!"), "zombies": tr("Zombie wave!"),
		"horde": tr("Skeleton horde!"), "swarm": tr("Swarm!")}.get(Run.wave_type(Run.wave), "")
	if Run.wave <= 0 or Run.wave % MILESTONE and not special:
		return
	_milestone.text = special if special else tr("Wave %d!") % Run.wave
	var t := _milestone.create_tween()
	_milestone.modulate.a = 0.0
	t.tween_property(_milestone, "modulate:a", 1.0, 0.6)
	t.tween_interval(1.8)
	t.tween_property(_milestone, "modulate:a", 0.0, 0.8)



func _box(c: BoxContainer, gap: int) -> BoxContainer:
	c.add_theme_constant_override("separation", gap)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A "Plate" panel in `parent`, aligned by `h_flags` and `v_flags`.
func _plate(parent: Control, h_flags: int, v_flags: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Plate"
	p.size_flags_horizontal = h_flags
	p.size_flags_vertical = v_flags
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## `bars` side by side in one frame, a divider between two, centered in `parent`.
func _gauge(parent: Control, bars: Array) -> void:
	var frame := PanelContainer.new()
	var box := StyleBoxTexture.new()  # its content margins: the texture's, so the bars fill the slot
	box.texture = FRAME
	box.set_texture_margin(SIDE_LEFT, CAP)  # the end caps keep their shape
	box.set_texture_margin(SIDE_RIGHT, CAP)
	box.set_texture_margin(SIDE_TOP, RIM)
	box.set_texture_margin(SIDE_BOTTOM, RIM)
	frame.add_theme_stylebox_override("panel", box)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _box(HBoxContainer.new(), 0)
	frame.add_child(row)
	for i in bars.size():
		if i:
			var gap := Control.new()  # the divider's width in the slot, it covers the rails
			gap.custom_minimum_size.x = DIVIDER.get_width()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ruby := TextureRect.new()
			ruby.texture = DIVIDER
			ruby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ruby.offset_top = -RIM
			ruby.offset_bottom = RIM
			ruby.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.add_child(ruby)
			row.add_child(gap)
		row.add_child(bars[i])
	parent.add_child(frame)


## A bar of `color` the slot's height, its fill a liquid.
func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, SLOT)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := UITheme.fill(color)
	fill.border_color = color.lightened(0.25)  # a soft top highlight
	fill.border_width_top = 2
	fill.set_corner_radius_all(SLOT / 2)  # the slot's round ends
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())  # see-through when empty
	var liquid := ShaderMaterial.new()  # the fill as a liquid: translucent, rippling
	liquid.shader = LIQUID
	liquid.set_shader_parameter("top", 0.0)
	liquid.set_shader_parameter("height", SLOT)
	bar.material = liquid
	return bar


func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = value


func _slot(slot: String) -> Control:
	var box := _box(VBoxContainer.new(), 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _busy_box)
	panel.custom_minimum_size = Vector2(84, 84)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.clip_contents = true
	# ponytail: the touch also starts player.gd's aim stick (right half, where
	# the slots sit); fine while a tap barely drags it.
	panel.gui_input.connect(func(e):
		if e is InputEventScreenTouch:
			var me: Node2D = main.local_player()
			if me:
				me.held[slot] = e.pressed)
	box.add_child(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var cd := ColorRect.new()
	cd.color = Color(UITheme.OUTLINE, 0.65)
	cd.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cd)
	var secs := UITheme.label("", "", 22)
	secs.add_theme_font_override("font", UITheme.BODY_BOLD)
	secs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	secs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	secs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(secs)
	var under := _box(HBoxContainer.new(), 6)
	under.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := UITheme.label("", "", 14)
	under.add_child(label)
	box.add_child(under)
	_slots[slot] = [icon, cd, null, null, label, panel, secs]
	return box


func _process(_delta: float) -> void:
	var p: Node2D = main.local_player()
	if not visible or not Run.active or not p:
		return
	_set_bar(_hp, p.hp, p.stats.hp)
	_set_bar(_mana, p.mana, p.stats.mana)
	_set_bar(_xp, Run.xp, Run.xp_to_next(Run.level))
	_size_gauges(p.stats.hp, p.stats.mana)
	var bosses := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.data.get("boss", false) and e.hp > 0.0)
	_boss.visible = not bosses.is_empty()
	if _boss.visible:  # several at once: one bar for all of them
		_boss.get_child(0).text = " · ".join(bosses.map(func(e): return tr(e.data.name)))
		_set_bar(_boss_bar, bosses.reduce(func(a, e): return a + e.hp, 0.0), bosses.reduce(func(a, e): return a + e.max_hp, 0.0))
	_score.text = "Score %d" % Run.score()
	_passive.visible = "shield" in p.passives
	if _passive.visible:  # no key: it applies itself
		_shield.text = "%s %d" % [tr(Profile.AUGMENTS.shield.name), p.shield]
		_shield_wait.offset_top = -_shield_wait.get_parent().size.y * clampf(p.shield_wait / p.SHIELD_WAIT, 0.0, 1.0)
	for slot in _slots:
		var ui: Array = _slots[slot]
		ui[0].get_parent().get_parent().visible = Run.spells.has(slot)  # secondary: an active augment slotted
		if not Run.spells.has(slot):
			continue
		var sp: Dictionary = Run.spells[slot]
		var cost := Run.mana_cost(slot)
		if not is_same(sp, ui[2]):
			ui[2] = sp
			ui[0].texture = _icon(sp)
		ui[4].text = Spell.label(sp)  # follows a language change
		var left: float = p.cooldowns.get(slot, 0.0)
		ui[1].offset_top = -ui[5].size.y * clampf(left / sp.cooldown, 0.0, 1.0)
		ui[6].text = ("%.1f" % left) if left > 0.05 and sp.cooldown >= 1.0 else ""
		var can: bool = p.mana >= cost  # short of mana it still casts, weakened (Player.cast)
		ui[0].modulate = Color.WHITE if can else Color(0.45, 0.45, 0.6)
		ui[5].add_theme_stylebox_override("panel", _ready_box if can and left <= 0.05 else _busy_box)


## HP and mana as wide as their max (XP a quarter of HP): SHARE of the screen
## at the base max, up to MAX_SHARE; the boss bar as wide as the three.
func _size_gauges(hp_max: float, mana_max: float) -> void:
	var screen := get_viewport_rect().size.x
	var total := hp_max * 1.25 + mana_max
	var per := screen * SHARE / (Stats.BASE.hp * 1.25 + Stats.BASE.mana)
	per = minf(per, screen * MAX_SHARE / total)
	_hp.custom_minimum_size.x = roundf(hp_max * per)
	_xp.custom_minimum_size.x = roundf(hp_max * per / 4.0)
	_mana.custom_minimum_size.x = roundf(mana_max * per)
	_boss_bar.custom_minimum_size.x = roundf(total * per) + DIVIDER.get_width() * 2


## The spell's icon, else the first frame of its projectile, else a disc of its color.
static func _icon(s: Dictionary) -> Texture2D:
	if s.icon_file:
		return SpellArt.sheet(s, s.icon_file)
	if not s.icon.is_empty():
		return SpellArt.texture(s.icon, s.palette)
	if UITheme.spell_icon(s):
		return UITheme.spell_icon(s)
	var anim := SpellArt.animation(s, s.emit.body)
	if not anim.is_empty():
		var a := AtlasTexture.new()
		a.atlas = anim[0]
		a.region = Rect2(0, 0, anim[1].size, anim[1].size)
		return a
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			if Vector2(x - 5.5, y - 5.5).length() < 5.5:
				img.set_pixel(x, y, Color(s.color))
	return ImageTexture.create_from_image(img)
