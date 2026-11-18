class_name SpellBody
extends Node2D
## Runtime of one emitted body (bolt or zone). Reads a sanitized body dict.
## Targets are nodes in the "enemies" group exposing: radius,
## take_damage(amount), add_status(name, power, duration), push(velocity).
## The caster exposes heal(amount).

var body: Dictionary
var caster: Node2D
var spell: Dictionary  # the whole spell: color and palette for the art
var color: Color
var anim: Array = []  # [texture, sheet] from SpellArt.animation, or [] (no art)
var dir := Vector2.RIGHT
var speed := 0.0
var age := 0.0
var pierce_left := 0
var bounce_left := 0
var tick_timer := 0.0
var hit_ids := {}
var origin := Vector2.ZERO
var wave_phase := 0.0
var homing := false  # auto-aim: no lifetime, see _physics_process
var depth := 0  # 0 = cast by the player, n = sub-cast n levels deep
var anchor := Vector2.ZERO  # beam / cone: offset from the caster, kept while it moves
var struck := false  # beam / cone: strike once, when cast
var target: Node2D  # beam: the enemy the arc grips

const ABOVE_DECOR := 11  # over the map's trees, roofs and statues (Arena.above, z 10)
const GROUND := -1  # zones and sub-casts (a hit's effects): under the mages, enemies and obstacles, over the floor


## Emit an "emit" dict from pos toward dir. Bursts are spread over time.
static func cast(emit: Dictionary, pos: Vector2, aim: Vector2, owner_node: Node2D, spell: Dictionary, world: Node, depth := 0) -> void:
	var dirs := _directions(emit, pos, aim, world)
	for i in dirs.size():
		if i > 0 and emit.burst_delay > 0.0:
			await world.get_tree().create_timer(emit.burst_delay).timeout
			if not is_instance_valid(world):
				return
		var b := _channeled(emit.body, owner_node, depth, world)
		if b:  # a channel tick renews the live arc / cone: one on screen, not a stack
			b.age = 0.0
			b.struck = false
			b.dir = dirs[i]
			b.position = pos
			SpellSound.play(spell, emit.body, depth, b, world)
			continue
		b = SpellBody.new()
		b.body = emit.body
		b.caster = owner_node
		b.spell = spell
		b.dir = dirs[i]
		b.position = pos
		b.depth = depth
		world.add_child(b)
		# One sound per emit; each body of a timed burst gets its own one-shot.
		if i == 0 or (emit.burst_delay > 0.0 and not SpellSound.is_continuous(emit.body)):
			SpellSound.play(spell, emit.body, depth, b, world)


static func _channeled(body: Dictionary, owner_node: Node2D, depth: int, world: Node) -> SpellBody:
	if body.shape not in ["beam", "cone"]:
		return null
	for n in world.get_children():
		if n is SpellBody and is_same(n.body, body) and n.caster == owner_node \
				and n.depth == depth and not n.is_queued_for_deletion():
			return n
	return null


static func _directions(emit: Dictionary, pos: Vector2, aim: Vector2, world: Node) -> Array:
	var n: int = emit.count
	var base := aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	if emit.pattern == "nearest":
		var e := nearest_enemy(world, pos, {})
		if e:
			base = (e.global_position - pos).normalized()
	var out := []
	for i in n:
		var a := 0.0
		match emit.pattern:
			"radial":
				a = TAU * i / n
			"random":
				a = deg_to_rad(randf_range(-emit.spread, emit.spread) / 2.0)
			_:
				a = 0.0 if n == 1 else deg_to_rad(emit.spread) * (float(i) / (n - 1) - 0.5)
		out.append(base.rotated(a))
	return out


static func nearest_enemy(world: Node, pos: Vector2, exclude: Dictionary) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in world.get_tree().get_nodes_in_group("enemies"):
		if exclude.has(e.get_instance_id()):
			continue
		var d := pos.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _ready() -> void:
	# Only the cast projectile flies over the decor; zones and sub-casts stay on the ground, under the movers.
	z_index = ABOVE_DECOR if depth == 0 and body.shape != "zone" else GROUND
	speed = body.speed
	pierce_left = body.pierce
	bounce_left = body.bounce
	origin = position
	if is_instance_valid(caster):
		anchor = position - caster.global_position
	homing = body.motion.any(func(m): return m.type == "homing" and m.strength > 0.0)
	color = Color.html(spell.color)
	if spell.get("weak"):  # the failsafe of a spell over the max mana (Upgrades.weakened)
		modulate.a = 0.45
	anim = SpellArt.animation(spell, body)
	var dot := SpellArt.texture(body.particle, spell.palette)
	if dot and body.sheet.is_empty():
		var p := CPUParticles2D.new()
		p.texture = dot
		p.amount = 10
		p.lifetime = 0.35
		p.local_coords = false
		p.gravity = Vector2.ZERO
		p.spread = 180.0
		p.initial_velocity_min = 10.0
		p.initial_velocity_max = 40.0
		p.scale_amount_min = SpellArt.PIXEL
		p.scale_amount_max = SpellArt.PIXEL
		add_child(p)


