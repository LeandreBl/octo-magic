extends VBoxContainer
## The scroll panel, between runs: the main spell, and blank scrolls to write
## words on, one per scroll (sent to the forge by game/main.gd). Used by the end-of-run
## and shop screens.

var main: Node
var _spell: Label
var _edit: LineEdit
var _write: Button
var _status: Label


func _ready() -> void:
	custom_minimum_size.x = 460
	add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	add_child(row)
	var icon := TextureRect.new()
	icon.texture = preload("res://ui/theme.gd").icon("scroll")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var head := Label.new()
	head.theme_type_variation = "Header"
	head.text = "Parchemin"
	row.add_child(head)
	_spell = Label.new()
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_spell)
	_edit = LineEdit.new()
	_edit.max_length = 200
	_edit.placeholder_text = "un mot par parchemin, ex : tempête, vampire, miroir"
	_edit.text_submitted.connect(func(_t): _on_write())
	add_child(_edit)
	_write = Button.new()
	_write.text = "Écrire les parchemins"
	_write.pressed.connect(_on_write)
	add_child(_write)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 18)
	add_child(_status)


func _on_write() -> void:
	main.write_scroll(_edit.text)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var s: Dictionary = Profile.equipped_spells().primary
	_spell.text = "Sort principal : %s\n%s" % [s.name, s.description]
	var can: bool = main.can_write()
	_edit.editable = can
	_write.disabled = not can
	var state := ""
	if not main.forge_job.is_empty():
		state = "Un parchemin est en cours d'écriture."
	elif Profile.blank_scrolls == 0:
		state = "Aucun parchemin vierge : les boss en laissent tomber."
	else:
		state = "Tu as %d parchemin(s) vierge(s). Écris un mot par parchemin (séparés par des espaces ou des virgules) pour transformer ton sort principal." % Profile.blank_scrolls
	_status.text = main.forge_status + "\n" + state if main.forge_status else state
