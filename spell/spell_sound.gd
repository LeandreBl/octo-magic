class_name SpellSound
## Spell sounds, synthesized from the spell data: no files, no API, so every
## spell (forged, levelled up, hand made) gets its own sounds. Same data ->
## same sound (the noise is seeded by the data).
## - a one-shot sound when an emit is cast (sub-casts too: higher, quieter);
## - a looping sound on continuous bodies (zones, orbits, ticking bodies),
##   instead of the one-shot, for as long as the body lives.

const RATE := 22050
const CAST_DB := -8.0
const LOOP_DB := -14.0

# ponytail: unbounded cache keyed by spell data, fine for the few spells of a
# run; make it an LRU if forged spells pile up in one session.
static var _cache := {}


static func is_continuous(body: Dictionary) -> bool:
	return body.shape == "zone" or not body.on_tick.is_empty() \
		or body.motion.any(func(m): return m.type == "orbit")


## Plays the sound of one emitted body: a loop on the body if it is
## continuous, else a one-shot left in the world where it was cast.
static func play(spell: Dictionary, body: Dictionary, depth: int, node: Node2D, world: Node) -> void:
	var p := AudioStreamPlayer2D.new()
	p.autoplay = true  # also when the world enters the tree later
	p.bus = "SFX"
	if is_continuous(body):
		p.stream = loop_stream(spell.element, body, depth)
		p.volume_db = LOOP_DB - 3.0 * depth
		node.add_child(p)
	else:
		p.stream = cast_stream(spell.element, body, depth)
		p.volume_db = CAST_DB - 4.0 * depth
		p.position = node.position
		p.finished.connect(p.queue_free)
		world.add_child(p)


static func _pitch(body: Dictionary, depth: int) -> float:
	return clampf(pow(6.0 / body.size, 0.25), 0.5, 1.6) * (1.0 + 0.2 * depth)


static func cast_stream(element: String, body: Dictionary, depth: int) -> AudioStreamWAV:
	var key := ["cast", element, body.hash(), depth]
	if not _cache.has(key):
		var length: float = 0.45 if body.shape == "zone" else 0.3 - body.speed / 1400.0 * 0.12
		_cache[key] = _wav(_cast(element, _pitch(body, depth), length, hash(key)), false)
	return _cache[key]


static func loop_stream(element: String, body: Dictionary, depth: int) -> AudioStreamWAV:
	var key := ["loop", element, body.hash(), depth]
	if not _cache.has(key):
		_cache[key] = _wav(_loop(element, _pitch(body, depth), hash(key)), true)
	return _cache[key]


## A short decaying sound, its texture set by the element.
static func _cast(element: String, pitch: float, length: float, seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / length
		var noise := rng.randf_range(-1.0, 1.0)
		var f := 0.0
		var s := 0.0
		match element:
			"fire":  # filtered roar + crackles
				lp += (noise - lp) * 0.2
				s = lp * 2.5 + (rng.randf_range(-1.0, 1.0) if rng.randf() < 0.02 else 0.0)
			"ice":  # rising glassy chime
				f = 1200.0 * pitch * (1.0 + 0.3 * k)
				s = sin(phase) * 0.6 + sin(phase * 2.76) * 0.3 + noise * 0.1 * (1.0 - k)
			"lightning":  # falling square zap + static
				f = 900.0 * pitch * (1.0 - 0.8 * k)
				s = signf(sin(phase)) * 0.4 + noise * 0.4 * (1.0 - k)
			"poison":  # wobbly low blob
				f = 220.0 * pitch * (1.0 + 0.3 * sin(t * 40.0))
				s = sin(phase) * 0.7 + sin(phase * 2.0) * 0.3
			"arcane":  # rising detuned sweep
				f = 440.0 * pitch * (1.0 + k) + 20.0 * sin(t * 30.0)
				s = sin(phase) * 0.5 + sin(phase * 1.01 + 1.0) * 0.4
			_:  # physical: falling thump + whoosh
				lp += (noise - lp) * 0.1
				f = 160.0 * pitch * (1.0 - 0.6 * k)
				s = sin(phase) * 0.8 + lp * (1.0 - k)
		phase += TAU * f / RATE
		out[i] = s * minf(1.0, t / 0.01) * pow(1.0 - k, 2.0)
	return out


## One second that loops seamlessly: whole Hz frequencies, periodic modulations.
static func _loop(element: String, pitch: float, seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := PackedFloat32Array()
	out.resize(RATE)
	var lp := 0.0
	var hz := func(f: float) -> float: return roundf(f * pitch)
	for i in RATE:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var s := 0.0
		match element:
			"fire":  # crackling fire
				lp += (noise - lp) * 0.15
				s = lp * 1.5 * (0.7 + 0.3 * sin(TAU * 3.0 * t)) \
					+ (rng.randf_range(-0.6, 0.6) if rng.randf() < 0.01 else 0.0)
			"ice":  # shimmer
				s = sin(TAU * hz.call(1320.0) * t) * 0.25 * (0.5 + 0.5 * sin(TAU * 3.0 * t)) \
					+ sin(TAU * hz.call(1760.0) * t) * 0.2 * (0.5 + 0.5 * sin(TAU * 5.0 * t + 1.0))
			"lightning":  # electric buzz
				s = signf(sin(TAU * hz.call(110.0) * t)) * 0.2 + noise * 0.15 * (0.5 + 0.5 * sin(TAU * 7.0 * t))
			"poison":  # bubbles, 6 per second
				var tb := fmod(t * 6.0, 1.0) / 6.0
				s = sin(TAU * (300.0 * pitch + 2000.0 * tb) * tb) * exp(-tb * 40.0) * 0.6
			"arcane":  # beating hum
				s = sin(TAU * hz.call(220.0) * t) * 0.35 + sin(TAU * (hz.call(220.0) + 1.0) * t) * 0.35 \
					+ sin(TAU * hz.call(330.0) * t) * 0.15
			_:  # physical: whirling wind
				lp += (noise - lp) * 0.08
				s = lp * 2.0 * (0.6 + 0.4 * sin(TAU * 4.0 * t))
		out[i] = s
	return out


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w
