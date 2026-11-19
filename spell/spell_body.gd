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
var links: Array = []  # beam: the enemies the arc jumps on to from its target (the caster's "chain" stat)
var index := 0  # beam / cone: which body of its emit (count > 1: one arc / cone each)
var turn := 0.0  # beam / cone: its angle off the caster's aim (spread, radial...)
var ember_timer := 0.0  # bolt: time since its last ember (the caster's "embers" stat)
var born := 0.0  # Arena.clock when added: a cone sends its waves from then on

const BURN_TIME := 3.0  # s: how long an immolated enemy burns after the bolt
const CONE_ALPHA := 0.9  # a cone wave's peak opacity: a cold wind, the enemies seen through it
const CONE_WAVES := 4  # cone waves in flight at once
const CONE_TRAVEL := 0.4  # s: a cone wave's flight from the staff to the reach
const CHILL_TIME := 1.0  # s: how long a chilled enemy stays slowed after the cone
const FREEZE_TIME := 0.6  # s: how long a Rigor freeze holds an enemy
const STUN_TIME := 0.6  # s: how long a Stupor stun holds an enemy
const CHAIN_REACH := 140.0  # px: how far a chained arc jumps from one enemy to the next
const EMBER_EVERY := 0.12  # s: a cast bolt drops one ember this often (Embers)
const BLAST := preload("res://assets/monsters/fx/boss_explosion.png")  # Displosio (_explode)
const BLOOD := preload("res://assets/monsters/fx/blood.png")  # a hit's splash (_bleed)
const BLOOD_SIZE := 14.0  # px: the splash's width on screen
const BLOOD_TIME := 0.35  # s: its fade-out
const ABOVE_DECOR := 11  # over the map's trees, roofs and statues (Arena.above, z 10)
const GROUND := -1  # zones and sub-casts (a hit's effects): under the mages, enemies and obstacles, over the floor


## Emit an "emit" dict from pos toward dir. Bursts are spread over time.
static func cast(emit: Dictionary, pos: Vector2, aim: Vector2, owner_node: Node2D, spell: Dictionary, world: Node, depth := 0) -> void:
	var dirs := _directions(emit, pos, aim, world)
	var base := aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	for i in dirs.size():
		if i > 0 and emit.burst_delay > 0.0:
			await world.get_tree().create_timer(emit.burst_delay).timeout
			if not is_instance_valid(world):
				return
		var b := _channeled(emit.body, owner_node, depth, i, spell, world)
		if b:  # a channel tick renews the live arc / cone: one on screen, not a stack
			b.body = emit.body  # this tick's damage (a crit, Vis Teli, short of mana)
			b.spell = spell
			b.modulate.a = spell.get("weak", 1.0)
			b.age = 0.0
			b.struck = false
			b.dir = dirs[i]
			b.turn = base.angle_to(dirs[i])
			b.position = pos
			SpellSound.play(spell, emit.body, depth, b, world)
			continue
		b = SpellBody.new()
		b.body = emit.body
		b.caster = owner_node
		b.spell = spell
		b.dir = dirs[i]
		b.turn = base.angle_to(dirs[i])
		b.index = i
		b.position = pos
		b.depth = depth
		world.add_child(b)
		# One sound per emit; each body of a timed burst gets its own one-shot.
		if i == 0 or (emit.burst_delay > 0.0 and not SpellSound.is_continuous(emit.body)):
			SpellSound.play(spell, emit.body, depth, b, world)


