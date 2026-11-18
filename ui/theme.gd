extends RefCounted
## The shared "abyssal grimoire" Theme, matching the PixelLab pixel art: hard
## edges, thick dark outlines, hard drop shadows; deep ink-blue panels with a
## blue rim and gold rivets, slate-blue buttons, gold accent.
## Frames are small generated images (nine-patch StyleBoxTexture), so rims,
## bevels and rivets stay pixel-sharp at any size.
## Type variations:
## - Label: "Title" (game name), "Header" (screen title, manuscript font),
##   "Subheader" (section title), "Caption" (small dim text), "Big" (numbers).
## - PanelContainer: "Plate" (HUD), "Tile" (stat box), "Well" (sunken box),
##   "Parchment" (scroll panel), "Badge" (small light tag).
## - Panel: "Slot" (spell slot).
## - Button: "Primary" (gold), "Danger" (red text), "Card" (level-up card,
##   shop item), "SideTab" (toggle, gold when on), "Tab" (toggle, underlined).

const Player := preload("res://game/player.gd")
const INK := Color("#0b1220")  # backgrounds
const PANEL := Color("#14233a")
const PANEL_HI := Color("#1c3150")
const RIM := Color("#2a4468")
const BUTTON := Color("#22324d")
const BUTTON_HI := Color("#2b3f60")
const OUTLINE := Color("#05080f")
const GOLD := Color("#ffc94a")  # accent: titles, focus, gold
const GOLD_DIM := Color("#c8901c")
const GOLD_LIGHT := Color("#ffe08a")
const ON_GOLD := Color("#1a1206")  # text on gold
const TEXT := Color("#f3ead8")
const TEXT_DIM := Color("#9fb0c8")
const GOOD := Color("#8fe39b")
const BAD := Color("#ff9a8c")
const HP := Color("#e0433a")
const MANA := Color("#3f8cff")
const XP := Color("#ffc94a")
const PARCH := Color("#e8d6a8")
const PARCH_LIGHT := Color("#f4e7c4")
const PARCH_INK := Color("#2b1d0e")
const PARCH_BROWN := Color("#6e5428")
const PARCH_RED := Color("#5a2a12")
const SHADOW := Color(0, 0, 0, 0.55)

## Fonts (assets/fonts, SIL OFL): Fredoka, a smooth rounded sans, for the whole
## game; Uncial Antiqua, an old manuscript hand, for titles and what is
## written on scrolls. Neither has Greek: EB Garamond fills in (πῦρ, ...).
## (Almendra stays for the website, web/style.css.)
const GREEK: FontFile = preload("res://assets/fonts/EBGaramond.ttf")
const BODY_FILE: FontFile = preload("res://assets/fonts/Fredoka.ttf")
const PARCHMENT: FontFile = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")
static var BODY := _weight(500)
static var BODY_BOLD := _weight(700)

## Small pixel glyphs ('#' = a pixel), drawn in code where no PixelLab icon exists.
const GLYPHS := {
	"back": ["..#....", ".##....", "#######", ".##....", "..#...."],
	"play": ["##.....", "###....", "####...", "#####..", "####...", "###....", "##....."],
	"pause": ["##.##", "##.##", "##.##", "##.##", "##.##"],
	"check": [".......#", "......##", ".....##.", "#...##..", "##.##...", ".###....", "..#....."],
	"shield": ["########", "#......#", "#......#", "#......#", "########", ".######.", "..####..", "...##...", "........"],
	"copy": ["####..", "#.....", "#.####", "#.#..#", "..#..#", "..####"],
	"user": [".###.", ".###.", ".###.", ".....", "#####", "#####"],
}


