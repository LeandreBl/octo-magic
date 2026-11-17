extends Control
## Shop, between runs, in tabs: equipment, permanent bonuses, equipped spells,
## the mage's look and the scroll panel; the mage and its total stats on the
## right. Reads and edits the Profile autoload.

signal closed

const UITheme := preload("res://ui/theme.gd")
const TABS := ["Equipment", "Bonuses", "Spells", "Look", "Scrolls"]

var main: Node
var _gold: Label
var _blank: Label
var _tab := "Equipment"
var _scroll: ScrollContainer
var _content: Container
var _scroll_panel: Control
var _worn: HBoxContainer
var _stats: VBoxContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [["left", 32], ["right", 32], ["top", 28], ["bottom", 28]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	add_child(m)
	var box := _vbox(20)
	m.add_child(box)

	var head := _hbox(16)
	box.add_child(head)
	var back := Button.new()
	back.icon = UITheme.glyph("back", UITheme.TEXT)
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.custom_minimum_size = Vector2(56, 56)
	back.tooltip_text = "Back"
	back.pressed.connect(closed.emit)
	head.add_child(back)
	var title := UITheme.label("Shop", "Header")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_gold = _counter(head, "gold", UITheme.GOLD)
	_blank = _counter(head, "scroll", UITheme.TEXT)

	var body := _hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var tabs := _vbox(12)
	tabs.custom_minimum_size.x = 200
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = t
		b.theme_type_variation = "SideTab"
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = t == _tab
		b.pressed.connect(func():
			_tab = t
			_rebuild())
		tabs.add_child(b)
		if t == _tab:
			set_meta("focus", b)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	var inner := _vbox(16)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(inner)
	_content = _vbox(16)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_content)
	_scroll_panel = preload("res://ui/scroll_panel.gd").new()
	_scroll_panel.main = main
	inner.add_child(_scroll_panel)

	var mage := PanelContainer.new()
	mage.custom_minimum_size.x = 280
	mage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mage.add_theme_stylebox_override("panel", UITheme.frame({"rings": [[UITheme.OUTLINE, 4], [UITheme.RIM, 2]],
		"bg": UITheme.PANEL, "rivets": UITheme.GOLD, "drop": 6}, 16))
	body.add_child(mage)
	var col := _vbox(10)
	mage.add_child(col)
	col.add_child(UITheme.label("Your mage", "Caption"))
	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", UITheme.flat(UITheme.INK, UITheme.OUTLINE, 3, 0, 0))
	stage.custom_minimum_size = Vector2(0, 196)
	var o := UITheme.octo(192)
	o.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage.add_child(o)
	col.add_child(stage)
	_worn = _hbox(8)
	_worn.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_worn)
	_stats = _vbox(6)
	col.add_child(_stats)

	Profile.changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)
	_rebuild()


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


func _counter(parent: Control, icon: String, color: Color) -> Label:
	var p := PanelContainer.new()
	p.theme_type_variation = "Plate"
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := _hbox(8)
	p.add_child(row)
	row.add_child(UITheme.icon_rect(UITheme.icon(icon), 32))
	var l := UITheme.label("", "", 24, color)
	row.add_child(l)
	parent.add_child(p)
	return l


## Rebuilt on every Profile change; keyboard/gamepad focus stays on the same button.
func _rebuild() -> void:
	if not is_visible_in_tree():
		return
	var buttons := _buttons()
	var focused := buttons.find(get_viewport().gui_get_focus_owner())
	for c in _content.get_children():  # not free(): a pressed button is mid-signal
		_content.remove_child(c)
		c.queue_free()
	_gold.text = str(Profile.gold)
	_blank.text = str(Profile.blank_scrolls)
	_scroll_panel.visible = _tab == "Scrolls"
	match _tab:
		"Equipment":
			var grid := _grid()
			for id in Profile.ITEMS:
				_item_card(grid, id)
		"Bonuses":
			var grid := _grid()
			for id in Profile.BONUSES:
				_bonus_card(grid, id)
		"Spells":
			for slot in Upgrades.SLOTS:
				_content.add_child(UITheme.label(tr(Upgrades.SLOT_NAMES[slot]), "Subheader"))
				var grid := _grid()
				for e in Profile.available_spells(slot):
					_spell_card(grid, slot, e)
		"Look":
			_content.add_child(UITheme.label("Hat", "Subheader"))
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 12)
			row.add_theme_constant_override("v_separation", 12)
			_content.add_child(row)
			for c in Profile.COLORS:
				var b := Button.new()
				b.custom_minimum_size = Vector2(56, 56)
				b.add_theme_stylebox_override("normal", UITheme.flat(Color(c), UITheme.OUTLINE, 4, 0, 4))
				b.add_theme_stylebox_override("hover", UITheme.flat(Color(c), UITheme.GOLD, 4, 0, 4))
				b.add_theme_stylebox_override("pressed", UITheme.flat(Color(c), UITheme.GOLD, 4, 0, 0))
				b.add_theme_stylebox_override("disabled", UITheme.flat(Color(c), UITheme.TEXT, 4, 0, 4))
				b.disabled = Profile.look.hat == c
				b.pressed.connect(func(): Profile.set_look("hat", c))
				row.add_child(b)
	_refresh_mage()

	buttons = _buttons()
	if focused >= 0 and not buttons.is_empty():
		buttons[mini(focused, buttons.size() - 1)].grab_focus()


func _buttons() -> Array:
	return _content.find_children("*", "Button", true, false)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 18)
	_content.add_child(g)
	return g


