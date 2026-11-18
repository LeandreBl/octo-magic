extends PanelContainer
## Characters screen (ui/ui.gd), after login: pick one of the account's
## characters (game/online.gd), or create one: name, hat color and starting
## spell, one of the first four of game/spells.json. Without characters it
## opens on the creation form.

signal closed

const UITheme := preload("res://ui/theme.gd")
const HUD := preload("res://ui/hud.gd")  # its spell icon (or projectile preview)
const STARTING_SPELLS := 4

var info: Label
var list: VBoxContainer
var form: VBoxContainer
var name_edit: LineEdit
var hats := ButtonGroup.new()
var spells := ButtonGroup.new()
var buttons := {}


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.theme_type_variation = "Header"
	title.text = "Characters"
	box.add_child(title)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	list = VBoxContainer.new()
	box.add_child(list)

	form = VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	box.add_child(form)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "name"
	name_edit.max_length = 24
	form.add_child(name_edit)
	var row := HBoxContainer.new()
	form.add_child(row)
	for c in Profile.COLORS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = hats
		b.custom_minimum_size = Vector2(44, 44)
		b.set_meta("color", c)
		for s in [["normal", UITheme.OUTLINE], ["hover", UITheme.GOLD], ["pressed", UITheme.TEXT]]:
			b.add_theme_stylebox_override(s[0], _swatch(c, s[1]))
		row.add_child(b)
	hats.get_buttons()[0].button_pressed = true
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	form.add_child(row)
	for e in Profile.base_spells.slice(0, STARTING_SPELLS):
		row.add_child(_spell_card(e))
	spells.get_buttons()[0].button_pressed = true

	box.add_child(Control.new())  # spacer
	row = HBoxContainer.new()
	box.add_child(row)
	for b in [["New character", _show_form], ["Create", _create], ["Back", closed.emit]]:
		var button := Button.new()
		button.text = b[0]
		button.pressed.connect(b[1])
		row.add_child(button)
		buttons[b[0]] = button
	set_meta("focus", buttons["New character"])
	visibility_changed.connect(_refresh)
	Online.changed.connect(_refresh)


## The list, or the form when the account has no character.
func _refresh() -> void:
	if not is_visible_in_tree():
		return
	for c in list.get_children():  # not free(): a pressed button is mid-signal
		list.remove_child(c)
		c.queue_free()
	for c in Online.characters:
		var spell := _spell(str(c.get("spell")))
		var b := Button.new()
		b.text = "%s  ·  %s%s" % [c.get("name"), Spell.label(spell.spell) if spell else "?",
			"  ✔" if str(c.get("id")) == Online.character else ""]
		b.pressed.connect(_select.bind(str(c.get("id"))))
		list.add_child(b)
	info.text = tr(Online.status) if Online.status else ""
	_set_form(Online.characters.is_empty())


func _set_form(on: bool) -> void:
	form.visible = on
	list.visible = not on
	buttons["New character"].visible = not on
	buttons["Create"].visible = on
	buttons["Back"].visible = not Online.character.is_empty()
	(name_edit if on else list.get_child(0) if list.get_child_count() else buttons["New character"]).grab_focus.call_deferred()


func _show_form() -> void:
	name_edit.text = ""
	_set_form(true)


func _select(id: String) -> void:
	info.text = tr("Loading…")
	await Online.select(id)  # Online.changed: ui/ui.gd goes to the title


func _create() -> void:
	if name_edit.text.strip_edges().is_empty():
		info.text = tr("Choose a name.")
		return
	info.text = tr("Creating…")
	var err := await Online.create_character(name_edit.text.strip_edges(),
		spells.get_pressed_button().get_meta("id"), {"hat": hats.get_pressed_button().get_meta("color")})
	if err:
		info.text = tr("Failed: %s") % tr(err)


## A toggle card: icon, name and description of a starting spell.
func _spell_card(e: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = spells
	b.set_meta("id", e.id)
	b.theme_type_variation = "Card"
	b.custom_minimum_size = Vector2(200, 300)
	var card := VBoxContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	card.add_theme_constant_override("separation", 6)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(card)
	var pic := UITheme.icon_rect(HUD._icon(e.spell), 72)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(pic)
	for line in [[Spell.label(e.spell), 22, UITheme.GOLD], [Spell.describe(e.spell), 15, UITheme.TEXT],
			[tr("Cost: %s mana") % Spell.cost_text(e.spell, Spell.mana_cost(e.spell)), 14, UITheme.TEXT_DIM]]:
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", line[2])
		if line[2] == UITheme.TEXT_DIM:  # the cost sits at the bottom of the card
			var spacer := Control.new()
			spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(spacer)
		card.add_child(l)
	return b


static func _spell(id: String) -> Dictionary:
	for e in Profile.base_spells:
		if e.id == id:
			return e
	return {}


static func _swatch(color: String, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color)
	s.border_color = border
	s.set_border_width_all(4)
	return s
