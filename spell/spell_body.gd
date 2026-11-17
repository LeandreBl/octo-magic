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
var frames: Array[Texture2D] = []
var art_scale := 1
var dir := Vector2.RIGHT
var speed := 0.0
var age := 0.0
var pierce_left := 0
var bounce_left := 0
var tick_timer := 0.0
var hit_ids := {}
var origin := Vector2.ZERO
var wave_phase := 0.0


## Emit an "emit" dict from pos toward dir. Bursts are spread over time.
static func cast(emit: Dictionary, pos: Vector2, aim: Vector2, owner_node: Node2D, spell: Dictionary, world: Node) -> void:
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
		world.add_child(b)


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
	color = Color.html(spell.color)
	for f in body.sprite:
		frames.append(SpellArt.texture(f, spell.palette))
	if not frames.is_empty():
		art_scale = SpellArt.scale_for(frames[0], body.size * 2.0)
	var dot := SpellArt.texture(body.particle, spell.palette)
	if dot:
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
	if age >= body.lifetime:
		_expire()
		return
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
	if not get_viewport_rect().grow(200).has_point(global_position):
		queue_free()


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
	queue_free()


func apply_effects(list: Array, pos: Vector2, target: Node2D) -> void:
	for f in list:
		match f.type:
			"heal":
				if is_instance_valid(caster):
					caster.heal(f.amount)
			"cast":
				SpellBody.cast(f.emit, pos, dir, caster, spell, get_parent())
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
	if not frames.is_empty():
		var tex: Texture2D = frames[int(age * 8.0) % frames.size()]
		var rot := dir.angle() if body.shape == "bolt" else 0.0
		draw_set_transform(Vector2.ZERO, rot, Vector2.ONE * art_scale)
		draw_texture(tex, -tex.get_size() / 2.0)
	elif body.shape == "zone":
		draw_circle(Vector2.ZERO, body.size, Color(color, 0.25))
		draw_arc(Vector2.ZERO, body.size, 0, TAU, 32, color, 2.0)
	else:
		draw_circle(Vector2.ZERO, body.size, color)
		draw_circle(-dir * body.size * 1.2, body.size * 0.6, Color(color, 0.4))
