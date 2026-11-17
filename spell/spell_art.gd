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


## Integer scale so the art covers about `diameter` screen pixels.
static func scale_for(tex: Texture2D, diameter: float) -> int:
	return maxi(1, roundi(diameter / maxf(tex.get_width(), tex.get_height())))
