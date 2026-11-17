extends Node2D
## An enemy. Implements the target interface used by SpellBody.
## Kinds, AIs and spells come from Run.ENEMIES (passed to setup as stats):
## the AI moves it, each of its spells is cast on its own timer (see cast).
## Coop: simulated on the host, chasing the nearest mage standing; peers get
## its position, hp and statuses, and draw its shots and zones.

signal killed(enemy: Node2D)
signal summoned(kind: String, pos: Vector2)  # summon spells and splits, spawned by main.gd

const CROWD := 120  # no summons past this many enemies

var kind := "melee"
var data := {}  # its Run.ENEMIES entry, scaled to the wave
var target: Node2D
var hp := 20.0
var max_hp := 20.0
var speed := 80.0
var radius := 12.0
var touch_damage := 10.0
var xp := 1
var gold := 1
var statuses := {}  # name -> [power, time_left]
var knock := Vector2.ZERO
var hit_cooldown := 0.0
var timers := []  # seconds until each of data.spells
var windup := 0.0  # charge: standing still, about to dash
var dash := Vector2.ZERO  # charge: velocity while dashing
var dash_time := 0.0
var age := 0.0
var side := 1.0  # flank: which side it comes from
var _heard_hp := 0.0  # hp at the last hit sound: hosts and peers hear hits on the synced hp


func setup(k: String, s: Dictionary) -> void:
	kind = k
	data = s
	max_hp = s.hp
	hp = s.hp
	speed = s.speed
	radius = s.radius
	touch_damage = s.damage
	xp = s.xp
	gold = s.gold
	_heard_hp = hp
	side = [-1.0, 1.0].pick_random()
	timers = s.get("spells", []).map(func(sp): return sp.every * randf_range(0.5, 1.0))


func _ready() -> void:
	add_to_group("enemies")


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		killed.emit(self)
		var split: Array = data.get("split", [])
		for i in (split[1] if split else 0):
			summoned.emit(split[0], position + Vector2.from_angle(TAU * i / split[1]) * radius)
		queue_free()


func add_status(status: String, power: float, duration: float) -> void:
	var cur: Array = statuses.get(status, [0.0, 0.0])
	statuses[status] = [maxf(cur[0], power), maxf(cur[1], duration)]


func push(velocity: Vector2) -> void:
	knock += velocity * data.get("heavy", 1.0)


## The nearest mage standing, or null.
static func nearest_player(from: Node2D) -> Node2D:
	var best: Node2D = null
	for p in from.get_tree().get_nodes_in_group("players"):
		if p.hp > 0.0 and (not best or from.position.distance_squared_to(p.position) < from.position.distance_squared_to(best.position)):
			best = p
	return best


func _physics_process(delta: float) -> void:
	queue_redraw()
	if hp < _heard_hp - 1.0:  # not every tick of burn or poison
		Sfx.play("hit")
		_heard_hp = hp
	_heard_hp = maxf(_heard_hp, hp)  # healed
	if not multiplayer.is_server():
		return
	age += delta
	var near := nearest_player(self)
	if near:
		target = near
	var slow := 1.0
	for s in statuses.keys():
		var p: float = statuses[s][0]
		statuses[s][1] -= delta
		match s:
			"burn", "poison": take_damage(p * delta)
			"slow": slow *= 1.0 / (1.0 + p * 0.5)
			"freeze", "stun": slow = 0.0
		if statuses[s][1] <= 0.0:
			statuses.erase(s)
	if hp <= 0.0 or not is_instance_valid(target) or target.hp <= 0.0:
		return
	var to := target.global_position - global_position
	var motion := _steer(to) * speed * slow
	windup -= delta
	dash_time -= delta
	if windup > 0.0:
		motion = Vector2.ZERO
	elif dash != Vector2.ZERO:
		if windup > -delta:  # the windup just ended: dash at the mage
			dash = to.normalized() * speed * 5.0
			dash_time = 0.45
		motion = dash * slow
		if dash_time <= 0.0:
			dash = Vector2.ZERO
	position = Decor.slide(position, (motion + knock) * delta, radius)
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	hit_cooldown -= delta
	if to.length() < radius + target.radius and hit_cooldown <= 0.0:
		hit_cooldown = 0.6
		target.hurt(touch_damage)
	var spells: Array = data.get("spells", [])
	for i in spells.size():
		timers[i] -= delta * slow
		if timers[i] <= 0.0 and windup <= 0.0 and dash == Vector2.ZERO and cast(spells[i], to):
			timers[i] = spells[i].every


