extends Node2D
## The mage. Twin-stick: keyboard/mouse, gamepad, or touch (left half of the
## screen moves, right half aims and fires the main spell).
## Spells: primary = left click / right stick / touch aim, secondary = right
## click / RB, ultimate = space / LB. `held` lets a touch UI fire any slot.
## Coop (see main.gd): the owner peer steers its mage (position, aim, firing
## are synced from it); the host owns the rest (hp, mana, loadout) and casts.

signal died

const BASE_SPEED := 220.0
const STICK_RANGE := 80.0

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
var max_hp := 100.0
var max_mana := 100.0
var mana_regen := 25.0
var speed := BASE_SPEED
var hp := max_hp
var mana := max_mana
var cooldowns := {}  # slot -> seconds left
var held := {}  # slot -> bool, from a touch UI
var aim := Vector2.RIGHT
var radius := 12.0
var look := {"hat": "#3a2a99", "skin": "#f1c27d", "robe": "#6a4cff", "staff": "#8d6e63", "ring": ""}

var _touch_move := {}  # finger index -> [start, current]
var _touch_aim := {}


## Stats from Profile.total_stats(), at the start of a run.
func setup(stats: Dictionary) -> void:
	max_hp = stats.hp
	max_mana = stats.mana
	mana_regen = stats.regen
	speed = BASE_SPEED * (1.0 + stats.speed)
	hp = max_hp
	mana = max_mana
	cooldowns = {}


func _ready() -> void:
	add_to_group("players")


## A player's loadout as it sends it (untrusted) -> a clean one: spells
## sanitized and priced here, stats clamped. "fresh": start of a run.
static func clean_loadout(raw: Variant) -> Dictionary:
	var l: Dictionary = raw if raw is Dictionary else {}
	var spells := {}
	var costs := {}
	for slot in Upgrades.SLOTS:
		var s: Variant = l.get("spells", {}).get(slot) if l.get("spells") is Dictionary else null
		if s is Dictionary:
			spells[slot] = Spell.sanitize(s)
			var mult: Variant = l.get("mult", {}).get(slot, 1.0) if l.get("mult") is Dictionary else 1.0
			costs[slot] = maxi(1, roundi(Spell.mana_cost(spells[slot]) * clampf(float(mult) if mult is float else 1.0, 0.2, 1.0)))
	var st: Dictionary = l.get("stats") if l.get("stats") is Dictionary else {}
	var look_in: Dictionary = l.get("look") if l.get("look") is Dictionary else {}
	var out_look := {}
	for k in ["hat", "skin", "robe", "staff", "ring"]:
		out_look[k] = Spell._color(look_in.get(k)) if look_in.get(k) else ""
	return {"spells": spells, "costs": costs, "look": out_look, "fresh": l.get("fresh") == true,
		"stats": {"hp": _clamp(st.get("hp"), 100.0, 1.0, 1000.0), "mana": _clamp(st.get("mana"), 100.0, 1.0, 1000.0),
			"regen": _clamp(st.get("regen"), 25.0, 0.0, 200.0), "speed": _clamp(st.get("speed"), 0.0, 0.0, 2.0)}}


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
	if l.fresh:
		setup(l.stats)
	else:
		max_hp = l.stats.hp
		max_mana = l.stats.mana
		mana_regen = l.stats.regen
		speed = BASE_SPEED * (1.0 + l.stats.speed)


class Loadout:
	var spells := {}
	var costs := {}

	func mana_cost(slot: String) -> int:
		return costs[slot]


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func hurt(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		died.emit()


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
	if peer_id == multiplayer.get_unique_id() and hp > 0.0:
		_steer(delta)
	if not multiplayer.is_server() or hp <= 0.0:
		return
	mana = minf(max_mana, mana + mana_regen * delta)
	for slot in Upgrades.SLOTS:
		cooldowns[slot] = cooldowns.get(slot, 0.0) - delta
		if firing.get(slot, false) and run and run.spells.has(slot):
			cast(slot)


func _steer(delta: float) -> void:
	# Input actions (project.godot): rebindable keys, arrows, left stick (ui/settings.gd).
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move = (move + _stick(_touch_move)).limit_length(1.0)
	position = Decor.slide(position, move * speed * delta, radius).clamp(Vector2.ZERO, get_viewport_rect().size)

	var fire := false
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var touch_aim := _stick(_touch_aim)
	if pad_aim.length() > 0.3:
		aim = pad_aim.normalized()
		fire = true
	elif touch_aim.length() > 0.2:
		aim = touch_aim.normalized()
		fire = true
	elif _touch_aim.is_empty():
		aim = (get_global_mouse_position() - global_position).normalized()
		fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	firing = {
		"primary": fire or held.get("primary", false),
		"secondary": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER) or held.get("secondary", false),
		"ultimate": Input.is_action_pressed("cast_ultimate") or held.get("ultimate", false),
	}


func cast(slot: String) -> bool:
	var cost: int = run.mana_cost(slot)
	if cooldowns.get(slot, 0.0) > 0.0 or mana < cost:
		return false
	var s: Dictionary = run.spells[slot]
	mana -= cost
	cooldowns[slot] = s.cooldown
	SpellBody.cast(s.emit, global_position + aim * radius, aim, self, s, get_parent())
	_cast_fx.rpc(slot, global_position + aim * radius, aim)
	return true


## Peers only draw the host's casts: their bodies apply no effects.
@rpc("authority", "call_remote", "unreliable_ordered")
func _cast_fx(slot: String, pos: Vector2, dir: Vector2) -> void:
	if run and run.spells.has(slot):
		SpellBody.cast(run.spells[slot].emit, pos, dir, self, run.spells[slot], get_parent())


func _draw() -> void:
	modulate.a = 1.0 if hp > 0.0 else 0.3  # down until the next run
	draw_circle(Vector2.ZERO, radius, Color(look.robe))
	draw_circle(Vector2(0, -radius * 0.2), radius * 0.45, Color(look.skin))  # face
	draw_colored_polygon(PackedVector2Array([Vector2(-radius * 0.8, -radius * 0.5),
		Vector2(radius * 0.8, -radius * 0.5), Vector2(0, -radius * 1.8)]), Color(look.hat))
	draw_line(Vector2.ZERO, aim * (radius + 12), Color(look.staff), 3.0)  # staff
	draw_circle(aim * (radius + 12), 3.0, Color(look.ring) if look.ring else Color.WHITE)
