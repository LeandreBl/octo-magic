extends Node
## Autoload `Run`: the state of the current run, for the game scene and the UI.
## Pure logic (no nodes): XP and level-ups, grimoires and their upgrade offers,
## run spells, waves.
## Scripts loaded by the tests never name the autoload: they get it passed.

signal changed
signal offered(offers: Array)  # a grimoire opened: let the player pick one
signal level_gained  # one or more levels: health and mana back to full

const BOSS_EVERY := 5
var active := false
var wave := 0
var level := 1
var xp := 0
var kills := 0
var bosses := 0
var gold := 0
var scrolls := 0
var spells := {}  # slot -> spell, the profile's spells (damage stat applied)
var levels := {}  # skill id -> level taken, in the order first taken
var list := Upgrades.LIST  # the skills offered (tests swap in their own)
var offers := []  # current grimoire choice, [] when none
var pending := []  # grimoires picked up, not chosen yet: Upgrades.KINDS ("hero" red, "spell" blue)
var rng := RandomNumberGenerator.new()
var bonuses := []  # the profile's Stats bonuses
var stats := Stats.total([])  # Stats.total(bonuses and the skills')
var passives := []  # the slotted Profile.AUGMENTS passive ids


## `equipped`: slot -> spell; `bonus_list`: Profile.bonus_list(); `augments`:
## Profile.slotted_augments(), an active one is the secondary spell. The
## damage stat is applied to the spells, once, here.
func start(equipped: Dictionary, bonus_list := [], augments := []) -> void:
	bonuses = bonus_list.duplicate()
	stats = Stats.total(bonuses)
	active = true
	wave = 0
	level = 1
	xp = 0
	kills = 0
	bosses = 0
	gold = 0
	scrolls = 0
	levels = {}
	offers = []
	pending = []
	spells = {}
	passives = []
	for slot in equipped:
		spells[slot] = Spell.scale_damage(equipped[slot], stats.damage)
	for a in augments:
		if a.kind == "active":
			spells.secondary = Spell.scale_damage(Spell.sanitize(a.spell), stats.damage)
		else:
			passives.append(a.id)
			for i in a.get("grimoires", 0):
				pending.append_array(Upgrades.KINDS)
	rng.randomize()
	if not pending.is_empty():
		_offer.call_deferred()  # once the run's screen is up
	changed.emit()


## The run between two waves, as JSON-safe data (Profile.run, saved in the cloud
## with the character): restore() takes it back, the next wave starts afresh.
func to_dict() -> Dictionary:
	return {"wave": wave, "level": level, "xp": xp, "kills": kills, "bosses": bosses, "gold": gold,
		"scrolls": scrolls, "spells": spells, "levels": levels,
		"pending": pending, "bonuses": bonuses, "passives": passives}


## Back to a to_dict() snapshot (a JSON copy: numbers come back as floats).
## False when it does not hold a run.
func restore(d: Dictionary) -> bool:
	var s: Variant = d.get("spells")
	if not s is Dictionary or not s.get("primary") is Dictionary:
		return false
	start({})
	for k in ["wave", "level", "xp", "kills", "bosses", "gold", "scrolls"]:
		set(k, maxi(0, int(d.get(k, get(k)))))
	level = maxi(level, 1)
	for slot in s:
		if slot in Spell.RUN_SLOTS and s[slot] is Dictionary:
			spells[slot] = Spell.sanitize(s[slot])
	var lv := _dict(d.get("levels"))
	for id in lv:
		if list.has(id) and (lv[id] is float or lv[id] is int):
			levels[id] = clampi(int(lv[id]), 1, list[id].max)
	pending = _arr(d.get("pending")).map(str).filter(func(k): return k in Upgrades.KINDS)
	passives = _arr(d.get("passives")).map(str)
	bonuses = _arr(d.get("bonuses")).filter(func(b): return b is Dictionary and b.values().all(func(v): return v is float or v is int))
	_restat()
	if not pending.is_empty():
		_offer.call_deferred()
	changed.emit()
	return true


