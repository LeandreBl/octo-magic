extends Line2D
## One ground tentacle of the octopus mage (game/player.gd), drawn under its body
## sprite: seen from above, the hat is on top.
## A muscular arm, not a rope: a Verlet chain pinned at the body that keeps its
## length and resists bending, each joint pulled toward a target curve (the tip
## curls more than the base), its first segment aimed at its tip's spot. Moving,
## it pulls the body along: it reaches forward on its side, the tip grips the
## ground like a sucker, the arm sweeps back past its base as the body goes by,
## then lets go, curls up as it lifts and unrolls ahead again (the bend runs from
## the base to the tip); the two groups pull out of phase (STAGGER). Slow, it
## steps to its rest spot; still, the arms writhe slowly and now and then one shifts. It is a body of its own: its
## points bump into the arena's walls and are shoved out of the enemies around
## (circles), the tip never planted inside either. Visual only: the body is the
## hitbox, and each peer simulates its own from the synced position. Shape by
## the code, texture by PixelLab (tools/make_octopus.py).

const TEX := preload("res://assets/octo/tentacle.png")
const POINTS := 6
const LENGTH := 29.0  # px, base to tip: the texture's width, drawn 1:1 to stay pixel art
const ROOT := 8.0  # px from the body centre to the base
const REACH := 0.85  # how far from its base the tip rests, in LENGTH: the slack curls the chain
const STEP := 0.45  # the tip steps when that far (in LENGTH) from its rest spot
const STEP_TIME := 0.3  # s: a step, lift to landing
const FIDGET_TIME := 0.9  # s: a slow shift while standing
const GAIT := 0.3  # s: the two tentacle groups take turns this long each
const LIFT := 0.25  # how much a stepping tip draws back toward its base mid-step
const DAMP := 0.7  # of a point's speed kept per frame: the water's drag
const CURL := 0.25  # rad per joint at the tip: the resting hook
const SWING_BEND := 0.5  # rad: the bend that runs down a stepping arm
const BEND_STIFF := 0.3  # how hard a joint is pulled to its target bend, per pass
const ROOT_STIFF := 0.5  # how hard the first segment leaves the body along the arm's direction
const PACE := 80.0  # px/s: up to it the gait keeps its times; faster, it quickens with the speed
const MIN_PACE := 0.3  # the quickest gait, in its slow times: beyond, the strides lengthen
const LEAD := 0.7  # how far ahead of its rest spot a step lands at most, in LENGTH
## Moving, the arms swim with the ground: each reaches forward on its side, grips,
## pulls back past its base as the body goes by, then lets go and reaches again.
const PULL_FROM := 30.0  # px/s: below it, it steps to its rest spot
const REACH_FAR := 1.0  # how far from its base an arm reaches ahead, in LENGTH
const PULL := 0.1  # it lets go once its tip is that far behind its base, in LENGTH
const STAGGER := 0.5  # in LENGTH: group 1 pulls that much longer, so the two groups never all pull at once
const REACH_FRONT := 0.15  # rad from the heading: where the front arms reach
const REACH_SPREAD := 0.25  # rad more per arm toward the rear: the rear ones reach to the side
const THICK := 3.0  # px: a point's radius against walls and enemies
const BOUNCE := 0.4  # of a point's speed into a wall sent back out
## The arm's targets (heading, bends, grip) eased toward the body's, per second: a
## first-order lag so a sudden turn or a gait change is a sweep, not a whip.
const TURN := 6.0
const EASE := 8.0

var dir := 0.0  # rad from the heading
var size := 1.0  # ROOT and LENGTH in the body's scale (game/player.gd SIZE)
var group := 0  # 0 or 1: groups step in turn, like legs
var foot := Vector2.ZERO  # where the tip is planted
var chain := PackedVector2Array()  # its points in world space: it trails behind the body
var _old := PackedVector2Array()
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _step_t := 0.0  # s left of the step
var _step_len := STEP_TIME  # s: the current step's duration
var _fidget := randf_range(1.0, 4.0)  # s until it shifts while standing
var _center := Vector2.ZERO  # the body's last position
var _speed := 0.0  # px/s: the body's, smoothed
var _side := 1.0  # which way it curls: outward, mirrored left and right
var _heading := 0.0  # rad: the body's heading, eased (TURN)
var _bend := PackedFloat32Array()  # the joints' target bends, eased (EASE)
var _hold := 1.0  # the tip's grip, eased (EASE)
var _reaching := false  # the current step reaches ahead to pull
var _reach := 0.0  # rad from the heading, on its side: where it reaches
var _gait := 0.0  # the gait's clock, in GAIT turns: the two groups take turns on its whole numbers


