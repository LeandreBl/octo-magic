extends Node2D
## A drop: XP crystal, gold heap, mana or life orb, or blank scroll. Flies to the player once within
## its pickup stat (or `magnet`, raised at the end of a wave), then reports itself.
## Coop: simulated on the host, flies to the nearest mage; peers get its position.

signal collected(kind: String, value: int)

const SIZES := {"xp": 12.0, "gold": 18.0, "mana": 14.0, "life": 16.0, "scroll": 20.0}  # px on the floor
const REFILL := 0.25  # a mana or life orb gives back this share of the max

var kind := "xp"
var value := 1
var target: Node2D
var magnet := 0.0
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
		give(target)
		collected.emit(kind, value)
		queue_free()
	elif to.length() < maxf(magnet, target.stats.pickup):
		speed = minf(speed + 1200.0 * delta, 700.0)
		position += to.normalized() * minf(speed * delta, to.length())


## Mana and life orbs refill the mage who takes them (the rest goes to Run).
func give(p: Node2D) -> void:
	if kind == "life":
		p.heal(p.stats.hp * REFILL)
	elif kind == "mana":
		p.mana = minf(p.stats.mana, p.mana + p.stats.mana * REFILL)


func _draw() -> void:
	var tex := preload("res://ui/theme.gd").icon("scroll" if kind == "scroll" else "drop_" + kind)
	var sz: float = SIZES[kind]
	draw_texture_rect(tex, Rect2(-sz / 2.0, -sz / 2.0, sz, sz), false)
