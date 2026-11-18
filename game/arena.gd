class_name Arena
extends Node2D
## The run's map: a graveyard, two painted pictures drawn SCALE times: its
## ground (assets/maps/graveyard/ground.png), and what stands up in the air
## (above.png: trees, roofs, statues), drawn over the movers and
## see-through inside the local mage's halo while it walks under one. Its obstacles are placed by hand in map.json
## (tools/map_editor.py; in the pictures' pixels): polygons (buildings, walls,
## fences, out of bounds) and circles (tombs, trunks, statues, lanterns).
## Movers slide around them. The monsters come out of its open graves (spawns).

const MAPS := ["crypt", "cave", "ruins"]  # one per run: its music for now
const ART := "res://assets/maps/graveyard/"
const SCALE := 1.5  # the pictures' pixels on the octopus' scale: a path about twice its width
const RECT := Rect2(0, 0, 1536 * SCALE, 1024 * SCALE)  # ground.png's size, scaled
const SEE := 140.0  # the mage's halo, in the world: what is above turns see-through inside it
const FADED := 0.5
const BODY := 20.0  # how far from its middle the mage's body is under something (world)

static var clock := 0.0  # s of game time, scaled by Engine.time_scale: animations run on it
static var _map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + "map.json"))
## Solid polygons, circles [x, y, r], spawns [x, y] and the mages' start,
## scaled. Static: movers slide without a reference.
static var polygons: Array = _map.polygons.map(func(poly): return PackedVector2Array(poly.map(func(v): return Vector2(v[0], v[1]) * SCALE))):
	set(v):
		polygons = v
		boxes = _boxes(v)
## Each polygon's bounding box: slide skips the polygons far from the mover
## (it runs for every mover, every frame).
static var boxes: Array = _boxes(polygons)
static var solids: Array = _map.circles.map(func(s): return [s[0] * SCALE, s[1] * SCALE, s[2] * SCALE])
static var spawns: Array = _map.spawns.map(func(s): return [s[0] * SCALE, s[1] * SCALE])
static var START := Vector2(_map.start[0], _map.start[1]) * SCALE

var ground: Texture2D = load(ART + "ground.png")
var above := Sprite2D.new()
var above_img: Image  # to tell when the mage is under something
var halo := 0.0  # 0 off .. 1 on: eased in and out


