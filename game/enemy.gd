extends Node2D
## An enemy. Implements the target interface used by SpellBody.
## Kinds, AIs and spells come from Run.ENEMIES (passed to setup as stats):
## the AI moves it, each of its spells is cast on its own timer (see cast).
## Coop: simulated on the host, chasing the nearest mage standing; peers get
## its position, hp and statuses, and draw its shots and zones.
## Look: PixelLab sprites (tools/make_monsters.py), assets/monsters/<kind>/
## <anim>.png strips of square frames seen from straight above, facing down,
## turned toward where it goes (or its mage when still), and the effects of
## its attacks in assets/monsters/fx/.

signal killed(enemy: Node2D)
signal summoned(kind: String, pos: Vector2, hp: float)  # summon spells, spawned by main.gd (hp: share of a real one's)

const CROWD := 120  # no summons past this many enemies
## Half the world seen on a 16:9 screen (1280x720 / Player.ZOOM): its spells
## reach the mage only from within it (see in_view), whatever the real window.
const VIEW := Vector2(480.0, 270.0)
const FPS := 12.0
const Self := preload("res://game/enemy.gd")  # its static art for the inner classes
## The move each spell type plays (assets/monsters/<look>/<anim>.png, skipped
## when not drawn), and for how long; "attack" also plays on a touch.
const SPELL_ANIM := {"summon": ["summon", 0.7], "ring": ["summon", 0.7],
	"bolt": ["attack", 0.5], "puddle": ["attack", 0.5], "burst": ["attack", 0.5],
	"laser": ["attack", 0.6], "teleport": ["vanish", 0.5]}
const LASER_WARN := 0.7  # s: the laser's line shows before it burns
const BITE_WARN := 0.5  # s: vanished, about to bite where the mage stood
const BOSS_CATCH_UP := 1.2  # out of cast range, a boss walks this much faster than its mage
const PREDICT_SHARE := 0.2  # of the enemies lead their mage: walk to cut it off, shoot where it will be
const PREDICT_MAX := 1.5  # s: the farthest ahead they guess

var kind := "skeleton"
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
var windup := 0.0  # laser, teleport: standing still until it ends
var age := 0.0
var _later := []  # [s left, Callable]: the delayed parts of its spells (host)
var _heard_hp := 0.0  # hp at the last hit sound: hosts and peers hear hits on the synced hp
var _last_pos := Vector2.ZERO
var _angle := PI / 2.0  # its heading: from the synced position (or the nearest mage), the same on every peer
var _moving := false
var _act := ""  # a special move playing (SPELL_ANIM), for _act_time seconds
var _act_time := 0.0
var _act_len := 1.0
var predicts := false  # leads its mage (PREDICT_SHARE of them, see lead)

static var _textures := {}


## res://assets/monsters/<file>.png, null when not generated.
static func art(file: String) -> Texture2D:
	if not _textures.has(file):
		var path := "res://assets/monsters/%s.png" % file
		_textures[file] = load(path) if ResourceLoader.exists(path) else null
	return _textures[file]


## Draws frame `f` (wrapped) of strip `tex` on `item`, centered, `size` wide.
static func draw_frame(item: CanvasItem, tex: Texture2D, f: int, size: float, tint := Color.WHITE) -> void:
	var n := tex.get_height()
	var src := Rect2(wrapi(f, 0, tex.get_width() / n) * n, 0, n, n)
	item.draw_texture_rect_region(tex, Rect2(-size / 2.0, -size / 2.0, size, size), src, tint)


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
	predicts = randf() < PREDICT_SHARE
	timers = s.get("spells", []).map(func(sp): return sp.every * randf_range(0.5, 1.0))


func _ready() -> void:
	add_to_group("enemies")


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		killed.emit(self)
		var gunk: Array = data.get("gunk", [])
		if gunk:  # a poison pool where it falls
			_zone.rpc(position, gunk[0], 0.0, 0.0, touch_damage * data.effect[1], Color(data.color), gunk[1], "poison")
		queue_free()


func add_status(status: String, power: float, duration: float) -> void:
	var cur: Array = statuses.get(status, [0.0, 0.0])
	statuses[status] = [maxf(cur[0], power), maxf(cur[1], duration)]


