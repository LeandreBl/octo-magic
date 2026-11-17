class_name Decor
extends Node2D
## Arena decor of one map, placed once at run start from a seed: props
## (non-blocking), obstacles ("wall": bolts stop, "rock": bolts bounce),
## breakable "crate"s (the game drops loot on `broken`), and small flickering lights.
## Art: assets/decor/<map>.png, 4x4 cells of 32x32 art pixels (PixelLab),
## drawn at SpellArt.PIXEL like the spells.

signal broken(pos: Vector2)

const CELL := 32
## map -> [cell, kind, light color]
const MAPS := {
	"crypt": [[0, "wall"], [1, "wall"], [2, "wall"], [12, "wall"], [11, "rock"], [3, "crate"], [4, "crate"],
		[5, "prop"], [6, "prop"], [7, "prop", "#ff9a3c"], [8, "prop", "#ffd27a"], [9, "prop"],
		[10, "prop"], [13, "prop"], [14, "prop"], [15, "prop"]],
	"cave": [[0, "wall"], [2, "wall"], [1, "rock"], [14, "rock"], [3, "crate"], [4, "crate"],
		[5, "prop", "#a070ff"], [6, "prop", "#a070ff"], [7, "prop", "#e080ff"], [8, "prop"], [9, "prop"],
		[10, "prop"], [11, "prop"], [13, "prop"], [15, "prop"]],
	"ruins": [[0, "wall"], [1, "wall"], [3, "wall"], [14, "wall"], [8, "wall", "#ff9a3c"], [2, "rock"],
		[4, "crate"], [5, "crate"], [6, "prop"], [7, "prop"], [9, "prop"], [12, "prop"], [13, "prop"], [15, "prop"]],
}
const COUNTS := {"wall": 5, "rock": 3, "crate": 4, "prop": 16}  # placement order
const EDGE := 64.0  # enemies come in from every side
const CENTER := 180.0  # the player starts in the middle
const GAP := 80.0  # room between solid items: the boss (radius 36) gets through

## Solid items of the current run: {pos, r, kind, cell, light}. Static so the
## player and enemies can slide around them without a reference.
static var obstacles: Array = []

var sheet: Texture2D
var items: Array = []  # every placed item, solid or not
var arena := Rect2()  # the walkable area: its edge is drawn, the camera scrolls past it
var glow := Node2D.new()
var halo: Texture2D
var t := 0.0


func _ready() -> void:
	z_index = -1  # under the player, enemies and spells
	glow.material = CanvasItemMaterial.new()
	glow.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.draw.connect(_draw_glow)
	add_child(glow)
	halo = _halo()


func build(map: String, rect: Rect2, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	sheet = load("res://assets/decor/%s.png" % map)
	var img := sheet.get_image()
	items = []
	arena = rect
	var inner := rect.grow(-EDGE)
	for kind in COUNTS:
		var cells: Array = MAPS[map].filter(func(c): return c[1] == kind)
		for i in COUNTS[kind]:
			var c: Array = cells[rng.randi() % cells.size()]
			var it := _shape(img, c[0])
			it.kind = kind
			it.light = Color.html(c[2]) if c.size() > 2 else Color.TRANSPARENT
			it.phase = rng.randf() * TAU
			for attempt in 30:
				it.pos = Vector2(rng.randf_range(inner.position.x, inner.end.x),
					rng.randf_range(inner.position.y, inner.end.y)).snapped(Vector2.ONE * SpellArt.PIXEL)
				if _free(it, rect.get_center()):
					items.append(it)
					break
	obstacles = items.filter(func(o): return o.kind != "prop")
	queue_redraw()


## Collision circle of a cell: the bottom of its drawing (top-down view).
func _shape(img: Image, cell: int) -> Dictionary:
	var at := Vector2i(cell % 4, cell / 4) * CELL
	var used := img.get_region(Rect2i(at, Vector2i(CELL, CELL))).get_used_rect()
	var r := used.size.x / 2.0
	var foot := Vector2(used.get_center().x, used.end.y - minf(r, used.size.y / 2.0))
	return {"cell": cell, "src": Rect2(at, Vector2(CELL, CELL)), "foot": foot, "r": r * 0.8 * SpellArt.PIXEL}


func _free(it: Dictionary, center: Vector2) -> bool:
	var solid: bool = it.kind != "prop"
	if solid and it.pos.distance_to(center) < CENTER + it.r:
		return false
	for o in items:
		var gap := GAP if solid and o.kind != "prop" else 0.0
		if it.pos.distance_to(o.pos) < it.r + o.r + gap:
			return false
	return true


## pos moved by motion, kept out of obstacles: a blocked mover turns along the
## obstacle's edge, so chasers go around it.
static func slide(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var p := pos + motion
	for o in obstacles:
		var d: Vector2 = p - o.pos
		var min_d: float = o.r + r
		if d.length() < min_d:
			var n := d.normalized() if d else Vector2.UP
			var tangent := n.orthogonal()
			if tangent.dot(motion) < 0.0:
				tangent = -tangent
			p = o.pos + (n * min_d + tangent * motion.length()).normalized() * min_d
	return p


static func hit(pos: Vector2, r: float) -> Dictionary:
	for o in obstacles:
		if pos.distance_to(o.pos) < o.r + r:
			return o
	return {}


func _physics_process(delta: float) -> void:
	t += delta
	for n in get_parent().get_children():
		if n is SpellBody and n.body.shape == "bolt" and not n.is_queued_for_deletion():
			var o := hit(n.global_position, n.body.size)
			if o.is_empty():
				continue
			if o.kind == "rock":
				var normal: Vector2 = (n.global_position - o.pos).normalized()
				n.dir = n.dir.bounce(normal)
				n.global_position = o.pos + normal * (o.r + n.body.size)
			else:
				if o.kind == "crate":
					_break(o)
				n._expire()
	queue_redraw()
	glow.queue_redraw()


func _break(o: Dictionary) -> void:
	items.erase(o)
	obstacles.erase(o)
	broken.emit(o.pos)


func _draw() -> void:
	draw_rect(arena, Color(0, 0, 0, 0.6), false, 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SpellArt.PIXEL)
	for it in items:
		draw_texture_rect_region(sheet, Rect2(it.pos / SpellArt.PIXEL - it.foot, it.src.size), it.src)


## Lights: a stepped pixel halo, added over the scene, flickering.
func _draw_glow() -> void:
	glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SpellArt.PIXEL)
	for it in items:
		if it.light.a > 0.0:
			var flicker := 0.75 + 0.25 * sin(t * 11.0 + it.phase) * sin(t * 4.3 + it.phase * 2.0)
			var at: Vector2 = it.pos / SpellArt.PIXEL - it.foot + Vector2(CELL, CELL) / 2.0
			glow.draw_texture(halo, at - halo.get_size() / 2.0, Color(it.light, flicker))


func _halo() -> Texture2D:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, 0.3 if d < 5 else 0.16 if d < 10 else 0.07 if d < 16 else 0.0))
	return ImageTexture.create_from_image(img)
