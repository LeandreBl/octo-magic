extends Node2D
## A drop: XP orb, gold coin or blank scroll. Flies to the player once close
## (or when `magnet` is raised at the end of a wave), then reports itself.
## Coop: simulated on the host, flies to the nearest mage; peers get its position.

signal collected(kind: String, value: int)

const COLORS := {"xp": "#4fc3f7", "gold": "#ffd54f", "scroll": "#fff3e0"}

var kind := "xp"
var value := 1
var target: Node2D
var magnet := 90.0
var speed := 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var near := preload("res://game/enemy.gd").nearest_player(self)
	if near:
		target = near
	if not is_instance_valid(target):
		return
	var to := target.position - position
	if to.length() < target.radius + 6.0:
		collected.emit(kind, value)
		queue_free()
	elif to.length() < magnet:
		speed = minf(speed + 1200.0 * delta, 700.0)
		position += to.normalized() * minf(speed * delta, to.length())


func _draw() -> void:
	var c := Color(COLORS[kind])
	if kind == "scroll":
		draw_rect(Rect2(-7, -9, 14, 18), c)
		draw_rect(Rect2(-7, -9, 14, 18), Color("#8d6e63"), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, 4.0 if kind == "xp" else 5.0, c)