func push(velocity: Vector2) -> void:
	knock += velocity * data.get("heavy", 1.0)


## The nearest mage standing (and passing `ok`, if given), or null.
static func nearest_player(from: Node2D, ok := Callable()) -> Node2D:
	var best: Node2D = null
	for p in from.get_tree().get_nodes_in_group("players"):
		if p.hp > 0.0 and (not ok.is_valid() or ok.call(p)) and (not best or from.position.distance_squared_to(p.position) < from.position.distance_squared_to(best.position)):
			best = p
	return best


func _physics_process(delta: float) -> void:
	queue_redraw()
	var step := position - _last_pos
	_last_pos = position
	_moving = step.length() > 0.2
	var near_mage := nearest_player(self)
	var heading := step if _moving or not near_mage else near_mage.position - position
	if heading.length() > 0.2:
		_angle = lerp_angle(_angle, heading.angle(), minf(1.0, 10.0 * delta))
	_act_time -= delta
	if hp < _heard_hp - 1.0:  # not every tick of burn or poison
		Sfx.play("hit", global_position)
		_heard_hp = hp
	_heard_hp = maxf(_heard_hp, hp)  # healed
	if not multiplayer.is_server():
		return
	age += delta
	if near_mage:
		target = near_mage
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
	for l in _later.duplicate():
		l[0] -= delta
		if l[0] <= 0.0:
			_later.erase(l)
			l[1].call()
	var to := target.global_position - global_position
	var motion := _steer(to) * walk_speed(to) * slow
	windup -= delta
	if windup > 0.0:
		motion = Vector2.ZERO
	position = Arena.slide(position, (motion + knock) * delta + Arena.apart(self, get_tree().get_nodes_in_group("enemies")), radius)
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	hit_cooldown -= delta
	if to.length() < radius + target.radius and hit_cooldown <= 0.0:
		hit_cooldown = 0.6
		target.hurt(touch_damage, data.get("fire", false))
		_afflict(target)
		if _act_time <= 0.0:
			_play.rpc("attack", 0.4)
	var spells: Array = data.get("spells", [])
	for i in spells.size():
		timers[i] -= delta * slow
		if timers[i] <= 0.0 and windup <= 0.0 and cast(spells[i], to):
			timers[i] = spells[i].every
			if SPELL_ANIM.has(spells[i].type):
				_play.rpc(SPELL_ANIM[spells[i].type][0], SPELL_ANIM[spells[i].type][1])


## Its "effect" (Run.ENEMIES) on mage `p`, from its touch or its shots.
func _afflict(p: Node2D) -> void:
	var e: Array = data.get("effect", [])
	if e:
		p.afflict(e[0], e[1] * (touch_damage if e[0] == "poison" else 1.0), e[2])


## The direction its AI walks, `to`: from it to its mage. It goes toward the
## mage around the walls (Arena.way).
func _steer(to: Vector2) -> Vector2:
	var ai: String = data.get("ai", "chase")
	var w := Arena.way(position, position + to, radius)
	if predicts and w.dot(to.normalized()) > 0.9:  # in the open: cuts it off (around walls it follows the path)
		w = lead(to, speed).normalized()
	if ai != "chase" and not in_view(to):  # too far to cast: walks in
		return w
	match ai:
		"still":
			return Vector2.ZERO
		"weave":
			return w.rotated(sin(age * 5.0) * 0.8) if w.dot(to.normalized()) > 0.9 else w  # weaves only in the open
	return w


## From it to where its mage (`to`: from it to the mage) will be when
## something at `v` px/s from it gets there (its mage's velocity kept, at most
## PREDICT_MAX ahead); `to` itself when it does not predict.
func lead(to: Vector2, v: float) -> Vector2:
	if not predicts or not is_instance_valid(target) or v <= 0.0:
		return to
	var at := to
	for i in 3:  # a few fixed-point steps of the interception time
		at = to + target.velocity * minf(at.length() / v, PREDICT_MAX)
	return at


## Its walking speed toward its mage (`to`): a boss out of cast range
## (in_view) outruns the mage, so kiting never keeps it from casting.
func walk_speed(to: Vector2) -> float:
	if data.get("boss", false) and not in_view(to):
		return maxf(speed, target.stats.speed * BOSS_CATCH_UP)
	return speed


