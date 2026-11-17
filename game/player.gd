extends Node2D
## The mage. Twin-stick: keyboard/mouse, gamepad, or touch (left half of the
## screen moves, right half aims and fires the main spell).
## Main spell: left click / right stick or RT / touch aim; secondary (bought in the
## run): right click / Space / RB. `held` lets a touch UI fire them.
## Passive "shield" (bought in the run): absorbs SHIELD_HP damage, comes back
## SHIELD_WAIT seconds after it breaks.
## Every number of the mage comes from `stats` (game/stats.gd, from the loadout).
## Coop (see main.gd): the owner peer steers its mage (position, aim, firing
## are synced from it); the host owns the rest (hp, mana, loadout) and casts.

signal died

const STICK_RANGE := 80.0
const SHIELD_HP := 40.0
const SHIELD_WAIT := 8.0
## The octopus seen from above (PixelLab, tools/make_octopus.py): strips of
## square frames, head to the top, turned toward where it goes.
const SPRITES := {"walk": preload("res://assets/octo/walk.png"), "idle": preload("res://assets/octo/idle.png"),
	"cast": preload("res://assets/octo/cast.png"), "channel": preload("res://assets/octo/channel.png")}
const CAST_TIME := 0.4  # s: the cast animation, played once per cast

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
var passive := ""  # a Run.SHOP id
var shield := 0.0  # hp left on the shield, synced for drawing
var shield_wait := 0.0  # seconds until a broken shield is back
var cooldowns := {}  # slot -> seconds left
var held := {}  # slot -> bool, from a touch UI
var aim := Vector2.RIGHT
var radius := 12.0
var look := {"hat": "#3a2a99", "robe": "#6a4cff", "staff": "#8d6e63", "ring": ""}

var _angle := 0.0  # where the sprite heads: its move, else its aim (turned smoothly)
var _moving := false
var _cast_t := 0.0  # s left of the cast animation
var _channel_t := 0.0  # s left of the channel animation: renewed by each tick of a beam or cone
var _last_pos := Vector2.ZERO
var _heard_hp: float = stats.hp  # hosts and peers hear hurts on the synced hp
var _touch_move := {}  # finger index -> [start, current]
var _touch_aim := {}


## Full HP and mana with these stats, at the start of a run.
func setup(s: Dictionary) -> void:
	stats = s
	hp = s.hp
	mana = s.mana
	cooldowns = {}
	shield_wait = 0.0


func _ready() -> void:
	add_to_group("players")
	if peer_id == multiplayer.get_unique_id():  # this peer's mage stays mid-screen, the map scrolls
		var cam := Camera2D.new()
		add_child(cam)
		cam.make_current()


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
	for slot in Upgrades.RUN_SLOTS:
		var s: Variant = l.get("spells", {}).get(slot) if l.get("spells") is Dictionary else null
		if s is Dictionary:
			spells[slot] = Spell.sanitize(s)
			var mult: Variant = l.get("mult", {}).get(slot, 1.0) if l.get("mult") is Dictionary else 1.0
			costs[slot] = maxi(1, roundi(Spell.mana_cost(spells[slot]) * clampf(float(mult) if mult is float else 1.0, 0.2, 1.0) * stats.mana_cost))
	var look_in: Dictionary = l.get("look") if l.get("look") is Dictionary else {}
	var out_look := {}
	for k in ["hat", "robe", "staff", "ring"]:
		out_look[k] = Spell._color(look_in.get(k)) if look_in.get(k) else ""
	return {"spells": spells, "costs": costs, "look": out_look, "fresh": l.get("fresh") == true,
		"passive": l.get("passive") if l.get("passive") in ["shield"] else "",
		"stats": stats}


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
	else:  # a hero augment: the extra health and mana come filled
		hp += maxf(0.0, l.stats.hp - stats.hp)
		mana += maxf(0.0, l.stats.mana - stats.mana)
		stats = l.stats
	if l.passive != passive:  # bought, or a new run
		passive = l.passive
		shield = SHIELD_HP if passive == "shield" else 0.0


class Loadout:
	var spells := {}
	var costs := {}

	func mana_cost(slot: String) -> int:
		return costs[slot]


func heal(amount: float) -> void:
	hp = minf(stats.hp, hp + amount)


