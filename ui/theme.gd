extends RefCounted
## The shared "pixel arcade" Theme, matching the PixelLab pixel art: hard
## edges, thick dark outlines, hard drop shadows; rust (brick) panels,
## slate buttons, gold accent.
## Type variations: "Title" and "Header" (Label), "Slot" (Panel),
## "Plate" (PanelContainer, tight margins, for the HUD), "Card" (Button).

const INK := Color("#16181d")  # backgrounds
const PANEL := Color("#8a3b2a")
const BUTTON := Color("#3a404c")
const BUTTON_HI := Color("#525a69")
const OUTLINE := Color("#0b0c10")
const GOLD := Color("#ffc94a")  # accent: titles, focus, gold
const GOLD_DIM := Color("#a07a1f")
const TEXT := Color("#fff1e0")
const TEXT_DIM := Color("#a7adb9")
const HP := Color("#e0433a")
const MANA := Color("#3f8cff")
const XP := Color("#ffc94a")
const SHADOW := Color(0, 0, 0, 0.55)

## Fonts (assets/fonts, SIL OFL): Pixelify Sans, a pixel font, for the whole
## game; Uncial Antiqua, an old manuscript hand, for what is written on
## scrolls. Neither has Greek: EB Garamond fills in (πῦρ, ...).
## (Almendra stays for the website, web/style.css.)
const GREEK: FontFile = preload("res://assets/fonts/EBGaramond.ttf")
const PIXEL_FILE: FontFile = preload("res://assets/fonts/PixelifySans.ttf")
const PARCHMENT: FontFile = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")
static var PIXEL := _weight(500)
static var PIXEL_BOLD := _weight(700)


static func make() -> Theme:
	for f in [PIXEL_FILE, PARCHMENT]:
		f.fallbacks = [GREEK]
	var t := Theme.new()
	t.default_font = PIXEL
	t.default_font_size = 20

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", SHADOW)
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_type_variation("Title", "Label")
	t.set_font_size("font_size", "Title", 80)
	t.set_font("font", "Title", PIXEL_BOLD)
	t.set_color("font_color", "Title", GOLD)
	t.set_color("font_shadow_color", "Title", OUTLINE)
	t.set_constant("shadow_offset_x", "Title", 5)
	t.set_constant("shadow_offset_y", "Title", 5)
	t.set_type_variation("Header", "Label")
	t.set_font_size("font_size", "Header", 34)
	t.set_font("font", "Header", PIXEL_BOLD)
	t.set_color("font_color", "Header", GOLD)
	t.set_color("font_shadow_color", "Header", OUTLINE)
	t.set_constant("shadow_offset_x", "Header", 3)
	t.set_constant("shadow_offset_y", "Header", 3)

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, OUTLINE, 4, 22, 6))
	t.set_stylebox("panel", "Panel", _box(PANEL, OUTLINE, 4, 0, 6))
	t.set_type_variation("Plate", "PanelContainer")
	t.set_stylebox("panel", "Plate", _box(Color(PANEL, 0.92), OUTLINE, 4, 10, 4))
	t.set_type_variation("Slot", "Panel")
	t.set_stylebox("panel", "Slot", _box(PANEL, OUTLINE, 4, 0, 4))

	for type in ["Button", "OptionButton", "CheckButton", "Card"]:
		t.set_stylebox("normal", type, _box(BUTTON, OUTLINE, 4, 10, 5))
		t.set_stylebox("hover", type, _box(BUTTON_HI, OUTLINE, 4, 10, 5))
		t.set_stylebox("pressed", type, _box(BUTTON.darkened(0.2), OUTLINE, 4, 10, 0, 5))
		t.set_stylebox("disabled", type, _box(Color(BUTTON.darkened(0.3), 0.7), OUTLINE, 4, 10, 0))
		var focus := _box(Color.TRANSPARENT, GOLD, 4, 10, 0)
		focus.set_expand_margin_all(4)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_focus_color", type, GOLD)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_disabled_color", type, TEXT_DIM)
		t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.5))
		t.set_constant("h_separation", type, 8)
	t.set_type_variation("Card", "Button")
	t.set_stylebox("hover", "Card", _box(BUTTON_HI, GOLD, 4, 10, 5))
	t.set_stylebox("focus", "Card", _box(Color.TRANSPARENT, GOLD, 4, 10, 0))

	t.set_stylebox("normal", "LineEdit", _box(Color(OUTLINE, 0.6), OUTLINE, 4, 10, 0))
	t.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, GOLD, 4, 10, 0))
	t.set_stylebox("read_only", "LineEdit", _box(Color(OUTLINE, 0.3), Color(OUTLINE, 0.6), 4, 10, 0))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", GOLD)

	t.set_stylebox("background", "ProgressBar", _box(Color(OUTLINE, 0.85), OUTLINE, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", fill(HP))
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("slider", "HSlider", _box(OUTLINE, OUTLINE, 0, 4, 0))
	t.set_stylebox("grabber_area", "HSlider", _box(GOLD_DIM, Color.TRANSPARENT, 0, 4, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, Color.TRANSPARENT, 0, 4, 0))
	t.set_icon("grabber", "HSlider", _square(18, TEXT, OUTLINE))
	t.set_icon("grabber_highlight", "HSlider", _square(18, GOLD, OUTLINE))

	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(Color(OUTLINE, 0.6), Color.TRANSPARENT, 0, 4, 0))
		t.set_stylebox("grabber", bar, _box(BUTTON, OUTLINE, 2, 4, 0))
		t.set_stylebox("grabber_highlight", bar, _box(BUTTON_HI, OUTLINE, 2, 4, 0))
		t.set_stylebox("grabber_pressed", bar, _box(GOLD, OUTLINE, 2, 4, 0))

	t.set_stylebox("panel", "TooltipPanel", _box(INK, GOLD, 3, 8, 0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, OUTLINE, 4, 6, 0))
	t.set_stylebox("hover", "PopupMenu", _box(BUTTON_HI, Color.TRANSPARENT, 0, 4, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
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


## A TextureRect showing `tex` at `px`, pixel-sharp.
static func icon_rect(tex: Texture2D, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A bar fill colored like `color`, a lighter band on top, for ProgressBar "fill".
static func fill(color: Color) -> StyleBoxFlat:
	var b := _box(color, color.lightened(0.35), 0, 0, 0)
	b.border_width_top = 4
	return b


## A flat box: `width` outline, a hard drop shadow `drop` px below-right.
static func _box(bg: Color, border: Color, width: int, margin: int, drop: int, nudge := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_content_margin_all(margin)
	b.content_margin_top += nudge  # pressed: the label sinks with the button
	b.content_margin_bottom -= nudge
	if drop:
		b.shadow_color = SHADOW
		b.shadow_size = 1
		b.shadow_offset = Vector2(drop, drop)
	return b


static func _weight(w: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = PIXEL_FILE
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return v


static func _square(px: int, color: Color, border: Color) -> ImageTexture:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	img.fill(border)
	img.fill_rect(Rect2i(3, 3, px - 6, px - 6), color)
	return ImageTexture.create_from_image(img)