## Casts spell `sp` at its mage (`to`: from it to the mage). False when it
## does not fit now (out of reach, too many enemies...): tried again next frame.
func cast(sp: Dictionary, to: Vector2) -> bool:
	if not in_view(to):
		return false
	var dmg: float = touch_damage * sp.get("dmg", 0.8)
	var d := to.length()
	match sp.type:
		"bolt":
			_shot(lead(to, 260.0).normalized(), 260.0, dmg)
		"ring":  # shots all around
			var a := randf() * TAU
			for i in sp.count:
				_shot(Vector2.from_angle(a + TAU * i / sp.count), 180.0, dmg)
		"puddle":  # a poison pool where the mage stands
			if d > 550.0:
				return false
			_zone.rpc(target.position, sp.radius, 1.0, 0.0, dmg, Color(data.color), sp.get("linger", 4.0), sp.get("fx", "poison"))
			if sp.get("imps", 0) > 0:  # hatching from the fire once it lands
				_later.append([1.0, _hatch.bind(target.position, sp.imps)])
		"burst":  # volleys of missiles at the mage
			for b in sp.bursts:
				_later.append([b * 0.3, _volley.bind(sp.count, dmg)])
		"laser":  # stands still, a line warns, then it burns along it
			windup = LASER_WARN + sp.time
			_beam.rpc(position, to.angle(), sp.length, LASER_WARN, sp.time, dmg)
		"teleport":  # vanishes, then bites where the mage stood
			windup = BITE_WARN
			_zone.rpc(position, radius, 0.0, 0.0, 0.0, Color(data.color), 0.0, "shadow")
			_zone.rpc(target.position, radius, BITE_WARN, 0.0, 0.0, Color(data.color), 0.0, "")
			_later.append([BITE_WARN, _bite.bind(target.position, touch_damage * sp.dmg)])
		"summon":
			if get_tree().get_nodes_in_group("enemies").size() >= CROWD:
				return false
			for i in sp.count:
				var at := position + Vector2.from_angle(randf() * TAU) * (radius + 20.0)
				_zone.rpc(at, 24.0, 0.0, 0.0, 0.0, Color(data.color), 0.0, "summon")
				summoned.emit(sp.kind, at, sp.get("hp", 1.0))
	return true


## A volley of `count` missiles side by side at its mage.
func _volley(count: int, dmg: float) -> void:
	var dir := lead(target.position - position, 300.0).normalized()
	for i in count:
		_shot(dir.rotated((i - (count - 1) / 2.0) * 0.2), 300.0, dmg)


## Appears at `at` and bites the mages there.
func _bite(at: Vector2, dmg: float) -> void:
	position = Arena.slide(at, Vector2.ZERO, radius)
	_zone.rpc(position, radius, 0.0, 0.0, 0.0, Color(data.color), 0.0, "shadow")
	_play.rpc("attack", 0.4)
	for p in get_tree().get_nodes_in_group("players"):
		if p.hp > 0.0 and position.distance_to(p.position) < radius + p.radius + 10.0:
			p.hurt(dmg)
	hit_cooldown = 0.6  # the bite is its touch


## `n` imps out of a landed fireball at `at`.
func _hatch(at: Vector2, n: int) -> void:
	for i in n:
		if get_tree().get_nodes_in_group("enemies").size() >= CROWD:
			return
		summoned.emit("hell_imp", at + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 40.0), 1.0)


## Whether its mage (`to`: from it to the mage) would see all of it on a
## 16:9 screen centred on the mage (VIEW).
func in_view(to: Vector2) -> bool:
	return absf(to.x) <= VIEW.x - radius and absf(to.y) <= VIEW.y - radius


func _shot(dir: Vector2, v: float, dmg: float) -> void:
	_spawn_shot.rpc(position, dir * v, dmg, data.get("shot", "bolt"))


@rpc("authority", "call_local", "unreliable_ordered")
func _spawn_shot(pos: Vector2, velocity: Vector2, dmg: float, fx: String) -> void:
	Sfx.play("shot", pos)
	var s := Shot.new()
	s.from = self
	s.position = pos
	s.velocity = velocity
	s.damage = dmg
	s.fx = fx
	s.fire = data.get("fire", false)
	get_parent().add_child(s)