## The live arc / cone of this spell's body: matched by spell id, not by dict,
## as a crit or Vis Teli tick casts a scaled copy (Spell.scale_damage).
static func _channeled(body: Dictionary, owner_node: Node2D, depth: int, index: int, spell: Dictionary, world: Node) -> SpellBody:
	if body.shape not in ["beam", "cone"]:
		return null
	for n in world.get_children():
		if n is SpellBody and n.body.shape == body.shape and n.spell.get("id") == spell.get("id") and n.caster == owner_node \
				and n.depth == depth and n.index == index and not n.is_queued_for_deletion():
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
	born = Arena.clock
	if is_instance_valid(caster):
		anchor = position - caster.global_position
	homing = body.motion.any(func(m): return m.type == "homing" and m.strength > 0.0)
	color = Color.html(spell.color)
	if spell.has("weak"):  # cast short of mana (Spell.weakened): 1 % of damage, 1 % visible
		modulate.a = spell.weak
	anim = SpellArt.animation(spell, body)
	if body.shape == "beam":  # gripped before its first draw: no straight arc for a frame
		target = _beam_target()
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
		if depth == 0:
			_drop_embers(delta)
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
					var diff := angle_difference(dir.angle(), (e.global_position - global_position).angle())
					# Turn rate grows with speed (turning radius about 50 px /
					# strength), so fast bolts don't circle a target inside it.
					var rate: float = m.strength * maxf(3.0, speed / 50.0)
					dir = dir.rotated(clampf(clampf(diff, -1, 1) * rate * delta, -absf(diff), absf(diff)))
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
	# Released: after its strike, the arc / cone stops at once, not at the end
	# of its lifetime. ponytail: any held slot keeps it, per-slot if a mage gets two channels.
	var firing: Variant = caster.get("firing") if struck and depth == 0 and is_instance_valid(caster) else null
	if firing is Dictionary and not firing.values().has(true):
		queue_free()
		return
	if is_instance_valid(caster):
		var aim: Variant = caster.get("aim")
		if depth == 0 and aim is Vector2 and aim != Vector2.ZERO:
			dir = aim.normalized().rotated(turn)
			anchor = dir * anchor.length()
		global_position = caster.gem() if depth == 0 and caster.has_method("gem") else caster.global_position + anchor
	if struck:
		if body.shape == "beam":
			target = _beam_target()
			links = _chain()
		return
	struck = true
	if body.shape == "beam":
		target = _beam_target()
		links = _chain()
		var from := global_position
		for e in ([target] if target else []) + links:
			apply_effects(body.on_hit, e.global_position if e != target else global_position, e)
			_stun(e)
			_bleed(e, from)
			from = e.global_position
	else:
		var gust := _stat("gust")  # Procella (Upgrades "hurricane"): an engine stat, not spell data
		for e in get_tree().get_nodes_in_group("enemies"):
			if _in_reach(e):
				apply_effects(body.on_hit, global_position, e)
				if gust > 0.0 and multiplayer.is_server():
					e.push((e.global_position - global_position).normalized() * gust)
				_chill(e)
				_harden(e)
				_bleed(e, global_position)
		if gust > 0.0:  # Procella also turns the shots (archers' arrows...) in the cone away; every peer, as _repel_shots
			var k := _cone_scale()
			for s in get_tree().get_nodes_in_group("shots"):
				var away: Vector2 = s.position - global_position
				if away.length() <= body.speed * k + s.RADIUS and s.velocity.dot(away) < 0.0 \
						and absf(angle_difference(dir.angle(), away.angle())) <= deg_to_rad(body.angle) * k / 2.0:
					s.velocity = away.normalized() * maxf(s.velocity.length(), gust)


## Within `speed` px and `angle` degrees (full width) around the aim; a cone
## scaled by its caster's "cone" stat.
func _in_reach(e: Node2D) -> bool:
	var to := e.global_position - global_position
	var k := _cone_scale()
	return to.length() <= body.speed * k + e.radius \
		and absf(angle_difference(dir.angle(), to.angle())) <= deg_to_rad(body.angle) * k / 2.0


## The Conus Glaciei skill (Upgrades "cone_of_ice"): a cone's reach and width
## times its caster's "cone" stat. An engine stat, not spell data: no forged spell has it.
func _cone_scale() -> float:
	return maxf(_stat("cone"), 1.0) if body.shape == "cone" else 1.0  # no stats: 0, as 1


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


## The Catena skill (Upgrades "chaining"): from its target the arc jumps on to
## the nearest enemy within CHAIN_REACH not yet struck, once per "chain" of
## its caster's stats. An engine stat, not spell data: no forged spell has it.
func _chain() -> Array:
	var n := int(_stat("chain"))
	var out := []
	var hit := {}
	var from := target
	while from and out.size() < n:
		hit[from.get_instance_id()] = true
		var next := nearest_enemy(get_parent(), from.global_position, hit)
		if not next or from.global_position.distance_to(next.global_position) > CHAIN_REACH + next.radius:
			break
		out.append(next)
		from = next
	return out


