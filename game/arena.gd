class_name Arena
extends Node2D
## The run's map: a graveyard, two painted pictures drawn SCALE times: its
## ground (assets/maps/graveyard/ground.png), and what stands up in the air
## (above.png: trees, roofs, statues), drawn over the movers and
## see-through inside the local mage's halo while it walks under one. Its obstacles are placed by hand in map.json
## (tools/map_editor.py; in the pictures' pixels): polygons (buildings, walls,
## fences, out of bounds) and circles (tombs, trunks, statues, lanterns).
## Movers slide around them. The monsters come out of its open graves (spawns).

const ART := "res://assets/maps/graveyard/"
const SCALE := 1.5  # the pictures' pixels on the octopus' scale: a path about twice its width
const RECT := Rect2(0, 0, 1536 * SCALE, 1024 * SCALE)  # ground.png's size, scaled
const SEE := 140.0  # the mage's halo, in the world: what is above turns see-through inside it
const FADED := 0.5
const BODY := 20.0  # how far from its middle the mage's body is under something (world)
## The night over the map: this much darker, but around its lamps (lamps) and every mage.
const NIGHT := 0.72
const LAMP_LIGHT := 110.0  # world
const MAGE_LIGHT := 190.0  # world
const MAGES_LIT := 8  # the shader's room for mages
const LIGHTS := 48  # the shader's room for flashes (flash) and spells (the "spells" group, nearest the camera first)
const SPELL_LIGHT := 90.0  # world: the least light around a spell
const BEAM_LIGHT := 50.0  # world: the light around each point of a beam's arc

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
static var lamps: Array = _map.get("lamps", []).map(func(l): return Vector2(l[0], l[1]) * SCALE)  # lit in the night
static var flashes := []  # [at, radius, color, start clock, time s]: flash

var ground: Texture2D = load(ART + "ground.png")
var above := Sprite2D.new()
var above_img: Image  # to tell when the mage is under something
var halo := 0.0  # 0 off .. 1 on: eased in and out
var night := ColorRect.new()


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
	night.size = RECT.size
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night.z_as_relative = false
	night.z_index = 10  # over the movers and above (drawn after it), under the spells (SpellBody.ABOVE_DECOR)
	var dark := Shader.new()
	dark.code = """
shader_type canvas_item;
render_mode blend_premul_alpha;  // dark over the map, plus the flashes' light
uniform vec2 lamps[%d];
uniform vec2 mages[%d];
uniform int lit;  // mages used
uniform float night;
uniform vec4 flash_at[%d];  // flashes, then spells  // x, y, radius, strength
uniform vec3 flash_color[%d];
uniform int flashing;
varying vec2 world;
void vertex() { world = VERTEX; }
float glow(vec2 at, float r) { return 1.0 - smoothstep(0.3 * r, r, distance(world, at)); }
void fragment() {
	float l = 0.0;
	float flicker = 1.0 + 0.04 * sin(TIME * 9.0) * sin(TIME * 5.3);
	for (int i = 0; i < %d; i++) l = max(l, glow(lamps[i], %f * flicker));
	for (int i = 0; i < lit; i++) l = max(l, glow(mages[i], %f));
	vec3 shine = vec3(0.0);
	for (int i = 0; i < flashing; i++) {
		float g = glow(flash_at[i].xy, flash_at[i].z) * flash_at[i].w;
		l = max(l, g);
		shine += flash_color[i] * g;
	}
	float a = night * (1.0 - l);
	COLOR = vec4(vec3(0.01, 0.02, 0.06) * a + shine, a);
}
""" % [maxi(lamps.size(), 1), MAGES_LIT, LIGHTS, LIGHTS, maxi(lamps.size(), 1), LAMP_LIGHT, MAGE_LIGHT]
	night.material = ShaderMaterial.new()
	night.material.shader = dark
	night.material.set_shader_parameter("lamps", PackedVector2Array(lamps if lamps else [Vector2(-1e5, -1e5)]))  # a GLSL array is never empty
	night.material.set_shader_parameter("night", NIGHT)
	add_child(night)
	above_img = above.texture.get_image()
	walk_all()  # walked now rather than at the first wave's spawn
	# The mouse is a staff while the run's map is up: its gem, mirrored to the top left, points.
	var staff: Image = load("res://assets/icons/staff_crystal.png").get_image()
	staff.flip_x()
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(staff), Input.CURSOR_ARROW, Vector2(6, 6))


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


func _process(delta: float) -> void:
	clock += delta
	var cam := get_viewport().get_camera_2d()
	var mage: Vector2 = cam.get_parent().global_position if cam else Vector2(-1e4, -1e4)
	above.material.set_shader_parameter("mage", mage / RECT.size)
	halo = move_toward(halo, 1.0 if under(mage) else 0.0, delta * 6.0)
	above.material.set_shader_parameter("on", halo)
	var mages := PackedVector2Array(get_tree().get_nodes_in_group("players").slice(0, MAGES_LIT).map(func(p): return p.global_position))
	night.material.set_shader_parameter("lit", mages.size())
	mages.resize(MAGES_LIT)
	night.material.set_shader_parameter("mages", mages)
	flashes = flashes.filter(func(f): return clock < f[3] + f[4]).slice(-LIGHTS)
	var at := PackedVector4Array()
	var colors := PackedVector3Array()
	for f in flashes:  # growing from a third of its radius, fading
		var t: float = (clock - f[3]) / f[4]
		at.append(Vector4(f[0].x, f[0].y, f[1] * (0.3 + 0.7 * sqrt(t)), (1.0 - t) * (1.0 - t)))
		colors.append(Vector3(f[2].r, f[2].g, f[2].b))
	var spells := get_tree().get_nodes_in_group("spells")
	if spells.size() > LIGHTS - at.size():
		spells.sort_custom(func(a, b): return a.global_position.distance_squared_to(mage) < b.global_position.distance_squared_to(mage))
	for b in spells:  # their own color, dimmer, a zone's over its area; a beam's along its arc, uncolored and narrow (its points overlap: their colors summed to white)
		var beam: bool = b.body.shape == "beam"
		var r := BEAM_LIGHT if beam else maxf(b.body.size * (1.3 if b.body.shape == "zone" else 3.5), SPELL_LIGHT)
		for p in (b.lit if beam and b.lit else [b.global_position]):
			if at.size() < LIGHTS:
				at.append(Vector4(p.x, p.y, r, b.modulate.a))
				colors.append(Vector3.ZERO if beam else Vector3(b.color.r, b.color.g, b.color.b) * 0.6)
	night.material.set_shader_parameter("flashing", at.size())
	at.resize(LIGHTS)
	colors.resize(LIGHTS)
	night.material.set_shader_parameter("flash_at", at)
	night.material.set_shader_parameter("flash_color", colors)


## A burst of light on the ground at `at` (an explosion, a level-up), over the
## night: growing to radius, fading out over time s of game time; color is the
## light it adds at its heart (darker, dimmer).
static func flash(at: Vector2, radius: float, time: float, color := Color(1.0, 0.7, 0.3)) -> void:
	flashes.append([at, radius, color, clock, time])


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


## Where a monster of radius r comes out: never in a mage's view (views,
## grown by a monster's size), and only where it fits a way to the mages (its
## size's walkable grid). A random open grave off every view, else a random
## spot of that ground off every view, else the spot of it farthest from them.
static func spawn_point(seen: Array, r := 16.0) -> Vector2:
	var hidden := func(v: Vector2): return not seen.any(func(rect): return rect.grow(48.0).has_point(v))
	var grid: Dictionary = _grid(r)
	var snap := func(v: Vector2):  # a grave on its grid, or the grid's nearest cell to it (a boss beside a narrow grave)
		var c: Variant = _on_grid(v, r)
		return null if c == null else v if grid.links.has(Vector2i((v / CELL).floor())) else (Vector2(c) + Vector2(0.5, 0.5)) * CELL
	var graves: Array = spawns.map(func(s): return snap.call(Vector2(s[0], s[1]))).filter(func(v): return v != null)
	var shown: Array = graves.filter(hidden)
	if shown:
		return shown.pick_random() + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	var free: Array = grid.ground.filter(hidden)
	if free:
		return free.pick_random()
	var away := func(v: Vector2): return seen.map(func(rect): return rect.get_center().distance_to(v)).min() if seen else 0.0
	var all: Array = graves + grid.ground
	all.sort_custom(func(a, b): return away.call(a) > away.call(b))
	return all[0] if all else START


