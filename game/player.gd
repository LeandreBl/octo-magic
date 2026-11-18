extends Node2D
## The mage. Twin-stick: keyboard/mouse, gamepad, or touch (left half of the
## screen moves, right half aims and fires the main spell).
## Main spell: left click / right stick or RT / touch aim; secondary (an active
## augment): right click / Space / RB. `held` lets a touch UI fire them.
## Passive augments (PASSIVES): "shield" absorbs SHIELD_HP damage, comes back
## SHIELD_WAIT seconds after it breaks; "potions": POTIONS heals of POTION_HEAL,
## drunk below POTION_AT of the max HP; "blaze_of_glory": BLAZE bursts out of
## the mage as it dies (its kills count); "weird_eye": arrows to the grimoires
## and scrolls on the floor (drawn for the local mage).
## Every number of the mage comes from `stats` (game/stats.gd, from the loadout).
## Coop (see main.gd): the owner peer steers its mage (position, aim, firing
## are synced from it); the host owns the rest (hp, mana, loadout, statuses)
## and casts. Statuses from enemies (afflict): poison hurts every second (never below 1 hp),
## freeze slows, stun roots; the owner reads them to steer.

signal died

const ZOOM := 4.0 / 3.0  # on the mage: an art pixel (Arena.SCALE 1.5) is 2 screen pixels, the arena (Arena.RECT) about 2.4x2.8 screens
const SIZE := 1.2  # the mage drawn this much bigger than its art (sprite, tentacles, gem); the hitbox `radius` stays
const STICK_RANGE := 80.0
const MISSILE_FAN := 12.0  # degrees between Plura Tela missiles, on a spell with no spread
const STILL_TIME := 3.0  # s without moving before the mage channels
const SHIELD_HP := 40.0
const SHIELD_WAIT := 8.0
const PASSIVES := ["shield", "potions", "blaze_of_glory", "weird_eye"]
const POTIONS := 3
const POTION_AT := 0.3
const POTION_HEAL := 0.5
## A status's filter on the mage (rgb, a: strength), the first one it has wins.
const STATUS_FILTERS := {"quad": Color(0.7, 0.4, 1.0, 0.5), "freeze": Color(0.45, 0.8, 1.0, 0.6),
	"stun": Color(1.0, 0.95, 0.4, 0.45), "burn": Color(1.0, 0.45, 0.15, 0.55), "poison": Color(0.4, 0.9, 0.3, 0.55)}
const BURN_TIME := 0.6  # s: the burn filter after the last fire damage
const BLAZE := {"name": "Blaze of glory", "element": "fire", "color": "#ff7a1f", "cooldown": 1.0,
	"emit": {"pattern": "radial", "count": 24, "body": {"shape": "bolt", "speed": 380, "size": 10, "lifetime": 0.9,
		"on_hit": [{"type": "damage", "amount": 80}, {"type": "status", "status": "burn", "power": 5, "duration": 2}]}}}
const RATIO_STEPS := 20.0  # a cast short of mana deals its share of damage in 1/20 steps
const LEVEL_UP_HEAL := 100.0  # health and mana a level-up gives back (capped at the max)
## The octopus seen from above (PixelLab, tools/make_octopus.py): strips of
## square frames, head to the top, turned toward where it goes. Its ground
## tentacles are not in them: TENTACLES of game/tentacle.gd under the body.
## "cast": the staff struck forward, played once per non-channeled cast.
const SPRITES := {"idle": preload("res://assets/octo/idle.png"), "cast": preload("res://assets/octo/cast.png")}
const Tentacle := preload("res://game/tentacle.gd")
const TENTACLES := 8
const CAST_TIME := 0.4  # s: the staff strike and the gem's flash, once per cast
## Where the staff's crystal is in each frame, in pixels from the center, head
## up: spells leave from it and it flashes on a cast. Measured on the PixelLab
## strips (centroid of the bright blue pixels); remeasure when they are redrawn.
const GEM := {"idle": [Vector2(17, -20.7)],
	"cast": [Vector2(17, -18.6), Vector2(17, -15.6), Vector2(-14.9, -29.3), Vector2(-11.8, -27.8),
		Vector2(-11.3, -28.5), Vector2(-7.7, -28.3), Vector2(1.1, -26.2), Vector2(7.8, -24)]}
