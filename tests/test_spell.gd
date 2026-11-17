extends SceneTree
## Run: godot --headless --script tests/test_spell.gd  (see tests/run.sh)

const Enemy := preload("res://game/enemy.gd")
const Player := preload("res://game/player.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


func _initialize() -> void:
	# Garbage in -> valid spell out.
	var s := Spell.sanitize({"name": 42, "cooldown": -5, "color": "nope",
		"emit": {"count": 999, "pattern": "laser", "body": {"speed": "fast", "on_hit": [
			{"type": "damage", "amount": 1e9}, {"type": "explode"}, "junk"]}}})
	check(s.cooldown == 0.08, "cooldown clamped")
	check(s.color == "#ffffff", "bad color replaced")
	check(s.emit.count == 16, "count clamped")
	check(s.emit.pattern == "aim", "unknown pattern -> default")
	check(s.emit.body.speed == 400.0, "non-number -> default")
	check(s.emit.body.on_hit.size() == 1 and s.emit.body.on_hit[0].amount == 500.0, "effects filtered and clamped")
	check(Spell.sanitize(null).emit.body.shape == "bolt", "null -> default spell")
	check(Spell.sanitize(s) == s, "sanitize is idempotent")

	# Pixel art: grids are clipped, bad chars become transparent.
	var art := Spell.sanitize({"palette": ["#ff0000", "nope", 3], "icon": ["0x9", "", "1"],
		"emit": {"body": {"sprite": [["0" .repeat(40)], ["..."], 7], "particle": ["0"]}}})
	check(art.palette == ["#ff0000", "#ffffff", "#ffffff"], "palette sanitized")
	check(art.icon == ["0..", "", "1"], "grid chars sanitized")
	check(art.emit.body.sprite.size() == 1 and art.emit.body.sprite[0][0].length() == 16, "frames clipped, empty dropped")
	var tex := SpellArt.texture(art.icon, art.palette)
	check(tex.get_size() == Vector2(3, 3), "texture size from grid")
	check(tex.get_image().get_pixel(0, 0) == Color.RED and tex.get_image().get_pixel(1, 0).a == 0.0, "texture pixels")
	check(Spell.base().icon.size() > 0 and Spell.base().emit.body.sprite.size() == 2, "base spell has art")

	# Bundles: manifest + PNG sheets, loaded at runtime.
	var img := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var zp := ZIPPacker.new()
	zp.open("user://test.spell")
	zp.start_file("manifest.json")
	zp.write_file(JSON.stringify({"name": "B", "icon_file": "icon.png", "emit": {"body": {
		"sheet": {"file": "body0.png", "w": 4, "h": 4, "frames": 2, "fps": 12, "cols": 2},
		"burst_sheet": {"file": "../evil.png"}}}}).to_utf8_buffer())
	zp.close_file()
	for f in ["body0.png", "icon.png"]:
		zp.start_file(f)
		zp.write_file(img.save_png_to_buffer())
		zp.close_file()
	zp.close()
	var b := SpellArt.load_bundle("user://test.spell")
	check(b.name == "B" and b.emit.body.sheet.frames == 2, "bundle manifest loaded")
	check(b.emit.body.burst_sheet.is_empty(), "path-like file names refused")
	check(SpellArt.sheet(b, "body0.png").get_size() == Vector2(8, 4), "bundle PNG loaded")
	check(SpellArt.sheet(b, b.icon_file) != null, "bundle icon loaded")
	check(SpellArt.load_bundle("user://missing.spell").is_empty(), "missing bundle -> {}")

	# Recursion is depth-limited.
	var nested := {"type": "cast", "emit": {"body": {"on_expire": []}}}
	for i in 10:
		nested = {"type": "cast", "emit": {"body": {"on_expire": [nested]}}}
	var deep := Spell.sanitize({"emit": {"body": {"on_expire": [nested]}}})
	var depth := 0
	var body: Dictionary = deep.emit.body
	while not body.on_expire.is_empty():
		depth += 1
		body = body.on_expire[0].emit.body
	check(depth == Spell.MAX_DEPTH, "cast depth limited to MAX_DEPTH (got %d)" % depth)

	# Stronger spells cost more mana.
	var base := Spell.base()
	var big := base.duplicate(true)
	big.emit.count = 5
	check(Spell.mana_cost(big) > Spell.mana_cost(base), "more projectiles cost more mana")
	var boom := base.duplicate(true)
	boom.emit.body.on_expire = [{"type": "cast", "emit": base.emit}]
	check(Spell.power(Spell.sanitize(boom)) > Spell.power(base), "sub-casts add power")

	# Every example spell in the docs is valid and runs without crashing.
	var examples: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://spell/examples.json"))
	check(examples is Array and examples.size() > 0, "example spells load")
	_run_examples(examples if examples is Array else [])


func _run_examples(examples: Array) -> void:
	var world := Node2D.new()
	root.add_child(world)
	var p := Player.new()
	p.position = Vector2(640, 360)
	world.add_child(p)
	p.set_process(false)
	p.set_physics_process(false)
	for ex in examples:
		var spell := Spell.sanitize(ex)
		check(Spell.sanitize(ex).hash() == Spell.sanitize(spell).hash(), "%s stable" % spell.name)
		var hp_before := 0.0
		for i in 8:
			var e := Enemy.new()
			e.target = p
			e.speed = 0.0
			e.max_hp = 1e6
			e.hp = 1e6
			e.position = p.position + Vector2.from_angle(TAU * i / 8) * 120.0
			world.add_child(e)
			hp_before += e.hp
		for frame in 180:
			if frame % 20 == 0:
				SpellBody.cast(spell.emit, p.position, Vector2.RIGHT, p, spell, world)
			await physics_frame
		var hp_after := 0.0
		for e in get_nodes_in_group("enemies"):
			hp_after += e.hp
			e.free()
		check(hp_after < hp_before, "%s damages enemies" % spell.name)
		for c in world.get_children():
			if c is SpellBody:
				c.free()
	print("tests: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures else 0)
