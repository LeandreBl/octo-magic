extends Line2D
## One ground tentacle of the octopus mage, under its body sprite (game/player.gd):
## a Verlet chain pinned at the body whose tip is planted on the ground, and
## steps to a new spot ahead when the body has gone too far from it. Visual
## only: the body is the hitbox, and each peer simulates its own from the
## synced position. Shape by the code, texture by PixelLab (tools/make_octopus.py).

const TEX := preload("res://assets/octo/tentacle.png")
const POINTS := 6
const LENGTH := 29.0  # px, base to tip: the texture's width, drawn 1:1 to stay pixel art
const ROOT := 8.0  # px from the body centre to the base
const REACH := 0.85  # how far from its base the tip rests, in LENGTH: the slack curls the chain
const STEP := 0.45  # the tip steps when that far (in LENGTH) from its rest spot
const STEP_TIME := 0.1  # s: a step's glide
const GAIT := 0.15  # s: the two tentacle groups take turns this long each
const DAMP := 0.85
const SWAY := 0.2  # px/frame²: the sideways wiggle that keeps it alive

var dir := 0.0  # rad from the heading
var group := 0  # 0 or 1: groups step in turn, like legs
var foot := Vector2.ZERO  # where the tip is planted
var chain := PackedVector2Array()  # its points in world space: it trails behind the body
var _old := PackedVector2Array()
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _step_t := 0.0  # s left of the step
var _center := Vector2.ZERO  # the body's last position


func _init(direction := 0.0, step_group := 0) -> void:
	dir = direction
	group = step_group
	texture = TEX
	texture_mode = Line2D.LINE_TEXTURE_STRETCH
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	width = TEX.get_height()
	show_behind_parent = true


## One physics step, the body at `center` heading `heading` (rad), `t` the clock (s).
func follow(center: Vector2, heading: float, delta: float, t: float) -> void:
	var a := heading + dir
	var base := center + Vector2.from_angle(a) * ROOT
	var rest := base + Vector2.from_angle(a + 0.2 * sin(t * 1.3 + dir * 3.0)) * LENGTH * REACH
	if chain.is_empty():
		_center = center
		foot = rest
		for i in POINTS:
			chain.append(base.lerp(rest, float(i) / (POINTS - 1)))
		_old = chain.duplicate()
	if _step_t > 0.0:
		_step_t -= delta
		foot = _from.lerp(_to, ease(1.0 - maxf(_step_t, 0.0) / STEP_TIME, -2.0))
	else:
		var far := foot.distance_to(rest)
		var turn := int(t / GAIT) % 2 == group
		if far > LENGTH * STEP and turn or far > LENGTH * 0.7:  # too far: it steps anyway
			_from = foot
			var lead := (center - _center) / maxf(delta, 0.001) * (GAIT + STEP_TIME)  # lands where the body is going
			_to = rest + lead.limit_length(LENGTH * 0.5)
			_step_t = STEP_TIME
	_center = center
	var seg := LENGTH / (POINTS - 1)
	var side := Vector2.from_angle(a + PI / 2.0)
	for i in range(1, POINTS):
		var v := (chain[i] - _old[i]) * DAMP
		_old[i] = chain[i]
		chain[i] += v + side * SWAY * sin(t * 3.0 + i * 0.9 + dir * 5.0) * float(i) / POINTS
	for _k in 6:
		chain[0] = base
		chain[POINTS - 1] = chain[POINTS - 1].lerp(foot, 0.5)
		for i in POINTS - 1:
			var d := chain[i + 1] - chain[i]
			var fix := d * (1.0 - seg / maxf(d.length(), 0.001))
			if i == 0:
				chain[1] -= fix
			else:
				chain[i] += fix / 2.0
				chain[i + 1] -= fix / 2.0
	chain[0] = base
	var local := get_global_transform().affine_inverse() * chain if is_inside_tree() else chain.duplicate()
	for i in POINTS:
		local[i] = local[i].round()  # whole pixels: the texture stays crisp
	points = local
