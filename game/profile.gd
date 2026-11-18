extends Node
## Autoload `Profile`: everything kept between runs, saved in user:// as JSON.
## Gold, shop (items, permanent bonuses and augments), the mage's look, achievements and
## unlocks, local scores, blank scrolls and the player's spells.
## The UI reads these fields and calls the methods; logic stays here.

signal changed
signal saved  # written to disk (game/online.gd pushes it to the server)

const PATH := "user://profile.json"
const MAX_SCORES := 10
## What is saved, locally and on the server.
const FIELDS := ["gold", "blank_scrolls", "owned", "equipped", "bonuses", "look", "stats",
	"achievements", "scores", "spells", "forged", "augments", "slotted", "test_scrolls"]

## Items and permanent bonuses carry Stats bonuses (see game/stats.gd).
## Names and descriptions are English, translated where shown (locale/fr.po).
const ITEMS := {
	"staff_oak": {"kind": "staff", "name": "Oak staff", "price": 0, "color": "#8d6e63", "bonus": {}},
	"staff_ember": {"kind": "staff", "name": "Ember staff", "price": 150, "color": "#ff7043", "bonus": {"damage%": 0.15}},
	"staff_willow": {"kind": "staff", "name": "Willow staff", "price": 200, "color": "#a5d6a7", "bonus": {"mana_cost%": -0.15, "mana_regen": 5.0}},
	"staff_crystal": {"kind": "staff", "name": "Crystal staff", "price": 450, "color": "#80deea", "bonus": {"damage%": 0.3, "cooldown%": -0.1}},
	"robe_novice": {"kind": "robe", "name": "Novice robe", "price": 0, "color": "#6a4cff", "bonus": {}},
	"robe_warden": {"kind": "robe", "name": "Warden robe", "price": 120, "color": "#2e7d32", "bonus": {"hp": 30.0, "armor": 0.05}},
	"robe_wind": {"kind": "robe", "name": "Wind robe", "price": 200, "color": "#b0bec5", "bonus": {"speed%": 0.12, "pickup%": 0.3}},
	"robe_archmage": {"kind": "robe", "name": "Archmage robe", "price": 500, "color": "#b71c1c", "bonus": {"hp": 60.0, "mana": 20.0, "hp_regen": 1.0}},
	"ring_none": {"kind": "ring", "name": "No ring", "price": 0, "color": "", "bonus": {}},
	"ring_copper": {"kind": "ring", "name": "Copper ring", "price": 100, "color": "#d08b4b", "bonus": {"mana_regen": 5.0}},
	"ring_gold": {"kind": "ring", "name": "Ring of fortune", "price": 250, "color": "#ffd54f", "bonus": {"gold%": 0.25}},
	"ring_ruby": {"kind": "ring", "name": "Ruby ring", "price": 300, "color": "#e53935", "bonus": {"crit": 0.1}},
	"ring_sapphire": {"kind": "ring", "name": "Sapphire ring", "price": 350, "color": "#448aff", "bonus": {"mana": 30.0, "mana_regen": 5.0}},
}

## Augments: bought once and kept, a run starts with the ones put in the
## SLOTS: "active" (the secondary spell, right click: one at most) or
## "passive" (applied by game/player.gd).
const SLOTS := 3
const RING_OF_FIRE := {"name": "Ring of fire", "element": "fire", "color": "#ff7a1f", "cooldown": 3.0,
	"emit": {"pattern": "radial", "count": 12, "body": {"shape": "bolt", "speed": 320, "size": 8, "lifetime": 0.9,
		"on_hit": [{"type": "damage", "amount": 14}, {"type": "status", "status": "burn", "power": 3, "duration": 2}]}}}
const AUGMENTS := {
	"ring_of_fire": {"name": "Ring of fire", "desc": "Fireballs burst out all around you",
		"price": 1500, "kind": "active", "spell": RING_OF_FIRE},
	"shield": {"name": "Shield", "desc": "Absorbs 40 damage, back 8 s after it breaks",
		"price": 1000, "kind": "passive"},
}