func hurt(amount: float) -> void:
	if hp <= 0.0:
		return
	amount *= 1.0 - stats.armor
	var absorbed := minf(shield, amount)
	if absorbed > 0.0:
		shield -= absorbed
		amount -= absorbed
		if shield <= 0.0:
			shield_wait = SHIELD_WAIT
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
	var step := position - _last_pos  # from the synced position: the same on every peer
	_last_pos = position
	_moving = step.length() > 0.5
	_cast_t -= delta
	_channel_t -= delta
	var heading := aim if _cast_t > 0.0 or _channel_t > 0.0 or not _moving else step  # casting: faces its aim
	_angle = lerp_angle(_angle, heading.angle(), minf(1.0, 12.0 * delta))
	if hp < _heard_hp - 0.5:
		if hp <= 0.0:
			Sfx.play("death")
		elif peer_id == multiplayer.get_unique_id():
			Sfx.play("hurt")
	_heard_hp = hp
	if peer_id == multiplayer.get_unique_id() and hp > 0.0:
		_steer(delta)
	if not multiplayer.is_server() or hp <= 0.0:
		return
	mana = minf(stats.mana, mana + stats.mana_regen * delta)
	hp = minf(stats.hp, hp + stats.hp_regen * delta)
	if shield_wait > 0.0:
		shield_wait -= delta
		if shield_wait <= 0.0 and passive == "shield":
			shield = SHIELD_HP
	for slot in Upgrades.RUN_SLOTS:
		cooldowns[slot] = cooldowns.get(slot, 0.0) - delta
		if firing.get(slot, false) and run and run.spells.has(slot):
			cast(slot)


func _steer(delta: float) -> void:
	# Input actions (project.godot): rebindable keys, arrows, left stick (ui/settings.gd).
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move = (move + _stick(_touch_move)).limit_length(1.0)
	position = (position + move * stats.speed * delta).clamp(Arena.RECT.position, Arena.RECT.end)

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
	var cost: int = run.mana_cost(slot)
	if cooldowns.get(slot, 0.0) > 0.0 or mana < cost:
		return false
	var s: Dictionary = run.spells[slot]
	if randf() < stats.crit:
		s = Upgrades.scale_damage(s, Stats.CRIT_MULT)
	mana -= cost
	cooldowns[slot] = s.cooldown * stats.cooldown
	SpellBody.cast(s.emit, global_position + aim * radius, aim, self, s, get_parent())
	_animate_cast(s)
	_cast_fx.rpc(slot, global_position + aim * radius, aim)
	return true


## Peers only draw the host's casts: their bodies apply no effects.
@rpc("authority", "call_remote", "unreliable_ordered")
func _cast_fx(slot: String, pos: Vector2, dir: Vector2) -> void:
	if run and run.spells.has(slot):
		SpellBody.cast(run.spells[slot].emit, pos, dir, self, run.spells[slot], get_parent())
		_animate_cast(run.spells[slot])


## A channeled spell (beam, cone) holds the staff out while it ticks; any other
## thrusts it once (not restarted before the flash, for fast spells).
func _animate_cast(s: Dictionary) -> void:
	if s.emit.body.shape in ["beam", "cone"]:
		_channel_t = s.cooldown + 0.15
	elif _cast_t < CAST_TIME / 2.0:
		_cast_t = CAST_TIME


func _draw() -> void:
	modulate.a = 1.0 if hp > 0.0 else 0.3  # down until the next run
	draw_circle(Vector2.ZERO, radius * 1.6, Color(look.robe, 0.45))  # robe colour under it: who is who in coop
	var anim := "channel" if _channel_t > 0.0 else "cast" if _cast_t > 0.0 else "walk" if _moving else "idle"
	var tex: Texture2D = SPRITES[anim]
	var size := float(tex.get_height())
	var frames := tex.get_width() / tex.get_height()
	var f := int(Time.get_ticks_msec() / 1000.0 * (12.0 if anim in ["walk", "channel"] else 8.0)) % frames
	if anim == "cast":
		f = mini(int((1.0 - _cast_t / CAST_TIME) * frames), frames - 1)
	draw_set_transform(Vector2.ZERO, _angle + PI / 2.0)  # the sprite's head is up
	draw_texture_rect_region(tex, Rect2(Vector2(-size, -size) / 2.0, Vector2(size, size)), Rect2(f * size, 0, size, size))
	draw_set_transform(Vector2.ZERO)
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 6, 0.0, TAU, 32, Color(0.5, 0.85, 1.0, 0.3 + 0.5 * shield / SHIELD_HP), 3.0)
