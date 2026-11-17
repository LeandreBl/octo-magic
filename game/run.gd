extends Node
## Autoload `Run`: the state of the current run, for the game scene and the UI.
## Pure logic (no nodes): XP and level-ups, upgrade offers, run spells, waves.
## Scripts loaded by the tests never name the autoload: they get it passed.

signal changed
signal leveled_up(offers: Array)  # pause and let the player pick one

const BOSS_EVERY := 5
const RING_OF_FIRE := {"name": "Ring of fire", "element": "fire", "color": "#ff7a1f", "cooldown": 3.0,
	"emit": {"pattern": "radial", "count": 12, "body": {"shape": "bolt", "speed": 320, "size": 8, "lifetime": 0.9,
		"on_hit": [{"type": "damage", "amount": 14}, {"type": "status", "status": "burn", "power": 3, "duration": 2}]}}}
## Bought with the run's gold, one active (slot "secondary") and one passive
## per run, empty at the start. A passive is applied by game/player.gd.
const SHOP := {
	"ring_of_fire": {"name": "Ring of fire", "desc": "Fireballs burst out all around you",
		"price": 40, "slot": "secondary", "spell": RING_OF_FIRE},
	"shield": {"name": "Shield", "desc": "Absorbs 40 damage, back 8 s after it breaks",
		"price": 30, "slot": "passive"},
}

var active := false
var wave := 0
var level := 1
var xp := 0
var kills := 0
var bosses := 0
var gold := 0
var scrolls := 0
var spells := {}  # slot -> spell, upgraded copies of the profile's spells
var mana_mult := {}  # slot -> mana cost multiplier ("mana" upgrades)
var picked := []  # augment ids taken, in order
var offers := []  # current level-up choice, [] when none
var pending := 0  # level-ups not chosen yet
var rng := RandomNumberGenerator.new()
var stats := {}  # the mage's bonuses: the profile's, + hero augments
var passive := ""  # a Run.SHOP id, "" until one is bought


## `equipped`: slot -> spell; `bonus`: Profile.total_stats() (damage, gold, xp).
func start(equipped: Dictionary, bonus := {}) -> void:
	stats = bonus.duplicate()
	active = true
	wave = 0
	level = 1
	xp = 0
	kills = 0
	bosses = 0
	gold = 0
	scrolls = 0
	picked = []
	offers = []
	pending = 0
	spells = {}
	mana_mult = {}
	passive = ""
	for slot in equipped:
		spells[slot] = Upgrades.scale_damage(equipped[slot], 1.0 + stats.get("damage", 0.0))
		mana_mult[slot] = 1.0
	rng.randomize()
	changed.emit()


static func xp_to_next(lvl: int) -> int:
	return 5 + (lvl - 1) * 4


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		pending += 1
	if offers.is_empty() and pending > 0:
		_offer()
	changed.emit()


func _offer() -> void:
	offers = Upgrades.offers(spells.primary, mana_mult.primary, stats, rng)
	if offers.is_empty():  # nothing left to improve
		pending = 0
	else:
		leveled_up.emit(offers)


## Take offer `i`. Returns true while more level-ups wait for a choice.
func choose(i: int) -> bool:
	if i < 0 or i >= offers.size():
		return not offers.is_empty()
	var o: Dictionary = offers[i]
	var tier: int = Upgrades.RARITIES[o.rarity].tier
	var u: Dictionary = Upgrades.LIST[o.id]
	if u.has("stat"):
		stats[u.stat] = minf(u.max, stats.get(u.stat, 0.0) + Upgrades.amount(o.id, tier))
	elif o.id == "mana":
		mana_mult.primary = maxf(Upgrades.MANA_FLOOR, mana_mult.primary * (1.0 - Upgrades.amount(o.id, tier)))
	else:
		spells.primary = Upgrades.apply(spells.primary, o.id, tier)
	picked.append(o.id)
	pending -= 1
	offers = []
	if pending > 0:
		_offer()
	changed.emit()
	return not offers.is_empty()


