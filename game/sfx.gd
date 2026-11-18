class_name Sfx
extends Node
## Game sounds other than the spells (see SpellSound): short retro sounds
## synthesized at startup from the RECIPES below (no files), on the SFX or UI
## bus; and the music of each map (assets/music/<map>.ogg) on the Music bus.
## Autoload (SfxPlayer): the static calls do nothing without it (tests).
## Coop: every peer plays the sounds of the events it gets (RPCs, synced hp).

const RATE := 22050
## name -> wave, frequencies (slid between, or played as notes if "notes"),
## length (s), noise mix, sparkle (random high chimes per second), echo
## (repeats of a resonant tail), volume (dB), bus. Magic flavour: glassy
## bells, sparkles and echoes; enemy hits and hurts stay short and dry.
## Spells cast at -8 dB: the swarm (hits, shots, pickups) stays well under them.
const RECIPES := {
	"hit": {"wave": "bell", "f": [880, 620], "len": 0.06, "noise": 0.3, "db": -22.0},
	"die": {"wave": "bell", "f": [700, 180], "len": 0.25, "noise": 0.2, "sparkle": 30.0, "echo": 1, "db": -16.0},
	"shot": {"wave": "sine", "f": [1100, 420], "len": 0.1, "sparkle": 40.0, "db": -24.0},
	"crate": {"wave": "noise", "f": [0], "len": 0.25, "sparkle": 40.0, "echo": 1, "db": -12.0},
	"boss": {"wave": "saw", "f": [55, 85, 50], "len": 1.6, "noise": 0.3, "sparkle": 6.0, "echo": 2, "db": -6.0},
	"boss_die": {"wave": "bell", "f": [300, 40], "len": 1.4, "noise": 0.35, "sparkle": 25.0, "echo": 3, "db": -4.0},
	"blast": {"wave": "saw", "f": [110, 35], "len": 0.45, "noise": 0.75, "echo": 1, "db": -10.0},
	"boom": {"wave": "saw", "f": [70, 45, 18], "len": 1.8, "noise": 0.8, "echo": 3, "db": -2.0},
	"hurt": {"wave": "saw", "f": [240, 110], "len": 0.2, "noise": 0.3, "db": -10.0},
	"death": {"wave": "bell", "f": [440, 55], "len": 1.0, "noise": 0.15, "echo": 3, "db": -6.0},
	"xp": {"wave": "bell", "f": [1500, 1900], "len": 0.07, "echo": 1, "db": -22.0},
	"gold": {"wave": "bell", "f": [1319, 1976], "notes": true, "len": 0.16, "echo": 1, "db": -20.0},
	"mana": {"wave": "bell", "f": [880, 1175, 1568], "notes": true, "len": 0.25, "sparkle": 15.0, "echo": 1, "db": -16.0},
	"life": {"wave": "bell", "f": [523, 659, 784], "notes": true, "len": 0.35, "echo": 2, "db": -14.0},
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
const MIN_SPEED := 0.5  # the sound follows the level-up slow motion down to this (lower turns to rumble)

static var speed := 1.0  # every sound's pitch_scale factor (works with the web's sample playback)

static var _node: Sfx
var _players := {}  # name -> AudioStreamPlayer
var _last := {}  # name -> msec of the last play
var _music: AudioStreamPlayer


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
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = MUSIC_DB
	_music.add_to_group("sfx")
	add_child(_music)
	# Every button of the UI, whoever builds it.
	get_tree().node_added.connect(func(n):
		if n is BaseButton:
			n.pressed.connect(play.bind("click"))
			n.mouse_entered.connect(func(): if not n.disabled: play("hover")))


## Every sound (group "sfx") slows down with the game time.
func _process(_delta: float) -> void:
	var s := maxf(Engine.time_scale, MIN_SPEED)
	if s == speed:
		return
	speed = s
	for p in get_tree().get_nodes_in_group("sfx"):
		p.pitch_scale = p.get_meta("pitch", 1.0) * s


func _exit_tree() -> void:
	_node = null


static func play(sound: String) -> void:
	if not _node:
		return
	var now := Time.get_ticks_msec()
	if now - _node._last.get(sound, -100000) < GAP * 1000.0:
		return
	_node._last[sound] = now
	var p: AudioStreamPlayer = _node._players[sound]
	p.set_meta("pitch", randf_range(0.94, 1.06) if p.bus == "SFX" else 1.0)
	p.pitch_scale = p.get_meta("pitch") * speed
	p.play()


## The music of `map`, looped; "" (or a map without music) stops it.
static func music(map: String) -> void:
	if not _node:
		return
	var path := "res://assets/music/%s.ogg" % map
	var m := _node._music
	if map == "" or not ResourceLoader.exists(path):
		m.stop()
		return
	var s: AudioStreamOggVorbis = load(path)
	s.loop = true
	if m.stream != s or not m.playing:
		m.stream = s
		m.play()


## Holds the music where it is (pause menu), or lets it go on.
static func pause_music(paused: bool) -> void:
	if _node:
		_node._music.stream_paused = paused


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
