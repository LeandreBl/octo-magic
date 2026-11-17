extends Node2D
## The mage. Twin-stick: keyboard/mouse, gamepad, or touch (left half of the
## screen moves, right half aims and fires).

signal died

const SPEED := 220.0
const MAX_HP := 100.0
const MAX_MANA := 100.0
const MANA_REGEN := 25.0
const STICK_RANGE := 80.0

var spell: Dictionary
var mana_cost := 1
var hp := MAX_HP
var mana := MAX_MANA
var cooldown := 0.0
var aim := Vector2.RIGHT
var radius := 12.0

var _touch_move := {}  # finger index -> [start, current]
var _touch_aim := {}


func set_spell(s: Dictionary) -> void:
	spell = s
	mana_cost = Spell.mana_cost(s)


func heal(amount: float) -> void:
	hp = minf(MAX_HP, hp + amount)


func hurt(amount: float) -> void:
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
	position = (position + move * SPEED * delta).clamp(Vector2.ZERO, get_viewport_rect().size)

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

	mana = minf(MAX_MANA, mana + MANA_REGEN * delta)
	cooldown -= delta
	if fire and cooldown <= 0.0 and mana >= mana_cost:
		mana -= mana_cost
		cooldown = spell.cooldown
		SpellBody.cast(spell.emit, global_position + aim * radius, aim, self, spell, get_parent())
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color("#6a4cff"))
	draw_circle(Vector2(0, -radius * 0.6), radius * 0.7, Color("#3a2a99"))  # hat
	draw_line(Vector2.ZERO, aim * (radius + 10), Color.WHITE, 3.0)  # staff
