class_name Settings
## Player options, saved in user://settings.cfg: language, volumes, fullscreen,
## UI scale and the rebindable keys (first key of each action in REBINDABLE).
## Language: the saved choice, else (web) the website's, else the system's;
## on web it is shared with the website through localStorage (WEB_LANG).

const PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX", "UI"]
const REBINDABLE := {"move_up": "Up", "move_down": "Down", "move_left": "Left",
	"move_right": "Right", "pause": "Pause"}
const LANGUAGES := {"en": "English", "fr": "Français"}
const WEB_LANG := "octo.lang"  # localStorage key, shared with the website
const UI_SCALES := [0.75, 1.0, 1.25, 1.5]

static var cfg := ConfigFile.new()
## The last input came from a gamepad (set by ui/ui.gd): button prompts, and
## the mage stops aiming at the mouse.
static var pad := false
static var playstation := false  # that gamepad is a PlayStation one


## Name of a gamepad button for the prompts: Xbox name, or PlayStation one.
static func pad_button(xbox: String, ps: String) -> String:
	return ps if playstation else xbox


## Updates `pad` from an input event; true when it changed.
static func track_device(e: InputEvent) -> bool:
	var was := pad
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		pad = true
		var n := Input.get_joy_name(e.device)
		if OS.has_feature("web"):  # Godot names a standard pad "Standard Gamepad Mapping": ask the browser
			n = str(JavaScriptBridge.eval("(navigator.getGamepads()[%d] || {}).id || ''" % e.device))
		n = n.to_lower()
		playstation = ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony", "054c",
			"wireless controller"].any(func(w): return n.contains(w))
	elif e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch \
			or (e is InputEventMouseMotion and e.relative.length() > 2.0):
		pad = false
	return pad != was


static func get_value(section: String, key: String, default: Variant) -> Variant:
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	cfg.set_value(section, key, value)
	apply()


static func save() -> void:
	cfg.save(PATH)


static func load_and_apply() -> void:
	cfg.load(PATH)  # missing file: defaults
	apply()


## The game's language: "en" or "fr".
static func language() -> String:
	var lang: String = get_value("general", "language", "")
	if OS.has_feature("web"):
		var site := str(JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % WEB_LANG))
		lang = site if site else lang
	if not LANGUAGES.has(lang):
		lang = OS.get_locale_language()
	return lang if LANGUAGES.has(lang) else "en"


static func set_language(lang: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('%s', '%s')" % [WEB_LANG, lang])
	set_value("general", "language", lang)


static func apply() -> void:
	TranslationServer.set_locale(language())
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			# Not add_bus(): on the web its sample buses insert the new bus at
			# index 0 (Godot 4.7), the Master no longer reaches the speakers and
			# the browser plays nothing. A new count appends, sent to Master.
			AudioServer.bus_count += 1
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		var v: float = get_value("audio", bus, 1.0)
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, linear_to_db(v))
		AudioServer.set_bus_mute(i, v <= 0.0)
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var full: bool = get_value("display", "fullscreen", false)
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	for action in REBINDABLE:
		var code: int = get_value("controls", action, 0)
		var ev := key_event(action)
		if code and ev:
			ev.physical_keycode = code


## The rebindable key of an action (the first key event in the InputMap).
static func key_event(action: String) -> InputEventKey:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev
	return null


## Name of the key on the player's layout (Z on AZERTY), where Godot knows it.
static func key_name(action: String) -> String:
	var ev := key_event(action)
	if not ev:
		return "?"
	var code := ev.physical_keycode
	if OS.get_name() in ["Windows", "macOS", "Linux"] and DisplayServer.get_name() != "headless":
		code = DisplayServer.keyboard_get_label_from_physical(code)
	return OS.get_keycode_string(code)