const GEM_GLOW := Color("#8fe9ff")
const DYE := preload("res://game/dye.gdshader")

var run: Object  # spells and mana costs: a Loadout in game, a Run in tests
var peer_id := 1  # the owner's peer; 1 = host (or solo)
var firing := {}  # slot -> bool, from the owner
## Spells, stats and look as sanitized JSON (see clean_loadout), synced from
## the host to every peer.
var loadout_json := "":
	set(v):
		loadout_json = v
		var l: Variant = JSON.parse_string(v) if v else null
		if l is Dictionary:
			_apply(l)
var stats := Stats.total([])
var hp: float = stats.hp
var mana: float = stats.mana
var passives := []  # Profile.AUGMENTS passive ids, those of PASSIVES
var potions := 0  # left this run
var shield := 0.0  # hp left on the shield, synced for drawing
var shield_wait := 0.0  # seconds until a broken shield is back
var statuses := {}  # name -> [power, time_left], from the host
var cooldowns := {}  # slot -> seconds left
var held := {}  # slot -> bool, from a touch UI
var _weak := {}  # slot -> [spell, ratio, its weakened version], see _spell
var aim := Vector2.RIGHT
var radius := 12.0
var look := {"hat": "#3a2a99", "robe": "#6a4cff", "staff": "#8d6e63", "ring": ""}

var _angle := 0.0  # where the sprite heads: its move, else its aim (turned smoothly)
var _moving := false
var _still := 0.0  # s since the mage last moved: past STILL_TIME it channels (Meditatio skill)
var _cast_t := 0.0  # s left of the cast animation
var _channel_t := 0.0  # s left of the channel animation: renewed by each tick of a beam or cone
var _last_pos := Vector2.ZERO
var velocity := Vector2.ZERO  # px/s, from its synced position (smoothed)
var _heard_hp: float = stats.hp  # hosts and peers hear hurts on the synced hp
var _touch_move := {}  # finger index -> [start, current]
var _touch_aim := {}
var _dye := [dyed(true), dyed(false)]  # look.hat on the body sprite, on the tentacles


## Full HP and mana with these stats, at the start of a run.
func setup(s: Dictionary) -> void:
	stats = s
	hp = s.hp
	statuses = {}
	mana = s.mana
	cooldowns = {}
	shield_wait = 0.0


func _ready() -> void:
	add_to_group("players")
	scale = Vector2.ONE * SIZE
	material = _dye[0]
	for i in TENTACLES:
		var t := Tentacle.new((i + 0.5) * TAU / TENTACLES, i % 2)
		t.size = SIZE
		t.material = _dye[1]
		add_child(t)
	for m in _dye:
		dye(m, look.hat)
	if peer_id == multiplayer.get_unique_id():  # this peer's mage stays mid-screen, the map scrolls
		var cam := Camera2D.new()  # stops at the arena's edges: near one, the mage leaves mid-screen
		cam.zoom = Vector2.ONE * ZOOM
		cam.limit_left = int(Arena.RECT.position.x)
		cam.limit_top = int(Arena.RECT.position.y)
		cam.limit_right = int(Arena.RECT.end.x)
		cam.limit_bottom = int(Arena.RECT.end.y)
		add_child(cam)
		cam.make_current()
		var ear := AudioListener2D.new()  # world sounds are heard from the mage, not the edge-clamped camera
		add_child(ear)
		ear.make_current()
		_fit_camera(cam)
		get_viewport().size_changed.connect(_fit_camera.bind(cam))


## ZOOM, or closer when the window is so elongated (a tall phone in portrait,
## a very wide screen) that the arena would not fill it.
func _fit_camera(cam: Camera2D) -> void:
	var fit := get_viewport_rect().size / Arena.RECT.size
	cam.zoom = Vector2.ONE * maxf(ZOOM, maxf(fit.x, fit.y))


