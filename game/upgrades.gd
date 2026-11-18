class_name Upgrades
## Level-up augments, each rolled with a rarity that multiplies its strength.
## Spell augments edit the equipped spell's JSON (Spell.sanitize clamps it
## again; "mana" is kept outside the spell, see Run.mana_mult); hero augments
## ("stat") are Stats bonuses on the mage (Run.bonuses, see game/stats.gd). "desc" formats the value: "step" times the tier.

const SLOTS := ["primary"]  # the spell equipped from the profile
const RUN_SLOTS := ["primary", "secondary"]  # secondary: an active augment (Profile.AUGMENTS)
const SLOT_NAMES := {"primary": "Spell", "secondary": "Secondary spell"}  # English, translated where shown
const RARITIES := {
	"common": {"name": "Common", "tier": 1, "weight": 60.0, "color": "#d8d2c4"},
	"rare": {"name": "Rare", "tier": 2, "weight": 30.0, "color": "#4fa3ff"},
	"epic": {"name": "Epic", "tier": 3, "weight": 10.0, "color": "#c06bff"},
}
const LIST := {
	"damage": {"name": "Power", "desc": "+%d%% damage", "step": 20},
	"cooldown": {"name": "Haste", "desc": "-%d%% cooldown", "step": 10},
	"count": {"name": "Multiplication", "desc": "+%d projectile(s)", "step": 1},
	"speed": {"name": "Velocity", "desc": "+%d%% projectile speed", "step": 15},
	"mana": {"name": "Thrift", "desc": "-%d%% mana cost", "step": 10},
	"area": {"name": "Amplitude", "desc": "+%d%% size and area", "step": 15},
	"pierce": {"name": "Piercing", "desc": "+%d enemies pierced", "step": 1},
	"toughness": {"name": "Toughness", "desc": "+%d max health", "step": 20, "stat": "hp"},
	"mending": {"name": "Mending", "desc": "+%d health per second", "step": 1, "stat": "hp_regen"},
	"reservoir": {"name": "Reservoir", "desc": "+%d max mana", "step": 20, "stat": "mana"},
	"flow": {"name": "Flow", "desc": "+%d mana per second", "step": 5, "stat": "mana_regen"},
	"fleetness": {"name": "Fleetness", "desc": "+%d%% move speed", "step": 8, "stat": "speed%", "pct": true},
	"magnetism": {"name": "Magnetism", "desc": "+%d%% pickup radius", "step": 25, "stat": "pickup%", "pct": true},
	"ward": {"name": "Ward", "desc": "-%d%% damage taken", "step": 4, "stat": "armor", "pct": true},
	"precision": {"name": "Precision", "desc": "+%d%% critical chance", "step": 4, "stat": "crit", "pct": true},
	"fortune": {"name": "Fortune", "desc": "+%d%% gold", "step": 15, "stat": "gold%", "pct": true},
	"insight": {"name": "Insight", "desc": "+%d%% experience", "step": 15, "stat": "xp%", "pct": true},
}
const MANA_FLOOR := 0.4  # "mana" augments stop at 40 % of the cost


## The augment's text at `rarity`, translated.
static func describe(id: String, rarity: String) -> String:
	return TranslationServer.translate(LIST[id].desc) % (LIST[id].step * RARITIES[rarity].tier)


## The augment's raw amount at `tier`: a fraction for "%" ones.
static func amount(id: String, tier: int) -> float:
	var u: Dictionary = LIST[id]
	return u.step * tier * (0.01 if u.get("pct") or not u.has("stat") else 1.0)


## Hero augment `id` at `tier` as a Stats bonus.
static func bonus(id: String, tier: int) -> Dictionary:
	return {LIST[id].stat: amount(id, tier)}


## Can `id` still improve the spell or the stats (Run.stats: below its bound)?
## (mana_mult: the cost multiplier)
static func applies(spell: Dictionary, id: String, mana_mult := 1.0, stats := {}) -> bool:
	if LIST[id].has("stat"):
		var k: String = LIST[id].stat.trim_suffix("%")
		return stats.get(k, Stats.BASE[k]) < Stats.BOUNDS[k][1]
	var e: Dictionary = spell.emit
	var b: Dictionary = e.body
	match id:
		"cooldown": return spell.cooldown > 0.08
		"count": return e.count < 16
		"speed": return b.speed > 0.0 and b.speed < 1400.0 and not b.motion.any(func(m): return m.type == "orbit")
		"mana": return mana_mult > MANA_FLOOR
		"area": return b.size < 220.0
		"pierce": return b.shape == "bolt" and b.pierce < 20
	return id == "damage"


## The spell with spell augment `id` applied at `tier` ("mana" leaves it unchanged).
static func apply(spell: Dictionary, id: String, tier := 1) -> Dictionary:
	var s := spell.duplicate(true)
	var e: Dictionary = s.emit
	var a := amount(id, tier)
	match id:
		"damage": return scale_damage(s, 1.0 + a)
		"cooldown": s.cooldown *= 1.0 - a
		"count":
			e.count += tier
			if e.pattern != "radial":
				e.spread = maxf(e.spread, 12.0 * (e.count - 1))
		"speed": e.body.speed *= 1.0 + a
		"area":
			e.body.size *= 1.0 + a
			_each_effect(e, func(f): if f.get("radius", 0.0) > 0.0: f.radius *= 1.0 + a)
		"pierce": e.body.pierce += tier
	return Spell.sanitize(s)


## Damage and damage-over-time of every body of the spell times `mult`.
static func scale_damage(spell: Dictionary, mult: float) -> Dictionary:
	var s := spell.duplicate(true)
	_each_effect(s.emit, func(f):
		if f.type == "damage": f.amount *= mult
		elif f.type == "status" and f.status in ["burn", "poison"]: f.power *= mult)
	return Spell.sanitize(s)


static func _each_effect(emit: Dictionary, fn: Callable) -> void:
	for key in ["on_hit", "on_expire", "on_tick"]:
		for f in emit.body[key]:
			fn.call(f)
			if f.type == "cast":
				_each_effect(f.emit, fn)


## Up to `n` distinct {id, rarity} offers among the augments that still apply
## to the equipped spell or the stats, each with its own rarity roll.
static func offers(spell: Dictionary, mana_mult: float, stats: Dictionary, rng: RandomNumberGenerator, n := 3) -> Array:
	var pool := LIST.keys().filter(func(id): return applies(spell, id, mana_mult, stats))
	for i in range(pool.size() - 1, 0, -1):  # Fisher-Yates with the run's rng
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var weights := PackedFloat32Array(RARITIES.values().map(func(r): return r.weight))
	return pool.slice(0, n).map(func(id): return {"id": id, "rarity": RARITIES.keys()[rng.rand_weighted(weights)]})
