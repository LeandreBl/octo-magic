extends Control
## In-run HUD: HP, mana, XP/level, wave, gold, score, spell slots with
## cooldown (touch a slot to cast it), the passive (shield left, time
## until it is back), scroll status, a pause button for touch.

signal paused

const UITheme := preload("res://ui/theme.gd")

var main: Node
var _hp: ProgressBar
var _mana: ProgressBar
var _xp: ProgressBar
var _wave: Label
var _gold: Label
var _spell: Label
var _scrolls: Label
var _slots := {}  # slot -> [icon TextureRect, cooldown ColorRect, spell shown, cost Label]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var plate := _plate(margin, Control.SIZE_SHRINK_BEGIN)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	plate.add_child(left)
	_hp = _bar(left, UITheme.HP)
	_mana = _bar(left, UITheme.MANA)
	_xp = _bar(left, UITheme.XP)
	_spell = Label.new()
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spell.custom_minimum_size.x = 280
	_spell.add_theme_font_size_override("font_size", 18)
	left.add_child(_spell)
	_scrolls = Label.new()
	_scrolls.autowrap_mode = TextServer.AUTOWRAP_WORD
	_scrolls.custom_minimum_size.x = 280
	_scrolls.add_theme_font_size_override("font_size", 16)
	_scrolls.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	left.add_child(_scrolls)

	_wave = Label.new()
	_wave.theme_type_variation = "Header"
	_plate(margin, Control.SIZE_SHRINK_CENTER).add_child(_wave)

	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 16)
	margin.add_child(right)
	var purse := HBoxContainer.new()
	_plate(right, Control.SIZE_SHRINK_BEGIN).add_child(purse)
	purse.add_child(UITheme.icon_rect(UITheme.icon("gold"), 40))
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", UITheme.GOLD)
	purse.add_child(_gold)
	var pause := Button.new()
	pause.text = "II"
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(56, 56)
	pause.pressed.connect(paused.emit)
	right.add_child(pause)

	var bottom := HBoxContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(bottom)
	for slot in Upgrades.RUN_SLOTS + ["passive"]:
		bottom.add_child(_slot(slot))
	_slots.passive[0].texture = UITheme.icon("ring_sapphire")


## A "Plate" panel in `parent`, at the top, aligned by `h_flags`.
func _plate(parent: Control, h_flags: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Plate"
	p.size_flags_horizontal = h_flags
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 26)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UITheme.fill(color))
	var text := Label.new()
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 16)
	bar.add_child(text)
	parent.add_child(bar)
	return bar


func _set_bar(bar: ProgressBar, value: float, max_value: float, text: String) -> void:
	bar.max_value = max_value
	bar.value = value
	bar.get_child(0).text = text


func _slot(slot: String) -> Control:
	var box := VBoxContainer.new()
	var panel := Panel.new()
	panel.theme_type_variation = "Slot"
	panel.custom_minimum_size = Vector2(72, 72)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# ponytail: the touch also reaches player.gd's aim stick (right half); fine
	# while every slot sits at the bottom center.
	panel.gui_input.connect(func(e):
		if e is InputEventScreenTouch:
			var me: Node2D = main.local_player()
			if me:
				me.held[slot] = e.pressed)
	box.add_child(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(icon)
	var cd := ColorRect.new()
	cd.color = Color(0, 0, 0, 0.6)
	cd.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.add_child(cd)
	var cost := Label.new()
	cost.add_theme_font_size_override("font_size", 14)
	cost.add_theme_color_override("font_color", UITheme.MANA.lightened(0.4))
	cost.position = Vector2(4, 50)
	panel.add_child(cost)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)
	_slots[slot] = [icon, cd, null, cost, label]
	return box


func _process(_delta: float) -> void:
	var p: Node2D = main.local_player()
	if not visible or not Run.active or not p:
		return
	_set_bar(_hp, p.hp, p.max_hp, tr("HP %d / %d  ·  shield %d") % [maxf(p.hp, 0.0), p.max_hp, p.shield]
		if p.passive else tr("HP %d / %d") % [maxf(p.hp, 0.0), p.max_hp])
	_set_bar(_mana, p.mana, p.max_mana, "Mana %d / %d" % [p.mana, p.max_mana])
	var need := Run.xp_to_next(Run.level)
	_set_bar(_xp, Run.xp, need, tr("Level %d  ·  XP %d / %d") % [Run.level, Run.xp, need])
	_wave.text = tr("Wave %d") % Run.wave
	_gold.text = tr("%d gold  ·  score %d") % [Run.gold, Run.score()]
	var s: Dictionary = Run.spells.primary
	_spell.text = Spell.label(s) + ("  [" + " + ".join(s.words) + "]" if not s.words.is_empty() else "")
	_scrolls.text = tr("Scrolls found: %d%s") % [Run.scrolls, "\n" + main.forge_note if main.forge_note else ""]
	var pas: Array = _slots.passive
	pas[0].get_parent().get_parent().visible = p.passive != ""  # no key: it applies itself
	if p.passive:
		pas[3].text = str(int(p.shield))
		pas[4].text = "%s\n%s" % [tr(Run.SHOP[p.passive].name), tr("Passive")]
		pas[1].offset_top = -pas[1].get_parent().size.y * clampf(p.shield_wait / p.SHIELD_WAIT, 0.0, 1.0)
	for slot in Upgrades.RUN_SLOTS:
		var ui: Array = _slots[slot]
		ui[0].get_parent().get_parent().visible = Run.spells.has(slot)  # secondary: once bought
		if not Run.spells.has(slot):
			continue
		var sp: Dictionary = Run.spells[slot]
		var cost := Run.mana_cost(slot)
		if not is_same(sp, ui[2]):
			ui[2] = sp
			ui[0].texture = _icon(sp)
		ui[3].text = str(cost)
		ui[4].text = "%s\n%s" % [Spell.label(sp), tr("Left click" if slot == "primary" else "Right click")]  # follows a language change
		ui[1].offset_top = -ui[1].get_parent().size.y * clampf(p.cooldowns.get(slot, 0.0) / sp.cooldown, 0.0, 1.0)
		ui[0].modulate = Color.WHITE if p.mana >= cost else Color(0.45, 0.45, 0.6)


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
