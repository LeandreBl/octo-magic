class_name Spell
## A spell is plain data (a Dictionary, saved as JSON). Anything that builds
## spells (the AI forge, the player) only edits that data; this file
## sanitizes it, prices it and runs it. See docs/spells.md for the format.

const SLOTS := ["primary"]  # the spell equipped from the profile
const RUN_SLOTS := ["primary", "secondary"]  # secondary: an active augment (Profile.AUGMENTS)
const MAX_DEPTH := 3  # nested "cast" effects
const MAX_LIST := 6  # effects / motions per list

const ELEMENTS := ["fire", "ice", "lightning", "poison", "arcane", "physical"]
const PATTERNS := ["aim", "radial", "random", "nearest"]
const SHAPES := ["bolt", "zone", "beam", "cone"]
const MOTIONS := ["homing", "wave", "accelerate", "boomerang", "orbit"]
const STATUSES := ["burn", "poison", "slow", "freeze", "stun"]
const EFFECTS := ["damage", "status", "knockback", "heal", "cast"]
const PIXELS := ".01234567"  # sprite grid chars: transparent, palette index

## The starting spell is the first example (spell/examples.json).
static func base() -> Dictionary:
	return sanitize(JSON.parse_string(FileAccess.get_file_as_string("res://spell/examples.json"))[0])


## The spell's name and description in the game's language: base spells are
## translated (locale/fr.po), forged ones carry a French description.
static func label(s: Dictionary) -> String:
	return TranslationServer.translate(s.name)


static func describe(s: Dictionary) -> String:
	if TranslationServer.get_locale().begins_with("fr") and s.get("description_fr", ""):
		return s.description_fr
	return TranslationServer.translate(s.description)


# --- sanitize: never trust spell data (AI output, save files) ---------------