const CELL := 24.0  # the walkable grid's step
## The movers' sizes a grid is walked for: a mover uses the first at least its
## radius (pickups and mages 16, monsters 24, bosses 60).
const SIZES := [16.0, 24.0, 60.0]
static var _grids := {}  # size -> {ground: [Vector2], links: {cell: [Vector2i]}, fields: {target cell: {cell: steps}}, near: {cell: its nearest grid cell}}
static var _grids_of: Array = []  # the polygons they were walked on


## The ground a mover of radius r reaches from the start, one point every
## CELL: a monster put anywhere else (out of bounds, a closed pen, a gap
## narrower than it) would be stuck there.
static func walkable(r := 16.0) -> Array:
	return _grid(r).ground


## Every size's grid, walked now (about a second each).
static func walk_all() -> void:
	for r in SIZES:
		_grid(r)


## The size class of radius r.
static func _size(r: float) -> float:
	for s in SIZES:
		if r <= s:
			return s
	return SIZES[-1]


## The walkable grid for a mover of radius r: walked once per map and size (a
## flood fill from the start, a step free only when its middle and the way
## to it fit the mover).
static func _grid(r: float) -> Dictionary:
	var R := _size(r)
	if _grids_of != polygons:
		_grids_of = polygons
		_grids = {}
	if _grids.has(R):
		return _grids[R]
	var size := Vector2i((RECT.size / CELL).ceil())
	var center := func(c: Vector2i): return (Vector2(c) + Vector2(0.5, 0.5)) * CELL
	var memo := {}
	var free := func(v: Vector2): return RECT.grow(-R).has_point(v) and slide(v, Vector2.ZERO, R) == v
	var free_cell := func(c: Vector2i):
		if not memo.has(c):
			memo[c] = c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y and free.call(center.call(c))
		return memo[c]
	var first := Vector2i((START / CELL).floor())
	var ring := 0
	while not free_cell.call(first) and ring < 8:  # a big mover may not fit right at the start: the nearest cell it does
		ring += 1
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if not free_cell.call(first) and free_cell.call(first + Vector2i(dx, dy)):
					first += Vector2i(dx, dy)
	var links := {first: []}
	var ground := []
	var todo := [first]
	while todo:
		var c: Vector2i = todo.pop_back()
		if free_cell.call(c):
			ground.append(center.call(c))
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n in links.get(c, []) or not free_cell.call(n) or not free.call((center.call(c) + center.call(n)) / 2.0):
				continue
			if not links.has(n):
				links[n] = []
				todo.append(n)
			links[c].append(n)
			links[n].append(c)
	_grids[R] = {"ground": ground, "links": links, "fields": {}, "near": {}}
	return _grids[R]


