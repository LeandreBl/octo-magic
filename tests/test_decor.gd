extends SceneTree
## Run: godot --headless --script tests/test_decor.gd  (see tests/run.sh)

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


func _initialize() -> void:
	var rect := Rect2(0, 0, 1280, 720)
	for map in Decor.MAPS:
		var d := Decor.new()
		root.add_child(d)
		d.build(map, rect, 7)
		var solid := Decor.obstacles
		check(d.items.size() > 25 and solid.size() >= 8, map + ": items placed")
		for o in solid:
			check(o.pos.distance_to(rect.get_center()) >= Decor.CENTER, map + ": center clear")
			check(rect.grow(-Decor.EDGE).has_point(o.pos), map + ": edges clear")
			for o2 in solid:
				check(o == o2 or o.pos.distance_to(o2.pos) >= o.r + o2.r + Decor.GAP, map + ": paths between obstacles")
		var layout := d.items.map(func(i): return i.pos)
		d.build(map, rect, 7)
		check(d.items.map(func(i): return i.pos) == layout, map + ": same seed, same layout")
		d.free()

	# Movers slide around obstacles instead of stopping on them.
	var o: Dictionary = Decor.obstacles[0]
	var start: Vector2 = o.pos + Vector2(-o.r - 20.0, 0.0)
	var p := start
	for i in 60:
		p = Decor.slide(p, Vector2(4, 0), 12.0)
		check(p.distance_to(o.pos) >= o.r + 11.9, "mover kept out")
	check(p.x > o.pos.x, "mover got past the obstacle")

	# A bolt breaks a crate: it stops, the crate drops gold.
	var d := Decor.new()
	root.add_child(d)
	d.build("crypt", rect, 7)
	var crate: Dictionary = Decor.obstacles.filter(func(x): return x.kind == "crate")[0]
	var bolt := SpellBody.new()
	bolt.body = Spell.base().emit.body
	bolt.spell = Spell.base()
	bolt.position = crate.pos
	root.add_child(bolt)
	var broken := []
	d.broken.connect(func(pos): broken.append(pos))
	d._physics_process(0.016)
	check(bolt.is_queued_for_deletion(), "bolt stopped by the crate")
	check(not Decor.obstacles.has(crate) and broken == [crate.pos], "crate broken, loot signaled")

	if failures == 0:
		print("decor tests: all passed")
	quit(1 if failures else 0)
