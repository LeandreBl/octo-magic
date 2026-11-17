extends SceneTree
## Run: godot --headless --script tests/test_game.gd  (see tests/run.sh)
## Game logic: level-ups, upgrades, waves, shop prices, save/load.

const RunState := preload("res://game/run.gd")
const ProfileState := preload("res://game/profile.gd")
const Enemy := preload("res://game/enemy.gd")
const Player := preload("res://game/player.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


func _initialize() -> void:
	_test_upgrades()
	_test_run()
	_test_waves()
	_test_profile()
	await _test_play()
	print("game tests: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures else 0)


func _damage(s: Dictionary) -> float:
	return s.emit.body.on_hit.filter(func(f): return f.type == "damage")[0].amount


func _test_upgrades() -> void:
	var s := Spell.base()
	var up := Upgrades.apply(s, "damage")
	check(is_equal_approx(_damage(up), _damage(s) * 1.25), "damage upgrade")
	check(Upgrades.apply(s, "count").emit.count == s.emit.count + 1, "count upgrade")
	check(Upgrades.apply(s, "cooldown").cooldown < s.cooldown, "cooldown upgrade")
	check(Upgrades.apply(s, "pierce").emit.body.pierce == s.emit.body.pierce + 1, "pierce upgrade")
	check(Upgrades.apply(up, "damage") == Spell.sanitize(Upgrades.apply(up, "damage")), "upgraded spell is sanitized")
	var maxed := s.duplicate(true)
	maxed.emit.count = 16
	check(Upgrades.apply(maxed, "count").emit.count == 16, "upgrades stay clamped")
	check(not Upgrades.applies(maxed, "count"), "maxed upgrade not offered")
	check(not Upgrades.applies(s, "mana", Upgrades.MANA_FLOOR), "mana floor")
	# Nested casts are scaled too.
	var boom := Spell.sanitize({"emit": {"body": {"on_expire": [{"type": "cast", "emit": {"body": {
		"on_hit": [{"type": "damage", "amount": 10}]}}}]}}})
	check(Upgrades.scale_damage(boom, 2.0).emit.body.on_expire[0].emit.body.on_hit[0].amount == 20.0, "nested damage scaled")
	var rng := RandomNumberGenerator.new()
	var offers := Upgrades.offers({"primary": s}, {}, rng)
	check(offers.size() == 3 and offers[0] != offers[1] and offers[1] != offers[2], "3 distinct offers")


func _test_run() -> void:
	var run := RunState.new()
	var p := ProfileState.new()
	run.start(p.equipped_spells(), {"damage": 0.5, "xp": 0.0})
	check(run.spells.keys() == ["primary"], "one spell, no secondary or ultimate")
	check(is_equal_approx(_damage(run.spells.primary), _damage(p.equipped_spells().primary) * 1.5), "damage bonus applied")
	var got := []
	run.leveled_up.connect(func(o): got.append(o))
	run.add_xp(RunState.xp_to_next(1) - 1)
	check(run.level == 1 and got.is_empty(), "no level-up before the threshold")
	run.add_xp(1 + RunState.xp_to_next(2))  # two level-ups at once
	check(run.level == 3 and run.pending == 2 and got.size() == 1 and run.offers.size() == 3, "level-ups queue")
	var o: Dictionary = run.offers[0]
	var before: Dictionary = run.spells[o.slot]
	var cost := run.mana_cost(o.slot)
	check(run.choose(0), "a second choice waits")
	check(run.spells[o.slot] != before or run.mana_cost(o.slot) <= cost, "choice applied")
	check(not run.choose(0) and run.pending == 0 and run.offers.is_empty(), "all choices made")
	check(run.picked.size() == 2, "picks recorded")
	run.start(p.equipped_spells(), {"gold": 0.5})
	run.collect("gold", 10)
	check(run.gold == 15, "gold bonus")
	run.wave = 6
	run.killed("boss")
	var r := run.finish()
	check(not run.active and r.bosses == 1 and r.score == run.score(), "run result")
	run.free()
	p.free()


func _test_waves() -> void:
	check(RunState.wave_plan(1).all(func(k): return k == "melee"), "wave 1 is melee only")
	var w4 := RunState.wave_plan(4)
	check("fast" in w4 and "ranged" in w4, "fast and ranged later")
	check(RunState.wave_plan(RunState.BOSS_EVERY)[0] == "boss", "boss wave")
	check(RunState.wave_plan(9).size() > RunState.wave_plan(4).size(), "waves grow")
	check(RunState.enemy_stats("melee", 10).hp > RunState.enemy_stats("melee", 1).hp, "enemies get tougher")


func _test_profile() -> void:
	var path := "user://test_profile.json"
	DirAccess.remove_absolute(path)
	var p := ProfileState.new()
	p.load_profile(path)
	check(p.gold == 0 and p.spells.primary == "fire_bolt", "fresh profile")
	check(p.available_spells("primary").size() == 1, "only the starter spell unlocked")
	# Bonus prices grow, and stop at max.
	check(p.bonus_price("vitality") == 50 and not p.buy_bonus("vitality"), "too poor")
	p.gold = 1000
	check(p.buy_bonus("vitality") and p.bonus_price("vitality") == 75 and p.gold == 950, "bonus bought, price grows")
	p.bonuses.focus = Profile_max("focus")
	check(p.bonus_price("focus") == -1 and not p.buy_bonus("focus"), "maxed bonus")
	check(p.buy_item("robe_warden") and p.equipped.robe == "robe_warden" and p.gold == 830, "item bought and equipped")
	check(not p.buy_item("robe_warden"), "item bought once")
	check(p.equip_item("robe_novice") and p.equip_item("robe_warden"), "re-equip owned")
	check(not p.equip_item("staff_crystal"), "cannot equip unowned")
	var st := p.total_stats()
	check(st.hp == 100.0 + 30.0 + 10.0 and st.regen == 25.0 + 3.0 * Profile_max("focus"), "stats sum items and bonuses")
	# End of run: gold kept, scores sorted, achievements unlock spells.
	var reached := p.record_run({"score": 300, "wave": 10, "level": 4, "kills": 120, "bosses": 1, "gold": 70, "scrolls": 1})
	p.record_run({"score": 900, "wave": 3, "level": 2, "kills": 5, "bosses": 0, "gold": 5, "scrolls": 0})
	check(p.gold == 905 and p.blank_scrolls == 1, "gold and scrolls kept")
	check(p.scores[0].score == 900 and p.scores.size() == 2, "scores sorted")
	check("hunter" in reached and "boss" in reached and "wave10" in reached, "achievements reached")
	check(p.available_spells("primary").size() == 4, "achievements unlock spells")
	check(p.equip_spell("primary", "spark") and not p.equip_spell("primary", "arcane_missiles"), "equip unlocked only")
	check(p.available_skills() == ["shield"] and not p.equip_skill("heal_zone"), "only the starter skill unlocked")
	p.achievements.boss3 = 1
	check(p.equip_skill("heal_zone"), "achievements unlock skills")
	check(p.add_forged(Spell.base(), "user://missing.spell") == "forged_1", "forged spell kept")
	p.set_look("hat", "#123456")
	p.set_look("hat", "not a color")
	# Save -> load round trip.
	var q := ProfileState.new()
	q.load_profile(path)
	for k in ["gold", "blank_scrolls", "owned", "equipped", "bonuses", "look", "stats", "spells", "skill", "scores"]:
		check(q.get(k) == p.get(k), "%s saved" % k)
	check(q.achievements == p.achievements, "achievements saved")
	check(q.equipped_spells().primary.name == Spell.base().name, "forged spell restored from its JSON")
	# A corrupt save is ignored, not fatal.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"gold": "lots", "equipped": {"robe": "robe_archmage"}, "bonuses": {"power": 99}, "spells": {"primary": "nope"}}')
	f.close()
	var c := ProfileState.new()
	c.load_profile(path)
	check(c.gold == 0 and c.equipped.robe == "robe_novice" and c.bonuses.power == 10 and c.spells.primary == "fire_bolt", "corrupt save sanitized")
	for x in [p, q, c]:
		x.free()


func Profile_max(id: String) -> int:
	return ProfileState.BONUSES[id].max


## Every base spell and enemy kind runs in a real scene.
func _test_play() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var run := RunState.new()
	var p := ProfileState.new()
	var spells := {}
	for e in p.base_spells:
		spells[e.id] = e.spell
	run.start(spells)
	var player := Player.new()
	player.run = run
	player.position = Vector2(640, 360)
	world.add_child(player)
	player.set_physics_process(false)
	for kind in ["melee", "fast", "ranged", "boss"]:
		var e := Enemy.new()
		e.setup(kind, RunState.enemy_stats(kind, 1))
		e.hp = 1e6
		e.max_hp = 1e6
		e.target = player
		e.position = player.position + Vector2(150, 0).rotated(randf() * TAU)
		world.add_child(e)
	await physics_frame
	var hp_before := 0.0
	for e in get_nodes_in_group("enemies"):
		hp_before += e.hp
	for id in spells:
		player.mana = 1000.0
		player.cooldowns = {}
		check(player.cast(id), "%s casts" % id)
		for i in 20:
			await physics_frame
	for i in 120:
		await physics_frame
	var hp_after := 0.0
	for e in get_nodes_in_group("enemies"):
		hp_after += e.hp
	check(hp_after < hp_before, "base spells damage enemies")
	check(player.hp < player.max_hp, "enemies hurt the player")
	# Skills: the shield blocks damage, the zones give hp and mana back.
	for id in Skills.LIST:
		player.skill = id
		player.skill_cooldown = 0.0
		player.mana = 100.0
		check(player.use_skill() and not player.use_skill(), "%s used, then on cooldown" % id)
	var hp := player.hp
	player.hurt(5.0)
	check(player.hp == hp, "shield blocks damage")
	player.hp = 1.0
	player.mana = 0.0
	for i in 30:
		await physics_frame
	check(player.hp > 1.0 and player.mana > 0.0, "zones heal and give mana")
	check(Player.clean_loadout({"skill": "nope"}).skill == "" and Player.clean_loadout({"skill": "shield"}).skill == "shield", "loadout skill checked")
	world.free()
	run.free()
	p.free()
