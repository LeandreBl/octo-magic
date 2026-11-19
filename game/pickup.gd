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
const HALO := 1.8  # the glow under a drop, to spot it on the floor: its size, x the drop's
## A scroll on the floor shines a golden aura, to spot it from afar: (size x the drop's, texture).
const AURA_WIDE := 9.0
const AURA_CORE := 3.5
static var _aura_wide := _make_halo(Color(1.0, 0.6, 0.1), 1.0, 0.55)
static var _aura_core := _make_halo(Color(1.0, 0.85, 0.45), 1.0, 0.7)
static var _halo := _make_halo(Color(1.0, 0.82, 0.25))
## A grimoire glows its own colour, and twinkles: red for the hero, blue for the spells.
static var _halos := {
	"grimoire_hero": _make_halo(Color(1.0, 0.2, 0.15), 0.8),
	"grimoire_spell": _make_halo(Color(0.25, 0.55, 1.0), 0.8),
}
const SHINE := {"size": 24, "frames": 7, "fps": 12, "loop": false}  # assets/icons/drop_gold_shine.png

var kind := "gold"
var value := 1
var target: Node2D
var magnet := 0.0
var speed := 0.0
var age := 0.0  # drawn only: the synced position stays on the floor


## A scroll's aura: additive light behind it, breathing slowly, each scroll on its own phase.
func _ready() -> void:
	if kind != "scroll":
		return
	var aura := Node2D.new()
	aura.name = "Aura"
	aura.show_behind_parent = true
	aura.material = CanvasItemMaterial.new()
	aura.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # light, not paint
	aura.draw.connect(func():
		for a in [[_aura_wide, SIZES.scroll * AURA_WIDE], [_aura_core, SIZES.scroll * AURA_CORE]]:
			aura.draw_texture_rect(a[0], Rect2(-a[1] / 2.0, -a[1] / 2.0, a[1], a[1]), false))
	add_child(aura)


func _process(delta: float) -> void:
	_shimmer()
	if has_node("Aura"):
		$Aura.scale = Vector2.ONE * (1.0 + 0.12 * sin(Arena.clock * 2.5 + get_instance_id() % 628 * 0.01))
	if kind in _halos:
		queue_redraw()  # the halo twinkles
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
	if kind == "scroll":  # its aura (see _ready) instead of the halo
		draw_texture_rect(tex, Rect2(-sz / 2.0, -sz / 2.0, sz, sz), false)
		return
	var h := sz * HALO
	var halo: Texture2D = _halos.get(kind, _halo)
	var glow := Color.WHITE
	if kind in _halos:  # twinkle: a slow swell with a quick flicker on top, each grimoire on its own phase
		var t := Arena.clock + get_instance_id() % 628 * 0.01
		h *= 1.15 + 0.15 * sin(t * 3.0)
		glow.a = clampf(0.75 + 0.25 * sin(t * 3.0) * sin(t * 11.0), 0.0, 1.0)
	draw_texture_rect(halo, Rect2(-h / 2.0, -h / 2.0, h, h), false, glow)
	draw_texture_rect(tex, Rect2(-sz / 2.0, -sz / 2.0, sz, sz), false)


static func _make_halo(c: Color, alpha := 0.55, mid := 0.65) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])  # mid: the light left at 35%: 0.65 is a straight fade
	g.colors = PackedColorArray([Color(c, alpha), Color(c, alpha * mid), Color(c, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex
