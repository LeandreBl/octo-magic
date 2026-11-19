class_name BossDeath
extends Node2D
## A boss's death, played on every peer where it fell (main.gd _killed): it
## staggers through its death strip, flickering, while blasts pop over its
## body and the screen trembles; then it blows up: a huge explosion over a
## shockwave, a ring of blasts, a white flash and a hard shake.
## Art: PixelLab (tools/make_monsters.py): <look>/death.png, fx/boss_blast.png,
## fx/boss_explosion.png, fx/shockwave.png. Missing art is skipped.

const Enemy := preload("res://game/enemy.gd")  # its art helpers
const AGONY := 1.4  # s of staggering before the big blast
const BLASTS := 10  # popping over its body during the agony
const RING := 8  # blasts thrown around it by the big one
const FLASH := 0.4  # s of the white screen fading out
const SHAKE := 18.0  # px of camera shake at the big blast (calibration knob)

var look := "boss"
var radius := 58.0
var angle := PI / 2.0  # its heading, as enemy.gd turns it
var age := 0.0
var _blasts := []  # [time s, offset, size px]
var _flash := ColorRect.new()


func _ready() -> void:
	z_index = SpellBody.ABOVE_DECOR
	for i in BLASTS:  # faster and faster toward the end
		var t := AGONY * sqrt(float(i) / BLASTS)
		_blasts.append([t, Vector2.from_angle(randf() * TAU) * randf() * radius, radius * randf_range(0.9, 1.6)])
	for i in RING:
		var a := TAU * i / RING + randf() * 0.4
		_blasts.append([AGONY + randf_range(0.05, 0.3), Vector2.from_angle(a) * radius * randf_range(1.6, 2.4), radius * randf_range(1.2, 1.8)])
	var layer := CanvasLayer.new()
	layer.layer = 9  # over the HUD, under the menus (ui.gd, 10)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
	add_child(layer)


## Seconds strip `file` plays once (0 when not generated).
static func length(file: String) -> float:
	var tex := Enemy.art(file)
	return tex.get_width() / tex.get_height() / Enemy.FPS if tex else 0.0


func _process(delta: float) -> void:
	var was := age
	age += delta
	queue_redraw()
	for b in _blasts:
		if was < b[0] and age >= b[0]:
			Sfx.play("blast", global_position)
			Arena.flash(global_position + b[1], b[2] * 2.5, 0.5)
	if was < AGONY and age >= AGONY:
		Arena.flash(global_position, radius * 9.0, 1.6, Color(0.85, 0.65, 0.45))
		Sfx.play("boom")
		Sfx.play("boss_die")
	var boom := age - AGONY
	_flash.color.a = clampf(1.0 - boom / FLASH, 0.0, 1.0) * 0.85 if boom >= 0.0 else 0.0
	var cam := get_viewport().get_camera_2d()
	if cam:  # trembles harder through the agony, then the jolt of the big one, settling
		var k := age / AGONY * 0.3 if boom < 0.0 else maxf(0.0, 1.0 - boom / 0.8)
		cam.offset = Vector2.from_angle(randf() * TAU) * SHAKE * k
	if boom > maxf(length("fx/boss_explosion"), FLASH) + 0.4:
		queue_free()


func _exit_tree() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.offset = Vector2.ZERO


func _draw() -> void:
	var boom := age - AGONY
	var size := radius * 2.5  # as enemy.gd draws it
	var death := Enemy.art(look + "/death")
	if boom < 0.0:  # the boss, flickering brighter and brighter
		var tex := death if death else Enemy.art(look + "/walk")
		if tex:
			var n := tex.get_width() / tex.get_height()
			var f := mini(int(age / AGONY * n), n - 1) if death else 0
			var glow := 1.0 + age / AGONY * (1.5 + sin(age * 40.0))
			draw_set_transform(Vector2.ZERO, angle - PI / 2.0)  # the art faces down
			Enemy.draw_frame(self, tex, f, size, Color(glow, glow, glow))
			draw_set_transform(Vector2.ZERO)
	else:
		_sheet("fx/shockwave", boom, radius * 8.0, Color(1, 1, 1, clampf(2.0 - boom * 2.0, 0.0, 1.0)))
		_sheet("fx/boss_explosion", boom, radius * 7.0)
	for b in _blasts:
		_sheet("fx/boss_blast", age - b[0], b[2], Color.WHITE, b[1])


## Frame at `t` s of one-shot strip `file`, `size` px, at `at`; nothing
## before it starts or once it ended.
func _sheet(file: String, t: float, size: float, tint := Color.WHITE, at := Vector2.ZERO) -> void:
	var tex := Enemy.art(file)
	if not tex or t < 0.0 or t >= length(file):
		return
	draw_set_transform(at)
	Enemy.draw_frame(self, tex, int(t * Enemy.FPS), size, tint)
	draw_set_transform(Vector2.ZERO)
