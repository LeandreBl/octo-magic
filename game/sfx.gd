class_name Sfx
extends Node
## Game sounds other than the spells (see SpellSound): short retro sounds
## synthesized at startup from the RECIPES below (no files), on the SFX or UI
## bus; and the music (assets/music/<track>.ogg, CREDITS.md) on the Music bus.
## Autoload (SfxPlayer): the static calls do nothing without it (tests).
## Coop: every peer plays the sounds of the events it gets (RPCs, synced hp).

const RATE := 22050
## name -> wave, frequencies (slid between, or played as notes if "notes"),
## length (s), noise mix, sparkle (random high chimes per second), echo
## (repeats of a resonant tail), volume (dB), bus. Magic flavour: glassy
## bells, sparkles and echoes; enemy hits and hurts stay short and dry.
## Spells cast at -8 dB: the swarm (hits, pickups) stays well under them; enemy shots
## (cast from up to a screen away, faded by the distance) just under.
const RECIPES := {
	"hit": {"wave": "bell", "f": [880, 620], "len": 0.06, "noise": 0.3, "db": -22.0},
	"die": {"wave": "bell", "f": [700, 180], "len": 0.25, "noise": 0.2, "sparkle": 30.0, "echo": 1, "db": -16.0},
	"shot": {"wave": "bell", "f": [1100, 380], "len": 0.18, "noise": 0.2, "sparkle": 30.0, "db": -12.0},  # heard from afar (ranged enemies)
	"boss": {"wave": "saw", "f": [55, 85, 50], "len": 1.6, "noise": 0.3, "sparkle": 6.0, "echo": 2, "db": -6.0},
	"boss_die": {"wave": "bell", "f": [300, 40], "len": 1.4, "noise": 0.35, "sparkle": 25.0, "echo": 3, "db": -4.0},
	"blast": {"wave": "saw", "f": [110, 35], "len": 0.45, "noise": 0.75, "echo": 1, "db": -10.0},
	"boom": {"wave": "saw", "f": [70, 45, 18], "len": 1.8, "noise": 0.8, "echo": 3, "db": -2.0},
	"hurt": {"wave": "saw", "f": [240, 110], "len": 0.2, "noise": 0.3, "db": -10.0},
	"death": {"wave": "bell", "f": [440, 55], "len": 1.0, "noise": 0.15, "echo": 3, "db": -6.0},
	"gold": {"wave": "bell", "f": [1319, 1976], "notes": true, "len": 0.16, "echo": 1, "db": -20.0},
	"mana": {"wave": "bell", "f": [880, 1175, 1568], "notes": true, "len": 0.25, "sparkle": 15.0, "echo": 1, "db": -16.0},
	"life": {"wave": "bell", "f": [523, 659, 784], "notes": true, "len": 0.35, "echo": 2, "db": -14.0},
	"quad": {"wave": "saw", "f": [220, 330, 440, 660], "notes": true, "len": 0.6, "sparkle": 20.0, "echo": 2, "db": -10.0},
	"scroll": {"wave": "bell", "f": [523, 659, 784, 1047, 1319], "notes": true, "len": 0.6, "sparkle": 20.0, "echo": 3, "db": -10.0},
	"level_up": {"wave": "bell", "f": [392, 523, 659, 784, 1047, 1568], "notes": true, "len": 0.7, "sparkle": 25.0, "echo": 3, "db": -12.0},
	"wave": {"wave": "bell", "f": [110, 104], "len": 1.2, "sparkle": 4.0, "echo": 2, "db": -8.0},
	"game_over": {"wave": "bell", "f": [392, 330, 262, 196], "notes": true, "len": 1.6, "echo": 3, "db": -6.0},
	"click": {"wave": "bell", "f": [1400, 1250], "len": 0.05, "echo": 1, "db": -18.0, "bus": "UI"},
	"hover": {"wave": "sine", "f": [2400, 2600], "len": 0.03, "db": -28.0, "bus": "UI"},
}
const ECHO_DELAY := 0.11  # s between repeats of the tail
const ECHO_FEEDBACK := 0.4
const GAP := 0.04  # s: the same sound twice closer than this plays once (boss rings, swarms)
const MUSIC_DB := -6.0
const MUSIC_FADE := 3.0  # s: a track fades out over the next one fading in
## assets/music: a run starts on one (the host's pick), then shuffles through the others.
const TRACKS := ["crypt", "ancient_evil", "catacombs", "apocalypse", "witch_lair", "dark_shrine", "dark_forest"]
## Sounds placed in the world (Sfx.play's `at`, spells) fade to silence this
## far (px) from the local mage, who hears them (AudioListener2D on it).
const HEARING := 900.0
const MIN_SPEED := 0.5  # the sound follows the level-up slow motion down to this (lower turns to rumble)