@rpc("authority", "call_local", "reliable")
func _play(anim: String, duration: float) -> void:
	_act = anim
	_act_time = duration
	_act_len = duration


## A zone: warns for `delay` seconds, then hurts once (`damage`) and/or
## every second for `linger` seconds (`dps`), showing effect `fx`
## (assets/monsters/fx/). Damage 0: a warning (or an effect) only.
@rpc("authority", "call_local", "reliable")
func _zone(pos: Vector2, r: float, delay: float, damage: float, dps: float, color: Color, linger: float, fx: String) -> void:
	var z := Zone.new()
	z.position = pos
	z.radius = r
	z.delay = delay
	z.damage = damage
	z.dps = dps
	z.color = color
	z.linger = linger
	z.fx = fx
	get_parent().add_child(z)


func _draw() -> void:
	var tint := Color.WHITE
	if statuses.has("freeze"): tint = Color("#9be7ff")
	elif statuses.has("stun"): tint = Color("#fff27a")
	elif statuses.has("burn"): tint = Color("#ffb08a")
	elif statuses.has("poison"): tint = Color("#d1b8ff")
	elif statuses.has("slow"): tint = Color("#cdeeff")
	var size := radius * 2.5  # the art fills ~90% of its frame: its body overflows the hit circle a bit
	var look: String = data.get("look", kind)
	var anim := _act if _act_time > 0.0 and art(look + "/" + _act) else "walk"
	var tex := art(look + "/" + anim)
	if tex:
		var n := tex.get_width() / tex.get_height()
		# still ones loop their walk strip (an idle) all the time
		var f := int(Arena.clock * FPS) if _moving or data.get("ai") == "still" else 0
		if anim != "walk":  # the move plays once over its duration
			f = mini(int((1.0 - _act_time / _act_len) * n), n - 1)
		draw_set_transform(Vector2.ZERO, _angle - PI / 2.0)  # the art faces down
		draw_frame(self, tex, f, size, tint)
		draw_set_transform(Vector2.ZERO)
	else:  # not generated yet
		draw_circle(Vector2.ZERO, radius, Color(data.get("color", "#4caf50")) * tint)


## A fallen enemy (main.gd _killed): plays <look>/death.png once where it
## fell, turned as it was, then fades out. Nothing when not generated.
class Corpse extends Node2D:
	const FADE := 0.4  # s
	var look := "skeleton"
	var radius := 12.0
	var angle := PI / 2.0
	var age := 0.0
	var _tex: Texture2D

	func _ready() -> void:
		z_index = -1  # under the living
		_tex = Self.art(look + "/death")
		if not _tex:
			queue_free()

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age > _len() + FADE:
			queue_free()

	func _len() -> float:
		return _tex.get_width() / _tex.get_height() / FPS

	func _draw() -> void:
		var n := _tex.get_width() / _tex.get_height()
		draw_set_transform(Vector2.ZERO, angle - PI / 2.0)  # the art faces down
		Self.draw_frame(self, _tex, mini(int(age * FPS), n - 1), radius * 2.5,
			Color(1, 1, 1, clampf((_len() + FADE - age) / FADE, 0.0, 1.0)))


@rpc("authority", "call_local", "reliable")
func _beam(pos: Vector2, angle: float, length: float, delay: float, time: float, dps: float) -> void:
	var b := Beam.new()
	b.position = pos
	b.rotation = angle
	b.length = length
	b.delay = delay
	b.time = time
	b.dps = dps
	get_parent().add_child(b)