func _physics_process(delta: float) -> void:
	age += delta
	# Auto-aim bolts never time out: they fly until they hit, or leave the
	# map while no enemy is left on it.
	if age >= body.lifetime and not homing:
		_expire()
		return
	if body.shape in ["beam", "cone"]:
		_channel()
	else:
		_move(delta)
	if body.shape == "bolt":
		_check_hits()
	if not body.on_tick.is_empty():
		tick_timer += delta
		if tick_timer >= body.tick_interval:
			tick_timer -= body.tick_interval
			apply_effects(body.on_tick, global_position, null)
	queue_redraw()


func _move(delta: float) -> void:
	var offset := Vector2.ZERO
	for m in body.motion:
		match m.type:
			"homing":
				var e := nearest_enemy(get_parent(), global_position, hit_ids)
				if e:
					var want := (e.global_position - global_position).angle()
					dir = dir.rotated(clampf(angle_difference(dir.angle(), want), -1, 1) * m.strength * 3.0 * delta)
			"accelerate":
				speed = maxf(0.0, speed + m.strength * 300.0 * delta)
			"boomerang":
				if age > body.lifetime / 2.0 and is_instance_valid(caster):
					dir = (caster.global_position - global_position).normalized()
			"wave":
				wave_phase += delta * 10.0
				offset += dir.orthogonal() * cos(wave_phase) * m.strength * 4.0
			"orbit":
				if is_instance_valid(caster):
					var r := maxf(30.0, speed)  # orbit: speed is the orbit radius
					var a: float = age * m.strength * 3.0 + dir.angle()
					position = caster.global_position + Vector2.from_angle(a) * r
					return
	position += dir * speed * delta + offset
	if homing:
		if global_position.distance_to(origin) > 1500.0 \
				and get_tree().get_nodes_in_group("enemies").is_empty():
			queue_free()
	elif global_position.distance_to(origin) > 1500.0:  # about off-screen
		queue_free()


## Beam and cone stay on the caster and strike once, when cast: a channeled
## spell is recast every `cooldown`, so each cast is one tick (and costs mana).
## Cast by the player, they follow its aim and its staff's gem every frame (the
## arc re-grips too).
func _channel() -> void:
	if is_instance_valid(caster):
		var aim: Variant = caster.get("aim")
		if depth == 0 and aim is Vector2 and aim != Vector2.ZERO:
			dir = aim.normalized()
			anchor = dir * anchor.length()
		global_position = caster.gem() if depth == 0 and caster.has_method("gem") else caster.global_position + anchor
	if struck:
		if body.shape == "beam":
			target = _beam_target()
		return
	struck = true
	if body.shape == "beam":
		target = _beam_target()
		if target:
			apply_effects(body.on_hit, global_position, target)
	else:
		for e in get_tree().get_nodes_in_group("enemies"):
			if _in_reach(e):
				apply_effects(body.on_hit, global_position, e)


## Within `speed` px and `angle` degrees (full width) around the aim.
func _in_reach(e: Node2D) -> bool:
	var to := e.global_position - global_position
	return to.length() <= body.speed + e.radius \
		and absf(angle_difference(dir.angle(), to.angle())) <= deg_to_rad(body.angle) / 2.0


## Each cast (tick) the arc grips the enemy in reach that is both nearest and
## closest to the aim: no lock. At the angle's edge an enemy counts as twice as far.
func _beam_target() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	var half := maxf(deg_to_rad(body.angle) / 2.0, 0.001)
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - global_position
		var score: float = to.length() * (1.0 + absf(angle_difference(dir.angle(), to.angle())) / half)
		if score < best_score and _in_reach(e):
			best_score = score
			best = e
	return best


func _check_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if hit_ids.has(e.get_instance_id()):
			continue
		if global_position.distance_to(e.global_position) > body.size + e.radius:
			continue
		hit_ids[e.get_instance_id()] = true
		apply_effects(body.on_hit, global_position, e)
		if pierce_left > 0:
			pierce_left -= 1
		elif bounce_left > 0:
			bounce_left -= 1
			var next := nearest_enemy(get_parent(), global_position, hit_ids)
			if next:
				dir = (next.global_position - global_position).normalized()
		else:
			_expire()
		return


func _expire() -> void:
	if is_queued_for_deletion():
		return
	apply_effects(body.on_expire, global_position, null)
	var burst := SpellArt.sheet(spell, body.burst_sheet.get("file", ""))
	if burst:  # one-shot by convention, whatever its "loop" says
		var fx := Burst.new()
		fx.tex = burst
		fx.s = body.burst_sheet.merged({"loop": false}, true)
		fx.position = position
		fx.z_index = z_index
		get_parent().add_child(fx)
	queue_free()