## The direction its AI walks, `to`: from it to its mage.
func _steer(to: Vector2) -> Vector2:
	var d := to.length()
	match data.get("ai", "chase"):
		"weave":
			return to.normalized().rotated(sin(age * 5.0) * 0.8)
		"flank":
			return to.normalized() if d < 140.0 else (to + to.orthogonal().normalized() * side * 160.0).normalized()
		"kite":  # hold the range, strafe around the mage
			var r: float = data.get("range", 260.0)
			return to.normalized() if d > r + 30.0 else -to.normalized() if d < r - 30.0 else to.orthogonal().normalized() * side
	return to.normalized()


## Casts spell `sp` at its mage (`to`: from it to the mage). False when it
## does not fit now (out of reach, nobody to heal...): tried again next frame.
func cast(sp: Dictionary, to: Vector2) -> bool:
	var dmg: float = touch_damage * sp.get("dmg", 0.8)
	var d := to.length()
	match sp.type:
		"bolt":
			_shot(to.normalized(), 260.0, dmg)
		"spread":  # a fan of shots
			for i in sp.count:
				_shot(to.normalized().rotated(sp.angle * (float(i) / (sp.count - 1) - 0.5)), 240.0, dmg)
		"ring":  # shots all around
			var a := randf() * TAU
			for i in sp.count:
				_shot(Vector2.from_angle(a + TAU * i / sp.count), 180.0, dmg)
		"nova":  # a slam around it, after a warning
			if d > sp.radius:
				return false
			_zone.rpc(position, sp.radius, 0.8, dmg, 0.0, Color(data.color), 0.0)
		"fuse":  # stops, glows, blows up
			if d > sp.range + radius:
				return false
			_zone.rpc(position, sp.radius, 0.7, dmg, 0.0, Color("#ff7043"), 0.0)
			windup = INF
			get_tree().create_timer(0.7, false, true).timeout.connect(queue_free)
		"puddle":  # a poison pool where the mage stands
			if d > 550.0:
				return false
			_zone.rpc(target.position, sp.radius, 1.0, 0.0, dmg, Color(data.color), 4.0)
		"charge":  # stops, then dashes at the mage
			if d > sp.range:
				return false
			windup = 0.6
			dash = Vector2.ONE  # dashing once the windup ends
			_zone.rpc(position, radius + 10.0, 0.6, 0.0, 0.0, Color.WHITE, 0.0)
		"blink":  # vanishes, comes back next to the mage
			var to_pos := target.position + Vector2.from_angle(randf() * TAU) * 110.0
			if d < 160.0 or Decor.hit(to_pos, radius):
				return false
			_zone.rpc(position, radius + 6.0, 0.3, 0.0, 0.0, Color(data.color), 0.0)
			position = to_pos
			_zone.rpc(position, radius + 6.0, 0.3, 0.0, 0.0, Color(data.color), 0.0)
		"heal":  # mends the wounded around it, itself included
			var hurt := get_tree().get_nodes_in_group("enemies").filter(
				func(e): return e.hp < e.max_hp and e.position.distance_to(position) < sp.radius)
			if hurt.is_empty():
				return false
			for e in hurt:
				e.hp = minf(e.max_hp, e.hp + e.max_hp * sp.ratio)
			_zone.rpc(position, sp.radius, 0.4, 0.0, 0.0, Color("#69f0ae"), 0.0)
		"summon":
			if get_tree().get_nodes_in_group("enemies").size() >= CROWD:
				return false
			for i in sp.count:
				summoned.emit(sp.kind, position + Vector2.from_angle(randf() * TAU) * (radius + 20.0))
	return true


