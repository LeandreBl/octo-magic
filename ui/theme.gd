extends RefCounted
## The shared heroic-fantasy Theme: dark violet panels, gold trims, parchment text.
## Type variations: "Title" and "Header" (Label), "Slot" (Panel).

const INK := Color("#14101f")
const PANEL := Color("#231a38")
const PANEL_HI := Color("#3a2c5c")
const GOLD := Color("#d4a83a")
const GOLD_DIM := Color("#7d6224")
const TEXT := Color("#f2e6c8")
const TEXT_DIM := Color("#a89c80")
const HP := Color("#c0392b")
const MANA := Color("#3d6fd8")
const XP := Color("#d4a83a")

## Fonts (assets/fonts, SIL OFL): Almendra, calligraphic, for the whole game;
## Uncial Antiqua, an old manuscript hand, for what is written on scrolls.
## Neither has Greek: EB Garamond fills in (πῦρ, ...).
const GREEK: FontFile = preload("res://assets/fonts/EBGaramond.ttf")
const MAGIC: FontFile = preload("res://assets/fonts/Almendra-Regular.ttf")
const MAGIC_BOLD: FontFile = preload("res://assets/fonts/Almendra-Bold.ttf")
const PARCHMENT: FontFile = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")


static func make() -> Theme:
	var t := Theme.new()
	for f in [MAGIC, MAGIC_BOLD, PARCHMENT]:
		f.fallbacks = [GREEK]
	t.default_font = MAGIC
	t.default_font_size = 22

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_type_variation("Title", "Label")
	t.set_font_size("font_size", "Title", 64)
	t.set_font("font", "Title", MAGIC_BOLD)
	t.set_color("font_color", "Title", GOLD)
	t.set_type_variation("Header", "Label")
	t.set_font_size("font_size", "Header", 34)
	t.set_font("font", "Header", MAGIC_BOLD)
	t.set_color("font_color", "Header", GOLD)

	t.set_stylebox("panel", "PanelContainer", _box(Color(PANEL, 0.94), GOLD_DIM, 2, 12, 20))
	t.set_stylebox("panel", "Panel", _box(Color(PANEL, 0.94), GOLD_DIM, 2, 12, 0))
	t.set_type_variation("Slot", "Panel")
	t.set_stylebox("panel", "Slot", _box(Color(INK, 0.85), GOLD_DIM, 2, 6, 0))

	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, _box(PANEL, GOLD_DIM, 2, 8, 10))
		t.set_stylebox("hover", type, _box(PANEL_HI, GOLD, 2, 8, 10))
		t.set_stylebox("pressed", type, _box(INK, GOLD, 2, 8, 10))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, TEXT, 3, 8, 10))
		t.set_stylebox("disabled", type, _box(Color(PANEL, 0.5), Color(GOLD_DIM, 0.4), 2, 8, 10))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_focus_color", type, GOLD)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_disabled_color", type, TEXT_DIM)

	t.set_stylebox("normal", "LineEdit", _box(INK, GOLD_DIM, 2, 6, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, GOLD, 2, 6, 10))
	t.set_stylebox("read_only", "LineEdit", _box(Color(INK, 0.5), Color(GOLD_DIM, 0.4), 2, 6, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	t.set_stylebox("background", "ProgressBar", _box(Color(INK, 0.85), GOLD_DIM, 2, 4, 0))
	t.set_stylebox("fill", "ProgressBar", _box(HP, Color.TRANSPARENT, 0, 4, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("slider", "HSlider", _box(INK, GOLD_DIM, 1, 4, 3))
	t.set_stylebox("grabber_area", "HSlider", _box(GOLD_DIM, Color.TRANSPARENT, 0, 4, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, Color.TRANSPARENT, 0, 4, 3))
	return t


## A PixelLab icon from assets/icons (tools/make_icons.py), null when missing.
static func icon(id: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null


## The icon of a base spell, found by name (spell dicts carry no id).
static func spell_icon(s: Dictionary) -> Texture2D:
	for e in Profile.base_spells:
		if e.spell.name == s.name:
			return icon(e.id)
	return null


## A fill colored like `color`, for ProgressBar "fill" overrides.
static func fill(color: Color) -> StyleBoxFlat:
	return _box(color, Color.TRANSPARENT, 0, 4, 0)


static func _box(bg: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	b.anti_aliasing = true
	return b
