extends CenterContainer
## Shop, between runs: items, permanent bonuses, equipped spells, the mage's
## look and the scroll panel. Reads and edits the Profile autoload.

signal closed

const UITheme := preload("res://ui/theme.gd")

var main: Node
var _gold: Label
var _content: VBoxContainer


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1060, 620)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.theme_type_variation = "Header"
	title.text = "Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var coin := TextureRect.new()
	coin.texture = UITheme.icon("gold")
	head.add_child(coin)
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", UITheme.GOLD)
	head.add_child(_gold)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	inner.add_child(_content)
	var scroll_panel := preload("res://ui/scroll_panel.gd").new()
	scroll_panel.main = main
	inner.add_child(scroll_panel)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(closed.emit)
	box.add_child(back)
	Profile.changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)
	_rebuild()


## Rebuilt on every Profile change; keyboard/gamepad focus stays on the same button.
func _rebuild() -> void:
	if not is_visible_in_tree():
		return
	var buttons := _buttons()
	var focused := buttons.find(get_viewport().gui_get_focus_owner())
	for c in _content.get_children():  # not free(): a pressed button is mid-signal
		_content.remove_child(c)
		c.queue_free()
	_gold.text = tr("%d gold  ·  %d blank scroll(s)") % [Profile.gold, Profile.blank_scrolls]

	var row := _section("Equipment")
	for id in Profile.ITEMS:
		var it: Dictionary = Profile.ITEMS[id]
		var on: bool = Profile.equipped[it.kind] == id
		var b := _button(row, tr(it.name) + (" ✔" if on else "" if Profile.owned.has(id) else " (%s)" % tr("%d gold") % it.price),
			func(): if not Profile.equip_item(id): Profile.buy_item(id))
		b.disabled = on or (not Profile.owned.has(id) and Profile.gold < it.price)
		b.tooltip_text = _bonus_text(it.bonus)
		b.icon = UITheme.icon(id)

	row = _section("Permanent bonuses")
	for id in Profile.BONUSES:
		var bo: Dictionary = Profile.BONUSES[id]
		var price := Profile.bonus_price(id)
		var b := _button(row, "%s %d/%d · %s (%s)" % [tr(bo.name), Profile.bonuses.get(id, 0), bo.max, tr(bo.desc),
			"max" if price < 0 else tr("%d gold") % price], func(): Profile.buy_bonus(id))
		b.disabled = price < 0 or Profile.gold < price

	for slot in Upgrades.SLOTS:
		row = _section(tr(Upgrades.SLOT_NAMES[slot]))
		for e in Profile.available_spells(slot):
			var b := _button(row, Spell.label(e.spell), func(): Profile.equip_spell(slot, e.id))
			b.disabled = Profile.spells[slot] == e.id
			b.tooltip_text = "%s (%d mana)" % [Spell.describe(e.spell), Spell.mana_cost(e.spell)]
			b.icon = UITheme.spell_icon(e.spell)

	row = _section("Hat")
	for c in Profile.COLORS:
		var b := _button(row, "", func(): Profile.set_look("hat", c))
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_stylebox_override("normal", _swatch(c, UITheme.OUTLINE))
		b.add_theme_stylebox_override("hover", _swatch(c, UITheme.GOLD))
		b.add_theme_stylebox_override("disabled", _swatch(c, UITheme.TEXT))
		b.disabled = Profile.look.hat == c

	buttons = _buttons()
	if focused >= 0 and not buttons.is_empty():
		buttons[mini(focused, buttons.size() - 1)].grab_focus()


func _buttons() -> Array:
	return _content.find_children("*", "Button", true, false)


func _section(title: String) -> HFlowContainer:
	var l := Label.new()
	l.text = title
	l.theme_type_variation = "Header"
	l.add_theme_font_size_override("font_size", 24)
	_content.add_child(l)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_content.add_child(row)
	return row


func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


static func _bonus_text(bonus: Dictionary) -> String:
	var names := {"hp": "HP", "mana": "mana", "regen": "mana/s", "speed": "speed",
		"damage": "damage", "gold": "gold", "xp": "XP"}
	var parts := []
	for k in bonus:
		var v: float = bonus[k]
		parts.append(("+%d %%" % roundi(v * 100) if k in ["speed", "damage", "gold", "xp"] else "+%d" % v) + " " + TranslationServer.translate(names.get(k, k)))
	return ", ".join(parts)


static func _swatch(color: String, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color)
	s.border_color = border
	s.set_border_width_all(4)
	s.shadow_color = UITheme.SHADOW
	s.shadow_size = 1
	s.shadow_offset = Vector2(4, 4)
	return s