## Its caster's `key` stat (game/stats.gd), 0 without one. A sub-skill stat
## (Upgrades "spell"): 0 on a weakened cast (short of mana), no sub-skill applies.
func _stat(key: String) -> float:
	var st: Variant = caster.get("stats") if is_instance_valid(caster) and not spell.has("weak") else null
	return float(st.get(key, 0.0)) if st is Dictionary else 0.0


## The Ventus Algidus skill (Upgrades "chill_wind"): a cone slows what it
## strikes by its caster's "chill" stat (a speed fraction) for CHILL_TIME.
## An engine stat, not spell data: no forged spell has it.
func _chill(e: Node2D) -> void:
	var c := _stat("chill")
	if c > 0.0 and multiplayer.is_server():
		e.add_status("slow", 2.0 * c / (1.0 - c), CHILL_TIME)  # Enemy: speed / (1 + power / 2) = speed * (1 - c)


## The Rigor skill (Upgrades "harden"): each cone strike freezes its target
## for FREEZE_TIME with its caster's "harden" stat as chance. An engine stat,
## not spell data: no forged spell has it.
func _harden(e: Node2D) -> void:
	var c := _stat("harden")
	if c > 0.0 and multiplayer.is_server() and randf() < c:
		e.add_status("freeze", 1.0, FREEZE_TIME)


## The Embers skill (Upgrades "embers"): a cast bolt leaves a trail of
## burning embers, small fire zones hurting the enemies on them. An engine
## stat, not spell data: no forged spell has it.
func _drop_embers(delta: float) -> void:
	var dmg := _stat("embers")
	if dmg <= 0.0:
		return
	ember_timer += delta
	if ember_timer < EMBER_EVERY:
		return
	ember_timer -= EMBER_EVERY
	var e := SpellBody.new()
	e.body = Spell._body({"shape": "zone", "size": 14, "lifetime": 2.0, "tick_interval": 0.5,
		"on_tick": [{"type": "damage", "amount": dmg * caster.stats.damage}],
		"sheet": {"file": "fire_pool.png", "size": 104, "frames": 8, "fps": 12}}, 1)
	e.caster = caster
	e.spell = spell.merged({"bundle": "res://assets/monsters/fx"}, true)  # the fire pool art
	e.position = position
	e.depth = 1
	get_parent().add_child(e)


## The Immolatio skill (Upgrades "immolation"): a cast bolt sets what it
## strikes on fire, its caster's "immolate" stat in damage a second for
## BURN_TIME. An engine stat, not spell data: no forged spell has it; none
## from a weakened cast (short of mana).
func _immolate(e: Node2D) -> void:
	var b := _stat("immolate")
	if b > 0.0 and depth == 0 and multiplayer.is_server():
		e.add_status("burn", b, BURN_TIME)


## The Stupor skill (Upgrades "stun"): each arc strike (target and chained
## links) stuns its enemy for STUN_TIME with its caster's "stun" stat as
## chance. An engine stat, not spell data: no forged spell has it.
func _stun(e: Node2D) -> void:
	var c := _stat("stun")
	if c > 0.0 and multiplayer.is_server() and randf() < c:
		e.add_status("stun", 1.0, STUN_TIME)


## The Displosio skill (Upgrades "explode"): Pila Ignea's hit also deals its
## damage to the other enemies within the caster's "explode" px, with the
## PixelLab blast (fx/boss_explosion.png) that wide. Run on every peer for the
## blast, damage host-side. An engine stat, not spell data: no forged spell has it.
func _explode(hit: Node2D) -> void:
	var r := _stat("explode")
	if r <= 0.0 or depth > 0:  # offered only with Pila Ignea (Run.base): its bolts
		return
	var n := BLAST.get_width() / BLAST.get_height()
	var fx := Sprite2D.new()
	fx.texture = BLAST
	fx.hframes = n
	fx.position = position
	fx.z_index = z_index
	fx.scale = Vector2.ONE * r * 2.0 / BLAST.get_height()
	get_parent().add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "frame", n - 1, n / 12.0)  # Enemy.FPS
	tw.tween_callback(fx.queue_free)
	if not multiplayer.is_server():
		return
	for f in body.on_hit:
		if f.type == "damage":
			for e in _targets(r, global_position, null):
				if e != hit:
					e.take_damage(f.amount * _quad())


