class_name Arena
extends Node2D
## The run's map, empty for now (objects come with task #92): only its edge is drawn.

const MAPS := ["crypt", "cave", "ruins"]  # one per run: its music for now
const RECT := Rect2(0, 0, 4800, 3200)  # about 4x4 screens: the camera shows a part of it


func _ready() -> void:
	z_index = -1  # under the player, enemies and spells


func _draw() -> void:
	draw_rect(RECT, Color(0, 0, 0, 0.6), false, 4.0)


## A spot inside the arena, just out of every mage's view (each camera is
## centred on its mage): the farthest of a few tries if none is out of all views.
## ponytail: the host's view size stands for every peer's (min 1280x720); a much wider client screen may see spawns
static func off_screen(mages: Array, view: Vector2) -> Vector2:
	var half := view.max(Vector2(1280, 720)) * 0.5 + Vector2(64, 64)  # margin: a sprite fully off-screen
	var best := RECT.get_center()
	var best_gap := -INF
	for i in 32:
		var near: Vector2 = mages.pick_random() if mages else best
		var pos := (near + Vector2.from_angle(randf() * TAU) * half.length() * randf_range(1.0, 1.5)).clamp(RECT.position, RECT.end)
		var gap := INF  # how far out of the nearest view, in view half-sizes (> 1: out)
		for m in mages:
			var d: Vector2 = (pos - m).abs() / half
			gap = minf(gap, maxf(d.x, d.y))
		if gap > 1.0:
			return pos
		if gap > best_gap:
			best = pos
			best_gap = gap
	return best
