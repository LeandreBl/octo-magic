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
	Arena.polygons = keep
	Arena.solids = circles
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
