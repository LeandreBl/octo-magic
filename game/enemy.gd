extends Node2D
## An enemy. Implements the target interface used by SpellBody.
## Kinds (stats from Run.enemy_stats): melee chases, fast chases quicker,
## ranged keeps its distance and shoots, boss chases and fires rings of shots.

signal killed(enemy: Node2D)

const COLORS := {"melee": "#4caf50", "fast": "#ffca28", "ranged": "#26c6da", "boss": "#8e24aa"}
const RANGE := 260.0  # distance a ranged enemy keeps

var kind := "melee"
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
var shot_timer := 2.0


func setup(k: String, s: Dictionary) -> void:
	kind = k
	max_hp = s.hp
	hp = s.hp
	speed = s.speed
	radius = s.radius
	touch_damage = s.damage
	xp = s.xp
	gold = s.gold


func _ready() -> void:
	add_to_group("enemies")


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		killed.emit(self)
		queue_free()


func add_status(status: String, power: float, duration: float) -> void:
	var cur: Array = statuses.get(status, [0.0, 0.0])
	statuses[status] = [maxf(cur[0], power), maxf(cur[1], duration)]


func push(velocity: Vector2) -> void:
	knock += velocity * (0.3 if kind == "boss" else 1.0)


func _physics_process(delta: float) -> void:
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
	if hp <= 0.0 or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	var dir := to.normalized()
	if kind == "ranged":  # hold the range, strafe around the player
		var d := to.length()
		dir = dir if d > RANGE + 30.0 else -dir if d < RANGE - 30.0 else dir.orthogonal()
	position += dir * speed * slow * delta + knock * delta
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	hit_cooldown -= delta
	if to.length() < radius + target.radius and hit_cooldown <= 0.0:
		hit_cooldown = 0.6
		target.hurt(touch_damage)
	shot_timer -= delta * slow
	if shot_timer <= 0.0 and kind in ["ranged", "boss"]:
		_shoot(to)
	queue_redraw()


func _shoot(to: Vector2) -> void:
	if kind == "boss":
		shot_timer = 3.0
		var a := randf() * TAU
		for i in 12:
			_shot(Vector2.from_angle(a + TAU * i / 12), 180.0)
	else:
		shot_timer = 2.0
		_shot(to.normalized(), 260.0)


func _shot(dir: Vector2, v: float) -> void:
	var s := Shot.new()
	s.position = position
	s.velocity = dir * v
	s.damage = touch_damage * 0.8
	s.target = target
	get_parent().add_child(s)


func _draw() -> void:
	var c := Color(COLORS[kind])
	if statuses.has("freeze"): c = Color("#9be7ff")
	elif statuses.has("burn"): c = Color("#ff8a50")
	elif statuses.has("poison"): c = Color("#b388ff")
	draw_circle(Vector2.ZERO, radius, c)
	if kind == "ranged":
		draw_circle(Vector2.ZERO, radius * 0.45, Color("#004d55"))
	elif kind == "boss":
		draw_arc(Vector2.ZERO, radius + 3, 0, TAU, 40, Color("#ffd54f"), 3.0)
	draw_rect(Rect2(-radius, -radius - 8, 2 * radius * maxf(hp, 0.0) / max_hp, 3), Color.RED)


## An enemy projectile: flies straight, hurts the player on touch.
class Shot extends Node2D:
	const RADIUS := 5.0
	var velocity := Vector2.ZERO
	var damage := 5.0
	var target: Node2D
	var age := 0.0

	func _physics_process(delta: float) -> void:
		position += velocity * delta
		age += delta
		if is_instance_valid(target) and position.distance_to(target.position) < RADIUS + target.radius:
			target.hurt(damage)
			queue_free()
		elif age > 6.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, RADIUS, Color("#ff5252"))
		draw_circle(Vector2.ZERO, RADIUS * 0.5, Color.WHITE)
