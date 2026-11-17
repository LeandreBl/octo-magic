extends PanelContainer
## The scroll panel, between runs, drawn as a parchment: the main spell, and
## blank scrolls to write words on, one per scroll (sent to the forge by
## game/main.gd). Used by the end-of-run and shop screens.

const UITheme := preload("res://ui/theme.gd")
const MAX_SHOWN := 8  # blank scrolls drawn

var main: Node
var _spell: Label
var _blanks: HBoxContainer
var _count: Label
var _edit: LineEdit
var _write: Button
var _status: Label


func _ready() -> void:
	theme_type_variation = "Parchment"
	custom_minimum_size.x = 480
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(UITheme.icon_rect(UITheme.icon("scroll"), 40))
	var head := _ink(Label.new(), 32, UITheme.PARCH_RED)
	head.text = "Scrolls"
	head.add_theme_font_override("font", UITheme.PARCHMENT)
	row.add_child(head)
	_spell = _ink(Label.new(), 18, UITheme.PARCH_INK)
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spell.add_theme_font_override("font", UITheme.GREEK)
	box.add_child(_spell)

	var blanks_row := HBoxContainer.new()
	blanks_row.add_theme_constant_override("separation", 10)
	box.add_child(blanks_row)
	_blanks = HBoxContainer.new()
	_blanks.add_theme_constant_override("separation", 8)
	blanks_row.add_child(_blanks)
	for i in MAX_SHOWN:
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PARCH_LIGHT, UITheme.PARCH_BROWN, 3, 2, 0))
		blank.custom_minimum_size = Vector2(52, 52)
		var word := _ink(Label.new(), 14, UITheme.PARCH_RED)
		word.add_theme_font_override("font", UITheme.PARCHMENT)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word.clip_text = true
		blank.add_child(word)
		_blanks.add_child(blank)
	_count = _ink(Label.new(), 16, UITheme.PARCH_BROWN)
	blanks_row.add_child(_count)

	_edit = LineEdit.new()
	_edit.max_length = 200
	_edit.add_theme_font_override("font", UITheme.PARCHMENT)
	_edit.add_theme_font_size_override("font_size", 22)
	_edit.add_theme_color_override("font_color", UITheme.PARCH_INK)
	_edit.add_theme_color_override("font_uneditable_color", UITheme.PARCH_BROWN)
	_edit.add_theme_color_override("font_placeholder_color", Color(UITheme.PARCH_BROWN, 0.8))
	_edit.add_theme_color_override("caret_color", UITheme.PARCH_RED)
	_edit.add_theme_stylebox_override("normal", UITheme.flat(UITheme.PARCH_LIGHT, UITheme.PARCH_BROWN, 3, 12, 0))
	_edit.add_theme_stylebox_override("read_only", UITheme.flat(Color(UITheme.PARCH_LIGHT, 0.5), Color(UITheme.PARCH_BROWN, 0.5), 3, 12, 0))
	_edit.placeholder_text = "one word per scroll, in a dead language, e.g. ignis, πῦρ, umbra"
	_edit.text_submitted.connect(func(_t): _on_write())
	box.add_child(_edit)
	var rule := _ink(Label.new(), 15, UITheme.PARCH_BROWN)
	rule.text = "Letters, ' and - only. A meaningless word gives its scroll back."
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(rule)

	_write = Button.new()
	_write.text = "Write the scrolls"
	_write.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_write.add_theme_font_override("font", UITheme.PIXEL_BOLD)
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
	box.add_child(_write)
	_status = _ink(Label.new(), 16, UITheme.PARCH_BROWN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)


## Dark ink on the parchment: no light text shadow.
func _ink(l: Label, size: int, color: Color) -> Label:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l


func _on_write() -> void:
	main.write_scroll(_edit.text)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var s: Dictionary = Profile.equipped_spells().primary
	_spell.text = tr("Main spell: %s\n%s") % [Spell.label(s), Spell.describe(s)]
	var can: bool = main.can_write()
	_edit.editable = can
	_write.disabled = not can
	var words := Array(_edit.text.replace(",", " ").split(" ", false))
	var n: int = Profile.blank_scrolls
	for i in MAX_SHOWN:
		var blank: Control = _blanks.get_child(i)
		blank.visible = i < maxi(n, 1)
		blank.modulate.a = 1.0 if i < n else 0.4
		blank.get_child(0).text = words[i] if i < words.size() and i < n else ""
	_count.text = tr("%d blank · %d word(s)") % [n, mini(words.size(), n)] if n else ""
	var state := ""
	if not main.forge_job.is_empty():
		state = tr("A scroll is being written.")
	elif n == 0:
		state = tr("No blank scroll: bosses drop them.")
	else:
		state = tr("The forge turns them into a new spell, equipped at your next run.")
	_status.text = main.forge_status + "\n" + state if main.forge_status else state