static func make() -> Theme:
	for f in [BODY_FILE, PARCHMENT]:
		f.fallbacks = [GREEK]
	var t := Theme.new()
	t.default_font = BODY
	t.default_font_size = 20

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", SHADOW)
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	_label(t, "Title", PARCHMENT, 84, GOLD, 5)
	_label(t, "Header", PARCHMENT, 46, GOLD, 4)
	_label(t, "Subheader", BODY_BOLD, 28, GOLD, 3)
	_label(t, "Big", BODY_BOLD, 40, TEXT, 3)
	t.set_type_variation("Caption", "Label")
	t.set_font_size("font_size", "Caption", 16)
	t.set_color("font_color", "Caption", TEXT_DIM)

	var panel := {"rings": [[OUTLINE, 4], [RIM, 2]], "bg": PANEL, "rivets": GOLD, "drop": 6}
	t.set_stylebox("panel", "PanelContainer", frame(panel, 28))
	t.set_stylebox("panel", "Panel", frame(panel, 0))
	t.set_type_variation("Plate", "PanelContainer")
	t.set_stylebox("panel", "Plate", frame({"rings": [[OUTLINE, 4], [RIM, 2]], "bg": Color(PANEL, 0.92), "drop": 4}, 10))
	t.set_type_variation("Tile", "PanelContainer")
	t.set_stylebox("panel", "Tile", frame({"rings": [[OUTLINE, 4], [RIM, 2]], "bg": PANEL, "drop": 4}, 14))
	t.set_type_variation("Well", "PanelContainer")
	t.set_stylebox("panel", "Well", frame({"rings": [[OUTLINE, 3]], "bg": INK}, 14))
	t.set_type_variation("Parchment", "PanelContainer")
	t.set_stylebox("panel", "Parchment", frame({"rings": [[OUTLINE, 4], [Color("#cdb47c"), 4], [PARCH, 4],
		[Color("#a9884a"), 2]], "bg": PARCH, "drop": 6}, 30))
	t.set_type_variation("Badge", "PanelContainer")
	t.set_stylebox("panel", "Badge", flat(TEXT, OUTLINE, 2, 6, 0))
	t.set_type_variation("Slot", "Panel")
	t.set_stylebox("panel", "Slot", frame({"rings": [[OUTLINE, 4]], "bg": PANEL, "drop": 4}, 0))

	var button := {"rings": [[OUTLINE, 4]], "bg": BUTTON, "top": Color("#2f4569"), "bottom": Color("#16233a"), "drop": 5}
	var hover := button.merged({"bg": BUTTON_HI, "top": Color("#3a5480"), "bottom": Color("#1b2a44")}, true)
	var pressed := button.merged({"bg": Color("#1a2840"), "top": Color("#16233a"), "bottom": Color("#1a2840"), "drop": 0}, true)
	for type in ["Button", "OptionButton", "CheckButton", "Card", "Primary", "Danger", "SideTab"]:
		t.set_stylebox("normal", type, frame(button, 10))
		t.set_stylebox("hover", type, frame(hover, 10))
		t.set_stylebox("pressed", type, frame(pressed, 10, 5))
		t.set_stylebox("hover_pressed", type, frame(pressed, 10, 5))
		t.set_stylebox("disabled", type, frame(button.merged({"bg": Color("#18233a"), "top": Color("#18233a"),
			"bottom": Color("#18233a"), "drop": 0}, true), 10))
		t.set_stylebox("focus", type, focus(GOLD))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_focus_color", type, GOLD)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.7))
		t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.5))
		t.set_constant("h_separation", type, 10)

	# Primary: the one gold button of a screen (Play, Resume, Start...).
	t.set_type_variation("Primary", "Button")
	t.set_font("font", "Primary", BODY_BOLD)
	var gold := {"rings": [[OUTLINE, 4]], "bg": GOLD, "top": GOLD_LIGHT, "bottom": GOLD_DIM, "bevel": 5, "drop": 5}
	t.set_stylebox("normal", "Primary", frame(gold, 10))
	t.set_stylebox("hover", "Primary", frame(gold.merged({"bg": Color("#ffd56e")}, true), 10))
	t.set_stylebox("pressed", "Primary", frame(gold.merged({"top": GOLD_DIM, "drop": 0}, true), 10, 5))
	t.set_stylebox("focus", "Primary", focus(TEXT))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Primary", ON_GOLD)
	t.set_type_variation("Danger", "Button")
	t.set_color("font_color", "Danger", BAD)

	# Card: a big button holding its own controls (level-up choice, shop item).
	t.set_type_variation("Card", "Button")
	var card := {"rings": [[OUTLINE, 4], [RIM, 2]], "bg": PANEL, "drop": 6}
	t.set_stylebox("normal", "Card", frame(card, 14))
	t.set_stylebox("hover", "Card", frame({"rings": [[GOLD, 4], [RIM, 2]], "bg": PANEL_HI, "drop": 6}, 14))
	t.set_stylebox("pressed", "Card", frame({"rings": [[GOLD, 4], [GOLD, 2]], "bg": PANEL_HI, "drop": 0}, 14, 5))
	t.set_stylebox("disabled", "Card", frame({"rings": [[OUTLINE, 4], [RIM, 2]], "bg": Color(PANEL, 0.6), "drop": 6}, 14))
	t.set_stylebox("focus", "Card", focus(TEXT))

	# SideTab: a vertical tab (toggle in a ButtonGroup), gold when chosen.
	t.set_type_variation("SideTab", "Button")
	t.set_stylebox("pressed", "SideTab", frame(gold, 10))
	t.set_stylebox("hover_pressed", "SideTab", frame(gold, 10))
	t.set_color("font_pressed_color", "SideTab", ON_GOLD)
	t.set_color("font_hover_pressed_color", "SideTab", ON_GOLD)
	# Tab: a horizontal tab, underlined in gold when chosen.
	t.set_type_variation("Tab", "Button")
	var under := flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 6, 0)
	under.border_width_bottom = 4
	var under_on := under.duplicate()
	under_on.border_color = GOLD
	for s in ["normal", "hover", "disabled"]:
		t.set_stylebox(s, "Tab", under)
	t.set_stylebox("pressed", "Tab", under_on)
	t.set_stylebox("hover_pressed", "Tab", under_on)
	t.set_stylebox("focus", "Tab", focus(GOLD))
	t.set_color("font_color", "Tab", TEXT_DIM)
	t.set_color("font_hover_color", "Tab", TEXT)
	t.set_color("font_pressed_color", "Tab", GOLD)
	t.set_color("font_hover_pressed_color", "Tab", GOLD)

	t.set_icon("checked", "CheckButton", _toggle(true))
	t.set_icon("unchecked", "CheckButton", _toggle(false))
	t.set_stylebox("normal", "CheckButton", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 0))
	t.set_stylebox("hover", "CheckButton", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 0))
	t.set_stylebox("pressed", "CheckButton", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 0))
	t.set_stylebox("hover_pressed", "CheckButton", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 0))

	t.set_stylebox("normal", "LineEdit", flat(INK, OUTLINE, 4, 12, 0))
	t.set_stylebox("focus", "LineEdit", focus(GOLD))
	t.set_stylebox("read_only", "LineEdit", flat(Color(INK, 0.5), Color(OUTLINE, 0.6), 4, 12, 0))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.7))
	t.set_color("caret_color", "LineEdit", GOLD)

	t.set_stylebox("background", "ProgressBar", flat(OUTLINE, OUTLINE, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", fill(HP))
	t.set_color("font_color", "ProgressBar", TEXT)

	var track := flat(OUTLINE, OUTLINE, 0, 0, 0)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(GOLD_DIM, Color.TRANSPARENT, 0, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(GOLD, Color.TRANSPARENT, 0, 0, 0))
	t.set_icon("grabber", "HSlider", _block(22, 28, TEXT))
	t.set_icon("grabber_highlight", "HSlider", _block(22, 28, GOLD))

	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, flat(Color(OUTLINE, 0.6), Color.TRANSPARENT, 0, 4, 0))
		t.set_stylebox("grabber", bar, flat(BUTTON, OUTLINE, 2, 4, 0))
		t.set_stylebox("grabber_highlight", bar, flat(BUTTON_HI, OUTLINE, 2, 4, 0))
		t.set_stylebox("grabber_pressed", bar, flat(GOLD, OUTLINE, 2, 4, 0))

	t.set_stylebox("panel", "TooltipPanel", flat(INK, GOLD, 3, 10, 0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("panel", "PopupMenu", flat(PANEL, OUTLINE, 4, 6, 0))
	t.set_stylebox("hover", "PopupMenu", flat(BUTTON_HI, Color.TRANSPARENT, 0, 4, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	return t


# --- helpers for the screens ---------------------------------------------------

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


## A GLYPHS entry as a texture, each pixel `px` screen pixels.
static func glyph(id: String, color: Color, px := 4) -> ImageTexture:
	var rows: Array = GLYPHS[id]
	var img := Image.create_empty(rows[0].length() * px, rows.size() * px, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				img.fill_rect(Rect2i(x * px, y * px, px, px), color)
	return ImageTexture.create_from_image(img)


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


## An icon in a sunken square box, `px` wide.
static func icon_box(tex: Texture2D, px: int, border := OUTLINE) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", flat(INK, border, 3, 0, 0))
	box.custom_minimum_size = Vector2(px, px)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		box.add_child(icon_rect(tex, px - px / 4))
	return box


## A Label of variation `variation` (or plain), `text`, optional size and color.
static func label(text: String, variation := "", size := 0, color := Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if size:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A small light tag ("HOST", "EQUIPPED"...), on gold when `gold`.
static func tag(text: String, gold := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Badge"
	if gold:
		p.add_theme_stylebox_override("panel", flat(GOLD, OUTLINE, 2, 6, 0))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, "", 13, ON_GOLD if gold else OUTLINE)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	p.add_child(l)
	return p


## The mage's idle animation (assets/octo/idle.png, 8 frames of 96 px), `px` wide
## (its first frame when not `animate`).
static func octo(px: int, animate := true) -> TextureRect:
	var sheet: Texture2D = load("res://assets/octo/idle.png")
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var frame_px := sheet.get_height()
	atlas.region = Rect2(0, 0, frame_px, frame_px)
	var r := icon_rect(atlas, px)
	# The ground tentacles are not in the sheet (game/player.gd): the same
	# game/tentacle.gd chains, behind the body, in art pixels scaled to the rect.
	var legs := Node2D.new()
	legs.show_behind_parent = true
	r.add_child(legs)
	for i in Player.TENTACLES:
		legs.add_child(Player.Tentacle.new((i + 0.5) * TAU / Player.TENTACLES, i % 2))
	var step := func(delta: float):
		legs.position = r.size / 2.0
		legs.scale = Vector2.ONE * minf(r.size.x, r.size.y) / frame_px
		for c in legs.get_children():
			c.follow(Vector2.ZERO, -PI / 2.0, delta, Time.get_ticks_msec() / 1000.0)  # head up
			var pts: PackedVector2Array = c.chain.duplicate()  # in the legs' art pixels, not the screen's
			for k in pts.size():
				pts[k] = pts[k].round()  # whole art pixels: the texture stays crisp
			c.points = pts
	step.call(0.0)
	r.resized.connect(step.bind(0.0))
	r.ready.connect(step.bind(0.0))  # a size set before it entered the tree
	if not animate:
		return r
	var sway := Timer.new()
	sway.wait_time = 1.0 / 30.0
	sway.autostart = true
	sway.timeout.connect(func(): step.call(sway.wait_time))
	r.add_child(sway)
	var frames := sheet.get_width() / frame_px
	var t := Timer.new()
	t.wait_time = 0.12
	t.autostart = true
	t.timeout.connect(func():
		atlas.region.position.x = fmod(atlas.region.position.x + frame_px, frame_px * frames))
	r.add_child(t)
	return r


## A bar fill colored like `color`, a lighter band on top, for ProgressBar "fill".
static func fill(color: Color) -> StyleBoxFlat:
	var b := flat(color, color.lightened(0.35), 0, 0, 0)
	b.border_width_top = 4
	return b


## A gamepad/keyboard focus ring, 4 px out of the control.
static func focus(color: Color) -> StyleBoxFlat:
	var f := flat(Color.TRANSPARENT, color, 4, 0, 0)
	f.set_expand_margin_all(8)
	return f


## A flat box: `width` outline, a hard drop shadow `drop` px below-right.
static func flat(bg: Color, border: Color, width: int, margin: int, drop: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_content_margin_all(margin)
	if drop:
		b.shadow_color = SHADOW
		b.shadow_size = 1
		b.shadow_offset = Vector2(drop, drop)
	return b


## A pixel frame as a nine-patch: `o.rings` ([color, width] from the outside
## in), `o.bg`, optional `o.top`/`o.bottom` bevel bands (`o.bevel` px), gold
## `o.rivets` in the corners, a hard drop shadow `o.drop` px. `nudge` sinks the
## content (pressed buttons).
static func frame(o: Dictionary, margin: int, nudge := 0) -> StyleBoxTexture:
	const CORNER := 18
	var box := CORNER * 2 + 1
	var drop: int = o.get("drop", 0)
	var img := Image.create_empty(box + drop, box + drop, false, Image.FORMAT_RGBA8)
	if drop:
		img.fill_rect(Rect2i(drop, drop, box, box), SHADOW)
	var inset := 0
	for ring in o.rings:
		img.fill_rect(Rect2i(inset, inset, box - inset * 2, box - inset * 2), ring[0])
		inset += ring[1]
	img.fill_rect(Rect2i(inset, inset, box - inset * 2, box - inset * 2), o.bg)
	var bevel: int = o.get("bevel", 4)
	if o.has("top"):
		img.fill_rect(Rect2i(inset, inset, box - inset * 2, bevel), o.top)
	if o.has("bottom"):
		img.fill_rect(Rect2i(inset, box - inset - bevel, box - inset * 2, bevel), o.bottom)
	if o.has("rivets"):
		for c in [Vector2i(10, 10), Vector2i(box - 18, 10), Vector2i(10, box - 18), Vector2i(box - 18, box - 18)]:
			img.fill_rect(Rect2i(c, Vector2i(8, 8)), o.rivets)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = CORNER
	s.texture_margin_top = CORNER
	s.texture_margin_right = CORNER + drop
	s.texture_margin_bottom = CORNER + drop
	s.expand_margin_right = drop
	s.expand_margin_bottom = drop
	s.set_content_margin_all(margin + inset if margin else 0)
	if margin:
		s.content_margin_top += nudge
		s.content_margin_bottom -= nudge
	return s


static func _label(t: Theme, variation: String, font: Font, size: int, color: Color, shadow: int) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font("font", variation, font)
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)
	t.set_color("font_shadow_color", variation, OUTLINE)
	t.set_constant("shadow_offset_x", variation, shadow)
	t.set_constant("shadow_offset_y", variation, shadow)


static func _weight(w: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = BODY_FILE
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): w}
	return v


## A solid block with a 3 px outline (slider grabber).
static func _block(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(OUTLINE)
	img.fill_rect(Rect2i(3, 3, w - 6, h - 6), color)
	return ImageTexture.create_from_image(img)


## The on/off switch of a CheckButton, 72x36.
static func _toggle(on: bool) -> ImageTexture:
	var img := Image.create_empty(72, 36, false, Image.FORMAT_RGBA8)
	img.fill(OUTLINE)
	img.fill_rect(Rect2i(4, 4, 64, 28), GOLD if on else BUTTON)
	img.fill_rect(Rect2i(42 if on else 6, 6, 24, 24), ON_GOLD if on else TEXT_DIM)
	return ImageTexture.create_from_image(img)