## A player's loadout as it sends it (untrusted) -> a clean one: spells
## sanitized and priced here, stats clamped. "fresh": start of a run.
static func clean_loadout(raw: Variant) -> Dictionary:
	var l: Dictionary = raw if raw is Dictionary else {}
	var spells := {}
	var costs := {}
	var st: Dictionary = l.get("stats") if l.get("stats") is Dictionary else {}
	var stats := {}
	for k in Stats.BASE:
		stats[k] = _clamp(st.get(k), Stats.BASE[k], Stats.BOUNDS[k][0], Stats.BOUNDS[k][1])
	for slot in Spell.RUN_SLOTS:
		var s: Variant = l.get("spells", {}).get(slot) if l.get("spells") is Dictionary else null
		if s is Dictionary:
			spells[slot] = Spell.sanitize(s)
			costs[slot] = Stats.cost(Spell.mana_cost(spells[slot]), Stats.cost_mult(stats, slot))
	var look_in: Dictionary = l.get("look") if l.get("look") is Dictionary else {}
	var out_look := {}
	for k in ["hat", "robe", "staff", "ring"]:
		out_look[k] = Spell._color(look_in.get(k)) if look_in.get(k) else ""
	return {"spells": spells, "costs": costs, "look": out_look, "fresh": l.get("fresh") == true,
		"refill": l.get("refill") == true,
		"passives": (l.get("passives") if l.get("passives") is Array else []).filter(func(id): return id in PASSIVES),
		"stats": stats}


