class_name SpellArt
## Turns the pixel grids of a spell (sprite frames, particle, icon) into
## textures. Pixels stay sharp: the project filters textures with "nearest".

const PIXEL := 3  # on-screen size of one art pixel, at 1280x720
const GRID_FPS := 8  # pixel-grid sprites (few frames) play slower than sheets

static var _cache := {}


static func texture(grid: Array, palette: Array) -> Texture2D:
	if grid.is_empty():
		return null
	var key := str(grid) + str(palette)
	if _cache.has(key):
		return _cache[key]
	var w := 0
	for row in grid:
		w = maxi(w, row.length())
	var img := Image.create_empty(w, grid.size(), false, Image.FORMAT_RGBA8)
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			var i := Spell.PIXELS.find(row[x]) - 1
			if i >= 0 and i < palette.size():
				img.set_pixel(x, y, Color.html(palette[i]))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static var _sheets := {}  # "<bundle>/<file>" -> Texture2D


## Load a .spell bundle (zip: manifest.json + PNGs). Returns {} if unreadable.
## A sheet whose PNG does not match its declared strip is dropped: the body
## falls back to its pixel grids.
static func load_bundle(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var manifest: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not manifest is Dictionary:
		zip.close()
		return {}
	var id := "%s#%d" % [path, Time.get_ticks_usec()]
	for f in zip.get_files():
		if f.ends_with(".png"):
			var img := Image.new()
			if img.load_png_from_buffer(zip.read_file(f)) == OK:
				_sheets[id + "/" + f] = ImageTexture.create_from_image(img)
	zip.close()
	manifest.bundle = id
	var spell := Spell.sanitize(manifest)
	for b in bodies(spell.emit, []):
		for key in ["sheet", "burst_sheet"]:
			var s: Dictionary = b[key]
			var tex: Texture2D = sheet(spell, s.get("file", ""))
			if s and (not tex or tex.get_size() != Vector2(s.size * s.frames, s.size)):
				b[key] = {}
	if spell.icon_file and not sheet(spell, spell.icon_file):
		spell.icon_file = ""
	return spell


## Every body of a spell, top-level first.
static func bodies(emit: Dictionary, out: Array) -> Array:
	out.append(emit.body)
	for key in ["on_hit", "on_expire", "on_tick"]:
		for f in emit.body[key]:
			if f.type == "cast":
				bodies(f.emit, out)
	return out


## A PNG of the spell's bundle; base spells (game/spells.json) point their
## bundle at a res:// folder (tools/make_spells.py), loaded on first use.
static func sheet(spell: Dictionary, file: String) -> Texture2D:
	var key: String = spell.get("bundle", "") + "/" + file
	if file and key.begins_with("res://") and not _sheets.has(key):
		_sheets[key] = load(key) if ResourceLoader.exists(key) else null
	return _sheets.get(key)


## A body's animation, whatever its source: the bundle sheet, else its pixel
## grids turned into the same strip format. -> [texture, sheet] or [].
static func animation(spell: Dictionary, body: Dictionary) -> Array:
	var tex := sheet(spell, body.sheet.get("file", ""))
	if tex:  # missing on coop peers: the bundle stays with its owner
		return [tex, body.sheet]
	if body.sprite.is_empty():
		return []
	var key := "strip" + str(body.sprite) + str(spell.palette)
	var size := 0
	for f in body.sprite:
		size = maxi(size, maxi(f.size(), f.reduce(func(m, r): return maxi(m, r.length()), 0)))
	if not _cache.has(key):
		var img := Image.create_empty(size * body.sprite.size(), size, false, Image.FORMAT_RGBA8)
		for i in body.sprite.size():
			var frame := texture(body.sprite[i], spell.palette).get_image()
			var at := Vector2i(i * size + (size - frame.get_width()) / 2, (size - frame.get_height()) / 2)
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
		_cache[key] = ImageTexture.create_from_image(img)
	return [_cache[key], {"size": size, "frames": body.sprite.size(), "fps": GRID_FPS, "loop": true}]


## Draw frame `t` seconds into a strip, centered, at art scale.
## Looping sheets wrap; one-shot sheets hold their last frame.
static func draw_sheet(canvas: CanvasItem, tex: Texture2D, s: Dictionary, t: float, angle: float) -> void:
	var i := int(t * s.fps)
	var n := int(s.frames)  # float when the spell came through JSON (coop peers)
	i = i % n if s.loop else mini(i, n - 1)
	canvas.draw_set_transform(Vector2.ZERO, angle, Vector2.ONE * PIXEL)
	canvas.draw_texture_rect_region(tex, Rect2(-s.size / 2.0, -s.size / 2.0, s.size, s.size),
		Rect2(i * s.size, 0, s.size, s.size))
