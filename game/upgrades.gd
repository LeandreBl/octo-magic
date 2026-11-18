class_name Upgrades
## Grimoire skills, with levels: each pick raises the skill one level (shown
## Skill I, II, III...), up to its "max"; a maxed skill is no longer offered.
## Every skill is a Stats bonus on the mage (Run.bonuses, see game/stats.gd):
## "step" of "stat" per level ("pct": a percentage, step 10 = +10 %). "desc"
## formats the per-level value. "kind": the grimoire that offers it, "hero"
## (red) or "spell" (blue). One entry per skill (tasks #309 to #320).

const SLOTS := ["primary"]  # the spell equipped from the profile
const RUN_SLOTS := ["primary", "secondary"]  # secondary: an active augment (Profile.AUGMENTS)
const SLOT_NAMES := {"primary": "Spell", "secondary": "Secondary spell"}  # English, translated where shown
const LIST := {
	"toughness": {"name": "Toughness", "desc": "+%d max HP", "step": 25, "max": 4, "kind": "hero", "stat": "hp"},
	"thrift": {"name": "Thrift", "desc": "-%d%% mana cost", "step": -15, "max": 11, "kind": "spell", "stat": "mana_cost%", "pct": true},
	"inspiration": {"name": "Inspiration", "desc": "+%d choice per grimoire", "step": 1, "max": 1, "kind": "hero", "stat": "choices"},
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


## Skill `u`'s text: its value per level, translated.
static func describe(u: Dictionary) -> String:
	return TranslationServer.translate(u.desc) % abs(u.step)  # the sign is in the text


## Skill `u` at `level` as a Stats bonus.
static func bonus(u: Dictionary, level: int) -> Dictionary:
	return {u.stat: u.step * level * (0.01 if u.get("pct") else 1.0)}


## Damage and damage-over-time of every body of the spell times `mult`.
static func scale_damage(spell: Dictionary, mult: float) -> Dictionary:
	var s := spell.duplicate(true)
	_each_effect(s.emit, func(f):
		if f.type == "damage": f.amount *= mult
		elif f.type == "status" and f.status in ["burn", "poison"]: f.power *= mult)
	return Spell.sanitize(s)


## The failsafe of a spell costing more than the max mana: `ratio` (max mana /
## cost) of its damage, its hits only deal damage (no status, push, sub-cast),
## drawn see-through (SpellBody reads "weak").
static func weakened(spell: Dictionary, ratio: float) -> Dictionary:
	var s := scale_damage(spell, ratio)
	_each_body(s.emit, func(b): b.on_hit = b.on_hit.filter(func(f): return f.type == "damage"))
	s.weak = true
	return s


static func _each_body(emit: Dictionary, fn: Callable) -> void:
	fn.call(emit.body)
	for key in ["on_expire", "on_tick"]:
		for f in emit.body[key]:
			if f.type == "cast":
				_each_body(f.emit, fn)


static func _each_effect(emit: Dictionary, fn: Callable) -> void:
	for key in ["on_hit", "on_expire", "on_tick"]:
		for f in emit.body[key]:
			fn.call(f)
			if f.type == "cast":
				_each_effect(f.emit, fn)


## Up to `n` distinct {id, level} offers (level: the one it would reach) among
## the skills of `list` of `kind` (KINDS, "" for both) below their max at
## `levels` (id -> level taken).
static func offers(levels: Dictionary, rng: RandomNumberGenerator, kind := "", n := 3, list := LIST) -> Array:
	var pool := list.keys().filter(func(id): return kind in ["", list[id].kind] and levels.get(id, 0) < list[id].max)
	for i in range(pool.size() - 1, 0, -1):  # Fisher-Yates with the run's rng
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, n).map(func(id): return {"id": id, "level": levels.get(id, 0) + 1})
