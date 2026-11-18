extends Control
## In-run HUD: pause and score (top left; the wave and gold are in the
## pause menu); HP, XP and mana gauges (no text), each as wide as its max
## and hollow when empty, with the bosses' health under them (top center: the
## other enemies show none); the spell slots, primary then secondary, with
## mana cost and cooldown (top right: touch a slot to cast it), then the
## passive (shield, time until it is back).

signal paused

const UITheme := preload("res://ui/theme.gd")
const FRAME: Texture2D = preload("res://assets/ui/gauge_frame.png")  # hollow, 9-sliced
const RIM := 6  # its rim, top and bottom (7 at the end caps)
const GAP := 6  # between the gauges
const SHARE := 1.0 / 3.0  # of the screen width the gauges take at base max HP and mana
const MAX_SHARE := 0.45  # their cap, however high the max HP and mana go

var main: Node
var _hp: ProgressBar
var _mana: ProgressBar
var _xp: ProgressBar
var _boss: VBoxContainer  # the bosses' names and health bar, hidden without one
var _score: Label
var _passive: Control
var _shield: Label
var _shield_wait: ColorRect  # covers the passive while a broken shield comes back
var _slots := {}  # slot -> [icon, cooldown ColorRect, spell shown, cost Label, name Label, panel, seconds Label]
var _ready_box: StyleBox
var _busy_box: StyleBox


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

	# Top center: HP, XP (the level in it) and mana gauges, sized by their
	# max; under them, the bosses' health while one is up.
	var top := _box(VBoxContainer.new(), 8)
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top)
	var gauges := _box(HBoxContainer.new(), GAP)
	gauges.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(gauges)
	# HP and mana each in a side as wide as the wider of the two, so the XP
	# stays at the screen's center whatever their max.
	_hp = _bar(_side(gauges, BoxContainer.ALIGNMENT_END), UITheme.HP, 28)
	_hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN  # empties from the left
	_xp = _bar(gauges, UITheme.XP, 28)
	_xp.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_mana = _bar(_side(gauges, BoxContainer.ALIGNMENT_BEGIN), UITheme.MANA, 28)
	_mana.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_boss = _box(VBoxContainer.new(), 2)
	top.add_child(_boss)
	var b_name := UITheme.label("", "", 20, UITheme.TEXT)
	b_name.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	b_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.add_child(b_name)
	_bar(_boss, UITheme.HP, 20).fill_mode = ProgressBar.FILL_END_TO_BEGIN

	# Top right: the primary spell, the secondary under it, then the passive.
	var right := _box(VBoxContainer.new(), 10)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(right)
	for slot in Upgrades.RUN_SLOTS:
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


func _side(parent: Control, align: int) -> HBoxContainer:
	var side := _box(HBoxContainer.new(), 0)
	side.alignment = align
	parent.add_child(side)
	return side


func _bar(parent: Control, color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := UITheme.fill(color)
	fill.set_corner_radius_all((height - RIM * 2) / 2)
	fill.set_expand_margin_all(-RIM)  # inside the frame
	fill.expand_margin_left = -RIM - 1
	fill.expand_margin_right = -RIM - 1
	# Its minimum size: ProgressBar draws value * (size - min) + min, so a
	# low value never shrinks the inset rect below zero (drawn off the frame).
	fill.set_content_margin(SIDE_TOP, RIM)
	fill.set_content_margin(SIDE_BOTTOM, RIM)
	fill.set_content_margin(SIDE_LEFT, RIM + 1)
	fill.set_content_margin(SIDE_RIGHT, RIM + 1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())  # see-through when empty
	var frame := Panel.new()  # the frame, hollow
	var box := StyleBoxTexture.new()
	box.texture = FRAME
	box.set_texture_margin(SIDE_LEFT, 12)  # the end caps keep their shape
	box.set_texture_margin(SIDE_RIGHT, 12)
	box.set_texture_margin(SIDE_TOP, 8)
	box.set_texture_margin(SIDE_BOTTOM, 8)
	frame.add_theme_stylebox_override("panel", box)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(frame)
	parent.add_child(bar)
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
	var cost := UITheme.label("", "", 14, UITheme.MANA.lightened(0.5))
	cost.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	cost.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	cost.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cost.offset_right = -6
	cost.offset_bottom = -2
	panel.add_child(cost)
	var under := _box(HBoxContainer.new(), 6)
	under.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := UITheme.label("", "", 14)
	under.add_child(label)
	box.add_child(under)
	_slots[slot] = [icon, cd, null, cost, label, panel, secs]
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
		_set_bar(_boss.get_child(1), bosses.reduce(func(a, e): return a + e.hp, 0.0), bosses.reduce(func(a, e): return a + e.max_hp, 0.0))
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
		ui[3].text = Spell.cost_text(sp, cost)
		ui[4].text = Spell.label(sp)  # follows a language change
		var left: float = p.cooldowns.get(slot, 0.0)
		ui[1].offset_top = -ui[5].size.y * clampf(left / sp.cooldown, 0.0, 1.0)
		ui[6].text = ("%.1f" % left) if left > 0.05 and sp.cooldown >= 1.0 else ""
		var can: bool = p.mana >= cost  # short of mana it still casts, weakened (Player.cast)
		ui[0].modulate = Color.WHITE if can else Color(0.45, 0.45, 0.6)
		ui[5].add_theme_stylebox_override("panel", _ready_box if can and left <= 0.05 else _busy_box)


## HP and mana as wide as their max (XP a quarter of HP): SHARE of the screen
## at the base max, up to MAX_SHARE; XP centered, the boss bar as wide as the three.
func _size_gauges(hp_max: float, mana_max: float) -> void:
	var screen := get_viewport_rect().size.x
	var total := hp_max * 1.25 + mana_max
	var per := screen * SHARE / (Stats.BASE.hp * 1.25 + Stats.BASE.mana)
	per = minf(per, screen * MAX_SHARE / total)
	_hp.custom_minimum_size.x = roundf(hp_max * per)
	_xp.custom_minimum_size.x = roundf(hp_max * per / 4.0)
	_mana.custom_minimum_size.x = roundf(mana_max * per)
	var side := maxf(_hp.custom_minimum_size.x, _mana.custom_minimum_size.x)
	_hp.get_parent().custom_minimum_size.x = side
	_mana.get_parent().custom_minimum_size.x = side
	_boss.get_child(1).custom_minimum_size.x = roundf(total * per) + GAP * 2


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
