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


## Emit an "emit" dict from pos toward dir. Bursts are spread over time.
static func cast(emit: Dictionary, pos: Vector2, aim: Vector2, owner_node: Node2D, spell: Dictionary, world: Node, depth := 0) -> void:
	var dirs := _directions(emit, pos, aim, world)
	for i in dirs.size():
		if i > 0 and emit.burst_delay > 0.0:
			await world.get_tree().create_timer(emit.burst_delay).timeout
			if not is_instance_valid(world):
				return
		var b := SpellBody.new()
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
	speed = body.speed
	pierce_left = body.pierce
	bounce_left = body.bounce
	origin = position
	if is_instance_valid(caster):
		anchor = position - caster.global_position
	homing = body.motion.any(func(m): return m.type == "homing" and m.strength > 0.0)
	color = Color.html(spell.color)
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
		if not get_viewport_rect().has_point(global_position) \
				and get_tree().get_nodes_in_group("enemies").is_empty():
			queue_free()
	elif not get_viewport_rect().grow(200).has_point(global_position):
		queue_free()


## Beam and cone stay on the caster and strike once, when cast: a channeled
## spell is recast every `cooldown`, so each cast is one tick (and costs mana).
func _channel() -> void:
	if is_instance_valid(caster):
		global_position = caster.global_position + anchor
	if struck:
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


## The arc grips its last target while it stays in reach, else the nearest one.
func _beam_target() -> Node2D:
	var last: Variant = caster.get_meta("beam_target") if is_instance_valid(caster) and caster.has_meta("beam_target") else null
	if is_instance_valid(last) and _in_reach(last):
		return last
	var best: Node2D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if _in_reach(e) and (not best or global_position.distance_squared_to(e.global_position)
				< global_position.distance_squared_to(best.global_position)):
			best = e
	if is_instance_valid(caster):
		caster.set_meta("beam_target", best)
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
		get_parent().add_child(fx)
	queue_free()


func apply_effects(list: Array, pos: Vector2, target: Node2D) -> void:
	for f in list:
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
		SpellArt.draw_sheet(self, anim[0], anim[1], age, dir.angle() if body.shape == "bolt" else 0.0)
	elif body.shape == "zone":
		draw_circle(Vector2.ZERO, body.size, Color(color, 0.25))
		draw_arc(Vector2.ZERO, body.size, 0, TAU, 32, color, 2.0)
	else:
		draw_circle(Vector2.ZERO, body.size, color)
		draw_circle(-dir * body.size * 1.2, body.size * 0.6, Color(color, 0.4))


## A jagged electric arc to the gripped enemy, or into the void at full reach.
## Redrawn every frame, so it crackles.
func _draw_arc() -> void:
	var end: Vector2 = target.global_position - global_position if is_instance_valid(target) else dir * body.speed
	var side := end.orthogonal().normalized()
	var n := maxi(2, int(end.length() / 16.0))
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in range(1, n):
		pts.append(end * i / n + side * randf_range(-9.0, 9.0))
	pts.append(end)
	draw_polyline(pts, Color(color, 0.3), 7.0)
	draw_polyline(pts, color, 3.0)
	draw_polyline(pts, Color.WHITE, 1.0)


func _draw_cone() -> void:
	var half := deg_to_rad(maxf(body.angle, 4.0)) / 2.0
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