## A tiny blood splash on the enemy's edge facing `from` (where the spell came
## from), fading out. Every peer: hits are detected on each, effects host-side.
func _bleed(e: Node2D, from: Vector2) -> void:
	var fx := Sprite2D.new()
	fx.texture = BLOOD
	fx.position = e.global_position + (from - e.global_position).limit_length(e.radius * 0.7)
	fx.rotation = randf() * TAU
	fx.scale = Vector2.ONE * BLOOD_SIZE / BLOOD.get_width()
	fx.z_index = ABOVE_DECOR
	get_parent().add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "modulate:a", 0.0, BLOOD_TIME).set_ease(Tween.EASE_IN)
	tw.tween_callback(fx.queue_free)


func _check_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if hit_ids.has(e.get_instance_id()):
			continue
		if global_position.distance_to(e.global_position) > body.size + e.radius:
			continue
		hit_ids[e.get_instance_id()] = true
		apply_effects(body.on_hit, global_position, e)
		_bleed(e, global_position - dir * body.size)
		_immolate(e)
		_explode(e)
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
						"damage": e.take_damage(f.amount * _quad())
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


## Its caster's Quad Damage (game/pickup.gd), 1 without one.
func _quad() -> float:
	var st: Variant = caster.get("statuses") if is_instance_valid(caster) else null
	return st.quad[0] if st is Dictionary and st.has("quad") else 1.0


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
	var from := end
	for e in links:  # Catena: straight jagged arcs from enemy to enemy
		if is_instance_valid(e):
			var to: Vector2 = e.global_position - global_position
			_bolt(PackedVector2Array([from, (from + to) / 2.0 + (to - from).orthogonal().normalized() * 6.0 * sin(Arena.clock * 40.0), to]))
			from = to
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
	_bolt(pts)
	if is_instance_valid(target):
		_glow(end)
	for e in links:
		if is_instance_valid(e):
			_glow(e.global_position - global_position)


## A small flickering round glow where the arc strikes, so it doesn't just stop.
func _glow(at: Vector2) -> void:
	var r := 7.0 + sin(Arena.clock * 37.0) * 1.5
	draw_circle(at, r * 1.6, Color(color, 0.15))
	draw_circle(at, r, Color(color, 0.35))
	draw_circle(at, r * 0.45, Color(Color.WHITE, 0.8))


func _bolt(pts: PackedVector2Array) -> void:
	draw_polyline(pts, Color(color, 0.3), 7.0, true)
	draw_polyline(pts, color, 3.0, true)
	draw_polyline(pts, Color.WHITE, 1.0, true)


## The cone's waves: its sheet (a crescent of cold wind on the right edge of
## the frame) sent out from the apex every CONE_TRAVEL / CONE_WAVES s, each one
## widening with the cone as it goes out to the reach, fading in then out, a
## little tilted at random. Timed on the clock (ticks renew age, not the waves);
## only the waves sent since the cast, none popping up mid-flight.
## No sheet: a flickering polygon.
func _draw_cone() -> void:
	var k := _cone_scale()
	var reach: float = body.speed * k
	var half := deg_to_rad(maxf(body.angle * k, 4.0)) / 2.0
	if anim:
		var s: Dictionary = anim[1]
		var a := minf(half, 1.4)
		for i in CONE_WAVES:
			var t := Arena.clock / CONE_TRAVEL + float(i) / CONE_WAVES
			var u := fposmod(t, 1.0)
			if Arena.clock - u * CONE_TRAVEL < born:
				continue
			var r := reach * lerpf(0.15, 1.0, u)
			var h := 2.0 * r * sin(a)
			draw_set_transform(Vector2.ZERO, dir.angle() + sin(floorf(t) * 12.9898) * 0.15)
			draw_texture_rect_region(anim[0], Rect2(r - h, -h / 2.0, h, h), Rect2(0, 0, s.size, s.size), Color(1, 1, 1, CONE_ALPHA * sin(u * PI)))
		draw_set_transform(Vector2.ZERO)
		return
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		pts.append(dir.rotated(lerpf(-half, half, i / 8.0)) * reach * randf_range(0.85, 1.0))
	draw_colored_polygon(pts, Color(color, 0.35))
	for i in 12:
		draw_circle(dir.rotated(randf_range(-half, half)) * reach * randf(), 2.0, Color(Color.WHITE, 0.8))


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
