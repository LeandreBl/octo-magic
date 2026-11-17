extends Node2D
## A chasing enemy. Implements the target interface used by SpellBody.

var target: Node2D
var hp := 20.0
var max_hp := 20.0
var speed := 80.0
var radius := 12.0
var touch_damage := 10.0
var statuses := {}  # name -> [power, time_left]
var knock := Vector2.ZERO
var hit_cooldown := 0.0


func _ready() -> void:
	add_to_group("enemies")


func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		queue_free()


func add_status(status: String, power: float, duration: float) -> void:
	var cur: Array = statuses.get(status, [0.0, 0.0])
	statuses[status] = [maxf(cur[0], power), maxf(cur[1], duration)]


func push(velocity: Vector2) -> void:
	knock += velocity


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
	if is_queued_for_deletion() or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	position += to.normalized() * speed * slow * delta + knock * delta
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	hit_cooldown -= delta
	if to.length() < radius + target.radius and hit_cooldown <= 0.0:
		hit_cooldown = 0.6
		target.hurt(touch_damage)
	queue_redraw()


func _draw() -> void:
	var c := Color("#4caf50")
	if statuses.has("freeze"): c = Color("#9be7ff")
	elif statuses.has("burn"): c = Color("#ff8a50")
	elif statuses.has("poison"): c = Color("#b388ff")
	draw_circle(Vector2.ZERO, radius, c)
	draw_rect(Rect2(-radius, -radius - 8, 2 * radius * hp / max_hp, 3), Color.RED)