static func sanitize(d: Variant) -> Dictionary:
	var s: Dictionary = d if d is Dictionary else {}
	var words: Array = []
	for w in _arr(s.get("words")):
		words.append(str(w).substr(0, 32))
	return {
		"name": str(s.get("name", "Spell")).substr(0, 40),
		"description": str(s.get("description", "")).substr(0, 200),
		"description_fr": str(s.get("description_fr", "")).substr(0, 200),
		"element": _enum(s.get("element"), ELEMENTS),
		"color": _color(s.get("color")),
		"cooldown": _num(s.get("cooldown"), 0.5, 0.08, 5.0),
		"words": words.slice(0, 20),
		"origin": str(s.get("origin", "")).substr(0, 40),
		"palette": _palette(s.get("palette")),
		"icon": _grid(s.get("icon"), 24),
		"icon_file": _file(s.get("icon_file")),
		"bundle": str(s.get("bundle", "")).substr(0, 64),
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
		"angle": _num(b.get("angle"), 60.0, 0.0, 180.0),
		"pierce": int(_num(b.get("pierce"), 0, 0, 20)),
		"bounce": int(_num(b.get("bounce"), 0, 0, 10)),
		"motion": motion,
		"on_hit": _effects(b.get("on_hit"), depth),
		"on_expire": _effects(b.get("on_expire"), depth),
		"tick_interval": _num(b.get("tick_interval"), 0.5, 0.1, 5.0),
		"on_tick": _effects(b.get("on_tick"), depth),
		"sprite": _frames(b.get("sprite")),
		"particle": _grid(b.get("particle"), 8),
		"sheet": _sheet(b.get("sheet")),
		"burst_sheet": _sheet(b.get("burst_sheet")),
		"sound": _file(b.get("sound"), "ogg"),
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


## A PNG (or `ext`) of the spell's bundle. Plain names only: no paths.
static func _file(v: Variant, ext := "png") -> String:
	var s := str(v) if v is String else ""
	var re := RegEx.create_from_string("^[a-z0-9_]{1,32}\\." + ext + "$")
	return s if re.search(s) else ""


## An animated sprite sheet of the bundle (docs/spells.md, "Bundle format"):
## one strip of `frames` square frames of `size` px, drawing centered,
## `scale` screen px per sheet pixel.
static func _sheet(v: Variant) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var file := _file(d.get("file"))
	if file.is_empty():
		return {}
	return {
		"file": file,
		"size": int(_num(d.get("size"), 16, 8, 256)),
		"frames": int(_num(d.get("frames"), 1, 1, 64)),
		"fps": int(_num(d.get("fps"), 12, 1, 60)),
		"loop": d.get("loop", true) == true,
		"scale": _num(d.get("scale"), SpellArt.PIXEL, 1.0, SpellArt.PIXEL),
	}


static func _palette(v: Variant) -> Array:
	var out: Array = []
	for c in _arr(v).slice(0, 8):
		out.append(_color(c))
	return out


static func _frames(v: Variant) -> Array:
	var out: Array = []
	for f in _arr(v).slice(0, 4):
		var g := _grid(f, 16)
		if not g.is_empty():
			out.append(g)
	return out


## A pixel grid: rows of PIXELS chars, at most size x size. Bad chars become
## transparent; an all-transparent grid is dropped (the engine draws a default).
static func _grid(v: Variant, size: int) -> Array:
	var rows: Array = []
	var visible := false
	for r in _arr(v).slice(0, size):
		var row := ""
		for ch in str(r).substr(0, size):
			row += ch if ch in PIXELS else "."
		visible = visible or row.replace(".", "") != ""
		rows.append(row)
	return rows if visible else []


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


## A cast costs CAST_BASE plus CAST_RATE per power (Pila Ignea, power 28: 15;
## Telum Magicum, power 5: 10). A channeled spell (beam, cone) costs CHANNEL_RATE per power a
## second (Fulmen, Flatus Gelidus 10/s), paid per tick: held down, it still
## drains faster than the base mana regen.
const CAST_RATE := 5.0 / 23.0
const CAST_BASE := 10.0 - 5.0 * CAST_RATE
const CHANNEL_RATE := 10.0 / 6.0


## Mana per cast: a whole number for a cast, a fraction per tick for a channel.
static func mana_cost(s: Dictionary) -> float:
	if s.emit.body.shape in ["beam", "cone"]:
		return power(s) * CHANNEL_RATE * s.cooldown
	return roundf(CAST_BASE + power(s) * CAST_RATE)


## A cost as shown: per second for a channeled spell (beam, cone: one cast per
## `cooldown`), else per cast. Checks and payments stay per cast (per tick).
static func cost_text(s: Dictionary, cost: float) -> String:
	if s.emit.body.shape in ["beam", "cone"]:
		return "%d/s" % roundi(cost / s.cooldown)
	return "%d" % roundi(cost)


static func _emit_power(e: Dictionary) -> float:
	return e.count * _body_power(e.body)


static func _body_power(b: Dictionary) -> float:
	var hits: float = 1.0 + b.pierce + b.bounce
	match b.shape:
		"zone": hits = 0.0  # zones only act through on_tick / on_expire
		"beam": hits = 1.0
		"cone": hits = 2.0  # ponytail: guess of enemies in a cone, tune in a balance pass
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


## Damage and damage-over-time of every body of the spell times `mult`.
static func scale_damage(spell: Dictionary, mult: float) -> Dictionary:
	var s := spell.duplicate(true)
	_each_effect(s.emit, func(f):
		if f.type == "damage": f.amount *= mult
		elif f.type == "status" and f.status in ["burn", "poison"]: f.power *= mult)
	return sanitize(s)


## A spell cast short of mana: `ratio` (mana left / cost) of its damage, its
## hits only deal damage (no status, push, sub-cast), drawn see-through
## (SpellBody reads "weak", the ratio, as alpha; SpellSound plays it that much quieter).
static func weakened(spell: Dictionary, ratio: float) -> Dictionary:
	var s := scale_damage(spell, ratio)
	_each_body(s.emit, func(b): b.on_hit = b.on_hit.filter(func(f): return f.type == "damage"))
	s.weak = ratio
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
