extends Node
## Autoload `Online`: the player's account on the online server
## (backend/, NestJS). Firebase email/password login through the Identity
## Toolkit REST API, the same code on web and native. Once logged in, the
## profile follows the account: pulled at login (the server's copy wins
## unless it is empty), pushed on every save, forged .spell bundles with it.
## The forge (/api/forge) and the coop lobby (game/net.gd) use its token.
##
## Server URL: OCTO_SERVER, else the page's origin on web, else
## octo/server_url in project.godot, else the production API. OCTO_AUTH_EMULATOR (host:port) logs in
## on the Firebase Auth emulator instead.

signal changed

const SESSION := "user://session.json"
const WEB_SESSION := "octo.session"  # localStorage key, shared with the website (web/site.js)
const SPELL_ID := "^[\\w-]{1,64}$"
## Login errors, in English (translated where shown, locale/fr.po).
const ERRORS := {"EMAIL_EXISTS": "email already in use", "EMAIL_NOT_FOUND": "invalid credentials",
	"INVALID_PASSWORD": "invalid credentials", "INVALID_LOGIN_CREDENTIALS": "invalid credentials",
	"INVALID_EMAIL": "invalid email", "MISSING_PASSWORD": "missing password",
	"WEAK_PASSWORD": "password too short (6 characters min.)",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too many attempts, try again later", "USER_DISABLED": "account disabled"}

var server := ""
var identity := "https://identitytoolkit.googleapis.com/v1/accounts:"
var secure_token := "https://securetoken.googleapis.com/v1/token?key="
var api_key := ""  # Firebase web API key, from /api/config
var email := ""
var status := ""  # last news, for the account panel (English, translated there)
var _token := ""
var _refresh := ""
var _expires := 0.0  # unix time of _token's end
var _pulling := false
var _pushing := false
var _dirty := false


func _ready() -> void:
	server = OS.get_environment("OCTO_SERVER")
	if server.is_empty() and OS.has_feature("web"):
		server = str(JavaScriptBridge.eval("location.origin"))
	if server.is_empty():
		server = ProjectSettings.get_setting("octo/server_url", "https://octo-magic.api.notdotio.com")
	server = server.trim_suffix("/")
	var emulator := OS.get_environment("OCTO_AUTH_EMULATOR")
	if emulator:
		identity = "http://%s/identitytoolkit.googleapis.com/v1/accounts:" % emulator
		secure_token = "http://%s/securetoken.googleapis.com/v1/token?key=" % emulator
	Profile.saved.connect(_on_saved)
	var s: Variant = _load_session()
	if s is Dictionary and s.get("refresh", "") != "":
		email = str(s.get("email", ""))
		_refresh = str(s.refresh)
		if await _config() and not (await id_token()).is_empty():
			await pull()
		changed.emit()


func logged_in() -> bool:
	return not _refresh.is_empty()


## Logs in (or creates the account), then syncs the profile. Returns an error
## message, or "".
func login(mail: String, password: String, create := false) -> String:
	if api_key.is_empty() and not await _config():
		return "server unreachable"
	var r := await _http(identity + ("signUp" if create else "signInWithPassword") + "?key=" + api_key,
		HTTPClient.METHOD_POST, {"email": mail.strip_edges(), "password": password, "returnSecureToken": true})
	if not r.ok:
		var e: Variant = r.json.get("error") if r.json is Dictionary else null
		var code := str(e.get("message", "")) if e is Dictionary else ""
		return ERRORS.get(code.get_slice(" ", 0), code if code else "identity server unreachable")
	email = str(r.json.get("email", mail))
	_set_session(r.json.idToken, r.json.refreshToken, r.json.expiresIn)
	await pull()
	changed.emit()
	return ""


func logout() -> void:
	email = ""
	_token = ""
	_refresh = ""
	status = ""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.removeItem('%s')" % WEB_SESSION)
	else:
		DirAccess.remove_absolute(SESSION)
	changed.emit()


## ["Authorization: Bearer <ID token>"]; [] when logged out.
func auth_headers() -> PackedStringArray:
	var token := await id_token()
	return PackedStringArray(["Authorization: Bearer " + token] if token else [])


## The Firebase ID token, refreshed when needed; "" when logged out or the
## session is gone.
func id_token() -> String:
	if not logged_in():
		return ""
	if _token.is_empty() or Time.get_unix_time_from_system() > _expires - 60.0:
		var r := await _http(secure_token + api_key, HTTPClient.METHOD_POST,
			"grant_type=refresh_token&refresh_token=" + _refresh.uri_encode(),
			["Content-Type: application/x-www-form-urlencoded"])
		if r.code == 400:  # revoked or expired: log in again
			logout()
			status = "Session expired, log in again."
		if not r.ok:
			return ""
		_set_session(r.json.id_token, r.json.refresh_token, r.json.expires_in)
	return _token


## GET/PUT on the server's /api, logged in. Body: a Dictionary (JSON) or bytes.
func api(path: String, method := HTTPClient.METHOD_GET, body: Variant = null) -> Dictionary:
	var headers := await auth_headers()
	if headers.is_empty():
		return {"ok": false, "code": 401, "body": PackedByteArray(), "json": null}
	return await _http(server + path, method, body, headers)


## The server's profile replaces the local one, with its spell bundles; a new
## account gets the local profile instead.
func pull() -> void:
	var r := await api("/api/profile")
	if not r.ok or not r.json is Dictionary:
		status = "Profile not synced (server unreachable)."
		return
	var d: Dictionary = r.json
	if d.is_empty():
		_push()
		for f in Profile.forged:
			if FileAccess.file_exists(f.file):
				api("/api/spells/" + f.id, HTTPClient.METHOD_PUT, FileAccess.get_file_as_bytes(f.file))
		status = "Profile sent to the server."
		return
	var forged: Array = d.get("forged") if d.get("forged") is Array else []
	DirAccess.make_dir_recursive_absolute("user://spells")
	for f in forged:
		if not f is Dictionary or not RegEx.create_from_string(SPELL_ID).search(str(f.get("id"))):
			continue
		f.file = "user://spells/%s.spell" % f.id  # never a path from the server
		# Always fetched: a local file of that name may be another account's.
		var b := await api("/api/spells/" + f.id)
		if b.ok and b.body.slice(0, 2).get_string_from_ascii() == "PK":
			var file := FileAccess.open(f.file, FileAccess.WRITE)
			file.store_buffer(b.body)
			file.close()
		else:
			DirAccess.remove_absolute(f.file)  # the spell falls back to its JSON, without art
	_pulling = true
	Profile.apply(d)
	Profile.save()
	_pulling = false
	status = "Profile synced."


## A forged spell's bundle, to the server (the profile follows on its save).
func push_spell(id: String, path: String) -> void:
	if logged_in():
		api("/api/spells/" + id, HTTPClient.METHOD_PUT, FileAccess.get_file_as_bytes(path))


func _on_saved() -> void:
	if logged_in() and not _pulling:
		_push()


## One PUT at a time, the last save wins.
func _push() -> void:
	if _pushing:
		_dirty = true
		return
	_pushing = true
	_dirty = true
	while _dirty:
		_dirty = false
		var r := await api("/api/profile", HTTPClient.METHOD_PUT, Profile.to_dict())
		status = "Profile synced." if r.ok else "Profile not synced (server unreachable)."
	_pushing = false


func _config() -> bool:
	var r := await _http(server + "/api/config")
	if not r.ok or not r.json is Dictionary:
		return false
	api_key = str(r.json.get("firebaseApiKey", ""))
	changed.emit()
	return not api_key.is_empty()


func _set_session(token: String, refresh: String, expires_in: Variant) -> void:
	_token = token
	_refresh = refresh
	_expires = Time.get_unix_time_from_system() + float(expires_in)
	var s := JSON.stringify({"email": email, "refresh": _refresh})
	if OS.has_feature("web"):  # JSON of a string is a JS string literal
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [WEB_SESSION, JSON.stringify(s)])
	else:
		FileAccess.open(SESSION, FileAccess.WRITE).store_string(s)


## {email, refresh} of the last login, or null. On web, the website's: logged
## in on the site, logged in in the game.
func _load_session() -> Variant:
	var text := ""
	if OS.has_feature("web"):
		text = str(JavaScriptBridge.eval("localStorage.getItem('%s') || 'null'" % WEB_SESSION))
	elif FileAccess.file_exists(SESSION):
		text = FileAccess.get_file_as_string(SESSION)
	return JSON.parse_string(text) if text else null


## One request: {ok (200), code, body, json (or null)}.
func _http(url: String, method := HTTPClient.METHOD_GET, body: Variant = null, headers := PackedStringArray()) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var err: int
	if body is PackedByteArray:
		err = req.request_raw(url, headers + PackedStringArray(["Content-Type: application/octet-stream"]), method, body)
	elif body is Dictionary:
		err = req.request(url, headers + PackedStringArray(["Content-Type: application/json"]), method, JSON.stringify(body))
	else:
		err = req.request(url, headers, method, str(body) if body != null else "")
	var r: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray()]
	if err == OK:
		r = await req.request_completed
	req.queue_free()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(r[3].get_string_from_utf8()) == OK else null
	return {"ok": r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200, "code": r[1], "body": r[3], "json": parsed}
