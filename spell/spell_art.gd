class_name SpellArt
## Turns the pixel grids of a spell (sprite frames, particle, icon) into
## textures. Pixels stay sharp: the project filters textures with "nearest".

const PIXEL := 3  # on-screen size of one art pixel, at 1280x720

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
static func load_bundle(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var manifest: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not manifest is Dictionary:
		return {}
	var id := "%s#%d" % [path, Time.get_ticks_usec()]
	for f in zip.get_files():
		if f.ends_with(".png"):
			var img := Image.new()
			if img.load_png_from_buffer(zip.read_file(f)) == OK:
				_sheets[id + "/" + f] = ImageTexture.create_from_image(img)
	zip.close()
	manifest.bundle = id
	return Spell.sanitize(manifest)


static func sheet(spell: Dictionary, file: String) -> Texture2D:
	return _sheets.get(spell.get("bundle", "") + "/" + file)


## Draw frame `t` seconds into an animated sheet, centered, at art scale.
static func draw_sheet(canvas: CanvasItem, tex: Texture2D, s: Dictionary, t: float, angle: float, loop := true) -> void:
	var i := int(t * s.fps)
	i = i % s.frames if loop else mini(i, s.frames - 1)
	var region := Rect2((i % s.cols) * s.w, (i / s.cols) * s.h, s.w, s.h)
	canvas.draw_set_transform(Vector2.ZERO, angle, Vector2.ONE * PIXEL)
	canvas.draw_texture_rect_region(tex, Rect2(-s.w / 2.0, -s.h / 2.0, s.w, s.h), region)


## Integer scale so the art covers about `diameter` screen pixels.
static func scale_for(tex: Texture2D, diameter: float) -> int:
	return maxi(1, roundi(diameter / maxf(tex.get_width(), tex.get_height())))
