class_name Upgrades
## Grimoire skills, with levels: each pick raises the skill one level (shown
## Skill I, II, III..., no numeral for a single-level skill), up to its "max"; a maxed skill is no longer offered.
## Every skill is a Stats bonus on the mage (Run.levels, see game/stats.gd):
## "step" of "stat" per level ("pct": a percentage, step 10 = +10 %). "desc"
## formats the per-level value. "kind": the grimoire that offers it, "hero"
## (red) or "spell" (blue). One entry per skill (tasks #309 to #320).
## "spell": a sub-skill, an augment of that base spell (game/spells.json id),
## offered only when the run's primary spell is it (Run.base). Its stat is
## read by the engine only, never part of the spell format: the forge cannot
## write it on a spell (tasks #369 and on).

const LIST := {
	"toughness": {"name": "Robur", "desc": "+%d max HP", "step": 25, "max": 4, "kind": "hero", "stat": "hp"},
	"thrift": {"name": "Parsimonia", "desc": "-%d%% mana cost", "step": -15, "max": 11, "kind": "spell", "stat": "mana_cost%", "pct": true},
	"inspiration": {"name": "Inspiratio", "desc": "+%d choice per grimoire", "step": 1, "max": 1, "kind": "hero", "stat": "choices"},
	"haste": {"name": "Celeritas", "desc": "+%d%% cast rate", "step": 10, "max": 9, "kind": "hero", "stat": "cast_rate%", "pct": true},
	"fireproof": {"name": "Tutela Ignis", "desc": "+%d%% fire resistance", "step": -10, "max": 9, "kind": "hero", "stat": "fire%", "pct": true},
	"flow": {"name": "Fluxus", "desc": "+%d%% mana regeneration", "step": 35, "max": 9, "kind": "hero", "stat": "mana_regen%", "pct": true},
	"reservoir": {"name": "Receptaculum", "desc": "+%d max mana", "step": 50, "max": 4, "kind": "hero", "stat": "mana"},
	"channeling": {"name": "Meditatio", "desc": "+%d%% mana regen standing still", "step": 300, "max": 1, "kind": "spell", "stat": "still_regen%", "pct": true},
	"antidote": {"name": "Antidotum", "desc": "+%d%% poison resistance", "step": -10, "max": 9, "kind": "hero", "stat": "poison%", "pct": true},
	"fleetness": {"name": "Pernicitas", "desc": "+%d%% move speed", "step": 10, "max": 8, "kind": "hero", "stat": "speed%", "pct": true},
	"magnetism": {"name": "Magnes", "desc": "+%d%% pickup radius", "step": 30, "max": 5, "kind": "hero", "stat": "pickup%", "pct": true},
	"damage": {"name": "Potentia", "desc": "+%d%% damage", "step": 25, "max": 9, "kind": "spell", "stat": "damage%", "pct": true},
	"chaining": {"name": "Catena", "desc": "Fulmen's arc jumps on to +%d enemy", "step": 1, "max": 5, "kind": "spell", "stat": "chain", "spell": "lightning"},
}
const KINDS := ["hero", "spell"]
const ROMAN := [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]


## `n` in roman numerals (the skill levels, 1 to 39).
static func roman(n: int) -> String:
	var out := ""
	for r in ROMAN:
		while n >= r[0]:
			out += r[1]
			n -= r[0]
	return out


## Skill `u`'s name at `level`, translated: "Celeritas III"; a single-level skill
## has no numeral.
static func title(u: Dictionary, level: int) -> String:
	var name := TranslationServer.translate(u.name)
	return name if u.max == 1 else "%s %s" % [name, roman(level)]


## Skill `u`'s text: its value per level, translated.
static func describe(u: Dictionary) -> String:
	return TranslationServer.translate(u.desc) % abs(u.step)  # the sign is in the text


## Skill `u` at `level` as a Stats bonus.
static func bonus(u: Dictionary, level: int) -> Dictionary:
	return {u.stat: u.step * level * (0.01 if u.get("pct") else 1.0)}


## Up to `n` distinct {id, level} offers (level: the one it would reach) among
## the skills of `list` of `kind` (KINDS, "" for both) below their max at
## `levels` (id -> level taken); a sub-skill only for its `base` spell.
static func offers(levels: Dictionary, rng: RandomNumberGenerator, kind := "", n := 3, list := LIST, base := "") -> Array:
	var pool := list.keys().filter(func(id): return kind in ["", list[id].kind] and levels.get(id, 0) < list[id].max and list[id].get("spell", base) == base)
	for i in range(pool.size() - 1, 0, -1):  # Fisher-Yates with the run's rng
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, n).map(func(id): return {"id": id, "level": levels.get(id, 0) + 1})
