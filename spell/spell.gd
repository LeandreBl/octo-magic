class_name Spell
## A spell is plain data (a Dictionary, saved as JSON). Anything that builds
## spells (the AI, level-ups, the player) only edits that data; this file
## sanitizes it, prices it and runs it. See docs/spells.md for the format.

const MAX_DEPTH := 3  # nested "cast" effects
const MAX_LIST := 6  # effects / motions per list

const ELEMENTS := ["fire", "ice", "lightning", "poison", "arcane", "physical"]
const PATTERNS := ["aim", "radial", "random", "nearest"]
const SHAPES := ["bolt", "zone"]
const MOTIONS := ["homing", "wave", "accelerate", "boomerang", "orbit"]
const STATUSES := ["burn", "poison", "slow", "freeze", "stun"]
const EFFECTS := ["damage", "status", "knockback", "heal", "cast"]

const BASE := {
	"name": "Étincelle",
	"description": "Une petite boule de feu.",
	"element": "fire",
	"color": "#ff7a1a",
	"cooldown": 0.35,
	"words": [],
	"emit": {
		"pattern": "aim", "count": 1, "spread": 0.0, "burst_delay": 0.0,
		"body": {
			"shape": "bolt", "speed": 520.0, "size": 6.0, "lifetime": 1.2,
			"pierce": 0, "bounce": 0, "motion": [],
			"on_hit": [{"type": "damage", "amount": 10.0, "radius": 0.0}],
			"on_expire": [], "tick_interval": 0.5, "on_tick": [],
		},
	},
}


# --- sanitize: never trust spell data (AI output, save files) ---------------

static func sanitize(d: Variant) -> Dictionary:
	var s: Dictionary = d if d is Dictionary else {}
	var words: Array = []
	for w in _arr(s.get("words")):
		words.append(str(w).substr(0, 32))
	return {
		"name": str(s.get("name", "Sort")).substr(0, 40),
		"description": str(s.get("description", "")).substr(0, 200),
		"element": _enum(s.get("element"), ELEMENTS),
		"color": _color(s.get("color")),
		"cooldown": _num(s.get("cooldown"), 0.5, 0.08, 5.0),
		"words": words.slice(0, 20),
		"emit": _emit(s.get("emit"), 0),
	}


static func _emit(d: Variant, depth: int) -> Dictionary:
	var e: Dictionary = d if d is Dictionary else {}
	return {
		"pattern": _enum(e.get("pattern"), PATTERNS),
		"count": int(_num(e.get("count"), 1, 1, 16)),
		"spread": _num(e.get("spread"), 0.0, 0.0, 360.0),
		"burst_delay": _num(e.get("burst_delay"), 0.0, 0.0, 0.5),
		"body": _body(e.get("body"), depth),
	}


static func _body(d: Variant, depth: int) -> Dictionary:
	var b: Dictionary = d if d is Dictionary else {}
	var motion: Array = []
	for m in _arr(b.get("motion")).slice(0, MAX_LIST):
		if m is Dictionary:
			motion.append({
				"type": _enum(m.get("type"), MOTIONS),
				"strength": _num(m.get("strength"), 1.0, -10.0, 10.0),
			})
	return {
		"shape": _enum(b.get("shape"), SHAPES),
		"speed": _num(b.get("speed"), 400.0, 0.0, 1400.0),
		"size": _num(b.get("size"), 6.0, 2.0, 220.0),
		"lifetime": _num(b.get("lifetime"), 1.0, 0.05, 10.0),
		"pierce": int(_num(b.get("pierce"), 0, 0, 20)),
		"bounce": int(_num(b.get("bounce"), 0, 0, 10)),
		"motion": motion,
		"on_hit": _effects(b.get("on_hit"), depth),
		"on_expire": _effects(b.get("on_expire"), depth),
		"tick_interval": _num(b.get("tick_interval"), 0.5, 0.1, 5.0),
		"on_tick": _effects(b.get("on_tick"), depth),
	}


static func _effects(d: Variant, depth: int) -> Array:
	var out: Array = []
	for f in _arr(d).slice(0, MAX_LIST):
		if not (f is Dictionary and f.get("type") in EFFECTS):
			continue
		var r := _num(f.get("radius"), 0.0, 0.0, 300.0)
		match f.type:
			"damage":
				out.append({"type": "damage", "amount": _num(f.get("amount"), 5.0, 0.0, 500.0), "radius": r})
			"status":
				out.append({"type": "status", "status": _enum(f.get("status"), STATUSES),
					"power": _num(f.get("power"), 1.0, 0.0, 100.0),
					"duration": _num(f.get("duration"), 2.0, 0.1, 10.0), "radius": r})
			"knockback":
				out.append({"type": "knockback", "force": _num(f.get("force"), 200.0, -800.0, 800.0), "radius": r})
			"heal":
				out.append({"type": "heal", "amount": _num(f.get("amount"), 5.0, 0.0, 100.0)})
			"cast":
				if depth < MAX_DEPTH:
					out.append({"type": "cast", "emit": _emit(f.get("emit"), depth + 1)})
	return out


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


static func _num(v: Variant, default: float, lo: float, hi: float) -> float:
	if not (v is float or v is int) or is_nan(float(v)):
		return default
	return clampf(float(v), lo, hi)


static func _enum(v: Variant, allowed: Array) -> String:
	return v if v in allowed else allowed[0]


static func _color(v: Variant) -> String:
	return v if v is String and Color.html_is_valid(v) else "#ffffff"


# --- pricing: the AI describes, the engine balances -------------------------
# ponytail: rough "damage potential" heuristic, replace with playtest-tuned
# weights once there is a real balance pass.

static func power(s: Dictionary) -> float:
	return _emit_power(s.emit)


static func mana_cost(s: Dictionary) -> int:
	return clampi(roundi(power(s) * 0.4), 1, 100)


static func _emit_power(e: Dictionary) -> float:
	return e.count * _body_power(e.body)


static func _body_power(b: Dictionary) -> float:
	var hits: float = 1.0 + b.pierce + b.bounce
	if b.shape == "zone":
		hits = 0.0  # zones only act through on_tick / on_expire
	var ticks: float = b.lifetime / b.tick_interval
	return hits * _effects_power(b.on_hit) + _effects_power(b.on_expire) \
		+ ticks * _effects_power(b.on_tick)


static func _effects_power(list: Array) -> float:
	var p := 0.0
	for f in list:
		var area: float = 1.0 + f.get("radius", 0.0) / 40.0  # area hits several enemies
		match f.type:
			"damage": p += f.amount * area
			"status": p += f.power * f.duration * area * 0.5
			"knockback": p += absf(f.force) / 100.0 * area
			"heal": p += f.amount
			"cast": p += _emit_power(f.emit)
	return p