## Permanent bonuses: level n costs price * GROWTH^n.
const GROWTH := 1.5
const BONUSES := {
	"vitality": {"name": "Vitality", "desc": "+10 HP", "price": 50, "max": 10, "bonus": {"hp": 10.0}},
	"power": {"name": "Power", "desc": "+5% damage", "price": 80, "max": 10, "bonus": {"damage%": 0.05}},
	"focus": {"name": "Focus", "desc": "+3 mana/s", "price": 60, "max": 5, "bonus": {"mana_regen": 3.0}},
	"swiftness": {"name": "Swiftness", "desc": "+5% speed", "price": 70, "max": 5, "bonus": {"speed%": 0.05}},
	"frugality": {"name": "Frugality", "desc": "-4% mana cost", "price": 90, "max": 5, "bonus": {"mana_cost%": -0.04}},
	"endurance": {"name": "Endurance", "desc": "-3% damage taken", "price": 90, "max": 5, "bonus": {"armor": 0.03}},
	"keen_eye": {"name": "Keen eye", "desc": "+2% critical chance", "price": 80, "max": 5, "bonus": {"crit": 0.02}},
	"attraction": {"name": "Attraction", "desc": "+15% pickup radius", "price": 40, "max": 5, "bonus": {"pickup%": 0.15}},
	"greed": {"name": "Greed", "desc": "+10% gold", "price": 60, "max": 5, "bonus": {"gold%": 0.1}},
	"wisdom": {"name": "Wisdom", "desc": "+10% XP", "price": 60, "max": 5, "bonus": {"xp%": 0.1}},
}

## Achievements: reached when stats[stat] >= goal. Some unlock spells
## (the "unlock" field of game/spells.json).
const ACHIEVEMENTS := {
	"first_blood": {"name": "First blood", "desc": "Defeat an enemy", "stat": "kills", "goal": 1},
	"hunter": {"name": "Hunter", "desc": "Defeat 100 enemies", "stat": "kills", "goal": 100},
	"slayer": {"name": "Scourge", "desc": "Defeat 1000 enemies", "stat": "kills", "goal": 1000},
	"boss": {"name": "Giant slayer", "desc": "Defeat a boss", "stat": "bosses", "goal": 1},
	"boss3": {"name": "Giant hunter", "desc": "Defeat 3 bosses", "stat": "bosses", "goal": 3},
	"boss10": {"name": "Bane of giants", "desc": "Defeat 10 bosses", "stat": "bosses", "goal": 10},
	"wave10": {"name": "Enduring", "desc": "Reach wave 10", "stat": "best_wave", "goal": 10},
	"wave20": {"name": "Unstoppable", "desc": "Reach wave 20", "stat": "best_wave", "goal": 20},
	"level10": {"name": "Scholar", "desc": "Reach level 10 in one run", "stat": "best_level", "goal": 10},
	"level20": {"name": "Archmage", "desc": "Reach level 20 in one run", "stat": "best_level", "goal": 20},
	"rich": {"name": "Wealthy", "desc": "Earn 1000 gold in total", "stat": "gold_total", "goal": 1000},
	"scribe": {"name": "Scribe", "desc": "Find 5 blank scrolls", "stat": "scrolls", "goal": 5},
	"veteran": {"name": "Veteran", "desc": "Play 10 runs", "stat": "runs", "goal": 10},
}

const COLORS := ["#3a2a99", "#6a1b9a", "#1565c0", "#00838f", "#2e7d32", "#f9a825", "#c62828", "#37474f", "#eceff1"]

var path := PATH
var gold := 0
var blank_scrolls := 0
var owned := {"staff_oak": true, "robe_novice": true, "ring_none": true}
var equipped := {"staff": "staff_oak", "robe": "robe_novice", "ring": "ring_none"}
var bonuses := {}  # id -> level
var look := {"hat": COLORS[0]}
var stats := {"kills": 0, "bosses": 0, "best_wave": 0, "best_level": 0, "gold_total": 0, "scrolls": 0, "runs": 0}
var achievements := {}  # id -> unix time reached
var scores := []  # best first: {score, wave, level, kills, time}
var spells := {}  # slot -> spell id equipped
var forged := []  # spells from the forge: {id, slot, file, spell}
var augments := {}  # AUGMENTS id -> true, bought
var slotted := []  # AUGMENTS ids in the slots, SLOTS at most
## The owner's one-off gift of TEST_SCROLLS blank scrolls, to try spells at
## the forge: given once to every save made before it (apply), kept here so
## it is not given again. A fresh profile counts as served.
const TEST_SCROLLS := 50
var test_scrolls := true
var base_spells := []  # game/spells.json: {id, slot, unlock, spell}


func _init() -> void:
	for d in JSON.parse_string(FileAccess.get_file_as_string("res://game/spells.json")):
		base_spells.append({"id": d.id, "slot": d.slot, "unlock": d.unlock, "spell": Spell.sanitize(d)})
	for slot in Upgrades.SLOTS:
		spells[slot] = available_spells(slot)[0].id


func _ready() -> void:
	load_profile()


# --- save --------------------------------------------------------------------

func load_profile(p := PATH) -> void:
	path = p
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if d is Dictionary:
		apply(d)


## Replaces the whole profile with `d` (a save, or the server's copy), sanitized.
func apply(d: Dictionary) -> void:
	var fresh: Node = get_script().new()
	for k in FIELDS:
		set(k, fresh.get(k))
	fresh.free()
	gold = maxi(0, int(d.get("gold", 0)))
	blank_scrolls = maxi(0, int(d.get("blank_scrolls", 0)))
	if not d.get("test_scrolls", false):
		blank_scrolls += TEST_SCROLLS
	for id in _dict(d.get("owned")):
		if ITEMS.has(id):
			owned[id] = true
	for kind in _dict(d.get("equipped")):
		var id = d.equipped[kind]
		if owned.has(id) and ITEMS[id].kind == kind:
			equipped[kind] = id
	for id in _dict(d.get("bonuses")):
		if BONUSES.has(id):
			bonuses[id] = clampi(int(d.bonuses[id]), 0, BONUSES[id].max)
	for k in _dict(d.get("look")):
		if look.has(k) and Color.html_is_valid(str(d.look[k])):
			look[k] = str(d.look[k])
	for k in _dict(d.get("stats")):
		if stats.has(k):
			stats[k] = maxi(0, int(d.stats[k]))
	for id in _dict(d.get("achievements")):
		if ACHIEVEMENTS.has(id):
			achievements[id] = int(d.achievements[id])
	for s in _arr(d.get("scores")):
		if s is Dictionary:
			scores.append({"score": int(s.get("score", 0)), "wave": int(s.get("wave", 0)),
				"level": int(s.get("level", 0)), "kills": int(s.get("kills", 0)), "time": int(s.get("time", 0))})
	for f in _arr(d.get("forged")):
		if f is Dictionary and str(f.get("slot")) in Upgrades.SLOTS:
			var file := str(f.get("file", ""))
			var s := SpellArt.load_bundle(file) if file.begins_with("user://") else {}
			forged.append({"id": str(f.get("id")), "slot": f.slot, "file": file,
				"spell": s if not s.is_empty() else Spell.sanitize(f.get("spell"))})
	for id in _dict(d.get("augments")):
		if AUGMENTS.has(id):
			augments[id] = true
	for id in _arr(d.get("slotted")):
		if can_slot(str(id)):
			slotted.append(str(id))
	for slot in _dict(d.get("spells")):
		if slot in Upgrades.SLOTS and _entry(str(d.spells[slot]), slot):
			spells[slot] = str(d.spells[slot])
	changed.emit()


func to_dict() -> Dictionary:
	var d := {"version": 1}
	for k in FIELDS:
		d[k] = get(k)
	return d


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), " "))
	saved.emit()


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


# --- stats -------------------------------------------------------------------

## Stats bonuses of the equipped items and permanent bonuses (one per level).
func bonus_list() -> Array:
	var out := []
	for kind in equipped:
		out.append(ITEMS[equipped[kind]].bonus)
	for id in bonuses:
		for i in bonuses[id]:
			out.append(BONUSES[id].bonus)
	return out


# --- shop --------------------------------------------------------------------

func buy_item(id: String) -> bool:
	if not ITEMS.has(id) or owned.has(id) or gold < ITEMS[id].price:
		return false
	gold -= ITEMS[id].price
	owned[id] = true
	equipped[ITEMS[id].kind] = id
	_saved()
	return true


func equip_item(id: String) -> bool:
	if not owned.has(id):
		return false
	equipped[ITEMS[id].kind] = id
	_saved()
	return true


## Price of the next level of bonus `id`, -1 when maxed.
func bonus_price(id: String) -> int:
	var lvl: int = bonuses.get(id, 0)
	return -1 if lvl >= BONUSES[id].max else int(BONUSES[id].price * pow(GROWTH, lvl))


func buy_bonus(id: String) -> bool:
	var price := bonus_price(id) if BONUSES.has(id) else -1
	if price < 0 or gold < price:
		return false
	gold -= price
	bonuses[id] = bonuses.get(id, 0) + 1
	_saved()
	return true


func buy_augment(id: String) -> bool:
	if not AUGMENTS.has(id) or augments.has(id) or gold < AUGMENTS[id].price:
		return false
	gold -= AUGMENTS[id].price
	augments[id] = true
	if can_slot(id):
		slotted.append(id)
	_saved()
	return true


## Owned, not slotted, a slot free, and no second active.
func can_slot(id: String) -> bool:
	return augments.has(id) and id not in slotted and slotted.size() < SLOTS \
		and not (AUGMENTS[id].kind == "active" and slotted.any(func(s): return AUGMENTS[s].kind == "active"))


## Puts augment `id` in a slot, or takes it out.
func toggle_augment(id: String) -> bool:
	if id in slotted:
		slotted.erase(id)
	elif can_slot(id):
		slotted.append(id)
	else:
		return false
	_saved()
	return true


## The slotted augments, what the next run starts with.
func slotted_augments() -> Array:
	return slotted.map(func(id): return AUGMENTS[id].merged({"id": id}))


func set_look(key: String, color: String) -> void:
	if look.has(key) and Color.html_is_valid(color):
		look[key] = color
		_saved()


func _saved() -> void:
	save()
	changed.emit()


# --- spells ------------------------------------------------------------------

func is_unlocked(entry: Dictionary) -> bool:
	return entry.get("unlock", "") == "" or achievements.has(entry.unlock)


## Spells the player can equip in `slot`: unlocked base spells, then forged.
func available_spells(slot: String) -> Array:
	return (base_spells + forged).filter(func(e): return e.slot == slot and is_unlocked(e))


## The spells equipped in the slots, as entries: the only ones the forge improves.
func equipped_entries() -> Array:
	return Upgrades.SLOTS.map(func(slot): return _entry(spells[slot], slot)).filter(func(e): return not e.is_empty())


func _entry(id: String, slot: String) -> Dictionary:
	for e in available_spells(slot):
		if e.id == id:
			return e
	return {}


func equip_spell(slot: String, id: String) -> bool:
	if _entry(id, slot).is_empty():
		return false
	spells[slot] = id
	_saved()
	return true


## slot -> spell, what the next run starts with.
func equipped_spells() -> Dictionary:
	var out := {}
	for slot in Upgrades.SLOTS:
		out[slot] = _entry(spells[slot], slot).spell
	return out


## A spell written by the forge (bundle saved at `file`): kept, and equipped
## in `slot` for the next run.
func add_forged(spell: Dictionary, file: String, slot := "primary") -> String:
	var id := file.get_file().get_basename()  # unique: see next_bundle_path
	forged.append({"id": id, "slot": slot, "file": file, "spell": spell})
	spells[slot] = id
	_saved()
	return id


## Where the next forged bundle is saved. Its name is the spell's id, unique
## across the account's characters (the server keeps bundles per account).
func next_bundle_path() -> String:
	DirAccess.make_dir_recursive_absolute("user://spells")
	return "user://spells/forged_%d.spell" % int(Time.get_unix_time_from_system() * 1000)


# --- end of run --------------------------------------------------------------

## Permadeath: the run is over, its gold and scrolls are kept. Updates stats,
## scores and achievements, saves. Returns the achievement ids just reached.
func record_run(r: Dictionary) -> Array:
	gold += r.gold
	blank_scrolls += r.scrolls
	stats.runs += 1
	stats.kills += r.kills
	stats.bosses += r.bosses
	stats.gold_total += r.gold
	stats.scrolls += r.scrolls
	stats.best_wave = maxi(stats.best_wave, r.wave)
	stats.best_level = maxi(stats.best_level, r.level)
	scores.append({"score": r.score, "wave": r.wave, "level": r.level, "kills": r.kills,
		"time": int(Time.get_unix_time_from_system())})
	scores.sort_custom(func(a, b): return a.score > b.score)
	scores = scores.slice(0, MAX_SCORES)
	var reached := []
	for id in ACHIEVEMENTS:
		if not achievements.has(id) and stats[ACHIEVEMENTS[id].stat] >= ACHIEVEMENTS[id].goal:
			achievements[id] = int(Time.get_unix_time_from_system())
			reached.append(id)
	_saved()
	return reached


## Base spells unlocked by these achievements, for the "new spell" message.
func unlocked_by(ids: Array) -> Array:
	return base_spells.filter(func(e): return e.unlock in ids)