func _ready() -> void:
	z_index = -1  # under the player, enemies and spells
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	above.texture = load(ART + "above.png")
	above.centered = false
	above.scale = Vector2.ONE * SCALE
	above.z_as_relative = false
	above.z_index = 10  # over the movers
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 mage;  // in UV
uniform vec2 halo;  // its radius, in UV on each axis
uniform float faded;
uniform float on;  // 0 off .. 1 on
void fragment() {
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= mix(mix(1.0, faded, on), 1.0, smoothstep(0.85, 1.0, length((UV - mage) / halo)));
}
"""
	above.material = ShaderMaterial.new()
	above.material.shader = shader
	above.material.set_shader_parameter("halo", Vector2.ONE * SEE / RECT.size)
	above.material.set_shader_parameter("faded", FADED)
	add_child(above)
	above_img = above.texture.get_image()
	walkable()  # walked now (about a second) rather than at the first wave's spawn


func _process(delta: float) -> void:
	clock += delta
	var cam := get_viewport().get_camera_2d()
	var mage: Vector2 = cam.get_parent().global_position if cam else Vector2(-1e4, -1e4)
	above.material.set_shader_parameter("mage", mage / RECT.size)
	halo = move_toward(halo, 1.0 if under(mage) else 0.0, delta * 6.0)
	above.material.set_shader_parameter("on", halo)


## Whether something above covers a mage at pos: its middle or its edge.
func under(pos: Vector2) -> bool:
	for k in 9:
		var p := pos + (Vector2.from_angle(TAU * k / 8.0) * BODY if k else Vector2.ZERO)
		var px := Vector2i(p / SCALE)
		if Rect2i(Vector2i.ZERO, above_img.get_size()).has_point(px) and above_img.get_pixelv(px).a > 0.3:
			return true
	return false


func _draw() -> void:
	draw_texture_rect(ground, RECT, false)


## What a mage at each of mages sees (the camera follows it, stopped at the
## arena's edges), view: the screen's size in the world.
static func views(mages: Array, view: Vector2) -> Array:
	return mages.map(func(m): return Rect2((m - view / 2.0).clamp(RECT.position, RECT.end - view), view))


## Where a monster comes out: never in a mage's view (views, grown by a
## monster's size). A random open grave off every view, else a random spot of
## the ground the mages walk (walkable) off every view, else the open grave
## farthest from them.
static func spawn_point(seen: Array) -> Vector2:
	var hidden := func(v: Vector2): return not seen.any(func(r): return r.grow(48.0).has_point(v))
	var graves: Array = spawns.map(func(s): return Vector2(s[0], s[1])).filter(hidden)
	if graves:
		return graves.pick_random() + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	var free: Array = walkable().filter(hidden)
	if free:
		return free.pick_random()
	var away := func(v: Vector2): return seen.map(func(r): return r.get_center().distance_to(v)).min()
	var all: Array = spawns.map(func(s): return Vector2(s[0], s[1]))
	all.sort_custom(func(a, b): return away.call(a) > away.call(b))
	return all[0] if all else RECT.get_center()


static var _ground: Array = []
static var _ground_of: Array = []  # the polygons it was walked on


## The ground reachable from the start, one point every CELL: a monster put
## anywhere else (out of bounds, a closed pen) would be stuck there. Walked
## once per map (a flood fill, a step free only when its middle is too).
static func walkable() -> Array:
	const CELL := 24.0
	const R := 16.0
	if _ground_of == polygons:
		return _ground
	_ground_of = polygons
	var size := Vector2i((RECT.size / CELL).ceil())
	var free := func(v: Vector2): return RECT.has_point(v) and slide(v, Vector2.ZERO, R) == v
	var seen := {}
	var todo := [Vector2i((START / CELL).floor())]
	seen[todo[0]] = true
	_ground = []
	while todo:
		var c: Vector2i = todo.pop_back()
		var v := (Vector2(c) + Vector2(0.5, 0.5)) * CELL
		if free.call(v):
			_ground.append(v)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y or seen.has(n):
				continue
			var w := (Vector2(n) + Vector2(0.5, 0.5)) * CELL
			if free.call(w) and free.call((v + w) / 2.0):
				seen[n] = true
				todo.append(n)
	return _ground


static func _boxes(polys: Array) -> Array:
	return polys.map(func(poly):
		var b := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			b = b.expand(v)
		return b)


## pos moved by motion, sliding around the solids (a mover of radius r).
static func slide(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var p := pos + motion
	for s in solids:
		var c := Vector2(s[0], s[1])
		var min_d: float = s[2] + r
		var d := p - c
		if d.length() < min_d:
			var n := d.normalized() if d else Vector2.UP
			var tangent := n.orthogonal()
			if tangent.dot(motion) < 0.0:
				tangent = -tangent
			p = c + (n * min_d + tangent * motion.length()).normalized() * min_d
	for k in polygons.size() * 3:  # pushed out to r from its nearest edge, sliding along it; thrice: out of one may push into a neighbour
		var j := k % polygons.size()
		if not boxes[j].grow(r + 1.0).has_point(p):
			continue  # outside it and farther than r from its edges
		var poly: PackedVector2Array = polygons[j]
		var inside := Geometry2D.is_point_in_polygon(p, poly)
		var best := Vector2.INF
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_squared_to(p) < best.distance_squared_to(p):
				best = q
		if inside or p.distance_to(best) < r:
			var out := (best - p if inside else p - best).normalized()
			p = best + (out if out else Vector2.UP) * r
	for j in polygons.size():
		if boxes[j].has_point(p) and Geometry2D.is_point_in_polygon(p, polygons[j]):
			return pos  # squeezed between zones closer than the mover's width: it stays put
	return p
