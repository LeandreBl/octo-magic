extends SceneTree
## Run: godot --headless --script tests/test_game.gd  (see tests/run.sh)
## Game logic: level-ups, upgrades, waves, shop prices, save/load.

const RunState := preload("res://game/run.gd")
const ProfileState := preload("res://game/profile.gd")
const Enemy := preload("res://game/enemy.gd")
const Player := preload("res://game/player.gd")
const Tentacle := preload("res://game/tentacle.gd")
const SPELL_TYPES := ["bolt", "ring", "puddle", "summon", "burst", "laser", "teleport"]

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
	_test_french()
	_test_sfx()
	_test_tentacle()
	var Forge: GDScript = load("res://ui/forge.gd")  # load: it needs the autoloads
	check(Forge.coverage(0) == 0.0 and Forge.coverage(30) < Forge.coverage(60) and Forge.coverage(3600) < 1.0,
		"forge runes fill the parchment, never full before the spell is back")
	var a := Enemy.new()
	var b := Enemy.new()
	b.position = Vector2(10, 0)  # radius 12 each: 14 too close
	check(Arena.apart(a, [a, b]) == Vector2(-7, 0) and Arena.apart(b, [a, b]) == Vector2(7, 0), "overlapping enemies push apart")
	b.hp = 0.0
	check(Arena.apart(a, [a, b]) == Vector2.ZERO, "the dead push nothing")
	a.free()
	b.free()
	await _test_play()
	_test_boss_death()  # in the tree, once it runs
	print("game tests: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures else 0)


## Every text of the game has its French translation (locale/fr.po): tr()
## literals in the code, and the names in the game's data.
func _test_french() -> void:
	TranslationServer.set_locale("fr")
	var texts := ["Spell"]
	var literal := RegEx.create_from_string("\\btr\\(\"((?:[^\"\\\\]|\\\\.)+)\"\\)")
	for dir in ["res://game/", "res://ui/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				for m in literal.search_all(FileAccess.get_file_as_string(dir + f)):
					texts.append(m.get_string(1).c_unescape())
	texts += Run.ENEMIES.values().filter(func(e): return e.has("name")).map(func(e): return e.name)
	for d in [Upgrades.LIST, ProfileState.AUGMENTS, ProfileState.ITEMS, ProfileState.BONUSES, ProfileState.ACHIEVEMENTS]:
		for v in d.values():
			texts.append(v.name)
			if v.has("desc") and not v.desc.begins_with("+3 mana/s"):
				texts.append(v.desc)
	var p := ProfileState.new()
	for e in p.base_spells:
		texts += [e.spell.name, e.spell.description]
	p.free()
	for m in RegEx.create_from_string("\"[A-Z_]+\": \"([^\"]+)\"").search_all(FileAccess.get_file_as_string("res://game/online.gd")):
		texts.append(m.get_string(1))  # Online.ERRORS (the autoload needs Profile)
	texts += Settings.REBINDABLE.values().filter(func(t): return t != "Pause")
	var same := ["Scribe", "Robur", "Parsimonia", "Inspiratio", "Celeritas", "Tutela Ignis", "Fluxus", "Receptaculum", "Meditatio", "Antidotum", "Pernicitas", "Magnes", "Potentia", "Catena", "Procella", "Aether", "Ventus Algidus", "Rigor", "Plura Tela", "Conus Glaciei", "Favillae", "Fortune", "Endurance", "Attraction", "Fulmen", "Flatus Gelidus", "Pila Ignea", "Telum Magicum", "Fragmen Glaciei", "Arcus Fulguris", "Spiculum Veneni", "Tela Arcana", "Poison", "Zone", "Projectiles", "Abomination"]
	for t in texts:
		check(t in same or TranslationServer.translate(t) != t, "French for: " + t)
	check(Spell.describe({"description": "x", "description_fr": "y"}) == "y", "forged spell described in French")
	TranslationServer.set_locale("en")
	check(Spell.describe({"description": "x", "description_fr": "y"}) == "x", "forged spell described in English")


func _damage(s: Dictionary) -> float:
	return s.emit.body.on_hit.filter(func(f): return f.type == "damage")[0].amount


## Skills for the tests (Upgrades.LIST is filled skill by skill).
const SKILLS := {
	"tough": {"name": "Tough", "desc": "+%d max health", "step": 25, "max": 4, "kind": "hero", "stat": "hp"},
	"quick": {"name": "Quick", "desc": "+%d%% move speed", "step": 10, "max": 1, "kind": "hero", "stat": "speed%", "pct": true},
	"vigor": {"name": "Vigor", "desc": "+%d max mana", "step": 50, "max": 4, "kind": "hero", "stat": "mana"},
	"magnet": {"name": "Magnet", "desc": "+%d%% pickup radius", "step": 30, "max": 5, "kind": "hero", "stat": "pickup%", "pct": true},
	"swift": {"name": "Swift", "desc": "-%d%% cooldown", "step": -10, "max": 9, "kind": "spell", "stat": "cooldown%", "pct": true},
	"thrift": {"name": "Thrift", "desc": "-%d%% mana cost", "step": -15, "max": 11, "kind": "spell", "stat": "mana_cost%", "pct": true},
}


func _test_upgrades() -> void:
	var s := Spell.base()
	# Nested casts are scaled too.
	var boom := Spell.sanitize({"emit": {"body": {"on_expire": [{"type": "cast", "emit": {"body": {
		"on_hit": [{"type": "damage", "amount": 10}]}}}]}}})
	check(Spell.scale_damage(boom, 2.0).emit.body.on_expire[0].emit.body.on_hit[0].amount == 20.0, "nested damage scaled")
	check(is_equal_approx(_damage(Spell.scale_damage(s, 1.5)), _damage(s) * 1.5), "damage scaled")
	check(["I", "II", "III", "IV", "V", "IX", "XI"] == [1, 2, 3, 4, 5, 9, 11].map(Upgrades.roman), "levels in roman numerals")
	check(Upgrades.title(Upgrades.LIST.haste, 3) == "Celeritas III" and Upgrades.title(Upgrades.LIST.channeling, 1) == "Meditatio", "single-level skill has no numeral")
	check(Upgrades.describe(Upgrades.LIST.thrift) == "-15% mana cost", "thrift described")
	var free := Stats.total([Upgrades.bonus(Upgrades.LIST.thrift, 11)])
	check(is_equal_approx(Stats.total([Upgrades.bonus(Upgrades.LIST.thrift, 2)]).mana_cost, 0.7) and free.mana_cost == 0.0, "thrift: -15% a level, down to free")
	check(Stats.cost(10, 0.01) == 1 and Stats.cost(10, free.mana_cost) == 0, "free spells only at -100%")
	check(Upgrades.describe(Upgrades.LIST.toughness) == "+25 max HP" and Upgrades.LIST.toughness.max == 4, "toughness described")
	check(Stats.total([Upgrades.bonus(Upgrades.LIST.toughness, 4)]).hp == 200.0, "toughness: +25 max HP a level, up to IV")
	check(Upgrades.describe(Upgrades.LIST.reservoir) == "+50 max mana" and Stats.total([Upgrades.bonus(Upgrades.LIST.reservoir, 4)]).mana == 300.0, "reservoir: +50 max mana a level, up to IV")
	check(Upgrades.describe(Upgrades.LIST.channeling) == "+300% mana regen standing still" and Upgrades.LIST.channeling.max == 1, "channeling described")
	check(Stats.total([Upgrades.bonus(Upgrades.LIST.channeling, 1)]).still_regen == 4.0 and Stats.BASE.still_regen == 1.0, "channeling: mana regen x4 standing still")
	var mage := Player.new()
	mage.stats = Stats.total([Upgrades.bonus(Upgrades.LIST.channeling, 1)])
	mage._still = Player.STILL_TIME + 0.1
	var still: bool = mage.channeling()
	mage._still = 0.0
	check(still and not mage.channeling(), "channeling only standing still")
	mage.free()
	check(Upgrades.LIST.fleetness.max == 8 and is_equal_approx(Stats.total([Upgrades.bonus(Upgrades.LIST.fleetness, 3)]).speed, 286.0), "fleetness: +10 % move speed a level, up to VIII")
	check(Upgrades.bonus(SKILLS.tough, 3) == {"hp": 75.0} and Upgrades.bonus(SKILLS.quick, 1) == {"speed%": 0.1}, "skills are Stats bonuses")
	var rng := RandomNumberGenerator.new()
	var offers := Upgrades.offers({}, rng, "", 3, SKILLS)
	check(offers.size() == 3 and offers.all(func(o): return o.level == 1), "3 offers, at level I")
	check(offers.map(func(o): return o.id).reduce(func(seen, id): seen[id] = 1; return seen, {}).size() == 3, "distinct offers")
	check(Upgrades.offers({}, rng, "spell", 3, SKILLS).size() == 2, "a kind offers its own skills")
	var catena: Dictionary = Upgrades.LIST.chaining
	check(catena.max == 5 and Upgrades.title(catena, 5) == "Catena V" and Stats.total([Upgrades.bonus(catena, 5)]).chain == 5.0, "Catena: +1 chained enemy a level, up to V")
	var aether: Dictionary = Upgrades.LIST.ether_charge
	check(aether.max == 5 and aether.spell == "lightning" and is_equal_approx(Stats.total([Upgrades.bonus(aether, 5)]).ether, 0.4), "Aether: -12 % Fulmen mana cost a level, up to V")
	var st := Stats.total([Upgrades.bonus(aether, 5)])
	check(Stats.cost(50, Stats.cost_mult(st, "primary")) == 20 and Stats.cost(50, Stats.cost_mult(st, "secondary")) == 50, "Aether lightens the primary spell only")
	var rigor: Dictionary = Upgrades.LIST.harden
	check(rigor.max == 5 and rigor.spell == "frost_jet" and is_equal_approx(Stats.total([Upgrades.bonus(rigor, 5)]).harden, 0.15), "Rigor: +3 % freeze chance a level, up to V, for Flatus Gelidus")
	var tela: Dictionary = Upgrades.LIST.more_missiles
	check(tela.max == 5 and tela.spell == "magic_missile" and Stats.total([Upgrades.bonus(tela, 5)]).missiles == 5.0, "Plura Tela: +1 missile a level, up to V, for Telum Magicum")
	var mm := Player.new()
	mm.stats = Stats.total([Upgrades.bonus(tela, 2)])
	var mms := {"emit": {"count": 1, "spread": 0}}
	check(mm.emit("primary", mms).count == 3 and mm.emit("primary", mms).spread > 0 and mm.emit("secondary", mms).count == 1 and mms.emit.count == 1, "Plura Tela adds missiles to the primary cast only, never to the spell data")
	mm.free()
	var sub := {"chaining": catena}
	check(Upgrades.offers({}, rng, "spell", 3, sub).is_empty() and Upgrades.offers({}, rng, "spell", 3, sub, "fireball").is_empty()
		and Upgrades.offers({}, rng, "spell", 3, sub, "lightning").size() == 1, "a sub-skill only for its base spell (Fulmen), never a forged one")
	var procella: Dictionary = Upgrades.LIST.hurricane
	check(procella.max == 5 and Upgrades.title(procella, 5) == "Procella V" and procella.spell == "frost_jet"
		and Stats.total([Upgrades.bonus(procella, 5)]).gust == 300.0, "Procella: a Flatus Gelidus sub-skill, up to V")
	var chill: Dictionary = Upgrades.LIST.chill_wind
	check(chill.max == 5 and chill.spell == "frost_jet" and is_equal_approx(Stats.total([Upgrades.bonus(chill, 5)]).chill, 0.5), "Ventus Algidus: Flatus Gelidus slows 10 % more a level, up to V")
	var conus := {"cone_of_ice": Upgrades.LIST.cone_of_ice}
	check(Upgrades.offers({}, rng, "spell", 3, conus, "frost_jet").size() == 1 and Upgrades.offers({}, rng, "spell", 3, conus, "lightning").is_empty()
		and Upgrades.title(conus.cone_of_ice, 5) == "Conus Glaciei V", "Conus Glaciei: for Flatus Gelidus only, up to V")
	var favillae: Dictionary = Upgrades.LIST.embers
	check(favillae.max == 5 and favillae.spell == "fireball" and Upgrades.title(favillae, 5) == "Favillae V"
		and Stats.total([Upgrades.bonus(favillae, 5)]).embers == 10.0 and not Spell.sanitize({"embers": 5}).has("embers"),
		"Favillae: embers +2 damage a tick a level, up to V, only for Pila Ignea, never spell data")
	check(Upgrades.offers({"tough": 2}, rng, "hero", 4, SKILLS).any(func(o): return o == {"id": "tough", "level": 3}), "the next level offered")
	check(Upgrades.offers({"tough": 4, "quick": 1, "vigor": 4, "magnet": 5}, rng, "hero", 3, SKILLS).is_empty(), "maxed skills not offered")
	var haste: Dictionary = Upgrades.LIST.haste
	check(haste.max == 9 and is_equal_approx(Stats.total([Upgrades.bonus(haste, 3)]).cast_rate, 1.3), "Haste: +10 % cast rate per level, 9 levels")
	var fireproof: Dictionary = Upgrades.LIST.fireproof
	check(fireproof.max == 9 and is_equal_approx(Stats.total([Upgrades.bonus(fireproof, 3)]).fire, 0.7), "Fireproof: +10 % fire resistance per level, 9 levels")
	var burnt := Player.new()
	burnt.stats = Stats.total([Upgrades.bonus(fireproof, 5)])
	burnt.hp = 100.0
	burnt.hurt(10.0, true)
	burnt.hurt(10.0)
	check(is_equal_approx(burnt.hp, 85.0), "Fireproof cuts fire damage only")
	burnt.free()
	check(RunState.ENEMIES.fire_mage.get("fire") and RunState.ENEMIES.burning_archer.get("fire") and not RunState.ENEMIES.archer.has("fire"), "fire enemies marked")
	var flow: Dictionary = Upgrades.LIST.flow
	check(flow.max == 9 and is_equal_approx(Stats.total([Upgrades.bonus(flow, 2)]).mana_regen, Stats.BASE.mana_regen * 1.7), "Flow: +35 % mana regeneration per level, 9 levels")
	var power: Dictionary = Upgrades.LIST.damage
	check(power.max == 9 and is_equal_approx(Stats.total([Upgrades.bonus(power, 3)]).damage, 1.75), "Power: +25 % spell damage per level, 9 levels")
	var antidote: Dictionary = Upgrades.LIST.antidote
	check(antidote.max == 9 and is_equal_approx(Stats.total([Upgrades.bonus(antidote, 3)]).poison, 0.7), "Antidote: +10 % poison resistance per level, 9 levels")
	var magnetism: Dictionary = Upgrades.LIST.magnetism
	check(magnetism.max == 5 and is_equal_approx(Stats.total([Upgrades.bonus(magnetism, 2)]).pickup, Stats.BASE.pickup * 1.6), "Magnetism: +30 % pickup radius per level, 5 levels")


func _test_run() -> void:
	var run := RunState.new()
	var p := ProfileState.new()
	run.start(p.equipped_spells(), [{"damage%": 0.5}])
	check(run.spells.keys() == ["primary"], "one spell, no secondary or ultimate")
	check(is_equal_approx(_damage(run.spells.primary), _damage(p.equipped_spells().primary) * 1.5), "damage bonus applied")
	var got := []
	run.offered.connect(func(o): got.append(o))
	var gained := [0]
	run.level_gained.connect(func(): gained[0] += 1)
	run.add_xp(RunState.xp_to_next(1) - 1)
	check(run.level == 1 and gained[0] == 0, "no level-up before the threshold")
	run.add_xp(1 + RunState.xp_to_next(2))  # two level-ups at once
	check(run.level == 3 and gained[0] == 1, "one refill for the levels gained at once")
	check(got.is_empty() and run.offers.is_empty(), "a level-up offers no upgrade")
	run.list = {}
	run.collect("grimoire_hero", 1)
	check(run.pending.is_empty() and run.offers.is_empty(), "a grimoire with no skill to offer is lost")
	run.list = SKILLS
	run.collect("grimoire_hero", 1)
	run.collect("grimoire_spell", 1)  # two grimoires queue
	check(run.pending == ["hero", "spell"] and got.size() == 1 and run.offers.size() == 3, "grimoires queue")
	check(run.offers.all(func(o): return SKILLS[o.id].kind == "hero"), "a red grimoire offers hero skills")
	run.offers = [{"id": "tough", "level": 1}]
	var hp: float = run.stats.hp
	check(run.choose(0), "a second choice waits")
	check(run.stats.hp == hp + 25.0 and run.levels == {"tough": 1}, "skill taken at level I")
	check(run.offers.all(func(o): return SKILLS[o.id].kind == "spell"), "a blue grimoire offers spell skills")
	var cost := run.mana_cost("primary")
	run.offers = [{"id": "thrift", "level": 1}]
	check(not run.choose(0) and run.pending.is_empty() and run.offers.is_empty(), "all choices made")
	check(run.mana_cost("primary") < cost, "spell skill applied")
	run.pending = ["hero"]
	run.offers = [{"id": "tough", "level": 2}]
	run.choose(0)
	check(run.stats.hp == hp + 50.0 and run.levels.tough == 2, "taken again: level II")
	run.start(p.equipped_spells())
	check(run.levels.is_empty() and run.stats.hp == Stats.BASE.hp, "a new run starts with no skill")
	_test_inspiration(run)
	run.list = Upgrades.LIST
	run.start(p.equipped_spells(), [{"gold%": 0.5}, {"mana_cost%": -0.5}])
	check(run.mana_cost("primary") == maxi(1, roundi(Spell.mana_cost(run.spells.primary) * 0.5)), "mana cost stat")
	run.collect("gold", 10)
	check(run.gold == 15, "gold bonus")
	_test_augments(run, p)
	run.wave = 6
	run.killed("boss")
	var kills := run.kills
	run.killed("grave_maw")
	check(run.kills == kills + 401, "a boss monster adds its kills")
	run.pending = ["spell"]
	run.list = SKILLS
	run.levels = {"tough": 2}
	run.base = "lightning"
	run._restat()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(run.to_dict()))  # as saved in the profile
	var back := RunState.new()
	back.list = SKILLS
	check(back.restore(snap) and back.wave == 6 and back.kills == run.kills and back.level == run.level
		and back.spells.primary == run.spells.primary and back.stats == run.stats and back.levels == run.levels
		and back.pending == ["spell"] and back.base == "lightning" and is_equal_approx(back.mana_cost("primary"), run.mana_cost("primary")),
		"a saved run comes back as it was")
	check(not back.restore({}) and not back.restore({"spells": "x"}), "no run in a broken save")
	run.list = Upgrades.LIST
	back.free()
	p.run = snap
	var p2 := ProfileState.new()
	p2.apply(p.to_dict())
	check(p2.run.wave == 6, "the saved run is part of the profile (and its cloud copy)")
	p2.free()
	p.run = {}
	var r := run.finish()
	check(not run.active and r.bosses == 2 and r.score == run.score(), "run result")
	run.free()
	p.free()


## Augments: bought once in the shop and kept, the slotted ones start every run.
func _test_augments(run: Object, p: Object) -> void:
	p.path = "user://test_augments.json"
	var in_cats := []
	for ids in ProfileState.AUGMENT_CATS.values():
		in_cats += ids
	in_cats.sort()
	var all: Array = ProfileState.AUGMENTS.keys()
	all.sort()
	check(in_cats == all, "every augment in one shop category")
	p.gold = 0
	check(not p.buy_augment("ring_of_fire") and p.augments.is_empty(), "too poor for the ring")
	p.gold = 3000
	check(p.buy_augment("ring_of_fire") and p.gold == 1500 and p.slotted == ["ring_of_fire"], "ring bought and slotted")
	check(not p.buy_augment("ring_of_fire") and p.gold == 1500, "bought once")
	check(p.buy_augment("shield") and p.slotted == ["ring_of_fire", "shield"], "shield bought and slotted")
	p.slotted = ["a", "b", "c"]  # full
	check(not p.can_slot("shield"), "no more than SLOTS")
	p.slotted = ["ring_of_fire"]
	check(p.toggle_augment("shield") and p.toggle_augment("ring_of_fire") and p.slotted == ["shield"], "slot and unslot")
	p.toggle_augment("ring_of_fire")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	saved.slotted.append("god_mode")
	p.apply(saved)
	check(p.augments.size() == 2 and p.slotted == ["shield", "ring_of_fire"], "augments saved, unknown dropped")
	run.start(p.equipped_spells(), [], p.slotted_augments())
	check(run.spells.secondary.emit.pattern == "radial" and run.passives == ["shield"], "a run starts with the slotted augments")
	var l := Player.clean_loadout(JSON.parse_string(JSON.stringify({"spells": run.spells, "passives": run.passives})))
	check(l.spells.has("secondary") and l.passives == ["shield"], "loadout keeps the augments")
	check(Player.clean_loadout({"passives": ["god_mode", "potions"]}).passives == ["potions"], "unknown passive dropped")
	var st: Dictionary = Player.clean_loadout({"stats": {"armor": 5, "hp": "x", "god": 1}}).stats
	check(st.armor == Stats.BOUNDS.armor[1] and st.hp == Stats.BASE.hp and st.keys() == Stats.BASE.keys(), "loadout stats clamped")
	var me := Player.new()
	me.loadout_json = JSON.stringify(l)
	me.hurt(30.0)
	check(me.hp == me.stats.hp and me.shield == Player.SHIELD_HP - 30.0, "shield absorbs")
	me.hurt(30.0)
	check(me.hp == me.stats.hp - 20.0 and me.shield == 0.0 and me.shield_wait == Player.SHIELD_WAIT, "shield breaks")
	l.passives = ["potions"]
	me.loadout_json = JSON.stringify(l)
	check(me.shield == 0.0 and me.potions == Player.POTIONS, "no shield without the passive, potions with theirs")
	me.hp = me.stats.hp
	me.hurt(me.stats.hp * 0.8)
	check(me.hp == me.stats.hp * 0.7 and me.potions == Player.POTIONS - 1, "a potion is drunk below 30% HP")
	me.hp = me.stats.hp - 20.0
	var orb := preload("res://game/pickup.gd").new()
	me.mana = 0.0
	orb.kind = "mana"
	orb.give(me)
	check(me.mana == me.stats.mana * orb.REFILL, "mana orb refills")
	orb.kind = "life"
	orb.give(me)
	check(me.hp == me.stats.hp, "life orb heals, capped")
	check(not orb.wants(me), "a life orb is left alone at full health")
	orb.kind = "mana"
	check(orb.wants(me), "a mana orb is wanted below full mana")
	me.mana = me.stats.mana
	check(not orb.wants(me), "a mana orb is left alone at full mana")
	orb.kind = "life"
	me.hurt(30.0)
	me.mana = 0.0
	l.refill = true
	me.loadout_json = JSON.stringify(Player.clean_loadout(JSON.parse_string(JSON.stringify(l))))
	check(me.hp == me.stats.hp and me.mana == minf(me.stats.mana, Player.LEVEL_UP_HEAL), "a level-up gives 100 health and mana, capped")
	orb.kind = "gold"
	var floor := Node2D.new()
	floor.add_child(orb)
	orb._process(0.1)
	check(orb._hop().x > 0.0, "gold pops up when dropped")
	orb._process(1.0)
	check(orb._hop() == Vector2.ZERO and floor.get_child_count() == 2, "gold lands and glints once")
	orb._process(1.0)
	check(floor.get_child_count() == 2, "a single glint")
	check(orb.gold_tier(1)[1] != orb.gold_tier(2)[1] and orb.gold_tier(3)[1] == orb.gold_tier(9)[1]
		and orb.gold_tier(40)[2] > orb.gold_tier(1)[2], "a gold heap looks as rich as it is")
	floor.free()
	me.free()
	run.start({}, [])
	check(run.passives.is_empty() and run.spells.is_empty(), "no augment slotted, none in the run")
	_test_perks(run, p)
	DirAccess.remove_absolute(p.path)


## Inspiration: a 4th card per grimoire, once; not stacked with Creativity.
func _test_inspiration(run: Object) -> void:
	run.list = SKILLS.merged({"inspiration": Upgrades.LIST.inspiration})
	var ids := func(): return run.offers.map(func(o): return o.id)
	for c in [[3, {}, 3, true], [3, {"inspiration": 1}, 4, false], [4, {}, 4, false]]:
		run.bonuses = [{"choices": c[0] - 3.0}]
		run.levels = c[1]
		run._restat()
		run.pending = ["hero"]
		run.offers = []
		run._offer()
		check(run.offers.size() == c[2] and (c[3] or not "inspiration" in ids.call()),
			"inspiration: %d cards with perk %d, skill %s" % [c[2], c[0], c[1]])
	run.bonuses = []
	run.levels = {}
	run.pending = []
	run.offers = []
	run._restat()


## Perks: passive augments with Stats bonuses, run rules, extra slots.
func _test_perks(run: Object, p: Object) -> void:
	p.gold = 100000
	p.slotted = []
	p.bonuses = {}
	for id in ["life_up", "creativity", "head_start", "hardcore"]:
		check(p.buy_augment(id), "%s bought" % id)
	check(p.slotted == ["life_up", "creativity", "head_start"], "three slots")
	check(p.bonus_price("slots") == 2500 and p.buy_bonus("slots") and p.bonus_price("slots") == 20000, "a fourth slot, the fifth far dearer")
	check(p.toggle_augment("hardcore") and p.slots() == 4, "fourth slot used")
	var s := Stats.total(p.bonus_list())
	check(s.hp == Stats.BASE.hp + 25.0 and s.armor == -1.0 and s.damage == 2.0, "perk bonuses in the stats")
	run.start(p.equipped_spells(), p.bonus_list(), p.slotted_augments())
	check(run.stats.choices == 4 and run.pending == Upgrades.KINDS, "4 choices, a red and a blue grimoire to open")
	run.list = SKILLS
	run._offer()
	check(run.offers.size() == 4, "a grimoire offers 4 cards")
	run.list = Upgrades.LIST
	var me := Player.new()
	me.loadout_json = JSON.stringify(Player.clean_loadout({"stats": run.stats, "fresh": true}))
	me.hurt(10.0)
	check(me.hp == me.stats.hp - 20.0, "hardcore: double damage taken")
	me.free()
	p.slotted = []
	p.bonuses = {}


## Bosses die in a show of their own: art for each, blasts, then gone.
func _test_boss_death() -> void:
	for k in RunState.BOSSES.values():
		check(Enemy.art(k + "/death") != null, "%s has a death animation" % k)
	check(BossDeath.length("fx/boss_explosion") > 0.5, "the big explosion plays")
	# every look plays a move for each of its spells, the melee ones a strike
	for k in RunState.ENEMIES:
		var e: Dictionary = RunState.ENEMIES[k]
		var anims: Array = e.get("spells", []).filter(func(sp): return Enemy.SPELL_ANIM.has(sp.type)).map(func(sp): return Enemy.SPELL_ANIM[sp.type][0])
		if not e.has("spells"):
			anims.append("attack")
		var looks := [k] + ([k + "_" + e.variant[0]] if e.has("variant") else [])
		for look in looks:
			for a in anims:
				check(Enemy.art(look + "/" + a) != null, "%s has its %s animation" % [look, a])
	var fx := BossDeath.new()
	root.add_child(fx)
	check(fx._blasts.size() == BossDeath.BLASTS + BossDeath.RING, "blasts planned")
	fx._process(BossDeath.AGONY + 0.1)
	check(fx._flash.color.a > 0.5, "the big blast flashes the screen")
	fx._process(10.0)
	check(fx.is_queued_for_deletion(), "gone once it blew up")
	fx.free()
	# every other monster falls in a death strip, then fades out
	for look in DirAccess.get_directories_at("res://assets/monsters"):
		check(look == "fx" or Enemy.art(look + "/death") != null, "%s has a death animation" % look)
	var c := Enemy.Corpse.new()
	root.add_child(c)
	check(not c.is_queued_for_deletion(), "a corpse plays its death")
	c._process(10.0)
	check(c.is_queued_for_deletion(), "a corpse fades out")
	c.free()


func _test_waves() -> void:
	check(RunState.wave_plan(1).all(func(k): return k == "skeleton"), "wave 1 is skeletons only")
	var w4 := RunState.wave_plan(4)
	check("imp" in w4 and w4.all(func(k): return RunState.ENEMIES[k].from <= 4), "kinds join wave after wave")
	check(RunState.wave_plan(4) == w4, "the same plan on every peer")
	var w12 := {}
	for k in RunState.wave_plan(12):
		w12[k] = true
	check(w12.size() >= 6, "late waves mix many kinds (%d)" % w12.size())
	for w in range(RunState.BOSS_EVERY, 50, RunState.BOSS_EVERY):
		var plan := RunState.wave_plan(w)
		check(RunState.is_boss(plan[0]) and plan.count(plan[0]) == 1, "boss wave")
		check(plan[0] == RunState.BOSSES[mini(w, 30)], "the boss of wave %d" % w)
	var attacks := []
	for k in ["bone_herald", "pyre_lord", "blight_eye", "grave_maw"]:  # each one adds an attack
		var types: Array = RunState.ENEMIES[k].spells.map(func(sp): return sp.type)
		check(types.slice(0, attacks.size()) == attacks and types.size() == attacks.size() + 1, "%s stacks the attacks" % k)
		attacks = types
	var imps := func(w): return RunState.enemy_stats("archfiend", w).spells.filter(func(sp): return sp.has("imps"))[0].imps
	check(RunState.enemy_stats("grave_maw", 25).spells[0].every < RunState.ENEMIES.grave_maw.spells[0].every, "bosses cast faster")
	check(imps.call(35) > imps.call(30) and imps.call(40) > imps.call(35), "more imps every time the last boss comes back")
	for k in RunState.ENEMIES:
		for sp in RunState.ENEMIES[k].get("spells", []):
			check(sp.type in SPELL_TYPES, "%s casts a known spell" % k)
		var summons: Array = RunState.ENEMIES[k].get("spells", []).filter(func(sp): return sp.type == "summon")
		for other in summons.map(func(sp): return sp.kind):
			check(RunState.ENEMIES.has(other), "%s summons a known kind" % k)
		var e: Array = RunState.ENEMIES[k].get("effect", [])
		check(not e or e[0] in ["poison", "freeze", "stun"], "%s puts a known status" % k)
		check(not RunState.ENEMIES[k].has("gunk") or e and e[0] == "poison", "%s gunk is poison" % k)
	check(RunState.wave_plan(9).size() > RunState.wave_plan(4).size(), "waves grow")
	# Waves spawn out of every mage's view: tests/test_arena.gd (Arena.spawn_point).
	check(RunState.enemy_stats("skeleton", 10).hp > RunState.enemy_stats("skeleton", 1).hp, "enemies get tougher")
	var looks := {}
	for i in 60:
		var st := RunState.enemy_stats("fire_mage", 1)
		looks[st.look] = st.hp
	check(looks.get("fire_mage_shield", 0.0) > looks.get("fire_mage", INF), "some mages wear a shield, tougher")


func _test_profile() -> void:
	# Menus pause the tree: a paused Online never finishes creating a character.
	check(root.get_node("Online").process_mode == Node.PROCESS_MODE_ALWAYS,"Online's requests run while menus pause the game")
	var path := "user://test_profile.json"
	DirAccess.remove_absolute(path)
	var p := ProfileState.new()
	p.load_profile(path)
	check(p.gold == 0 and p.spells.primary == "fireball", "fresh profile")
	check(p.available_spells("primary").size() == 4, "only the base spells unlocked")
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
	var st := Stats.total(p.bonus_list())
	check(st.hp == 100.0 + 30.0 + 10.0 and st.mana_regen == 5.0 + 3.0 * Profile_max("focus"), "stats sum items and bonuses")
	check(is_equal_approx(st.armor, 0.05), "robe armor")
	# End of run: gold kept, scores sorted, achievements unlock spells.
	var reached := p.record_run({"score": 300, "wave": 10, "level": 4, "kills": 120, "bosses": 1, "gold": 70, "scrolls": 1})
	p.record_run({"score": 900, "wave": 3, "level": 2, "kills": 5, "bosses": 0, "gold": 5, "scrolls": 0})
	check(p.gold == 905 and p.blank_scrolls == 1, "gold and scrolls kept")
	check(p.scores[0].score == 900 and p.scores.size() == 2, "scores sorted")
	check("hunter" in reached and "boss" in reached and "wave10" in reached, "achievements reached")
	check(p.available_spells("primary").size() == 7, "achievements unlock spells")
	check(p.equip_spell("primary", "spark") and not p.equip_spell("primary", "arcane_missiles"), "equip unlocked only")
	check(p.add_forged(Spell.base(), "user://spells/forged_1.spell") == "forged_1", "forged spell kept")
	var owned := p.equipped_entries()
	check(owned.size() == 1 and owned[0].id == "forged_1", "forge picks among the equipped spells only")
	owned = p.available_spells("primary")
	var Forge: GDScript = load("res://ui/forge.gd")
	check(Forge.step(owned, "forged_1", 1) == owned[0].id and Forge.step(owned, owned[0].id, -1) == "forged_1",
		"forge spell picker wraps around")
	var forge: Control = Forge.new()
	var rows: Array = forge.stats(Spell.base())
	check(rows[0] == ["Mana cost", Spell.cost_text(Spell.base(), Spell.mana_cost(Spell.base()))]
		and rows.any(func(r): return r[0] == "Damage" and r[1] != "0"), "forge spell view shows the cost and damage")
	forge.free()
	p.set_look("hat", "#123456")
	p.set_look("hat", "not a color")
	# Save -> load round trip.
	var q := ProfileState.new()
	q.load_profile(path)
	for k in ["gold", "blank_scrolls", "owned", "equipped", "bonuses", "look", "stats", "spells", "scores"]:
		check(q.get(k) == p.get(k), "%s saved" % k)
	check(q.achievements == p.achievements, "achievements saved")
	check(q.equipped_spells().primary.name == Spell.base().name, "forged spell restored from its JSON")
	# The server's copy replaces the profile, nothing doubled.
	q.apply(p.to_dict())
	check(q.scores.size() == 2 and q.forged.size() == 1 and q.gold == p.gold, "profile replaced by a copy")
	q.apply({})
	check(q.gold == 0 and q.scores.is_empty() and q.spells.primary == "fireball", "empty copy resets")
	# A corrupt save is ignored, not fatal.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"gold": "lots", "equipped": {"robe": "robe_archmage"}, "bonuses": {"power": 99}, "spells": {"primary": "nope"}}')
	f.close()
	var c := ProfileState.new()
	c.load_profile(path)
	check(c.gold == 0 and c.equipped.robe == "robe_novice" and c.bonuses.power == 10 and c.spells.primary == "fireball", "corrupt save sanitized")
	for x in [p, q, c]:
		x.free()


func Profile_max(id: String) -> int:
	return ProfileState.BONUSES[id].max


## Every base spell and enemy kind runs in a real scene.
## A tentacle keeps its length and stays at the body while it walks: its tip
## steps after it.
func _test_tentacle() -> void:
	var t := Tentacle.new(0.0, 0)
	var center := Vector2.ZERO
	var far := 0.0
	for i in 600:  # 10 s at 60 fps, 120 px/s to the right
		center.x += 2.0
		t.follow(center, 0.0, 1.0 / 60.0, i / 60.0)
		var length := 0.0
		for k in t.chain.size() - 1:
			length += t.chain[k].distance_to(t.chain[k + 1])
		check(absf(length - Tentacle.LENGTH) < Tentacle.LENGTH * 0.2, "tentacle keeps its length: %s" % length)
		far = maxf(far, t.foot.distance_to(center))
	check(far < Tentacle.LENGTH * 1.5, "tentacle steps after the body: %s" % far)
	check(t.chain[0].distance_to(center) < Tentacle.ROOT + 1.0, "tentacle base on the body")
	t.free()
	# At running speed the arms let go of the ground and stream behind the body.
	var behind := 0
	for d in 8:
		var w := Tentacle.new(d * TAU / 8, d % 2)
		for i in 120:  # 2 s at 210 px/s to the right
			w.follow(Vector2(i * 3.5, 0.0), 0.0, 1.0 / 60.0, i / 60.0)
		if w.chain[Tentacle.POINTS - 1].x < 119 * 3.5:
			behind += 1
		w.free()
	check(behind == 8, "swimming tentacles trail behind: %d of 8" % behind)
	# Against a wall and an enemy: no point goes through either.
	var walls := Rect2(0, 0, 400, 400)
	var enemy := [Vector2(40, 200), 12.0]
	for d in 8:
		var w := Tentacle.new(d * TAU / 8, d % 2)
		for i in 300:  # rubs along the left wall, then stands by the enemy
			w.follow(Vector2(Tentacle.ROOT + 1.0, 100.0 + minf(i, 100)), PI / 2, 1.0 / 60.0, i / 60.0, walls, [enemy])
		for p in w.chain.slice(1):
			check(walls.grow(-Tentacle.THICK + 0.01).has_point(p), "tentacle inside the walls: %s" % p)
			check(p.distance_to(enemy[0]) >= enemy[1] + Tentacle.THICK - 0.01, "tentacle out of the enemy: %s" % p)
		w.free()
	# Walking into the map's walls (as the body does, sliding): no point ends in one.
	var inside := 0
	for d in 8:
		var w := Tentacle.new(d * TAU / 8, d % 2)
		var body := Arena.START
		var go := Vector2.from_angle(d * TAU / 8)
		for i in 400:
			body = Arena.slide(body, go * 3.0, 12.0)  # the mage's radius
			w.follow(body, go.angle(), 1.0 / 60.0, i / 60.0, Arena.RECT, [], true)
			for p in w.chain.slice(1):
				if Arena.polygons.any(func(poly): return Geometry2D.is_point_in_polygon(p, poly)):
					inside += 1
		w.free()
	check(inside == 0, "tentacles stay out of the map's walls: %d points in" % inside)


func _test_sfx() -> void:
	for n in Sfx.RECIPES:
		var s := Sfx.synth(Sfx.RECIPES[n])
		var peak := 0.0
		for x in s:
			peak = maxf(peak, absf(x))
		check(s.size() > 0 and peak > 0.05 and peak <= 1.0, "sound %s is audible and does not clip (peak %.2f)" % [n, peak])
	check(Sfx.stream("hit").data.size() == Sfx.synth(Sfx.RECIPES.hit).size() * 2, "16-bit sound data")
	Sfx.play("hit")  # no autoload in tests: a no-op, not a crash
	var credits := FileAccess.get_file_as_string("res://assets/music/CREDITS.md")
	for t in Sfx.TRACKS:
		check(ResourceLoader.exists("res://assets/music/%s.ogg" % t) and (t + ".ogg") in credits, "music track and its credits: " + t)


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
	var summons := []
	for kind in RunState.ENEMIES:
		var e := Enemy.new()
		e.summoned.connect(func(k, _pos): summons.append(k))
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
	var cast := {}
	for e in get_nodes_in_group("enemies"):  # every spell, where it fits
		for sp in e.data.get("spells", []):
			e.hp = e.max_hp * 0.5
			if e.cast(sp, Vector2(40.0, 0.0)):
				cast[sp.type] = true
			e.hp = e.max_hp
		e.windup = 0.0
	check(cast.size() == SPELL_TYPES.size(), "every enemy spell casts: %s" % str(cast.keys()))
	var archer: Enemy = get_nodes_in_group("enemies").filter(func(e): return e.kind == "archer")[0]
	var far := Vector2(Enemy.VIEW.x + 100.0, 0.0)
	check(not archer.cast(archer.data.spells[0], far), "no enemy spell from off screen")
	check(archer._steer(far) != Vector2.ZERO and archer._steer(Vector2(100, 0)) == Vector2.ZERO, "a still one walks in until on screen")
	var lich: Enemy = get_nodes_in_group("enemies").filter(func(e): return e.kind == "boss")[0]
	check(lich.walk_speed(far) > player.stats.speed and lich.walk_speed(Vector2(100, 0)) == lich.speed, "a boss outruns the mage until in cast range")
	for i in 90:  # the delayed parts: missile volleys, bites, imps hatching (the mage kept standing)
		player.hp = player.stats.hp
		await physics_frame
	check("skeleton" in summons and "hell_imp" in summons, "summons asked from main")
	check(root.find_children("*", "Node2D", true, false).any(func(n): return n is Enemy.Beam), "the laser fires")
	var zones := root.find_children("*", "Node2D", true, false).filter(func(n): return n is Enemy.Zone)
	check(zones.size() >= 4, "spells leave zones")
	await physics_frame
	hp_before = 0.0
	for e in get_nodes_in_group("enemies"):
		hp_before += e.hp
	for id in spells:
		player.mana = 1000.0
		player.cooldowns = {}
		check(player.cast(id), "%s casts" % id)
		for i in 20:
			await physics_frame
	var id0: String = spells.keys()[0]
	var cost: int = run.mana_cost(id0)
	player.mana = cost * 0.5  # short of mana: all of it for half the damage
	player.cooldowns = {}
	check(player.cast(id0) and player.mana == 0.0, "a spell short of mana casts on what is left")
	var weak := player._spell(id0, 0.5)
	check(weak.weak == 0.5 and is_same(weak, player._spell(id0, 0.5)) and absf(_damage(weak) - _damage(spells[id0]) * 0.5) < 0.01,
		"weakened, it deals the share of damage, kept between casts")
	player.cooldowns = {}
	check(player.cast(id0) and player._weak[id0][1] == 1.0 / Player.RATIO_STEPS, "without mana it still casts, at the weakest")
	var rich := Spell.weakened(Spell.sanitize({"emit": {"body": {"on_hit": [{"type": "damage", "amount": 10},
		{"type": "status", "status": "slow", "power": 0.5, "duration": 1}]}}}), 0.5)
	check(rich.emit.body.on_hit.size() == 1 and rich.emit.body.on_hit[0].amount == 5.0, "the failsafe's hits only damage")
	player.stats.mana = Stats.BASE.mana
	for i in 120:
		await physics_frame
	var hp_after := 0.0
	for e in get_nodes_in_group("enemies"):
		hp_after += e.hp
	check(hp_after < hp_before, "base spells damage enemies")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	var zombie := Enemy.new()  # walks up, poisons the mage, leaves gunk when it dies
	zombie.setup("rotting_zombie", RunState.enemy_stats("rotting_zombie", 1))
	zombie.position = player.position + Vector2(20, 0)
	world.add_child(zombie)
	player.hp = player.stats.hp
	player.shield = 0.0
	for i in 30:
		await physics_frame
	check(player.statuses.has("poison"), "rotting zombie poisons the mage")
	var hp := player.hp
	player.statuses.poison[1] = 5.0
	player._physics_process(1.0)
	check(player.hp < hp, "poison hurts over time")
	player.hp = 2.0
	player._physics_process(1.0)
	player.hurt(1e9, false, true)
	check(is_equal_approx(player.hp, 1.0), "poison never kills: it leaves the mage at 1 hp")
	player.afflict("stun", 1.0, 1.0)
	var at := player.position
	player._steer(0.5)
	check(player.position == at, "a stunned mage does not move")
	player.statuses = {}
	player.hp = player.stats.hp
	player.hurt(1.0, true)
	await process_frame
	check(player.statuses.has("burn") and player._dye[1].get_shader_parameter("status") == Player.STATUS_FILTERS.burn,
		"fire damage burns the mage: its tentacles take the burn filter")
	player.statuses = {}
	zombie.take_damage(1e9)
	check(root.find_children("*", "Node2D", true, false).any(func(n): return n is Enemy.Zone and n.fx == "poison" and n.dps > 0.0),
		"rotting zombie leaves gunk")
	check(player.hp < player.stats.hp, "enemies hurt the player")
	_test_gamepad(player)
	world.free()
	run.free()
	p.free()


## Gamepad: right stick aims and fires, RT fires where the mage walks; the
## device in use switches on input events.
func _test_gamepad(player: Node2D) -> void:
	var b := InputEventJoypadButton.new()
	b.pressed = true
	check(Settings.track_device(b) and Settings.pad, "a gamepad button switches to gamepad")
	Input.action_press("aim_up")
	player._steer(0.0)
	check(player.aim.is_equal_approx(Vector2.UP) and player.firing.primary, "right stick aims and fires")
	Input.action_release("aim_up")
	Input.action_press("move_left")
	player._steer(0.0)
	check(player.aim.is_equal_approx(Vector2.LEFT) and not player.firing.primary, "idle stick: aims where it walks")
	Input.action_press("fire")
	player._steer(0.0)
	check(player.firing.primary, "RT fires")
	Input.action_release("fire")
	Input.action_release("move_left")
	check(Settings.track_device(InputEventKey.new()) and not Settings.pad, "a key switches back to keyboard")