## Which way a mover of radius r at `from` walks to reach `to` around the
## walls: straight at it when its size's grid between them is open, else down
## a flow field (steps to to's cell over that grid, walked once per cell the
## target stands in). A target where its size never goes (a mage in streets
## too narrow for a boss): to the grid's cell nearest it, not straight into a wall.
static func way(from: Vector2, to: Vector2, r := 16.0) -> Vector2:
	var grid: Dictionary = _grid(r)
	var links: Dictionary = grid.links
	var fields: Dictionary = grid.fields
	var goal: Variant = _nearest(to, r)
	var at: Variant = _nearest(from, r)
	if goal == null or at == null or _open(from, to, links):
		return (to - from).normalized()
	if not fields.has(goal):
		if fields.size() > 16:  # ponytail: drops every field at once, an LRU if mages hop cells faster than that
			fields.clear()
		var dist := {goal: 0}
		var todo := [goal]
		var i := 0
		while i < todo.size():  # a BFS: every link is one step
			var c: Vector2i = todo[i]
			i += 1
			for n in links[c]:
				if not dist.has(n):
					dist[n] = dist[c] + 1
					todo.append(n)
		fields[goal] = dist
	var field: Dictionary = fields[goal]
	if not field.has(at):
		return (to - from).normalized()
	# Down the field: toward the farthest cell of its path still in the open, so it cuts diagonals.
	var aim: Vector2i = at
	var c: Vector2i = at
	for k in 6:
		var next := c
		for n in links[c]:
			if field.get(n, 1 << 30) < field.get(next, 1 << 30):
				next = n
		if next == c:
			break
		c = next
		if not _open(from, (Vector2(c) + Vector2(0.5, 0.5)) * CELL, links):
			break
		aim = c
	if aim == at:  # its next cell is round a corner: to it
		aim = c
	var dir := (Vector2(aim) + Vector2(0.5, 0.5)) * CELL - from
	return dir.normalized() if dir.length() > 1.0 else (to - from).normalized()


## The cell of radius r's grid at pos, or the nearest one around it (a mover
## against a wall, a mage in a gap too narrow for a boss, stands where the
## grid is not), or null.
static func _on_grid(pos: Vector2, r := 16.0) -> Variant:
	var links: Dictionary = _grid(r).links
	var c := Vector2i((pos / CELL).floor())
	if links.has(c):
		return c
	var reach := ceili(_size(r) / CELL)  # a bigger mover's grid stops farther from the walls
	var best: Variant = null
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var n := c + Vector2i(dx, dy)
			if links.has(n) and (best == null or pos.distance_to((Vector2(n) + Vector2(0.5, 0.5)) * CELL) < pos.distance_to((Vector2(best) + Vector2(0.5, 0.5)) * CELL)):
				best = n
	return best


## _on_grid, else the grid's cell nearest pos anywhere (cached per cell), or null (no grid).
static func _nearest(pos: Vector2, r := 16.0) -> Variant:
	var c: Variant = _on_grid(pos, r)
	if c != null:
		return c
	var grid: Dictionary = _grid(r)
	var cell := Vector2i((pos / CELL).floor())
	if not grid.near.has(cell):
		var best: Variant = null
		for n in grid.links:
			if best == null or (n - cell).length_squared() < (best - cell).length_squared():
				best = n
		grid.near[cell] = best
	return grid.near[cell]


## Whether the straight line from a to b crosses only cells of the grid (links).
static func _open(a: Vector2, b: Vector2, links: Dictionary) -> bool:
	var n := ceili(a.distance_to(b) / (CELL / 3.0))
	for k in range(1, n):
		if not links.has(Vector2i((a.lerp(b, float(k) / n) / CELL).floor())):
			return false
	return true


static func _boxes(polys: Array) -> Array:
	return polys.map(func(poly):
		var b := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			b = b.expand(v)
		return b)


## How far `me` moves to get out of the living `others` (nodes with position,
## radius and hp) it overlaps: half of each overlap, the other one moving the
## other half on its own turn. Feed it to slide, to stay off the walls.
## ponytail: O(n) per mover, O(n²) a frame; a spatial grid if the crowds grow past ~200.
static func apart(me: Node2D, others: Array) -> Vector2:
	var out := Vector2.ZERO
	for o in others:
		if o == me or o.hp <= 0.0:
			continue
		var d: Vector2 = me.position - o.position
		var min_d: float = me.radius + o.radius
		if d.length_squared() < min_d * min_d:
			out += (d.normalized() if d else Vector2.from_angle(me.get_instance_id())) * (min_d - d.length()) * 0.5
	return out


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
