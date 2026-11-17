extends Node2D
## The mage. Twin-stick: keyboard/mouse, gamepad, or touch (left half of the
## screen moves, right half aims and fires the main spell).
## Spells: primary = left click / right stick / touch aim, secondary = right
## click / RB, ultimate = space / LB. `held` lets a touch UI fire any slot.

signal died

const BASE_SPEED := 220.0
const STICK_RANGE := 80.0

var run: Node  # the Run autoload (passed in: tests load this script alone)
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
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	move = (move + keys + _stick(_touch_move)).limit_length(1.0)
	var pad_move := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad_move.length() > 0.2:
		move = pad_move.limit_length(1.0)
	position = (position + move * speed * delta).clamp(Vector2.ZERO, get_viewport_rect().size)

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

	mana = minf(max_mana, mana + mana_regen * delta)
	var want := {
		"primary": fire,
		"secondary": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER),
		"ultimate": Input.is_physical_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER),
	}
	for slot in want:
		cooldowns[slot] = cooldowns.get(slot, 0.0) - delta
		if (want[slot] or held.get(slot, false)) and run and run.spells.has(slot):
			cast(slot)
	queue_redraw()


func cast(slot: String) -> bool:
	var cost: int = run.mana_cost(slot)
	if cooldowns.get(slot, 0.0) > 0.0 or mana < cost:
		return false
	var s: Dictionary = run.spells[slot]
	mana -= cost
	cooldowns[slot] = s.cooldown
	SpellBody.cast(s.emit, global_position + aim * radius, aim, self, s, get_parent())
	return true


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(look.robe))
	draw_circle(Vector2(0, -radius * 0.2), radius * 0.45, Color(look.skin))  # face
	draw_colored_polygon(PackedVector2Array([Vector2(-radius * 0.8, -radius * 0.5),
		Vector2(radius * 0.8, -radius * 0.5), Vector2(0, -radius * 1.8)]), Color(look.hat))
	draw_line(Vector2.ZERO, aim * (radius + 12), Color(look.staff), 3.0)  # staff
	draw_circle(aim * (radius + 12), 3.0, Color(look.ring) if look.ring else Color.WHITE)
