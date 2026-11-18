extends Node2D
## A drop: gold heap, mana or life orb, blank scroll, grimoire (red: hero
## stats, blue: spell stats; Run opens its upgrade choice), or Quad Damage
## (the mage's spells hit QUAD times as hard for QUAD_TIME s). Flies to the player once within
## its pickup stat (or `magnet`, raised at the end of a wave), then reports itself.
## Coop: simulated on the host, flies to the nearest mage; peers get its position.

signal collected(kind: String, value: int)

const TEXTURES := {  # PixelLab, tools/make_icons.py
	"gold": preload("res://assets/icons/drop_gold.png"),
	"mana": preload("res://assets/icons/drop_mana.png"), "life": preload("res://assets/icons/drop_life.png"),
	"scroll": preload("res://assets/icons/scroll.png"),
	"grimoire_hero": preload("res://assets/icons/drop_grimoire_hero.png"),
	"grimoire_spell": preload("res://assets/icons/drop_grimoire_spell.png"),
	"quad": preload("res://assets/icons/drop_quad.png"),
}
## A gold heap looks as rich as it is: (min value, texture, px), the last one reached wins.
const GOLD_TIERS := [
	[1, preload("res://assets/icons/drop_gold_1.png"), 18.0],
	[2, preload("res://assets/icons/drop_gold_2.png"), 22.0],
	[3, preload("res://assets/icons/drop_gold.png"), 24.0],
	[10, preload("res://assets/icons/drop_gold_hoard.png"), 36.0],
]
const SIZES := {"gold": 24.0, "mana": 20.0, "life": 22.0, "scroll": 24.0, "grimoire_hero": 26.0, "grimoire_spell": 26.0, "quad": 26.0}  # px on the floor
const RADIUS := 6.0  # px: its body against the obstacles as it flies
const REFILL := 0.25  # a mana or life orb gives back this share of the max
const QUAD := 4.0
const QUAD_TIME := 10.0  # s
const HOPS := [[0.32, 26.0], [0.18, 7.0]]  # gold pops out of the enemy: (duration s, height px) per hop
const HALO := 1.8  # the gold glow under a drop, to spot it on the floor: its size, x the drop's
static var _halo := _make_halo()
const SHINE := {"size": 24, "frames": 7, "fps": 12, "loop": false}  # assets/icons/drop_gold_shine.png

var kind := "gold"
var value := 1
var target: Node2D
var magnet := 0.0
var speed := 0.0
var age := 0.0  # drawn only: the synced position stays on the floor


func _process(delta: float) -> void:
	_shimmer()
	var total: float = HOPS[0][0] + HOPS[1][0]
	if kind != "gold" or age >= total:
		return
	age += delta
	queue_redraw()
	if age >= total:  # settled: the heap glints once
		var fx := SpellBody.Burst.new()
		fx.tex = preload("res://assets/icons/drop_gold_shine.png")
		fx.s = SHINE
		fx.position = position
		fx.scale = Vector2.ONE * 0.5
		get_parent().add_child(fx)


## Gold's draw offset and squash while it bounces: (lift px, squash 0..1).
func _hop() -> Vector2:
	var t := age
	for h in HOPS:
		if t < h[0]:
			var k: float = t / h[0]
			return Vector2(h[1] * sin(PI * k), 1.0 - absf(sin(PI * k)))
		t -= h[0]
	return Vector2.ZERO


## A soft shimmer: brightness drifts around white, each drop on its own phase.
func _shimmer() -> void:
	var v := 1.0 + 0.15 * sin(Arena.clock * 4.0 + get_instance_id() % 628 * 0.01)
	modulate = Color(v, v, v)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	target = preload("res://game/enemy.gd").nearest_player(self, wants)
	if not is_instance_valid(target):
		return
	var to := target.position - position
	if to.length() < target.radius + 6.0:
		give(target)
		collected.emit(kind, value)
		queue_free()
	elif to.length() < maxf(magnet, target.stats.pickup):
		speed = minf(speed + 1200.0 * delta, 700.0)
		# Around the obstacles, as a monster walks: down the flow field, sliding along them.
		position = Arena.slide(position, Arena.way(position, target.position) * minf(speed * delta, to.length()), RADIUS)


## A mana or life orb stays on the floor for a mage whose gauge is full.
func wants(p: Node2D) -> bool:
	if kind == "life":
		return p.hp < p.stats.hp
	if kind == "mana":
		return p.mana < p.stats.mana
	return true


## Mana and life orbs refill the mage who takes them (the rest goes to Run).
func give(p: Node2D) -> void:
	if kind == "life":
		p.heal(p.stats.hp * REFILL * p.stats.orbs)
	elif kind == "mana":
		p.mana = minf(p.stats.mana, p.mana + p.stats.mana * REFILL * p.stats.orbs)
	elif kind == "quad":
		p.afflict("quad", QUAD, QUAD_TIME)


## The gold tier for `value` (see GOLD_TIERS).
static func gold_tier(v: int) -> Array:
	var tier: Array = GOLD_TIERS[0]
	for t in GOLD_TIERS:
		if v >= t[0]:
			tier = t
	return tier


func _draw() -> void:
	var sz: float = SIZES[kind]
	var tex: Texture2D = TEXTURES[kind]
	if kind == "gold":
		var tier := gold_tier(value)
		tex = tier[1]
		sz = tier[2]
	var hop := _hop()
	if hop.x > 0.0:  # squashed as it touches the floor
		draw_set_transform(Vector2(0, -hop.x + hop.y * sz * 0.1), 0.0, Vector2(1.0 + hop.y * 0.2, 1.0 - hop.y * 0.2))
	var h := sz * HALO
	draw_texture_rect(_halo, Rect2(-h / 2.0, -h / 2.0, h, h), false)
	draw_texture_rect(tex, Rect2(-sz / 2.0, -sz / 2.0, sz, sz), false)


static func _make_halo() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.82, 0.25, 0.55), Color(1.0, 0.82, 0.25, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex
