class_name Sfx
extends Node
## Game sounds other than the spells (see SpellSound): short retro sounds
## synthesized at startup from the RECIPES below (no files), on the SFX or UI
## bus; and the music of each map (assets/music/<map>.ogg) on the Music bus.
## Autoload (SfxPlayer): the static calls do nothing without it (tests).
## Coop: every peer plays the sounds of the events it gets (RPCs, synced hp).

const RATE := 22050
## name -> wave, frequencies (slid between, or played as notes if "notes"),
## length (s), noise mix, volume (dB), bus. Spells cast at -8 dB: the
## swarm (hits, shots, pickups) stays well under them.
const RECIPES := {
	"hit": {"wave": "square", "f": [320, 120], "len": 0.05, "noise": 0.5, "db": -22.0},
	"die": {"wave": "square", "f": [420, 60], "len": 0.18, "noise": 0.35, "db": -16.0},
	"shot": {"wave": "square", "f": [760, 280], "len": 0.08, "db": -24.0},
	"crate": {"wave": "noise", "f": [0], "len": 0.22, "db": -12.0},
	"boss": {"wave": "saw", "f": [55, 85, 50], "len": 1.6, "noise": 0.35, "db": -6.0},
	"boss_die": {"wave": "saw", "f": [180, 25], "len": 1.4, "noise": 0.5, "db": -4.0},
	"hurt": {"wave": "saw", "f": [240, 110], "len": 0.2, "noise": 0.3, "db": -10.0},
	"death": {"wave": "saw", "f": [330, 40], "len": 1.0, "noise": 0.2, "db": -6.0},
	"xp": {"wave": "sine", "f": [1150, 1500], "len": 0.06, "db": -22.0},
	"gold": {"wave": "square", "f": [988, 1319], "notes": true, "len": 0.14, "db": -22.0},
	"scroll": {"wave": "sine", "f": [523, 659, 784, 1047], "notes": true, "len": 0.5, "db": -10.0},
	"level_up": {"wave": "square", "f": [392, 523, 659, 784, 1047], "notes": true, "len": 0.6, "db": -14.0},
	"wave": {"wave": "bell", "f": [110, 104], "len": 1.2, "db": -8.0},
	"game_over": {"wave": "sine", "f": [392, 330, 262, 196], "notes": true, "len": 1.6, "db": -6.0},
	"click": {"wave": "square", "f": [900, 700], "len": 0.035, "db": -18.0, "bus": "UI"},
	"hover": {"wave": "sine", "f": [1800], "len": 0.02, "db": -28.0, "bus": "UI"},
}
const GAP := 0.04  # s: the same sound twice closer than this plays once (boss rings, swarms)
const MUSIC_DB := -6.0

static var _node: Sfx
var _players := {}  # name -> AudioStreamPlayer
var _last := {}  # name -> msec of the last play
var _music: AudioStreamPlayer


func _enter_tree() -> void:
	_node = self
	process_mode = PROCESS_MODE_ALWAYS  # menus and level-ups pause the game, not the sound
	for n in RECIPES:
		var r: Dictionary = RECIPES[n]
		var p := AudioStreamPlayer.new()
		p.stream = stream(n)
		p.volume_db = r.db
		p.bus = r.get("bus", "SFX")
		p.max_polyphony = 4
		add_child(p)
		_players[n] = p
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	# Every button of the UI, whoever builds it.
	get_tree().node_added.connect(func(n):
		if n is BaseButton:
			n.pressed.connect(play.bind("click"))
			n.mouse_entered.connect(func(): if not n.disabled: play("hover")))


static func play(sound: String) -> void:
	if not _node:
		return
	var now := Time.get_ticks_msec()
	if now - _node._last.get(sound, -100000) < GAP * 1000.0:
		return
	_node._last[sound] = now
	var p: AudioStreamPlayer = _node._players[sound]
	p.pitch_scale = randf_range(0.94, 1.06) if p.bus == "SFX" else 1.0
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
	return out