static var speed := 1.0  # every sound's pitch_scale factor (works with the web's sample playback)

static var _node: Sfx
var _players := {}  # name -> AudioStreamPlayer
var _last := {}  # name -> msec of the last play
var _music: AudioStreamPlayer  # the one playing; _music_out the one fading out
var _music_out: AudioStreamPlayer
var _track := ""  # the one playing


func _enter_tree() -> void:
	if DisplayServer.get_name() == "headless":
		return  # nobody listens, and streams playing at quit leak (coop tests)
	_node = self
	process_mode = PROCESS_MODE_ALWAYS  # menus and level-ups pause the game, not the sound
	for n in RECIPES:
		var r: Dictionary = RECIPES[n]
		var p := AudioStreamPlayer.new()
		p.stream = stream(n)
		p.volume_db = r.db
		p.bus = r.get("bus", "SFX")
		p.max_polyphony = 4
		p.add_to_group("sfx")
		add_child(p)
		_players[n] = p
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.add_to_group("sfx")
		# Ends without a fade if the position does not move (web sample playback).
		m.finished.connect(func(): if m == _music and _track != "": music(TRACKS.filter(func(t): return t != _track).pick_random()))
		add_child(m)
		_music_out = _music
		_music = m
	# Every button of the UI, whoever builds it, once: a button moved to
	# another parent (remove_child, add_child) enters the tree again.
	get_tree().node_added.connect(func(n):
		if n is BaseButton and not n.has_meta("sfx"):
			n.set_meta("sfx", true)
			n.pressed.connect(play.bind("click"))
			n.mouse_entered.connect(func(): if not n.disabled: play("hover")))


## Every sound (group "sfx") slows down with the game time.
func _process(_delta: float) -> void:
	# The track near its end: the next one (another at random) fades in over it.
	if _track != "" and _music.playing and not _music.stream_paused \
			and _music.stream.get_length() - _music.get_playback_position() < MUSIC_FADE:
		music(TRACKS.filter(func(t): return t != _track).pick_random())
	var s := maxf(Engine.time_scale, MIN_SPEED)
	if s == speed:
		return
	speed = s
	for p in get_tree().get_nodes_in_group("sfx"):
		p.pitch_scale = p.get_meta("pitch", 1.0) * s


func _exit_tree() -> void:
	_node = null


## `at`: a world position, the sound is panned and fades with the distance
## to the local mage; null: heard as is (UI, waves, the mage's own hurt).
static func play(sound: String, at: Variant = null) -> void:
	if not _node:
		return
	var now := Time.get_ticks_msec()
	if now - _node._last.get(sound, -100000) < GAP * 1000.0:
		return
	_node._last[sound] = now
	var p: AudioStreamPlayer = _node._players[sound]
	if at is Vector2:
		var p2 := AudioStreamPlayer2D.new()
		p2.stream = p.stream
		p2.volume_db = p.volume_db
		p2.bus = p.bus
		p2.max_distance = HEARING
		p2.position = at  # the autoload is a plain Node: local is global
		p2.set_meta("pitch", randf_range(0.94, 1.06))
		p2.pitch_scale = p2.get_meta("pitch") * speed
		p2.add_to_group("sfx")
		p2.finished.connect(p2.queue_free)
		_node.add_child(p2)
		p2.play()
		return
	p.set_meta("pitch", randf_range(0.94, 1.06) if p.bus == "SFX" else 1.0)
	p.pitch_scale = p.get_meta("pitch") * speed
	p.play()


