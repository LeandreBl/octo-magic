class_name Upgrades
## Level-up upgrades. An upgrade edits a spell's JSON, then Spell.sanitize
## clamps it again; "mana" is the only one kept outside the spell (the cost is
## derived from the spell's power, see Run.mana_cost).

const SLOTS := ["primary"]  # one spell: no secondary or ultimate (task #94)
const SLOT_NAMES := {"primary": "Spell"}  # names: English, translated where shown
const LIST := {
	"damage": {"name": "Power", "desc": "+25% damage"},
	"cooldown": {"name": "Haste", "desc": "-15% cooldown"},
	"count": {"name": "Multiplication", "desc": "+1 projectile"},
	"speed": {"name": "Velocity", "desc": "+20% projectile speed"},
	"mana": {"name": "Thrift", "desc": "-15% mana cost"},
	"area": {"name": "Amplitude", "desc": "+20% size and area"},
	"pierce": {"name": "Piercing", "desc": "Passes through one more enemy"},
}
const MANA_FLOOR := 0.4  # "mana" upgrades stop at 40 % of the cost


## Can `id` still improve this spell? (mana_mult: the slot's cost multiplier)
static func applies(spell: Dictionary, id: String, mana_mult := 1.0) -> bool:
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


## The spell with upgrade `id` applied ("mana" leaves it unchanged).
static func apply(spell: Dictionary, id: String) -> Dictionary:
	var s := spell.duplicate(true)
	var e: Dictionary = s.emit
	match id:
		"damage": return scale_damage(s, 1.25)
		"cooldown": s.cooldown *= 0.85
		"count":
			e.count += 1
			if e.pattern != "radial":
				e.spread = maxf(e.spread, 12.0 * (e.count - 1))
		"speed": e.body.speed *= 1.2
		"area":
			e.body.size *= 1.2
			_each_effect(e, func(f): if f.get("radius", 0.0) > 0.0: f.radius *= 1.2)
		"pierce": e.body.pierce += 1
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


## Up to `n` distinct {slot, id} offers among the upgrades that still apply.
static func offers(spells: Dictionary, mana_mult: Dictionary, rng: RandomNumberGenerator, n := 3) -> Array:
	var pool := []
	for slot in SLOTS:
		if spells.has(slot):
			for id in LIST:
				if applies(spells[slot], id, mana_mult.get(slot, 1.0)):
					pool.append({"slot": slot, "id": id})
	for i in range(pool.size() - 1, 0, -1):  # Fisher-Yates with the run's rng
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, n)