func _init(direction := 0.0, step_group := 0) -> void:
	dir = direction
	group = step_group
	_side = 1.0 if sin(direction) >= 0.0 else -1.0
	_reach = REACH_FRONT + REACH_SPREAD * (absf(angle_difference(0.0, direction)) / (PI / 4.0) - 0.5)
	texture = TEX
	texture_mode = Line2D.LINE_TEXTURE_STRETCH
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	width = TEX.get_height()
	show_behind_parent = true  # under the body: never over the hat


## One physics step, the body at `center` heading `heading` (rad), `t` the clock (s),
## inside the walls `walls`, among `obstacles`: [position, radius] circles;
## `map`: also out of the arena's solid zones (Arena.slide), as the body is.
func follow(center: Vector2, heading: float, delta: float, t: float,
		walls := Rect2(-1e9, -1e9, 2e9, 2e9), obstacles: Array = [], map := false) -> void:
	var length := LENGTH * size
	var root_r := ROOT * size
	var reach := root_r + length * 1.5 + THICK
	map = map and Arena.boxes.any(func(b: Rect2): return b.grow(reach).has_point(center))  # none near: skip it
	if chain.is_empty():
		_heading = heading
	_heading = lerp_angle(_heading, heading, 1.0 - exp(-TURN * delta))
	heading = _heading
	var ease_k := 1.0 - exp(-EASE * delta)
	var a := heading + dir
	var base := center + Vector2.from_angle(a) * root_r
	var rest := base + Vector2.from_angle(a + 0.2 * sin(t * 0.6 + dir * 3.0)) * length * REACH
	if chain.is_empty():
		_center = center
		foot = rest
		for i in POINTS:
			chain.append(base.lerp(rest, float(i) / (POINTS - 1)))
		_old = chain.duplicate()
	var vel := (center - _center) / maxf(delta, 0.001)
	_speed = lerpf(_speed, vel.length(), 1.0 - exp(-8.0 * delta))
	_center = center
	var pace := clampf(PACE / maxf(_speed, 1.0), MIN_PACE, 1.0)  # faster: quicker steps, the same strides
	_gait += delta / (GAIT * pace)
	var hold := 1.0  # how hard the tip is held at the foot
	var s := -1.0  # the step's progress, 0 to 1, or -1: planted
	if _step_t > 0.0:
		_step_t -= delta
		s = 1.0 - maxf(_step_t, 0.0) / _step_len
		var lift := sin(PI * s)
		if _reaching:  # the spot ahead moves with the body: aimed at until the tip lands
			_to = _free(base + Vector2.from_angle(heading + _side * _reach) * length * REACH_FAR, walls, obstacles, map)
		foot = _from.lerp(_to, ease(s, -2.0)).lerp(base, LIFT * lift)  # drawn back up, then laid down
		hold = 0.3  # lifted: the muscle shapes it more than the path
	else:
		var far := foot.distance_to(rest)
		var turn := int(_gait) % 2 == group
		_fidget -= delta
		var shift := _fidget <= 0.0 and _speed < 5.0
		var moving := _speed > PULL_FROM
		var back := (foot - base).dot(Vector2.from_angle(heading)) / length  # how far ahead of its base the tip is
		var step := (back < -PULL - STAGGER * group or foot.distance_to(base) > length * 1.2) if moving \
				else (far > length * STEP and turn or far > length * 0.7 or shift and turn)  # too far: it steps anyway
		if step:
			_from = foot
			_reaching = moving
			var lead := vel * (GAIT + STEP_TIME) * pace  # lands where the body is going
			var spot := rest + lead.limit_length(length * LEAD)
			if shift:
				spot = rest + Vector2.from_angle(randf() * TAU) * length * 0.15
			_to = _free(spot, walls, obstacles, map)  # reaching: aimed at each frame of the step
			_step_len = FIDGET_TIME if shift else STEP_TIME * pace
			_step_t = _step_len
			_fidget = randf_range(1.5, 5.0)
	_hold = lerpf(_hold, hold, ease_k)
	hold = _hold
	var writhe := 1.0 + 0.6 * sin(t * 0.35 + dir * 7.0) * sin(t * 0.15 + dir * 3.0)  # slow, its own
	var bend := PackedFloat32Array()  # target turn at each joint, from the previous segment's direction
	bend.resize(POINTS)
	if _bend.is_empty():
		_bend.resize(POINTS)
	for i in range(1, POINTS - 1):
		var u := float(i) / (POINTS - 2)  # 0 at the base, 1 at the last joint
		var crawl := CURL * writhe * u
		if s >= 0.0:  # the bend of a step runs down the arm
			crawl += SWING_BEND * sin(PI * s) * exp(-pow((u - s) * 2.5, 2.0))
		_bend[i] = lerpf(_bend[i], _side * crawl, ease_k)
		bend[i] = _bend[i]
	for i in range(1, POINTS):
		var v := (chain[i] - _old[i]) * DAMP
		_old[i] = chain[i]
		chain[i] += v
	var seg := length / (POINTS - 1)
	for k in 6:
		chain[0] = base
		chain[1] = chain[1].lerp(base + (foot - base).normalized() * seg, ROOT_STIFF)  # aimed at its tip's spot
		for i in POINTS - 1:
			var d := chain[i + 1] - chain[i]
			var fix := d * (1.0 - seg / maxf(d.length(), 0.001))
			if i == 0:
				chain[1] -= fix
			else:
				chain[i] += fix / 2.0
				chain[i + 1] -= fix / 2.0
		for i in range(1, POINTS - 1):  # muscle: each joint turned toward its target bend
			var was := (chain[i] - chain[i - 1]).angle()
			var now := chain[i + 1] - chain[i]
			var to := lerp_angle(now.angle(), was + bend[i], BEND_STIFF)
			chain[i + 1] = chain[i] + Vector2.from_angle(to) * now.length()
		chain[POINTS - 1] = chain[POINTS - 1].lerp(foot, 0.6 * hold)  # the sucker holds, after the muscle
		for i in range(1, POINTS):  # then the length again, from the base: a sucker left behind never stretches the arm
			chain[i] = chain[i - 1] + (chain[i] - chain[i - 1]).normalized() * seg
		for i in range(1, POINTS):
			chain[i] = _free(chain[i], walls, obstacles, map and k == 5)  # the map's zones on the last pass: slide is costly
	for i in range(1, POINTS):  # a bounce off the walls: the speed into one flips, damped
		var inner := walls.grow(-THICK)
		if chain[i].x <= inner.position.x or chain[i].x >= inner.end.x:
			_old[i].x = chain[i].x + (chain[i].x - _old[i].x) * BOUNCE
		if chain[i].y <= inner.position.y or chain[i].y >= inner.end.y:
			_old[i].y = chain[i].y + (chain[i].y - _old[i].y) * BOUNCE
	foot = _free(foot, walls, obstacles, map)
	chain[0] = base
	var local := get_global_transform().affine_inverse() * chain if is_inside_tree() else chain.duplicate()
	for i in POINTS:
		local[i] = local[i].round()  # whole pixels: the texture stays crisp
	points = local


## `p` pushed out of the obstacles' circles, then of the map's zones (`map`), then inside the walls.
static func _free(p: Vector2, walls: Rect2, obstacles: Array, map := false) -> Vector2:
	for o in obstacles:
		var d: Vector2 = p - o[0]
		var r: float = o[1] + THICK
		if d.length_squared() < r * r:
			p = o[0] + (d if d != Vector2.ZERO else Vector2.RIGHT).normalized() * r
	if map:
		p = Arena.slide(p, Vector2.ZERO, THICK)
	return p.clamp(walls.position + Vector2(THICK, THICK), walls.end - Vector2(THICK, THICK))