## The dye of game/dye.gdshader for the body sprite (`body`: its hat's ribbon
## and its staff's grip) or a tentacle (all of it), in the color `hat`.
static func dyed(body: bool, hat := "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DYE
	m.set_shader_parameter("body", body)
	dye(m, hat)
	return m


## `m` (from dyed) now in the color `hat`; "": the art's own colors.
static func dye(m: ShaderMaterial, hat: String) -> void:
	m.set_shader_parameter("on", Color.html_is_valid(hat))
	if Color.html_is_valid(hat):
		m.set_shader_parameter("dye", Color(hat))


static func _clamp(v: Variant, default: float, lo: float, hi: float) -> float:
	return clampf(float(v), lo, hi) if v is float or v is int else default


func _apply(l: Dictionary) -> void:
	var lo := Loadout.new()
	lo.spells = l.spells
	lo.costs = l.costs
	run = lo
	for k in l.look:
		if l.look[k] or k == "ring":
			look[k] = l.look[k]
	for m in _dye:
		dye(m, look.hat)
	if l.fresh:
		setup(l.stats)
	else:  # a skill: the extra health and mana come filled
		hp += maxf(0.0, l.stats.hp - stats.hp)
		mana += maxf(0.0, l.stats.mana - stats.mana)
		stats = l.stats
	if l.refill:  # a level-up
		hp = minf(stats.hp, hp + LEVEL_UP_HEAL)
		mana = minf(stats.mana, mana + LEVEL_UP_HEAL)
	if l.passives != passives:  # a new run
		passives = l.passives
		shield = SHIELD_HP if "shield" in passives else 0.0
		potions = POTIONS if "potions" in passives else 0


class Loadout:
	var spells := {}
	var costs := {}

	func mana_cost(slot: String) -> float:
		return costs[slot]


func heal(amount: float) -> void:
	hp = minf(stats.hp, hp + amount)


## `fire`: fire damage (fire mages and archers, burning skeletons, fire pools), under the "fire" stat.
func hurt(amount: float, fire := false, poison := false) -> void:
	if hp <= 0.0:
		return
	amount *= (1.0 - stats.armor) * (stats.fire if fire else 1.0)
	var absorbed := minf(shield, amount)
	if absorbed > 0.0:
		shield -= absorbed
		amount -= absorbed
		if shield <= 0.0:
			shield_wait = SHIELD_WAIT
	if fire and amount > 0.0:  # burnt: only a filter (STATUS_FILTERS), fire hurts no longer
		afflict("burn", 0.0, BURN_TIME)
	if poison:  # poison never kills: it leaves the mage at 1 hp at worst
		amount = maxf(0.0, minf(amount, hp - 1.0))
	hp -= amount
	if hp > 0.0 and hp < stats.hp * POTION_AT and potions > 0:
		potions -= 1
		heal(stats.hp * POTION_HEAL)
	if hp <= 0.0:
		if "blaze_of_glory" in passives and is_inside_tree():
			_blaze.rpc()
		died.emit()


## Blaze of glory: cast by the host (its bodies hurt), drawn by the peers.
@rpc("authority", "call_local", "reliable")
func _blaze() -> void:
	var s := Spell.sanitize(BLAZE)
	SpellBody.cast(s.emit, global_position, aim, self, s, get_parent())


## Status `status` from an enemy for `duration` s (host): the strongest and
## longest of the current one and this one.
func afflict(status: String, power: float, duration: float) -> void:
	if hp <= 0.0:
		return
	var cur: Array = statuses.get(status, [0.0, 0.0])
	statuses[status] = [maxf(cur[0], power), maxf(cur[1], duration)]


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var half := get_viewport_rect().size.x / 2.0
		var slot := _touch_move if event.position.x < half else _touch_aim
		if event.pressed:
			slot[event.index] = [event.position, event.position]
		else:
			_touch_move.erase(event.index)
			_touch_aim.erase(event.index)
	elif event is InputEventScreenDrag:
		for slot in [_touch_move, _touch_aim]:
			if slot.has(event.index):
				slot[event.index][1] = event.position


func _stick(slot: Dictionary) -> Vector2:
	for k in slot:
		return ((slot[k][1] - slot[k][0]) / STICK_RANGE).limit_length(1.0)
	return Vector2.ZERO


func _physics_process(delta: float) -> void:
	queue_redraw()
	var step := position - _last_pos  # from the synced position: the same on every peer
	_last_pos = position
	if delta > 0.0:  # smoothed over the synced jitter: what predicting enemies lead
		velocity = velocity.lerp(step / delta, minf(1.0, 8.0 * delta))
	_moving = step.length() > 0.5
	_still = 0.0 if _moving else _still + delta
	_cast_t -= delta
	_channel_t -= delta
	var heading := aim if _cast_t > 0.0 or _channel_t > 0.0 or not _moving else step  # casting: faces its aim
	_angle = lerp_angle(_angle, heading.angle(), minf(1.0, 12.0 * delta))
	var t := Arena.clock
	var near := []  # the enemies within a tentacle's reach: its obstacles
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(global_position) < (Tentacle.ROOT + Tentacle.LENGTH) * SIZE + e.radius:
			near.append([e.global_position, e.radius])
	for c in get_children():
		if c is Tentacle:
			c.follow(global_position, _angle, delta, t, Arena.RECT, near, true)
	if hp < _heard_hp - 0.5:
		if hp <= 0.0:
			Sfx.play("death", null if peer_id == multiplayer.get_unique_id() else global_position)
		elif peer_id == multiplayer.get_unique_id():
			Sfx.play("hurt")
	_heard_hp = hp
	if peer_id == multiplayer.get_unique_id() and hp > 0.0:
		_steer(delta)
	if not multiplayer.is_server() or hp <= 0.0:
		return
	for st in statuses.keys():
		statuses[st][1] -= delta
		if st == "poison":
			hurt(statuses[st][0] * delta * stats.poison, false, true)
		if statuses[st][1] <= 0.0:
			statuses.erase(st)
	mana = minf(stats.mana, mana + stats.mana_regen * (stats.still_regen if channeling() else 1.0) * delta)
	hp = minf(stats.hp, hp + stats.hp_regen * delta)
	if shield_wait > 0.0:
		shield_wait -= delta
		if shield_wait <= 0.0 and "shield" in passives:
			shield = SHIELD_HP
	for slot in Spell.RUN_SLOTS:
		cooldowns[slot] = cooldowns.get(slot, 0.0) - delta
		if firing.get(slot, false) and run and run.spells.has(slot):
			cast(slot)


func _steer(delta: float) -> void:
	# Input actions (project.godot): rebindable keys, arrows, left stick (ui/settings.gd).
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move = (move + _stick(_touch_move)).limit_length(1.0)
	if statuses.has("stun"):
		move = Vector2.ZERO
	elif statuses.has("freeze"):
		move *= 0.5
	position = Arena.slide(position, move * stats.speed * delta + Arena.apart(self, get_tree().get_nodes_in_group("players")), radius).clamp(Arena.RECT.position, Arena.RECT.end)

	# Gamepad (any connected one): right stick aims and fires, RT fires
	# where the mage aims; with the right stick idle it aims where it walks.
	var fire := Input.is_action_pressed("fire")
	var pad_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var touch_aim := _stick(_touch_aim)
	if pad_aim != Vector2.ZERO:
		aim = pad_aim.normalized()
		fire = true
	elif touch_aim.length() > 0.2:
		aim = touch_aim.normalized()
		fire = true
	elif Settings.pad:
		if move.length() > 0.3:
			aim = move.normalized()
	elif _touch_aim.is_empty():
		aim = (get_global_mouse_position() - global_position).normalized()
		fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	firing = {
		"primary": fire or held.get("primary", false),
		"secondary": Input.is_action_pressed("cast_secondary") or held.get("secondary", false),
	}


func cast(slot: String) -> bool:
	if cooldowns.get(slot, 0.0) > 0.0:
		return false
	# Short of mana it still casts, weakened, on what is left: that share of the
	# cost deals that share of the damage. Stepped by 5 % (at least 5 %) so a
	# channel's ticks keep one weakened body (SpellBody._channeled).
	var cost: float = run.mana_cost(slot)
	var ratio := clampf(ceilf(maxf(mana, 0.0) / cost * RATIO_STEPS) / RATIO_STEPS, 1.0 / RATIO_STEPS, 1.0)
	var s := _spell(slot, ratio)
	# Vis Teli (Upgrades "potent_missiles"): the primary cast hits harder; an
	# engine stat, not spell data: no forged spell has it, nor pays mana for it.
	var mult: float = stats.get("potency", 1.0) if slot == "primary" and ratio >= 1.0 else 1.0
	if randf() < stats.crit:
		mult *= Stats.CRIT_MULT
	if mult != 1.0:
		s = Spell.scale_damage(s, mult)
	mana = maxf(0.0, mana - cost)
	cooldowns[slot] = s.cooldown * stats.cooldown / stats.cast_rate
	_animate_cast(s)
	SpellBody.cast(emit(slot, s), gem(), aim, self, s, get_parent())
	_cast_fx.rpc(slot, gem(), aim, ratio)
	return true


## The emit `slot`'s spell `s` is cast with: the Plura Tela sub-skill
## (Upgrades "more_missiles") adds its "missiles" stat to the primary's bodies,
## fanned out over MISSILE_FAN degrees a body when the spell has no spread.
## An engine stat, not spell data: no forged spell has it, nor pays mana for it.
func emit(slot: String, s: Dictionary) -> Dictionary:
	var n := int(stats.get("missiles", 0.0))
	if slot != "primary" or n == 0 or s.has("weak"):  # no sub-skill on a cast short of mana
		return s.emit
	var e: Dictionary = s.emit.duplicate()
	e.count += n
	if e.spread == 0:
		e.spread = MISSILE_FAN * n
	return e


## The spell of `slot`, weakened (Spell.weakened) when ratio < 1 (cast
## short of mana). Kept
## while the slot's spell and ratio hold: a channel's ticks renew one body.
func _spell(slot: String, ratio: float) -> Dictionary:
	var s: Dictionary = run.spells[slot]
	if ratio >= 1.0:
		return s
	var w: Array = _weak.get(slot, [])
	if w.is_empty() or not is_same(w[0], s) or w[1] != ratio:
		w = [s, ratio, Spell.weakened(s, ratio)]
		_weak[slot] = w
	return w[2]


## Peers only draw the host's casts: their bodies apply no effects.
@rpc("authority", "call_remote", "unreliable_ordered")
func _cast_fx(slot: String, pos: Vector2, dir: Vector2, ratio := 1.0) -> void:
	if run and run.spells.has(slot):
		var s := _spell(slot, ratio)
		SpellBody.cast(emit(slot, s), pos, dir, self, s, get_parent())
		_animate_cast(s)


## A channeled spell (beam, cone) keeps the gem glowing while it ticks; any
## other flashes it once (not restarted before half way, for fast spells).
func _animate_cast(s: Dictionary) -> void:
	if s.emit.body.shape in ["beam", "cone"]:
		_channel_t = s.cooldown + 0.15
	elif _cast_t < CAST_TIME / 2.0:
		_cast_t = CAST_TIME


## The animation and frame drawn now: the cast strip while a cast plays (not
## while channeling: a beam or cone only glows), else the idle loop.
func _frame() -> Array:
	var anim := "cast" if _cast_t > 0.0 and _channel_t <= 0.0 else "idle"
	var frames: int = SPRITES[anim].get_width() / SPRITES[anim].get_height()
	var f := int(Arena.clock * 8.0) % frames
	if anim == "cast":
		f = clampi(int((1.0 - _cast_t / CAST_TIME) * frames), 0, frames - 1)
	return [anim, f]


## The staff's crystal of the frame drawn now, in the sprite's coordinates.
func _gem_local() -> Vector2:
	var af := _frame()
	var pts: Array = GEM[af[0]]
	return pts[mini(af[1], pts.size() - 1)]


## The staff's crystal, in global coordinates, as drawn now.
func gem() -> Vector2:
	return global_position + SIZE * _gem_local().rotated(_angle + PI / 2.0)


## Standing still with the Meditatio skill: mana regen times stats.still_regen.
## A short wait so a frame without a synced position is not a stop.
func channeling() -> bool:
	return stats.still_regen > 1.0 and _still > STILL_TIME


func _draw() -> void:
	modulate.a = 1.0 if hp > 0.0 else 0.3  # down until the next run
	if channeling() and hp > 0.0:  # mana spirals in
		for i in 3:
			var a := Arena.clock * 3.0 + i * TAU / 3.0
			draw_arc(Vector2.ZERO, radius + 4.0 + 2.0 * sin(Arena.clock * 4.0), a, a + 1.2, 8, Color(0.4, 0.7, 1.0, 0.6), 2.0)
	var af := _frame()
	var tex: Texture2D = SPRITES[af[0]]
	var f: int = af[1]
	var size := float(tex.get_height())
	draw_set_transform(Vector2.ZERO, _angle + PI / 2.0)  # the sprite's head is up
	var filter := Color.TRANSPARENT  # on the body and the tentacles (game/dye.gdshader)
	for st in STATUS_FILTERS:
		if statuses.has(st):
			filter = STATUS_FILTERS[st]
			break
	for m in _dye:
		m.set_shader_parameter("status", filter)
	draw_texture_rect_region(tex, Rect2(Vector2(-size, -size) / 2.0, Vector2(size, size)), Rect2(f * size, 0, size, size))
	# The gem's glow: a flash fading over a cast, a steady flicker while channeling.
	var glow := 0.7 + 0.3 * sin(Arena.clock * 25.0) if _channel_t > 0.0 else maxf(0.0, _cast_t / CAST_TIME)
	var gem_at := _gem_local()
	if glow > 0.0:
		draw_circle(gem_at, 6.0 * glow, Color(GEM_GLOW, 0.35 * glow))
		draw_circle(gem_at, 3.5 * glow, Color(GEM_GLOW, 0.7 * glow))
		draw_circle(gem_at, 1.5 * glow, Color(Color.WHITE, glow))
	draw_set_transform(Vector2.ZERO)
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 6, 0.0, TAU, 32, Color(0.5, 0.85, 1.0, 0.3 + 0.5 * shield / SHIELD_HP), 3.0)
	if "weird_eye" in passives and peer_id == multiplayer.get_unique_id():
		for d in get_tree().get_nodes_in_group("pickups"):
			var to: Vector2 = (d.position - position) / SIZE
			if (d.kind.begins_with("grimoire") or d.kind == "scroll") and to.length() > 80.0:
				var u := to.normalized()
				var tip := u * 34.0
				draw_colored_polygon(PackedVector2Array([tip, tip - u * 9.0 + u.orthogonal() * 5.0,
					tip - u * 9.0 - u.orthogonal() * 5.0]), Color("#ffd54f"))