## The stats from the profile's bonuses and the skills taken.
func _restat() -> void:
	stats = Stats.total(bonuses + levels.keys().map(func(id): return Upgrades.bonus(list[id], levels[id])))


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


static func xp_to_next(lvl: int) -> int:
	return 5 + (lvl - 1) * 4


func add_xp(amount: int) -> void:
	xp += amount
	var before := level
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	if level > before:
		level_gained.emit()
	changed.emit()


## Opens the next grimoire: its kind's offers; one with every skill maxed is lost.
func _offer() -> void:
	var n := int(stats.choices)  # Creativity and Inspiration do not stack (Stats.BOUNDS)
	# A dead pick at the cap: Inspiration counted as taken.
	var lv := levels if n < Stats.BOUNDS.choices[1] else levels.merged({"inspiration": 1})
	while offers.is_empty() and not pending.is_empty():
		offers = Upgrades.offers(lv, rng, pending[0], n, list)
		if offers.is_empty():
			pending.pop_front()
	if not offers.is_empty():
		offered.emit(offers)


## Take offer `i`. Returns true while more grimoires wait for a choice.
func choose(i: int) -> bool:
	if i < 0 or i >= offers.size():
		return not offers.is_empty()
	levels[offers[i].id] = offers[i].level
	_restat()
	pending.pop_front()
	offers = []
	_offer()
	changed.emit()
	return not offers.is_empty()


func mana_cost(slot: String) -> int:
	return Stats.cost(Spell.mana_cost(spells[slot]), stats.mana_cost)


func collect(kind: String, value: int) -> void:
	match kind:
		"xp": add_xp(roundi(value * stats.xp))
		"gold": gold += roundi(value * stats.gold)
		"scroll": scrolls += value
		"grimoire_hero", "grimoire_spell":
			pending.append(kind.trim_prefix("grimoire_"))
			if offers.is_empty():
				_offer()
	changed.emit()


func killed(kind: String) -> void:
	kills += 1 + ENEMIES.get(kind, {}).get("kills", 0)  # a boss monster counts for many
	if is_boss(kind):
		bosses += 1
	changed.emit()


func score() -> int:
	return kills * 10 + maxi(wave - 1, 0) * 100 + bosses * 500


## Ends the run (permadeath). The result goes to Profile.record_run.
func finish() -> Dictionary:
	active = false
	offers = []
	pending = []
	changed.emit()
	return {"score": score(), "wave": wave, "level": level, "kills": kills,
		"bosses": bosses, "gold": gold, "scrolls": scrolls}


# --- waves: what spawns, and how strong --------------------------------------

