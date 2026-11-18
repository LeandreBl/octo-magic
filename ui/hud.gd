extends Control
## In-run HUD: level, HP, mana, XP (top left), wave and the boss countdown
## (top center), gold, score and a pause button for touch (top right), spell
## slots with key, mana cost and cooldown (bottom center: touch a slot to cast
## it; key or gamepad button below), the passive (shield left, time until
## it is back), and the bosses' health under the wave (theirs only: the other
## enemies show none).

signal paused

const UITheme := preload("res://ui/theme.gd")

var main: Node
var _hp: ProgressBar
var _mana: ProgressBar
var _xp: ProgressBar
var _level: Label
var _wave: Label
var _pips: Array[ColorRect] = []  # waves left before the boss
var _boss: VBoxContainer  # the bosses' names and health bar, hidden without one
var _gold: Label
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

	# Top left: level badge and bars.
	var vitals := _plate(margin, Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	var row := _box(HBoxContainer.new(), 10)
	vitals.add_child(row)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.flat(UITheme.INK, UITheme.GOLD, 3, 0, 0))
	badge.custom_minimum_size = Vector2(64, 64)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b_col := _box(VBoxContainer.new(), -4)
	b_col.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(b_col)
	var lv := UITheme.label("LV.", "", 12, UITheme.TEXT_DIM)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_col.add_child(lv)
	_level = UITheme.label("", "", 28, UITheme.GOLD)
	_level.add_theme_font_override("font", UITheme.BODY_BOLD)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_col.add_child(_level)
	row.add_child(badge)
	var bars := _box(VBoxContainer.new(), 6)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bars)
	_hp = _bar(bars, UITheme.HP, 24)
	_mana = _bar(bars, UITheme.MANA, 24)
	_xp = _bar(bars, UITheme.XP, 10)

	# Top center: the wave, and pips counting down to the next boss; under
	# it, the bosses' health while one is up.
	var top := _box(VBoxContainer.new(), 8)
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top)
	var wave := _plate(top, Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN)
	var w_col := _box(VBoxContainer.new(), 4)
	wave.add_child(w_col)
	_wave = UITheme.label("", "", 32, UITheme.GOLD)
	_wave.add_theme_font_override("font", UITheme.BODY_BOLD)
	_wave.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	_wave.add_theme_constant_override("shadow_offset_x", 3)
	_wave.add_theme_constant_override("shadow_offset_y", 3)
	_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w_col.add_child(_wave)
	var pips := _box(HBoxContainer.new(), 6)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	w_col.add_child(pips)
	for i in Run.BOSS_EVERY:
		var boss := i == Run.BOSS_EVERY - 1
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.OUTLINE, UITheme.OUTLINE, 2, 2, 0))
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14) if boss else Vector2(10, 10)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(pip)
		pips.add_child(frame)
		_pips.append(pip)
	pips.add_child(UITheme.label("boss", "", 13, UITheme.TEXT_DIM))
	_boss = _box(VBoxContainer.new(), 2)
	top.add_child(_boss)
	var b_name := UITheme.label("", "", 20, UITheme.TEXT)
	b_name.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	b_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.add_child(b_name)
	_bar(_boss, UITheme.HP, 16).custom_minimum_size.x = 640

	# Top right: purse, score, pause.
	var right := _box(HBoxContainer.new(), 12)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(right)
	var purse := _plate(right, Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	var p_col := _box(VBoxContainer.new(), 0)
	purse.add_child(p_col)
	var g_row := _box(HBoxContainer.new(), 6)
	g_row.alignment = BoxContainer.ALIGNMENT_END
	p_col.add_child(g_row)
	g_row.add_child(UITheme.icon_rect(UITheme.icon("gold"), 28))
	_gold = UITheme.label("", "", 24, UITheme.GOLD)
	g_row.add_child(_gold)
	_score = UITheme.label("", "", 15, UITheme.TEXT_DIM)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p_col.add_child(_score)
	var pause := Button.new()
	pause.icon = UITheme.glyph("pause", UITheme.TEXT)
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.tooltip_text = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(56, 56)
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause.pressed.connect(paused.emit)
	right.add_child(pause)

	# Bottom center: spell slots, then the passive.
	var bottom := _box(HBoxContainer.new(), 14)
	bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	margin.add_child(bottom)
	for slot in Upgrades.RUN_SLOTS:
		bottom.add_child(_slot(slot))
	_passive = _box(VBoxContainer.new(), 6)
	_passive.size_flags_vertical = Control.SIZE_SHRINK_END
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
	bottom.add_child(_passive)


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


func _bar(parent: Control, color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UITheme.fill(color) if height > 12 else UITheme.flat(color, color, 0, 0, 0))
	var text := Label.new()
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	bar.add_child(text)
	var regen := Label.new()  # child 1: the bar's regen per second, right-aligned
	regen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	regen.offset_right = -8
	regen.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	regen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	regen.add_theme_font_size_override("font_size", 13)
	regen.add_theme_color_override("font_shadow_color", UITheme.OUTLINE)
	bar.add_child(regen)
	parent.add_child(bar)
	return bar


func _set_bar(bar: ProgressBar, value: float, max_value: float, text: String, regen := "") -> void:
	bar.max_value = max_value
	bar.value = value
	bar.get_child(0).text = text
	bar.get_child(1).text = regen


func _slot(slot: String) -> Control:
	var box := _box(VBoxContainer.new(), 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _busy_box)
	panel.custom_minimum_size = Vector2(84, 84)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.clip_contents = true
	# ponytail: the touch also reaches player.gd's aim stick (right half); fine
	# while every slot sits at the bottom center.
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
	var key := UITheme.tag("")
	under.add_child(key)
	var label := UITheme.label("", "", 14)
	under.add_child(label)
	box.add_child(under)
	_slots[slot] = [icon, cd, null, cost, label, panel, secs, key.get_child(0)]
	return box


func _process(_delta: float) -> void:
	var p: Node2D = main.local_player()
	if not visible or not Run.active or not p:
		return
	_set_bar(_hp, p.hp, p.stats.hp, tr("HP %d / %d") % [maxf(p.hp, 0.0), p.stats.hp] + ("  · " + tr("Potions %d") % p.potions if p.potions > 0 else ""),
			"+%.1f/s" % p.stats.hp_regen if p.stats.hp_regen > 0.0 else "")
	_set_bar(_mana, p.mana, p.stats.mana, "Mana %d / %d" % [p.mana, p.stats.mana],
			"+%d/s" % p.stats.mana_regen if p.stats.mana_regen > 0.0 else "")
	_set_bar(_xp, Run.xp, Run.xp_to_next(Run.level), "")
	_level.text = str(Run.level)
	_wave.text = tr("Wave %d") % Run.wave
	var done := Run.BOSS_EVERY if Run.wave > 0 and Run.wave % Run.BOSS_EVERY == 0 else Run.wave % Run.BOSS_EVERY
	for i in _pips.size():
		var boss := i == _pips.size() - 1
		_pips[i].color = (UITheme.HP if boss else UITheme.GOLD) if i < done or boss else UITheme.RIM
	var bosses := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.data.get("boss", false) and e.hp > 0.0)
	_boss.visible = not bosses.is_empty()
	if _boss.visible:  # several at once: one bar for all of them
		_boss.get_child(0).text = " · ".join(bosses.map(func(e): return tr(e.data.name)))
		_set_bar(_boss.get_child(1), bosses.reduce(func(a, e): return a + e.hp, 0.0), bosses.reduce(func(a, e): return a + e.max_hp, 0.0), "")
	_gold.text = str(Run.gold)
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
		ui[7].text = _binding(slot)
		var left: float = p.cooldowns.get(slot, 0.0)
		ui[1].offset_top = -ui[5].size.y * clampf(left / sp.cooldown, 0.0, 1.0)
		ui[6].text = ("%.1f" % left) if left > 0.05 and sp.cooldown >= 1.0 else ""
		var can: bool = p.mana >= mini(cost, floori(p.stats.mana))  # over the max mana: the failsafe (Player.cast)
		ui[0].modulate = Color.WHITE if can else Color(0.45, 0.45, 0.6)
		ui[5].add_theme_stylebox_override("panel", _ready_box if can and left <= 0.05 else _busy_box)


## The button of a spell slot, for the device in use.
func _binding(slot: String) -> String:
	if Settings.pad:
		return Settings.pad_button("RT", "R2") if slot == "primary" else Settings.pad_button("RB", "R1")
	return tr("Left click" if slot == "primary" else "Right click")


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