## Is SHOP item `id` for sale: its slot empty and enough gold?
func can_buy(id: String) -> bool:
	var it: Dictionary = SHOP[id]
	return active and gold >= it.price and (passive == "" if it.slot == "passive" else not spells.has(it.slot))


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	gold -= SHOP[id].price
	var it: Dictionary = SHOP[id]
	if it.slot == "passive":
		passive = id
	else:
		spells[it.slot] = Upgrades.scale_damage(Spell.sanitize(it.spell), 1.0 + stats.get("damage", 0.0))
		mana_mult[it.slot] = 1.0
	changed.emit()
	return true


func mana_cost(slot: String) -> int:
	return maxi(1, roundi(Spell.mana_cost(spells[slot]) * mana_mult[slot]))


func collect(kind: String, value: int) -> void:
	match kind:
		"xp": add_xp(roundi(value * (1.0 + stats.get("xp", 0.0))))
		"gold": gold += roundi(value * (1.0 + stats.get("gold", 0.0)))
		"scroll": scrolls += value
	changed.emit()


func killed(kind: String) -> void:
	kills += 1
	if is_boss(kind):
		bosses += 1
	changed.emit()


func score() -> int:
	return kills * 10 + maxi(wave - 1, 0) * 100 + bosses * 500


## Ends the run (permadeath). The result goes to Profile.record_run.
func finish() -> Dictionary:
	active = false
	offers = []
	pending = 0
	changed.emit()
	return {"score": score(), "wave": wave, "level": level, "kills": kills,
		"bosses": bosses, "gold": gold, "scrolls": scrolls}


# --- waves: what spawns, and how strong --------------------------------------