## Monster kinds: the undead and creatures of the graveyard. Stats at wave 1;
## "from": first wave it shows up in, with "weight" (0: only summoned, or a
## boss). Look: "color" (its zones), sprites in assets/monsters/<kind>/.
## "ai" moves it (game/enemy.gd): chase, weave (zigzags in), still (archers, mages: hold still once on screen,
## see Enemy.VIEW, walk in when the mage is off it).
## "heavy": share of knockback taken.
## "spells": its own casts, each every "every" seconds (see Enemy.cast);
## "dmg" scales its "damage". "shot": the effect its shots fly as
## (assets/monsters/fx/). "effect": [status, power, seconds] put on the mage
## by its touch and its shots (Player.afflict; poison: power x damage per s).
## "fire": its touch and shots deal fire damage (Stats "fire"; the fire pools always do).
## "gunk": [radius, seconds] of poison pool left where it dies.
## "variant": [name, chance, {stat: factor}]: some wear it (helmet, shield...),
## drawn from assets/monsters/<kind>_<name>/.
## "kills": added to the run's kills when it falls (the boss monsters).
## "loot": richer drops (life and mana orbs, Quad Damage), see main.gd.
const ENEMIES := {
	"skeleton": {"hp": 18.0, "speed": 80.0, "radius": 19.0, "damage": 8.0, "xp": 1, "gold": 1,
		"from": 1, "weight": 6.0, "ai": "chase", "color": "#e0dccb"},
	"imp": {"hp": 9.0, "speed": 150.0, "radius": 14.0, "damage": 6.0, "xp": 1, "gold": 1,
		"from": 2, "weight": 3.0, "ai": "weave", "color": "#e53935"},
	"archer": {"hp": 12.0, "speed": 60.0, "radius": 18.0, "damage": 7.0, "xp": 2, "gold": 2,
		"from": 2, "weight": 1.5, "ai": "still", "color": "#8d6e63", "shot": "arrow",
		"spells": [{"type": "bolt", "every": 2.4}]},
	"zombie": {"hp": 55.0, "speed": 45.0, "radius": 22.0, "damage": 18.0, "xp": 2, "gold": 2,
		"from": 3, "weight": 1.5, "ai": "chase", "heavy": 0.6, "color": "#9e9e9e"},
	"skeletal_warrior": {"hp": 16.0, "speed": 95.0, "radius": 19.0, "damage": 13.0, "xp": 2, "gold": 1,
		"from": 3, "weight": 2.0, "ai": "chase", "color": "#d7ccc8",
		"variant": ["helmet", 0.5, {"hp": 1.4}]},
	"marksman": {"hp": 26.0, "speed": 60.0, "radius": 18.0, "damage": 9.0, "xp": 2, "gold": 2,
		"from": 4, "weight": 1.2, "ai": "still", "color": "#6d4c41", "shot": "arrow",
		"spells": [{"type": "bolt", "every": 2.0}]},
	"skeletal_knight": {"hp": 45.0, "speed": 95.0, "radius": 21.0, "damage": 13.0, "xp": 3, "gold": 2,
		"from": 5, "weight": 1.0, "ai": "chase", "heavy": 0.7, "color": "#90a4ae",
		"variant": ["gauntlets", 0.5, {"damage": 1.2}]},
	"wraith": {"hp": 14.0, "speed": 140.0, "radius": 18.0, "damage": 7.0, "xp": 2, "gold": 1,
		"from": 5, "weight": 1.2, "ai": "chase", "color": "#f5f5f5", "effect": ["freeze", 1.0, 1.5]},
	"poison_mage": {"hp": 14.0, "speed": 60.0, "radius": 18.0, "damage": 5.0, "xp": 3, "gold": 3,
		"from": 5, "weight": 0.8, "ai": "still", "color": "#7cb342", "shot": "poison_orb",
		"effect": ["poison", 0.6, 3.0], "variant": ["shield", 0.35, {"hp": 2.0}],
		"spells": [{"type": "bolt", "every": 2.4, "dmg": 1.0}]},
	"rotting_zombie": {"hp": 55.0, "speed": 45.0, "radius": 22.0, "damage": 16.0, "xp": 3, "gold": 2,
		"from": 6, "weight": 1.0, "ai": "chase", "heavy": 0.6, "color": "#827717",
		"effect": ["poison", 0.3, 3.0], "gunk": [50.0, 5.0]},
	"burning_skeleton": {"hp": 16.0, "speed": 115.0, "radius": 19.0, "damage": 13.0, "xp": 2, "gold": 2,
		"from": 6, "weight": 1.2, "ai": "chase", "color": "#ff7043", "fire": true},
	"frost_mage": {"hp": 14.0, "speed": 60.0, "radius": 18.0, "damage": 5.0, "xp": 3, "gold": 3,
		"from": 6, "weight": 0.8, "ai": "still", "color": "#4fc3f7", "shot": "frost_orb",
		"effect": ["freeze", 1.0, 2.0], "variant": ["shield", 0.35, {"hp": 2.0}],
		"spells": [{"type": "bolt", "every": 2.4, "dmg": 1.0}]},
	"putrid_archer": {"hp": 26.0, "speed": 60.0, "radius": 18.0, "damage": 8.0, "xp": 3, "gold": 2,
		"from": 7, "weight": 1.0, "ai": "still", "color": "#689f38", "shot": "poison_arrow",
		"effect": ["poison", 0.4, 3.0], "spells": [{"type": "bolt", "every": 2.0}]},
	"fire_mage": {"hp": 14.0, "speed": 60.0, "radius": 18.0, "damage": 20.0, "xp": 3, "gold": 3,
		"from": 7, "weight": 0.8, "ai": "still", "color": "#ff5722", "shot": "fireball", "fire": true,
		"variant": ["shield", 0.35, {"hp": 2.0}], "spells": [{"type": "bolt", "every": 2.6, "dmg": 1.0}]},
	"burning_archer": {"hp": 12.0, "speed": 60.0, "radius": 18.0, "damage": 16.0, "xp": 3, "gold": 2,
		"from": 8, "weight": 0.8, "ai": "still", "color": "#ff9800", "shot": "fire_arrow", "fire": true,
		"spells": [{"type": "bolt", "every": 2.4, "dmg": 1.0}]},
	"lightning_mage": {"hp": 14.0, "speed": 60.0, "radius": 18.0, "damage": 11.0, "xp": 3, "gold": 3,
		"from": 8, "weight": 0.8, "ai": "still", "color": "#e3f2fd", "shot": "spark",
		"effect": ["stun", 1.0, 0.6], "variant": ["shield", 0.35, {"hp": 2.0}],
		"spells": [{"type": "bolt", "every": 2.8, "dmg": 1.0}]},
	# bosses, one every BOSS_EVERY waves (BOSSES)
	"boss": {"name": "Lich King", "hp": 400.0, "speed": 50.0, "radius": 58.0, "damage": 25.0, "xp": 20, "gold": 40,
		"boss": true, "ai": "chase", "heavy": 0.3, "color": "#7e57c2",
		"spells": [{"type": "ring", "every": 3.0, "count": 12}, {"type": "summon", "every": 8.0, "kind": "skeleton", "count": 3}]},
	# the boss monsters: each one adds an attack to the last one's
	"bone_herald": {"name": "Bone Herald", "hp": 450.0, "speed": 55.0, "radius": 56.0, "damage": 24.0, "xp": 25, "gold": 40,
		"boss": true, "kills": 100, "ai": "chase", "heavy": 0.3, "color": "#e0dccb", "shot": "bone_missile",
		"spells": [BURST]},
	"pyre_lord": {"name": "Pyre Lord", "hp": 500.0, "speed": 55.0, "radius": 56.0, "damage": 26.0, "xp": 30, "gold": 50,
		"boss": true, "kills": 200, "ai": "chase", "heavy": 0.3, "color": "#ff7043", "shot": "bone_missile",
		"spells": [BURST, FIREBALL]},
	"blight_eye": {"name": "Blight Eye", "hp": 550.0, "speed": 50.0, "radius": 56.0, "damage": 26.0, "xp": 35, "gold": 60,
		"boss": true, "kills": 300, "ai": "chase", "heavy": 0.3, "color": "#76ff03", "shot": "bone_missile",
		"spells": [BURST, FIREBALL, LASER]},
	"grave_maw": {"name": "Grave Maw", "hp": 600.0, "speed": 60.0, "radius": 56.0, "damage": 28.0, "xp": 40, "gold": 70,
		"boss": true, "kills": 400, "ai": "chase", "heavy": 0.3, "color": "#78909c", "shot": "bone_missile",
		"spells": [BURST, FIREBALL, LASER, BITE]},
	"archfiend": {"name": "Archfiend", "hp": 650.0, "speed": 60.0, "radius": 60.0, "damage": 28.0, "xp": 50, "gold": 80,
		"boss": true, "kills": 500, "ai": "chase", "heavy": 0.3, "color": "#d50000", "shot": "bone_missile",
		"spells": [BURST, HELLFIRE, LASER, BITE]},
	# hatched by the Archfiend's fireballs only
	"hell_imp": {"hp": 9.0, "speed": 170.0, "radius": 14.0, "damage": 6.0, "xp": 1, "gold": 2,
		"from": 1, "weight": 0.0, "ai": "weave", "color": "#ff6d00", "loot": true},
}
## The boss monsters' attacks, stacked: 3 bursts of 2 missiles; a fireball
## leaving a fire pool that burns hard whoever stands in it; a green laser
## burning along its line; a vanish, then a bite where the mage stood.
const BURST := {"type": "burst", "every": 3.0, "bursts": 3, "count": 2, "dmg": 0.6}
const FIREBALL := {"type": "puddle", "every": 4.5, "radius": 60.0, "dmg": 1.5, "fx": "fire_pool", "linger": 4.0}
const HELLFIRE := {"type": "puddle", "every": 4.5, "radius": 60.0, "dmg": 1.5, "fx": "fire_pool", "linger": 4.0, "imps": 2}  # hatches imps
const LASER := {"type": "laser", "every": 6.0, "length": 520.0, "time": 1.6, "dmg": 1.2}
const BITE := {"type": "teleport", "every": 7.0, "dmg": 2.5}
## Wave -> its boss; past the last one, the last one comes back every BOSS_EVERY
## waves, its fireballs hatching more imps each time (enemy_stats).
const BOSSES := {5: "boss", 10: "bone_herald", 15: "pyre_lord", 20: "blight_eye", 25: "grave_maw", 30: "archfiend"}
const IMPS_PER_FIGHT := 2  # more imps per fireball each time the last boss comes back
const BOSS_HASTE := 0.6  # a boss's spells come this much sooner than their "every"


