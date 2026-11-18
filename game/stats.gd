class_name Stats
## The mage's stats, as data. Every source (shop items, permanent bonuses,
## hero augments) is a bonus dict: "stat": n adds n, "stat%": p multiplies by
## (1 + p). Total = (BASE + every add) * every (1 + p), clamped to BOUNDS.
## Unknown stats are ignored. The host clamps them again (Player.clean_loadout).

const BASE := {
	"hp": 100.0,  # max HP
	"hp_regen": 0.0,  # HP per second
	"mana": 100.0,  # max mana
	"mana_regen": 25.0,  # mana per second
	"mana_cost": 1.0,  # multiplier on Spell.mana_cost
	"cooldown": 1.0,  # multiplier on spell cooldowns
	"cast_rate": 1.0,  # casts per cooldown: spell cooldowns are divided by it
	"speed": 220.0,  # move speed, px/s
	"pickup": 90.0,  # drops closer than this fly to the mage, px
	"armor": 0.0,  # fraction of the damage taken that is removed (< 0: more is taken)
	"crit": 0.05,  # chance a cast deals CRIT_MULT times its damage
	"damage": 1.0,  # multiplier on spell damage
	"gold": 1.0,  # multiplier on gold picked up
	"xp": 1.0,  # multiplier on XP from kills
	"poison": 1.0,  # multiplier on poison damage taken
	"orbs": 1.0,  # multiplier on what mana and life orbs refill
	"luck": 1.0,  # multiplier on grimoire and scroll drop chances (the best mage's, on the host)
	"choices": 3.0,  # cards a grimoire offers
}
const BOUNDS := {
	"hp": [1.0, 1000.0], "hp_regen": [0.0, 50.0], "mana": [10.0, 1000.0],
	"mana_regen": [0.0, 200.0], "mana_cost": [0.0, 3.0], "cooldown": [0.4, 3.0], "cast_rate": [0.2, 5.0],
	"speed": [80.0, 660.0], "pickup": [30.0, 600.0], "armor": [-1.0, 0.75],
	"crit": [0.0, 1.0], "damage": [0.1, 20.0], "gold": [0.0, 6.0], "xp": [0.0, 6.0],
	"poison": [0.0, 1.0], "orbs": [0.0, 4.0], "luck": [0.0, 4.0],
	"choices": [3.0, 4.0],
}
const CRIT_MULT := 2.0


## A spell's mana cost under the "mana_cost" multiplier: at least 1, 0 only at 0 (free spells).
static func cost(base: int, mult: float) -> int:
	return maxi(roundi(base * mult), 1 if mult > 0.0 else 0)


static func total(bonuses: Array) -> Dictionary:
	var add := {}
	var mult := {}
	for b in bonuses:
		for k: String in b:
			var stat := k.trim_suffix("%")
			if k.ends_with("%"):
				mult[stat] = mult.get(stat, 1.0) * (1.0 + b[k])
			else:
				add[stat] = add.get(stat, 0.0) + b[k]
	var s := {}
	for k in BASE:
		s[k] = clampf((BASE[k] + add.get(k, 0.0)) * mult.get(k, 1.0), BOUNDS[k][0], BOUNDS[k][1])
	return s