## A shop card: icon (and a tag), name, details, then a price/state line.
func _card(parent: Control, tex: Texture2D, name: String, details: String, on: bool, fn: Callable) -> Array:
	var b := Button.new()
	b.theme_type_variation = "Card"
	b.custom_minimum_size = Vector2(220, 176)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.pressed.connect(fn)
	if on:
		b.add_theme_stylebox_override("normal", UITheme.frame({"rings": [[UITheme.GOLD, 4], [UITheme.RIM, 2]],
			"bg": UITheme.PANEL, "drop": 6}, 14))
		b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
	var col := _vbox(6)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var top := _hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(UITheme.icon_box(tex, 56))
	if on:
		top.add_child(UITheme.tag(tr("EQUIPPED"), true))
	col.add_child(top)
	var n := UITheme.label(name, "", 20, UITheme.GOLD if on else UITheme.TEXT)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(n)
	var d := UITheme.label(details, "", 15, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(d)
	var price := _hbox(6)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(price)
	parent.add_child(b)
	return [b, price]


## The price line: "Owned · equip" in green, or the gold icon and the price (red with what is missing).
func _price(row: HBoxContainer, text: String, price: int) -> void:
	if price < 0:
		row.add_child(UITheme.label(text, "", 16, UITheme.GOOD))
		return
	row.add_child(UITheme.icon_rect(UITheme.icon("gold"), 20))
	var short := price - Profile.gold
	row.add_child(UITheme.label(tr("%d · %d missing") % [price, short] if short > 0 else str(price), "", 18,
		UITheme.BAD if short > 0 else UITheme.GOLD))


func _item_card(grid: Control, id: String) -> void:
	var it: Dictionary = Profile.ITEMS[id]
	var on: bool = Profile.equipped[it.kind] == id
	var owned: bool = Profile.owned.has(id)
	var bonus := _bonus_text(it.bonus)
	var c := _card(grid, UITheme.icon(id), tr(it.name), bonus if bonus else tr("No bonus"), on,
		func(): if not Profile.equip_item(id): Profile.buy_item(id))
	c[0].disabled = on or (not owned and Profile.gold < it.price)
	if not on:
		_price(c[1], tr("Owned · equip"), -1 if owned else it.price)


func _bonus_card(grid: Control, id: String) -> void:
	var bo: Dictionary = Profile.BONUSES[id]
	var price := Profile.bonus_price(id)
	var have: int = Profile.bonuses.get(id, 0)
	var c := _card(grid, null, "%s %d/%d" % [tr(bo.name), have, bo.max], tr(bo.desc), false, func(): Profile.buy_bonus(id))
	c[0].disabled = price < 0 or Profile.gold < price
	# The icon box shows the level as pips.
	var box: PanelContainer = c[0].get_child(0).get_child(0).get_child(0)
	var pips := GridContainer.new()
	pips.columns = 5
	pips.add_theme_constant_override("h_separation", 2)
	pips.add_theme_constant_override("v_separation", 2)
	pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in bo.max:
		var p := ColorRect.new()
		p.color = UITheme.GOLD if i < have else UITheme.RIM
		p.custom_minimum_size = Vector2(7, 7)
		pips.add_child(p)
	box.add_child(pips)
	if price < 0:
		c[1].add_child(UITheme.label("max", "", 16, UITheme.GOOD))
	else:
		_price(c[1], "", price)


func _spell_card(grid: Control, slot: String, e: Dictionary) -> void:
	var on: bool = Profile.spells[slot] == e.id
	var c := _card(grid, UITheme.spell_icon(e.spell), Spell.label(e.spell),
		"%d mana" % Spell.mana_cost(e.spell), on, func(): Profile.equip_spell(slot, e.id))
	c[0].disabled = on
	c[0].tooltip_text = Spell.describe(e.spell)


## The mage panel: worn items, and the total stats with every bonus.
func _refresh_mage() -> void:
	for c in _worn.get_children() + _stats.get_children():
		c.queue_free()
	for kind in ["staff", "robe", "ring"]:
		var id: String = Profile.equipped[kind]
		var tex := UITheme.icon(id)
		_worn.add_child(UITheme.icon_box(tex, 56, UITheme.GOLD if tex else UITheme.RIM))
	var s := Profile.total_stats()
	var rows := [["HP", "%d" % s.get("hp", 0)], ["Mana", "%d" % s.get("mana", 0)], ["Mana/s", "%d" % s.get("regen", 0)]]
	for k in [["damage", "Damage"], ["speed", "Speed"], ["gold", "Gold"], ["xp", "XP"]]:
		if s.get(k[0], 0.0) > 0.0:
			rows.append([k[1], "+%d %%" % roundi(s[k[0]] * 100)])
	for r in rows:
		var row := _hbox(8)
		var n := UITheme.label(r[0], "", 16, UITheme.TEXT_DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UITheme.label(r[1], "", 16))
		_stats.add_child(row)


static func _bonus_text(bonus: Dictionary) -> String:
	var names := {"hp": "HP", "mana": "mana", "regen": "mana/s", "speed": "speed",
		"damage": "damage", "gold": "gold", "xp": "XP"}
	var parts := []
	for k in bonus:
		var v: float = bonus[k]
		parts.append(("+%d %%" % roundi(v * 100) if k in ["speed", "damage", "gold", "xp"] else "+%d" % v) + " " + TranslationServer.translate(names.get(k, k)))
	return ", ".join(parts)