func apply_effects(list: Array, pos: Vector2, target: Node2D) -> void:
	for f in list:
		if f.type == "knockback" and f.force > 0.0:
			_repel_shots(f.get("radius", 0.0), pos, f.force)
		if f.type != "cast" and not multiplayer.is_server():
			continue  # coop: the host applies effects, peers only draw
		match f.type:
			"heal":
				if is_instance_valid(caster):
					caster.heal(f.amount)
			"cast":
				SpellBody.cast(f.emit, pos, dir, caster, spell, get_parent(), depth + 1)
			_:
				for e in _targets(f.get("radius", 0.0), pos, target):
					match f.type:
						"damage": e.take_damage(f.amount)
						"status": e.add_status(f.status, f.power, f.duration)
						"knockback": e.push((e.global_position - pos).normalized() * f.force)


## A repelling knockback also turns enemy shots (Enemy.Shot) in reach away from
## `pos`, same speed. Run on every peer: shots are local, their hits host-side.
func _repel_shots(radius: float, pos: Vector2, force: float) -> void:
	if radius <= 0.0:
		if body.shape != "zone":
			return  # a single-target hit
		radius = body.size
	for s in get_tree().get_nodes_in_group("shots"):
		var away: Vector2 = s.position - pos
		if away.length() <= radius + s.RADIUS and s.velocity.dot(away) < 0.0:
			s.velocity = away.normalized() * maxf(s.velocity.length(), force)


func _targets(radius: float, pos: Vector2, target: Node2D) -> Array:
	if radius <= 0.0:
		if body.shape == "zone":
			radius = body.size  # a zone's own area
		else:
			return [target] if is_instance_valid(target) else []
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if pos.distance_to(e.global_position) <= radius + e.radius:
			out.append(e)
	return out


func _draw() -> void:
	if body.shape == "beam":
		_draw_arc()
	elif body.shape == "cone":
		_draw_cone()
	elif anim:  # bolts face their direction (sheets are drawn facing right)
		var zone: bool = body.shape == "zone"
		SpellArt.draw_sheet(self, anim[0], anim[1], age, 0.0 if zone else dir.angle(),
			body.size * 2.0 if zone else 0.0)
	elif body.shape == "zone":
		draw_circle(Vector2.ZERO, body.size, Color(color, 0.25))
		draw_arc(Vector2.ZERO, body.size, 0, TAU, 32, color, 2.0)
	else:
		draw_circle(Vector2.ZERO, body.size, color)
		draw_circle(-dir * body.size * 1.2, body.size * 0.6, Color(color, 0.4))


## An electric arc leaving along the aim and bending in a circle arc onto the
## gripped enemy, or straight into the void at full reach (off-screen). Its
## shimmer is a smooth function of time, so successive casts line up.
func _draw_arc() -> void:
	var end: Vector2 = target.global_position - global_position if is_instance_valid(target) else dir * body.speed
	# Quadratic Bezier whose control point sits where the aim meets the end
	# tangent of a circle arc: tangent to the aim at the staff.
	var cos_a := maxf(0.3, cos(angle_difference(dir.angle(), end.angle())))
	var ctrl := dir * end.length() / (2.0 * cos_a)
	var side := end.orthogonal().normalized()
	var t := Arena.clock
	var n := maxi(8, int(end.length() / 12.0))
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / n
		var p := ctrl * 2.0 * u * (1.0 - u) + end * u * u
		pts.append(p + side * sin(u * PI) * 3.0 * sin(u * 23.0 - t * 30.0))
	draw_polyline(pts, Color(color, 0.3), 7.0, true)
	draw_polyline(pts, color, 3.0, true)
	draw_polyline(pts, Color.WHITE, 1.0, true)


## The cone's sheet (apex on its left edge) stretched over the area it hurts;
## no sheet: a flickering polygon.
func _draw_cone() -> void:
	var half := deg_to_rad(maxf(body.angle, 4.0)) / 2.0
	if anim:
		var s: Dictionary = anim[1]
		var i := int(Arena.clock * s.fps) % int(s.frames)  # the clock: ticks renew age, not the animation
		var h: float = 2.0 * body.speed * tan(minf(half, 1.4))
		draw_set_transform(Vector2.ZERO, dir.angle())
		draw_texture_rect_region(anim[0], Rect2(0, -h / 2.0, body.speed, h), Rect2(i * s.size, 0, s.size, s.size))
		return
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		pts.append(dir.rotated(lerpf(-half, half, i / 8.0)) * body.speed * randf_range(0.85, 1.0))
	draw_colored_polygon(pts, Color(color, 0.35))
	for i in 12:
		draw_circle(dir.rotated(randf_range(-half, half)) * body.speed * randf(), 2.0, Color(Color.WHITE, 0.8))


## One-shot impact animation from the bundle.
class Burst extends Node2D:
	var tex: Texture2D
	var s: Dictionary
	var age := 0.0

	func _process(delta: float) -> void:
		age += delta
		if age * s.fps >= s.frames:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		SpellArt.draw_sheet(self, tex, s, age, 0.0)