## Plays `track` to its end, then another of TRACKS at random, each fading
## into the next; "" (or a track that is not there) fades the music out.
static func music(track: String) -> void:
	if not _node:
		return
	var path := "res://assets/music/%s.ogg" % track
	if track == "" or not ResourceLoader.exists(path):
		_node._track = ""
		_node._fade(_node._music, false)
		return
	if track == _node._track and _node._music.playing:
		return
	_node._track = track
	var m := _node._music_out
	_node._music_out = _node._music
	_node._music = m
	_node._fade(_node._music_out, false)
	m.stream = load(path)
	m.volume_db = -60.0
	m.stream_paused = false
	m.play()
	_node._fade(m, true)


## Fades `m` in to MUSIC_DB, or out to silence and stops it.
func _fade(m: AudioStreamPlayer, fade_in: bool) -> void:
	if m.has_meta("tween"):
		(m.get_meta("tween") as Tween).kill()
	if not m.playing:
		return
	var t := create_tween()
	m.set_meta("tween", t)
	t.tween_property(m, "volume_db", MUSIC_DB if fade_in else -60.0, MUSIC_FADE)
	if not fade_in:
		t.tween_callback(m.stop)


## Holds the music where it is (pause menu), or lets it go on.
static func pause_music(paused: bool) -> void:
	if _node:
		_node._music.stream_paused = paused
		_node._music_out.stream_paused = paused
		for m in [_node._music, _node._music_out]:
			var t: Tween = m.get_meta("tween", null)
			if t and t.is_valid() and paused:
				t.pause()
			elif t and t.is_valid():
				t.play()


static func stream(sound: String) -> AudioStreamWAV:
	var r: Dictionary = RECIPES[sound]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	var pcm := PackedByteArray()
	var s := synth(r)
	pcm.resize(s.size() * 2)
	for i in s.size():
		pcm.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	wav.data = pcm
	return wav


## sfxr-like: one oscillator sliding through (or stepping over) the
## frequencies, some noise, a fast attack and a decay.
static func synth(r: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r)
	var f: Array = r.f
	var notes: bool = r.get("notes", false)
	var noise_mix: float = 1.0 if r.wave == "noise" else r.get("noise", 0.0)
	var length: float = r.len
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / length
		var hz: float
		var env := pow(1.0 - k, 2.0)
		if notes:  # each note restarts its own small decay
			var x: float = k * f.size()
			hz = f[mini(int(x), f.size() - 1)]
			env = (1.0 - k) * (1.0 - 0.6 * fmod(x, 1.0))
		else:  # piecewise linear slide
			var x: float = k * (f.size() - 1)
			var j := mini(int(x), maxi(f.size() - 2, 0))
			hz = lerpf(f[j], f[mini(j + 1, f.size() - 1)], x - j)
		phase += TAU * hz / RATE
		var s := 0.0
		match r.wave:
			"sine": s = sin(phase)
			"square": s = signf(sin(phase)) * 0.5
			"saw": s = fmod(phase / TAU, 1.0) * 1.2 - 0.6
			"bell": s = sin(phase) * 0.6 + sin(phase * 2.76) * 0.25 + sin(phase * 5.4) * 0.15 * (1.0 - k)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3  # darker noise
		s = s * (1.0 - noise_mix) + lp * 1.5 * noise_mix
		out[i] = s * minf(1.0, t / 0.005) * env
	# Sparkle: short high chimes scattered over the sound.
	for g in int(r.get("sparkle", 0.0) * length):
		var at := rng.randi_range(0, n - 1)
		var hz := rng.randf_range(2500.0, 5000.0)
		var amp := rng.randf_range(0.1, 0.25) * (1.0 - float(at) / n)
		for i in mini(int(RATE * 0.04), n - at):
			out[at + i] += sin(TAU * hz * i / RATE) * amp * (1.0 - i / (RATE * 0.04))
	# Echo: the sound repeats fainter, a resonant tail.
	var repeats: int = r.get("echo", 0)
	if repeats:
		var d := int(RATE * ECHO_DELAY)
		out.resize(n + d * repeats)
		for i in range(d, n + d * repeats):  # forwards: echoes of echoes
			out[i] += out[i - d] * ECHO_FEEDBACK
	var peak := 0.0
	for x in out:
		peak = maxf(peak, absf(x))
	if peak > 0.9:
		for i in out.size():
			out[i] *= 0.9 / peak
	return out