func _shot(dir: Vector2, v: float, dmg: float) -> void:
	_spawn_shot.rpc(position, dir * v, dmg)


@rpc("authority", "call_local", "unreliable_ordered")
func _spawn_shot(pos: Vector2, velocity: Vector2, dmg: float) -> void:
	Sfx.play("shot")
	var s := Shot.new()
	s.position = pos
	s.velocity = velocity
	s.damage = dmg
	get_parent().add_child(s)


## A zone: warns for `delay` seconds, then hurts once (`damage`) and/or
## every second for `linger` seconds (`dps`). Damage 0: a warning only.
@rpc("authority", "call_local", "reliable")
func _zone(pos: Vector2, r: float, delay: float, damage: float, dps: float, color: Color, linger: float) -> void:
	var z := Zone.new()
	z.position = pos
	z.radius = r
	z.delay = delay
	z.damage = damage
	z.dps = dps
	z.color = color
	z.linger = linger
	get_parent().add_child(z)


func _draw() -> void:
	var c := Color(data.get("color", "#4caf50"))
	if statuses.has("freeze"): c = Color("#9be7ff")
	elif statuses.has("burn"): c = Color("#ff8a50")
	elif statuses.has("poison"): c = Color("#b388ff")
	var sides: int = data.get("sides", 0)
	if sides:
		var pts := PackedVector2Array()
		for i in sides:
			pts.append(Vector2.from_angle(-PI / 2 + TAU * i / sides) * radius * 1.15)
		draw_colored_polygon(pts, c)
	else:
		draw_circle(Vector2.ZERO, radius, c)
	if data.get("ai") == "kite":
		draw_circle(Vector2.ZERO, radius * 0.45, c.darkened(0.6))
	if data.get("boss", false):
		draw_arc(Vector2.ZERO, radius + 3, 0, TAU, 40, Color("#ffd54f"), 3.0)
	draw_rect(Rect2(-radius, -radius - 8, 2 * radius * maxf(hp, 0.0) / max_hp, 3), Color.RED)


## A ground zone cast by an enemy (see _zone); hurts mages on the host only.
class Zone extends Node2D:
	var radius := 50.0
	var delay := 1.0
	var damage := 0.0
	var dps := 0.0
	var linger := 0.0
	var color := Color.RED
	var age := 0.0

	func _ready() -> void:
		z_index = -1  # under the mages and enemies

	func _physics_process(delta: float) -> void:
		var was := age
		age += delta
		queue_redraw()
		if age >= delay and multiplayer.is_server():
			for p in get_tree().get_nodes_in_group("players"):
				if p.hp > 0.0 and position.distance_to(p.position) < radius + p.radius:
					if was < delay and damage > 0.0:
						p.hurt(damage)
					if dps > 0.0:
						p.hurt(dps * delta)
		if age > delay + maxf(linger, 0.2):
			queue_free()

	func _draw() -> void:
		if age < delay:  # the warning: an outline filling up
			draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(color, 0.8), 2.0)
			draw_circle(Vector2.ZERO, radius * age / delay, Color(color, 0.25))
		else:
			draw_circle(Vector2.ZERO, radius, Color(color, 0.45 if linger > 0.0 else 0.6 * (1.0 - (age - delay) / 0.2)))


## An enemy projectile: flies straight, hurts a mage on touch (on the host;
## peers only draw it).
class Shot extends Node2D:
	const RADIUS := 5.0
	var velocity := Vector2.ZERO
	var damage := 5.0
	var age := 0.0

	func _physics_process(delta: float) -> void:
		position += velocity * delta
		age += delta
		var hit: Node2D = null
		for p in get_tree().get_nodes_in_group("players"):
			if p.hp > 0.0 and position.distance_to(p.position) < RADIUS + p.radius:
				hit = p
		if hit:
			if multiplayer.is_server():
				hit.hurt(damage)
			queue_free()
		elif age > 6.0 or Decor.hit(position, RADIUS):
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, RADIUS, Color("#ff5252"))
		draw_circle(Vector2.ZERO, RADIUS * 0.5, Color.WHITE)