## Monster kinds. Stats at wave 1; "from": first wave it shows up in, with
## "weight" (0: only summoned, or a boss). Look: "color" (its zones), sprites in assets/monsters/<kind>/
## "ai" moves it (game/enemy.gd): chase, weave (zigzags in), flank (comes from
## the side), kite (holds "range", strafes). "heavy": share of knockback taken.
## "spells": its own casts, each every "every" seconds (see Enemy.cast);
## "dmg" scales its "damage". "split": summoned on death.
const ENEMIES := {
	"melee": {"hp": 20.0, "speed": 80.0, "radius": 12.0, "damage": 10.0, "xp": 1, "gold": 1,
		"from": 1, "weight": 6.0, "ai": "chase", "color": "#4caf50"},
	"fast": {"hp": 10.0, "speed": 150.0, "radius": 9.0, "damage": 6.0, "xp": 1, "gold": 1,
		"from": 2, "weight": 3.0, "ai": "weave", "color": "#ffca28"},
	"ranged": {"hp": 16.0, "speed": 70.0, "radius": 11.0, "damage": 8.0, "xp": 2, "gold": 2,
		"from": 3, "weight": 2.0, "ai": "kite", "color": "#26c6da",
		"spells": [{"type": "bolt", "every": 2.0}]},
	"bomber": {"hp": 12.0, "speed": 125.0, "radius": 10.0, "damage": 6.0, "xp": 1, "gold": 1,
		"from": 3, "weight": 1.5, "ai": "chase", "color": "#ff7043",
		"spells": [{"type": "fuse", "every": 0.1, "range": 50.0, "radius": 75.0, "dmg": 2.5}]},
	"slime": {"hp": 30.0, "speed": 60.0, "radius": 14.0, "damage": 8.0, "xp": 1, "gold": 1,
		"from": 4, "weight": 1.5, "ai": "chase", "color": "#7cb342", "split": ["slimelet", 2]},
	"slimelet": {"hp": 8.0, "speed": 100.0, "radius": 8.0, "damage": 5.0, "xp": 1, "gold": 0,
		"from": 4, "weight": 0.0, "ai": "weave", "color": "#aed581"},
	"brute": {"hp": 60.0, "speed": 55.0, "radius": 16.0, "damage": 18.0, "xp": 3, "gold": 2,
		"from": 4, "weight": 1.0, "ai": "chase", "heavy": 0.5, "color": "#8d6e63",
		"spells": [{"type": "charge", "every": 4.0, "range": 280.0}]},
	"stalker": {"hp": 18.0, "speed": 115.0, "radius": 10.0, "damage": 9.0, "xp": 2, "gold": 1,
		"from": 5, "weight": 1.5, "ai": "flank", "color": "#ab47bc"},
	"spitter": {"hp": 22.0, "speed": 65.0, "radius": 12.0, "damage": 8.0, "xp": 2, "gold": 2,
		"from": 6, "weight": 1.0, "ai": "kite", "range": 300.0, "color": "#9e9d24",
		"spells": [{"type": "puddle", "every": 5.0, "radius": 55.0, "dmg": 1.2}]},
	"shaman": {"hp": 24.0, "speed": 70.0, "radius": 12.0, "damage": 6.0, "xp": 3, "gold": 3,
		"from": 6, "weight": 0.7, "ai": "kite", "range": 340.0, "color": "#26a69a",
		"spells": [{"type": "heal", "every": 4.0, "radius": 180.0, "ratio": 0.3}]},
	"wraith": {"hp": 20.0, "speed": 90.0, "radius": 11.0, "damage": 12.0, "xp": 2, "gold": 2,
		"from": 7, "weight": 1.0, "ai": "chase", "color": "#b0bec5",
		"spells": [{"type": "blink", "every": 3.5}]},
	"necromancer": {"hp": 35.0, "speed": 60.0, "radius": 13.0, "damage": 8.0, "xp": 4, "gold": 4,
		"from": 8, "weight": 0.5, "ai": "kite", "range": 360.0, "color": "#5e35b1",
		"spells": [{"type": "summon", "every": 6.0, "kind": "fast", "count": 2}, {"type": "bolt", "every": 3.0}]},
	"sorcerer": {"hp": 26.0, "speed": 70.0, "radius": 12.0, "damage": 9.0, "xp": 3, "gold": 3,
		"from": 9, "weight": 0.8, "ai": "kite", "range": 300.0, "color": "#ec407a",
		"spells": [{"type": "spread", "every": 2.8, "count": 5, "angle": 0.9}]},
	"golem": {"hp": 120.0, "speed": 45.0, "radius": 20.0, "damage": 22.0, "xp": 5, "gold": 4,
		"from": 10, "weight": 0.5, "ai": "chase", "heavy": 0.4, "color": "#78909c",
		"spells": [{"type": "nova", "every": 3.0, "radius": 110.0, "dmg": 1.5}]},
	# bosses, one every BOSS_EVERY waves in turn
	"boss": {"hp": 400.0, "speed": 50.0, "radius": 36.0, "damage": 25.0, "xp": 20, "gold": 40,
		"boss": true, "ai": "chase", "heavy": 0.3, "color": "#e65100",
		"spells": [{"type": "ring", "every": 3.0, "count": 12}, {"type": "summon", "every": 8.0, "kind": "melee", "count": 3}]},
	"warlord": {"hp": 500.0, "speed": 60.0, "radius": 34.0, "damage": 28.0, "xp": 20, "gold": 40,
		"boss": true, "ai": "chase", "heavy": 0.3, "color": "#c62828",
		"spells": [{"type": "charge", "every": 3.5, "range": 420.0}, {"type": "nova", "every": 5.0, "radius": 150.0, "dmg": 1.2}]},
	"broodmother": {"hp": 450.0, "speed": 45.0, "radius": 38.0, "damage": 22.0, "xp": 20, "gold": 40,
		"boss": true, "ai": "kite", "range": 280.0, "heavy": 0.3, "color": "#827717",
		"spells": [{"type": "spread", "every": 2.5, "count": 7, "angle": 1.2},
			{"type": "puddle", "every": 4.0, "radius": 70.0, "dmg": 0.6},
			{"type": "summon", "every": 7.0, "kind": "slimelet", "count": 3}]},
}
const BOSSES := ["boss", "warlord", "broodmother"]


static func is_boss(kind: String) -> bool:
	return ENEMIES.get(kind, {}).get("boss", false)


## The enemy kinds of wave `w`: a boss every BOSS_EVERY waves (in turn) with
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
		out.append(BOSSES[(w / BOSS_EVERY - 1) % BOSSES.size()])
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
	return s
