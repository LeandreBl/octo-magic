extends SceneTree
## Run: godot --headless --script tests/test_arena.gd  (see tests/run.sh)


func _initialize() -> void:
	var failures := 0
	var square := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
	var keep: Array = Arena.polygons
	Arena.polygons = [square]
	var circles: Array = Arena.solids
	Arena.solids = []
	# Walking right into the square's left side: stopped at its side, still sliding down.
	var p := Vector2(-30, 50)
	for i in 10:
		p = Arena.slide(p, Vector2(5, 3), 12.0)
	if not (absf(p.x + 12.0) < 0.1 and p.y > 50.0 + 20.0):
		failures += 1
		printerr("FAIL: a mover slides along a polygon (%s)" % p)
	# Pushed out of it when inside (spawned there).
	if Geometry2D.is_point_in_polygon(Arena.slide(Vector2(20, 50), Vector2.ZERO, 12.0), square):
		failures += 1
		printerr("FAIL: out of a polygon it is in")
	# A closed pen (a thick square ring, away from the start): no monster comes out inside.
	var pen := PackedVector2Array([Vector2(100, 100), Vector2(500, 100), Vector2(500, 500), Vector2(100, 500),
		Vector2(100, 101), Vector2(140, 140), Vector2(140, 460), Vector2(460, 460), Vector2(460, 140), Vector2(140, 140), Vector2(100, 101)])
	Arena.polygons = [pen]
	var open := Arena.walkable()
	if open.is_empty() or open.any(func(v): return Rect2(100, 100, 400, 400).has_point(v)):
		failures += 1
		printerr("FAIL: the ground stops at a closed pen (%d points)" % open.size())
	# A monster behind a long wall walks around it to its mage (straight at it, it would stay against the wall).
	var s := Arena.START
	Arena.polygons = [PackedVector2Array([s + Vector2(60, -300), s + Vector2(90, -300), s + Vector2(90, 300), s + Vector2(60, 300)])]
	if _walk(s, s + Vector2(200, 0)) > 40.0:
		failures += 1
		printerr("FAIL: a monster walks around a wall")
	Arena.polygons = keep
	Arena.solids = circles
	# On the graveyard: from every grave, a monster reaches the start.
	for g in Arena.spawns:
		var left := _walk(Vector2(g[0], g[1]), Arena.START)
		if left > 40.0:
			failures += 1
			printerr("FAIL: a monster from the grave at %s stops %d px from the start" % [g, left])
	if not Arena.RECT.has_point(Arena.START):
		failures += 1
		printerr("FAIL: the graveyard's map.json loads")
	for poly in Arena.polygons:
		if Geometry2D.is_point_in_polygon(Arena.START, poly):
			failures += 1
			printerr("FAIL: the start is free")
	# Monsters come out off every mage's view, even when the graves are all in one.
	var view := Vector2(640, 360)
	var mages := [Arena.START, Arena.START + Vector2(900, 0)]
	var seen := Arena.views(mages, view)
	for i in 50:
		var at := Arena.spawn_point(seen)
		if seen.any(func(r): return r.has_point(at)):
			failures += 1
			printerr("FAIL: a monster comes out in a mage's view (%s)" % at)
			break
	var keep_spawns: Array = Arena.spawns
	Arena.spawns = [[Arena.START.x, Arena.START.y]]
	if seen.any(func(r): return r.has_point(Arena.spawn_point(seen))):
		failures += 1
		printerr("FAIL: an open grave in view is not used")
	Arena.spawns = keep_spawns
	print("arena tests: ", "OK" if failures == 0 else "%d failed" % failures)
	quit(1 if failures else 0)


## How far from `to` a monster (radius 12, 80 px/s) walking from `from` ends after 60 s.
func _walk(from: Vector2, to: Vector2) -> float:
	var p := from
	for i in 3600:
		if p.distance_to(to) < 24.0:
			break
		p = Arena.slide(p, Arena.way(p, to) * 80.0 / 60.0, 12.0)
	return p.distance_to(to)
