extends Node2D
## An enemy. Implements the target interface used by SpellBody.
## Kinds, AIs and spells come from Run.ENEMIES (passed to setup as stats):
## the AI moves it, each of its spells is cast on its own timer (see cast).
## Coop: simulated on the host, chasing the nearest mage standing; peers get
## its position, hp and statuses, and draw its shots and zones.
## Look: PixelLab sprites (tools/make_monsters.py), assets/monsters/<kind>/
## <anim>.png strips of square frames seen from straight above, facing down,
## turned toward where it goes (or its mage when still; the bosses, a bit
## from the front, only mirrored), and the effects of its
## attacks in assets/monsters/fx/.

signal killed(enemy: Node2D)
signal summoned(kind: String, pos: Vector2)  # summon spells, spawned by main.gd

const CROWD := 120  # no summons past this many enemies
## Half the world seen on a 16:9 screen (1280x720 / Player.ZOOM): its spells
## reach the mage only from within it (see in_view), whatever the real window.
const VIEW := Vector2(480.0, 270.0)
const FPS := 12.0
const Self := preload("res://game/enemy.gd")  # its static art for the inner classes
## The move a spell plays (assets/monsters/<kind>/<anim>.png, if any).
## The move each spell type plays (assets/monsters/<look>/<anim>.png, skipped
## when not drawn), and for how long; "attack" also plays on a touch.
const SPELL_ANIM := {"charge": ["windup", 0.6], "summon": ["summon", 0.7], "ring": ["summon", 0.7], "nova": ["slam", 0.8],
	"bolt": ["attack", 0.5], "spread": ["attack", 0.5], "puddle": ["attack", 0.5]}

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
var windup := 0.0  # charge: standing still, about to dash
var dash := Vector2.ZERO  # charge: velocity while dashing
var dash_time := 0.0
var age := 0.0
var side := 1.0  # kite: which way it strafes
var _heard_hp := 0.0  # hp at the last hit sound: hosts and peers hear hits on the synced hp
var _last_pos := Vector2.ZERO
var _flip: bool:  # a boss faces left: mirrored (its death too, main.gd)
	get: return data.get("boss", false) and cos(_angle) < 0.0
var _angle := PI / 2.0  # its heading: from the synced position (or the nearest mage), the same on every peer
var _moving := false
var _act := ""  # a special move playing (SPELL_ANIM), for _act_time seconds
var _act_time := 0.0
var _act_len := 1.0

static var _textures := {}


## res://assets/monsters/<file>.png, null when not generated.
static func art(file: String) -> Texture2D:
	if not _textures.has(file):
		var path := "res://assets/monsters/%s.png" % file
		_textures[file] = load(path) if ResourceLoader.exists(path) else null
	return _textures[file]


## Draws frame `f` (wrapped) of strip `tex` on `item`, centered, `size` wide.
static func draw_frame(item: CanvasItem, tex: Texture2D, f: int, size: float, flip := false, tint := Color.WHITE) -> void:
	var n := tex.get_height()
	var src := Rect2(wrapi(f, 0, tex.get_width() / n) * n, 0, n, n)
	var dst := Rect2(-size / 2.0, -size / 2.0, size, size)
	if flip:
		dst = Rect2(size / 2.0, -size / 2.0, -size, size)
	item.draw_texture_rect_region(tex, dst, src, tint)


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
	position = Arena.slide(position, (motion + knock) * delta, radius)
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	hit_cooldown -= delta
	if to.length() < radius + target.radius and hit_cooldown <= 0.0:
		hit_cooldown = 0.6
		target.hurt(touch_damage)
		_afflict(target)
		if _act_time <= 0.0:
			_play.rpc("attack", 0.4)
	var spells: Array = data.get("spells", [])
	for i in spells.size():
		timers[i] -= delta * slow
		if timers[i] <= 0.0 and windup <= 0.0 and dash == Vector2.ZERO and cast(spells[i], to):
			timers[i] = spells[i].every
			if SPELL_ANIM.has(spells[i].type):
				_play.rpc(SPELL_ANIM[spells[i].type][0], SPELL_ANIM[spells[i].type][1])


## Its "effect" (Run.ENEMIES) on mage `p`, from its touch or its shots.
func _afflict(p: Node2D) -> void:
	var e: Array = data.get("effect", [])
	if e:
		p.afflict(e[0], e[1] * (touch_damage if e[0] == "poison" else 1.0), e[2])


## The direction its AI walks, `to`: from it to its mage. It goes toward the
## mage around the walls (Arena.way), backs off and strafes straight.
func _steer(to: Vector2) -> Vector2:
	var d := to.length()
	var ai: String = data.get("ai", "chase")
	if ai != "chase" and not in_view(to):  # too far to cast: walks in
		return Arena.way(position, position + to)
	match ai:
		"still":
			return Vector2.ZERO
		"weave":
			var w := Arena.way(position, position + to)
			return w.rotated(sin(age * 5.0) * 0.8) if w.dot(to.normalized()) > 0.9 else w  # weaves only in the open
		"kite":  # hold the range, strafe around the mage
			var r: float = minf(data.get("range", 260.0), VIEW.y - radius - 30.0)  # strafes on screen
			return Arena.way(position, position + to) if d > r + 30.0 else -to.normalized() if d < r - 30.0 else to.orthogonal().normalized() * side
	return Arena.way(position, position + to)


## Casts spell `sp` at its mage (`to`: from it to the mage). False when it
## does not fit now (out of reach, too many enemies...): tried again next frame.
func cast(sp: Dictionary, to: Vector2) -> bool:
	if not in_view(to):
		return false
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
			_zone.rpc(position, sp.radius, 0.8, dmg, 0.0, Color(data.color), 0.0, "shockwave")
		"puddle":  # a poison pool where the mage stands
			if d > 550.0:
				return false
			_zone.rpc(target.position, sp.radius, 1.0, 0.0, dmg, Color(data.color), 4.0, "poison")
		"charge":  # stops, then dashes at the mage
			if d > sp.range:
				return false
			windup = 0.6
			dash = Vector2.ONE  # dashing once the windup ends
			_zone.rpc(position, radius + 10.0, 0.6, 0.0, 0.0, Color.WHITE, 0.0, "")
		"summon":
			if get_tree().get_nodes_in_group("enemies").size() >= CROWD:
				return false
			for i in sp.count:
				var at := position + Vector2.from_angle(randf() * TAU) * (radius + 20.0)
				_zone.rpc(at, 24.0, 0.0, 0.0, 0.0, Color(data.color), 0.0, "summon")
				summoned.emit(sp.kind, at)
	return true


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
	elif statuses.has("burn"): tint = Color("#ffb08a")
	elif statuses.has("poison"): tint = Color("#d1b8ff")
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
		if not data.get("boss", false):  # bosses, seen a bit from the front: mirrored (_flip), never turned
			draw_set_transform(Vector2.ZERO, _angle - PI / 2.0)  # the art faces down
		draw_frame(self, tex, f, size, _flip, tint)
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
		Self.draw_frame(self, _tex, mini(int(age * FPS), n - 1), radius * 2.5, false,
			Color(1, 1, 1, clampf((_len() + FADE - age) / FADE, 0.0, 1.0)))


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
						p.hurt(damage)
					if dps > 0.0:
						p.hurt(dps * delta)
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
			Self.draw_frame(self, _fx_tex, f if linger > 0.0 else mini(f, n - 1), radius * 2.4, false,
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
	var from: Node2D  # its enemy, for its effect (may be dead by the hit)
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
