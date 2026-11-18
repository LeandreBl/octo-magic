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

	# Bundles: manifest + PNG strips, loaded at runtime (docs/spells.md).
	var strip := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)  # 2 frames of 8x8
	strip.fill(Color.RED)
	var zp := ZIPPacker.new()
	zp.open("user://test.spell")
	zp.start_file("manifest.json")
	zp.write_file(JSON.stringify({"format": 1, "name": "B", "icon_file": "icon.png", "emit": {"body": {
		"sheet": {"file": "body0.png", "size": 8, "frames": 2, "fps": 12, "loop": true},
		"burst_sheet": {"file": "../evil.png"},
		"on_expire": [{"type": "cast", "emit": {"body": {
			"sheet": {"file": "body1.png", "size": 8, "frames": 3, "fps": 12}}}}]}}}).to_utf8_buffer())
	zp.close_file()
	for f in ["body0.png", "body1.png", "icon.png"]:
		zp.start_file(f)
		zp.write_file(strip.save_png_to_buffer())
		zp.close_file()
	zp.close()
	var b := SpellArt.load_bundle("user://test.spell")
	check(b.name == "B" and b.emit.body.sheet.frames == 2, "bundle manifest loaded")
	check(b.emit.body.burst_sheet.is_empty(), "path-like file names refused")
	check(b.emit.body.on_expire[0].emit.body.sheet.is_empty(), "sheet not matching its PNG dropped")
	var anim := SpellArt.animation(b, b.emit.body)
	check(anim[0].get_size() == Vector2(16, 8) and anim[1].size == 8, "bundle sheet animation")
	check(SpellArt.sheet(b, b.icon_file) != null, "bundle icon loaded")
	check(SpellArt.load_bundle("user://missing.spell").is_empty(), "missing bundle -> {}")

	# Base spells: every bolt has its PixelLab sheets, matching the strip format (the burst is optional).
	for d in JSON.parse_string(FileAccess.get_file_as_string("res://game/spells.json")):
		var base := Spell.sanitize(d)
		if base.emit.body.shape != "bolt":
			continue
		for key in ["sheet", "burst_sheet"]:
			var meta: Dictionary = base.emit.body[key]
			if key == "burst_sheet" and meta.is_empty():
				continue
			var strip_tex := SpellArt.sheet(base, meta.get("file", ""))
			check(strip_tex and strip_tex.get_size() == Vector2(meta.size * meta.frames, meta.size), "%s %s" % [d.id, key])

	# Pixel grids become the same strip format as bundle sheets.
	var grid := SpellArt.animation(Spell.base(), Spell.base().emit.body)
	check(grid[0].get_size() == Vector2(16, 8) and grid[1].frames == 2 and grid[1].loop, "grid sprites -> strip")
	check(SpellArt.animation(Spell.base(), Spell.sanitize({}).emit.body).is_empty(), "no art -> no animation")

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

	# Sounds: synthesized from the data, a loop for continuous bodies.
	for el in Spell.ELEMENTS:
		var w := SpellSound.cast_stream(el, base.emit.body, 0)
		check(w.data.count(0) < w.data.size() / 2 and w.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s cast sound" % el)
		var l := SpellSound.loop_stream(el, base.emit.body, 1)
		check(l.data.count(0) < l.data.size() / 2 and l.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loop sound" % el)
	check(SpellSound.is_continuous(Spell.sanitize({"emit": {"body": {"shape": "zone"}}}).emit.body), "zones loop")
	check(not SpellSound.is_continuous(base.emit.body), "bolts play once")
	check(SpellSound.cast_stream("fire", base.emit.body, 0) != SpellSound.cast_stream("fire", base.emit.body, 1), "sub-casts sound different")

	await _check_homing_lifetime()
	await _check_channel()
	await _check_loop_once()

	# Every example spell in the docs is valid and runs without crashing.
	var examples: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://spell/examples.json"))
	check(examples is Array and examples.size() > 0, "example spells load")
	_run_examples(examples if examples is Array else [])


## Overlapping zones of one spell play their loop once; a survivor takes it over.
func _check_loop_once() -> void:
	await process_frame  # the root in the tree: bodies leaving it hand the loop over
	var zone := Spell.sanitize({"emit": {"body": {"shape": "zone"}}})
	var sw := Node2D.new()
	root.add_child(sw)
	var za := Node2D.new()
	var zb := Node2D.new()
	sw.add_child(za)
	sw.add_child(zb)
	SpellSound.play(zone, zone.emit.body, 0, za, sw)
	SpellSound.play(zone, zone.emit.body, 0, zb, sw)
	SpellSound.play(zone, zone.emit.body, 0, za, sw)  # a channel tick on the same body
	check(za.get_child_count() == 1 and zb.get_child_count() == 0, "one loop for overlapping zones")
	za.free()
	check(zb.get_child_count() == 1, "the surviving zone takes the loop over")
	sw.free()


## Auto-aim bolts outlive their lifetime; out of the map they die only once
## no enemy is left.
func _check_homing_lifetime() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var spell := Spell.sanitize({"emit": {"body": {"speed": 0, "lifetime": 0.05,
		"motion": [{"type": "homing", "strength": 1}]}}})
	SpellBody.cast(spell.emit, Vector2(100, 100), Vector2.RIGHT, null, spell, world)
	for i in 10:
		await physics_frame
	var bolt: SpellBody = world.get_child(0)
	check(is_instance_valid(bolt), "homing bolt outlives its lifetime")
	var e := Enemy.new()
	e.position = Vector2(-500, -500)
	world.add_child(e)
	bolt.position = Vector2(-3000, 100)  # far off-screen, an enemy still there
	await physics_frame
	await physics_frame
	check(is_instance_valid(bolt), "far homing bolt kept while enemies remain")
	e.free()
	await physics_frame
	await physics_frame
	check(not is_instance_valid(bolt), "far homing bolt freed once no enemy is left")
	world.free()


## Beam: grips the nearest, most centered enemy within its wide angle, once
## per cast, picked again each cast. Cone: hits every enemy within its short reach and angle.
func _check_channel() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var spells := {}
	for d in JSON.parse_string(FileAccess.get_file_as_string("res://game/spells.json")):
		spells[d.id] = Spell.sanitize(d)
	var at := func(pos: Vector2) -> Node2D:
		var e := Enemy.new()
		e.speed = 0.0
		e.max_hp = 1000.0
		e.hp = 1000.0
		e.position = pos
		world.add_child(e)
		return e
	var near_behind: Node2D = at.call(Vector2(60, 100))  # nearest, but behind the aim
	var wide: Node2D = at.call(Vector2(150, 170))  # 54 degrees off the aim, nearest ahead
	var aimed: Node2D = at.call(Vector2(300, 100))
	var far: Node2D = at.call(Vector2(380, 110))
	SpellBody.cast(spells.lightning.emit, Vector2(100, 100), Vector2.RIGHT, null, spells.lightning, world)
	for i in 3:
		await physics_frame
	check(wide.hp < 1000.0 and near_behind.hp == 1000.0 and aimed.hp == 1000.0 and far.hp == 1000.0,
		"beam grips the nearest enemy within its wide angle")
	var wide_hp: float = wide.hp
	for i in 3:
		await physics_frame
	check(wide.hp == wide_hp, "beam strikes once per cast")
	SpellBody.cast(spells.frost_jet.emit, Vector2(230, 100), Vector2.RIGHT, null, spells.frost_jet, world)
	for i in 3:
		await physics_frame
	check(aimed.hp < 1000.0 and near_behind.hp == 1000.0 and wide.hp == wide_hp and far.hp == 1000.0, "cone hits in reach and angle only")
	far.position = Vector2(190, 100)  # centered, a bit farther than the off-center one
	SpellBody.cast(spells.lightning.emit, Vector2(100, 100), Vector2.RIGHT, null, spells.lightning, world)
	for i in 3:
		await physics_frame
	check(far.hp < 1000.0 and wide.hp == wide_hp, "beam prefers a centered enemy to a slightly nearer off-center one")
	var far_hp: float = far.hp
	var hp: float = aimed.hp
	aimed.position = Vector2(140, 100)  # now nearer than the last target
	SpellBody.cast(spells.lightning.emit, Vector2(100, 100), Vector2.RIGHT, null, spells.lightning, world)
	for i in 3:
		await physics_frame
	check(aimed.hp < hp and wide.hp == wide_hp, "beam retargets the nearest enemy each cast")
	check(far.hp == far_hp, "beam drops its last target for a better one")
	var mage := Player.new()
	mage.position = Vector2(100, 100)
	world.add_child(mage)
	mage.set_physics_process(false)  # aim set by hand, not by the mouse
	mage.aim = Vector2.RIGHT
	SpellBody.cast(spells.lightning.emit, Vector2(110, 100), Vector2.RIGHT, mage, spells.lightning, world)
	await physics_frame
	mage.aim = Vector2.DOWN
	await physics_frame
	SpellBody.cast(spells.lightning.emit, Vector2(110, 100), Vector2.RIGHT, mage, spells.lightning, world)
	var arcs := world.get_children().filter(func(n): return n is SpellBody and n.caster == mage)
	check(arcs.size() == 1, "held beam renews its arc instead of stacking a new one each tick")
	var arc: SpellBody = arcs[0]
	await physics_frame
	check(arc.dir == Vector2.DOWN and arc.position.is_equal_approx(mage.gem()) and mage.gem() != mage.position,
		"beam follows the caster's aim and gem every frame")
	mage.free()
	check(Spell.mana_cost(spells.fireball) > 3 * Spell.mana_cost(spells.magic_missile), "fireball costs far more than a missile")
	check(Spell.cost_text(spells.lightning, 2) == "%d/s" % roundi(2 / spells.lightning.cooldown), "a channeled cost is shown per second")
	check(Spell.cost_text(spells.fireball, 7) == "7", "a cast cost is shown per cast")
	world.free()


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
