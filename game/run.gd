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
	"ring_of_fire": {"name": "Ring of fire", "desc": "Fireballs burst out all around you (right click)",
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
var picked := []  # upgrade ids taken, in order
var offers := []  # current level-up choice, [] when none
var pending := 0  # level-ups not chosen yet
var rng := RandomNumberGenerator.new()
var stats := {}  # the mage's permanent bonuses for this run
var passive := ""  # a Run.SHOP id, "" until one is bought


## `equipped`: slot -> spell; `bonus`: Profile.total_stats() (damage, gold, xp).
func start(equipped: Dictionary, bonus := {}) -> void:
	stats = bonus
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
	offers = Upgrades.offers(spells, mana_mult, rng)
	if offers.is_empty():  # nothing left to improve
		pending = 0
	else:
		leveled_up.emit(offers)


## Take offer `i`. Returns true while more level-ups wait for a choice.
func choose(i: int) -> bool:
	if i < 0 or i >= offers.size():
		return not offers.is_empty()
	var o: Dictionary = offers[i]
	if o.id == "mana":
		mana_mult[o.slot] *= 0.85
	else:
		spells[o.slot] = Upgrades.apply(spells[o.slot], o.id)
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
	if kind == "boss":
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

## The enemy kinds of wave `w`: a boss every BOSS_EVERY waves, else a growing
## mix where fast enemies join at wave 2 and ranged ones at wave 3.
static func wave_plan(w: int) -> Array:
	var out := []
	if w % BOSS_EVERY == 0:
		out.append("boss")
		for i in w / BOSS_EVERY * 2:
			out.append("melee")
		return out
	for i in 4 + w * 2:
		if w >= 3 and i % 4 == 3:
			out.append("ranged")
		elif w >= 2 and i % 3 == 1:
			out.append("fast")
		else:
			out.append("melee")
	return out


## Stats of an enemy of `kind` at wave `w`: tougher every wave.
static func enemy_stats(kind: String, w: int) -> Dictionary:
	var s: Dictionary = {
		"melee": {"hp": 20.0, "speed": 80.0, "radius": 12.0, "damage": 10.0, "xp": 1, "gold": 1},
		"fast": {"hp": 10.0, "speed": 150.0, "radius": 9.0, "damage": 6.0, "xp": 1, "gold": 1},
		"ranged": {"hp": 16.0, "speed": 70.0, "radius": 11.0, "damage": 8.0, "xp": 2, "gold": 2},
		"boss": {"hp": 400.0, "speed": 50.0, "radius": 36.0, "damage": 25.0, "xp": 20, "gold": 40},
	}[kind].duplicate()
	s.hp *= 1.0 + (w - 1) * 0.2
	s.speed *= 1.0 + minf(w - 1, 20) * 0.02
	s.damage *= 1.0 + (w - 1) * 0.05
	s.gold = s.gold + w / BOSS_EVERY
	return s