## A laser cast by an enemy (see _beam): a line warns for `delay` s, then it
## burns the mages on it (`dps`) for `time` s; hurts on the host only.
class Beam extends Node2D:
	const WIDTH := 28.0
	var length := 500.0
	var delay := 0.7
	var time := 1.5
	var dps := 30.0
	var age := 0.0
	var _tex: Texture2D

	func _ready() -> void:
		_tex = Self.art("fx/green_laser")

	func _physics_process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= delay and multiplayer.is_server():
			var dir := Vector2.from_angle(rotation)
			for p in get_tree().get_nodes_in_group("players"):
				var q := Geometry2D.get_closest_point_to_segment(p.position, position, position + dir * length)
				if p.hp > 0.0 and p.position.distance_to(q) < WIDTH / 2.0 + p.radius:
					p.hurt(dps * delta)
		if age > delay + time:
			queue_free()

	func _draw() -> void:
		if age < delay:  # the warning: a thin line
			draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.46, 1.0, 0.0, 0.3 + 0.5 * age / delay), 2.0)
		elif _tex:  # its sheet stretched along the line, fading out at the end
			var n := _tex.get_height()
			var f := wrapi(int((age - delay) * FPS), 0, _tex.get_width() / n)
			draw_texture_rect_region(_tex, Rect2(0, -WIDTH, length, WIDTH * 2.0), Rect2(f * n, 0, n, n),
				Color(1, 1, 1, clampf((delay + time - age) / 0.2, 0.0, 1.0)))
		else:
			draw_line(Vector2.ZERO, Vector2(length, 0), Color("#76ff03"), WIDTH)


## A ground zone cast by an enemy (see _zone); hurts mages on the host only.
class Zone extends Node2D:
	var radius := 50.0
	var delay := 1.0
	var damage := 0.0
	var dps := 0.0
	var linger := 0.0
	var color := Color.RED
	var fx := ""
	var age := 0.0
	var _fx_tex: Texture2D

	func _ready() -> void:
		z_index = -1  # under the mages and enemies
		_fx_tex = Self.art("fx/" + fx) if fx else null

	func _physics_process(delta: float) -> void:
		var was := age
		age += delta
		queue_redraw()
		if age >= delay and multiplayer.is_server():
			for p in get_tree().get_nodes_in_group("players"):
				if p.hp > 0.0 and position.distance_to(p.position) < radius + p.radius:
					if was < delay and damage > 0.0:
						p.hurt(damage, fx == "fire_pool", fx == "poison")
					if dps > 0.0:
						p.hurt(dps * delta, fx == "fire_pool", fx == "poison")
		if age > delay + maxf(linger, _fx_len()):
			queue_free()

	## Seconds the effect plays once.
	func _fx_len() -> float:
		return _fx_tex.get_width() / _fx_tex.get_height() / FPS if _fx_tex else 0.2

	func _draw() -> void:
		if age < delay:  # the warning: an outline filling up
			draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(color, 0.8), 2.0)
			draw_circle(Vector2.ZERO, radius * age / delay, Color(color, 0.25))
		elif _fx_tex:  # once, or looping while it lingers; fades out at the end
			var n := _fx_tex.get_width() / _fx_tex.get_height()
			var f := int((age - delay) * FPS)
			var left := delay + maxf(linger, _fx_len()) - age
			Self.draw_frame(self, _fx_tex, f if linger > 0.0 else mini(f, n - 1), radius * 2.4,
				Color(1, 1, 1, clampf(left / 0.3, 0.0, 1.0)))
		else:
			draw_circle(Vector2.ZERO, radius, Color(color, 0.45 if linger > 0.0 else 0.6 * (1.0 - (age - delay) / 0.2)))


## An enemy projectile: flies straight, hurts a mage on touch (on the host;
## peers only draw it).
class Shot extends Node2D:
	const RADIUS := 5.0
	var velocity := Vector2.ZERO
	var damage := 5.0
	var fx := "bolt"
	var fire := false  # fire damage (Player.hurt)
	var from: Node2D  # its enemy, for its effect (may be dead by the hit)
	var age := 0.0

	func _ready() -> void:
		add_to_group("shots")  # repelled by spells (SpellBody._repel_shots)

	func _physics_process(delta: float) -> void:
		position += velocity * delta
		age += delta
		var hit: Node2D = null
		for p in get_tree().get_nodes_in_group("players"):
			if p.hp > 0.0 and position.distance_to(p.position) < RADIUS + p.radius:
				hit = p
		if hit:
			if multiplayer.is_server():
				hit.hurt(damage, fire)
				if is_instance_valid(from):
					from._afflict(hit)
			queue_free()
		elif age > 6.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var tex: Texture2D = Self.art("fx/" + fx)
		if not tex:
			draw_circle(Vector2.ZERO, RADIUS, Color("#ff5252"))
			return
		draw_set_transform(Vector2.ZERO, velocity.angle())  # the art flies right
		Self.draw_frame(self, tex, int(age * FPS), RADIUS * 6.0)