static func is_boss(kind: String) -> bool:
	return ENEMIES.get(kind, {}).get("boss", false)


## The enemy kinds of wave `w`: a boss every BOSS_EVERY waves (BOSSES) with
## a small escort, else a growing mix of the kinds unlocked so far. Seeded by
## `w`: the same plan on every peer.
static func wave_plan(w: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = w
	var pool := ENEMIES.keys().filter(func(k): return ENEMIES[k].get("weight", 0.0) > 0.0 and ENEMIES[k].from <= w)
	var weights := PackedFloat32Array(pool.map(func(k): return ENEMIES[k].weight))
	var out := []
	var n := 4 + w * 2
	if w % BOSS_EVERY == 0:
		out.append(BOSSES[mini(w, BOSSES.keys().max())])
		n = w / BOSS_EVERY * 2
	for i in n:
		out.append(pool[rng.rand_weighted(weights)])
	return out


## Stats of an enemy of `kind` at wave `w`: tougher every wave.
static func enemy_stats(kind: String, w: int) -> Dictionary:
	var s: Dictionary = ENEMIES[kind].duplicate(true)
	s.hp *= 1.0 + (w - 1) * 0.2
	s.speed *= 1.0 + minf(w - 1, 20) * 0.02
	s.damage *= 1.0 + (w - 1) * 0.05
	s.gold = s.gold + w / BOSS_EVERY
	for sp in s.get("spells", []):
		if s.get("boss", false):
			sp.every *= BOSS_HASTE
		if sp.has("imps"):
			sp.imps += maxi(w - BOSSES.keys().max(), 0) / BOSS_EVERY * IMPS_PER_FIGHT
	var v: Array = s.get("variant", [])
	s.look = kind
	if v and randf() < v[1]:  # rolled on the host, sent to peers with the stats
		s.look = kind + "_" + v[0]
		for stat in v[2]:
			s[stat] *= v[2][stat]
	return s
