extends Node
## Autoload `Online`: the player's account on the online server
## (backend/, NestJS). Firebase email/password or Google login through the
## Identity Toolkit REST API. Google: on web through the website's account
## page (web/site.js); native in the system browser, which comes back on a
## local port (GOOGLE_PORT). An account has several
## characters, each with its profile; once logged in, the profile is the
## active character's: pulled at login (the server's copy wins; an account
## without characters gets one from the local profile), pushed on every save,
## forged .spell bundles (per account) with it.
## The forge (/api/forge) and the coop lobby (game/net.gd) use its token.
##
## Server URL: OCTO_SERVER, else the page's origin on web, else
## octo/server_url in project.godot, else the production API. OCTO_AUTH_EMULATOR (host:port) logs in
## on the Firebase Auth emulator instead.

signal changed

const SESSION := "user://session.json"
const WEB_SESSION := "octo.session"  # localStorage key, shared with the website (web/site.js)
## The native Google login's redirect, http://localhost:GOOGLE_PORT/, is
## registered on the Google OAuth client: change both together.
const GOOGLE_PORT := 47815
const GOOGLE_PAGE := "<!doctype html><meta charset=utf-8><title>Octo Magic</title><p>Octo Magic: back to the game, you can close this tab."
const SPELL_ID := "^[\\w-]{1,64}$"
## Login errors, in English (translated where shown, locale/fr.po).
const ERRORS := {"EMAIL_EXISTS": "email already in use", "EMAIL_NOT_FOUND": "invalid credentials",
	"INVALID_PASSWORD": "invalid credentials", "INVALID_LOGIN_CREDENTIALS": "invalid credentials",
	"INVALID_EMAIL": "invalid email", "MISSING_PASSWORD": "missing password",
	"WEAK_PASSWORD": "password too short (6 characters min.)",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too many attempts, try again later", "USER_DISABLED": "account disabled",
	"INVALID_IDP_RESPONSE": "Google login cancelled or refused",
	"NEED_CONFIRMATION": "this email has a password account: log in with the password, Google will be linked to it"}

var server := ""
var identity := "https://identitytoolkit.googleapis.com/v1/accounts:"
var secure_token := "https://securetoken.googleapis.com/v1/token?key="
var api_key := ""  # Firebase web API key, from /api/config
var email := ""
var character := ""  # active character's id, kept in the session
var characters := []  # the account's [{id, name, spell, updatedAt}], from the last pull
var status := ""  # last news, for the account panel (English, translated there)
var _token := ""
var _refresh := ""
var _expires := 0.0  # unix time of _token's end
var _pulling := false
var _pushing := false
var _dirty := false
var _pending := []  # [character id, profile] of the last save, for _push
var _google: TCPServer  # the native Google login waiting for the browser
var _link := ""  # Google ID token to link to the account at the next password login


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
		character = str(s.get("character", ""))
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
	if r.ok and _link:  # see login_google()
		var link := _link
		_link = ""
		var l := await _idp({"idToken": r.json.idToken, "postBody": "id_token=%s&providerId=google.com" % link,
			"requestUri": "http://localhost"})
		if l.ok:
			r = l
	return await _logged_in(r, mail)


## Logs in with Google: on web, the website's account page does it and comes
## back to the game; native, in the system browser, back on GOOGLE_PORT.
## Returns an error message, or "".
func login_google() -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.top.location.assign('/account?google')")
		return ""
	if api_key.is_empty() and not await _config():
		return "server unreachable"
	var uri := "http://localhost:%d/" % GOOGLE_PORT
	var r := await _http(identity + "createAuthUri?key=" + api_key, HTTPClient.METHOD_POST,
		{"providerId": "google.com", "continueUri": uri, "authFlowType": "CODE_FLOW"})  # ?code=, a #fragment never reaches the port
	if not r.ok:
		return _error(r)
	if _google:
		_google.stop()  # a login left in the browser: this one replaces it
	var tcp := TCPServer.new()
	_google = tcp
	if tcp.listen(GOOGLE_PORT, "127.0.0.1") != OK:
		return "local port %d busy" % GOOGLE_PORT
	OS.shell_open(str(r.json.authUri))
	# ponytail: reads only the first chunk of each request, enough for its first line.
	var query := ""
	var peers: Array[StreamPeerTCP] = []
	var deadline := Time.get_ticks_msec() + 600000
	while query.is_empty() and tcp.is_listening() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if tcp.is_connection_available():
			peers.append(tcp.take_connection())
		for p in peers:
			p.poll()
			if p.get_status() != StreamPeerTCP.STATUS_CONNECTED or p.get_available_bytes() == 0:
				continue
			var path := p.get_utf8_string(p.get_available_bytes()).get_slice("\r\n", 0).get_slice(" ", 1)
			var back := path.begins_with("/?")  # GET /?state=…&code=… (a favicon gets an empty page)
			p.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n"
				+ (GOOGLE_PAGE if back else "")).to_utf8_buffer())
			p.disconnect_from_host()
			if back:
				query = path
	tcp.stop()
	if query.is_empty():
		return "Google login cancelled or refused"
	r = await _idp({"requestUri": uri + query.trim_prefix("/"), "sessionId": r.json.sessionId, "returnIdpCredential": true})
	if r.ok and r.json is Dictionary and r.json.get("needConfirmation", false):
		_link = str(r.json.get("oauthIdToken", ""))
		return ERRORS.NEED_CONFIRMATION
	return await _logged_in(r, "")


func _idp(body: Dictionary) -> Dictionary:
	body.returnSecureToken = true
	return await _http(identity + "signInWithIdp?key=" + api_key, HTTPClient.METHOD_POST, body)


## The end of a login: the session, then the profile. Returns an error message, or "".
func _logged_in(r: Dictionary, mail: String) -> String:
	if not r.ok:
		return _error(r)
	email = str(r.json.get("email", mail))
	_set_session(r.json.idToken, r.json.refreshToken, r.json.expiresIn)
	await pull()
	changed.emit()
	return ""


func _error(r: Dictionary) -> String:
	var e: Variant = r.json.get("error") if r.json is Dictionary else null
	var code := str(e.get("message", "")) if e is Dictionary else ""
	return ERRORS.get(code.get_slice(" ", 0), code if code else "identity server unreachable")


func logout() -> void:
	email = ""
	character = ""
	characters = []
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


## Makes `id` the active character and loads its profile.
func select(id: String) -> void:
	character = id
	_save_session()
	await pull()
	changed.emit()


## A new character with a fresh profile, made active. Returns an error
## message, or "".
func create_character(char_name: String, spell: String) -> String:
	var r := await api("/api/characters", HTTPClient.METHOD_POST,
		{"name": char_name, "spell": spell, "profile": {"spells": {"primary": spell}}})
	if not r.ok or not r.json is Dictionary:
		var e: Variant = r.json.get("error") if r.json is Dictionary else null
		return str(e) if e else "server unreachable"
	await select(str(r.json.id))
	return ""


## The active character's profile replaces the local one, with its spell
## bundles (no saved active character: the first one). An account without
## characters gets one from the local profile.
func pull() -> void:
	var l := await api("/api/characters")
	if not l.ok or not l.json is Array:
		status = "Profile not synced (server unreachable)."
		return
	characters = l.json
	if characters.is_empty():
		var c := await api("/api/characters", HTTPClient.METHOD_POST,
			{"name": "Mage", "spell": Profile.spells.primary, "profile": Profile.to_dict()})
		if not c.ok:
			status = "Profile not synced (server unreachable)."
			return
		characters = [c.json]
		character = str(c.json.id)
		_save_session()
		for f in Profile.forged:
			if FileAccess.file_exists(f.file):
				api("/api/spells/" + f.id, HTTPClient.METHOD_PUT, FileAccess.get_file_as_bytes(f.file))
		status = "Profile sent to the server."
		return
	if not characters.any(func(c): return c is Dictionary and str(c.get("id")) == character):
		character = str(characters[0].id)
		_save_session()
	var r := await api("/api/characters/%s/profile" % character.uri_encode())
	if not r.ok or not r.json is Dictionary:
		status = "Profile not synced (server unreachable)."
		return
	var d: Dictionary = r.json
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
	if logged_in() and not _pulling and not character.is_empty():
		_push()


## One PUT at a time, the last save wins. Taken at the save: a character
## switch meanwhile does not send one character's profile to the other.
func _push() -> void:
	_pending = [character, Profile.to_dict()]
	if _pushing:
		_dirty = true
		return
	_pushing = true
	_dirty = true
	while _dirty:
		_dirty = false
		var r := await api("/api/characters/%s/profile" % _pending[0].uri_encode(), HTTPClient.METHOD_PUT, _pending[1])
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
	_save_session()


func _save_session() -> void:
	var s := JSON.stringify({"email": email, "refresh": _refresh, "character": character})
	if OS.has_feature("web"):  # JSON of a string is a JS string literal
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [WEB_SESSION, JSON.stringify(s)])
	else:
		FileAccess.open(SESSION, FileAccess.WRITE).store_string(s)


## {email, refresh, character} of the last login, or null. On web, the website's: logged
## in on the site, logged in in the game.
func _load_session() -> Variant:
	var text := ""
	if OS.has_feature("web"):
		text = str(JavaScriptBridge.eval("localStorage.getItem('%s') || 'null'" % WEB_SESSION))
	elif FileAccess.file_exists(SESSION):
		text = FileAccess.get_file_as_string(SESSION)
	return JSON.parse_string(text) if text else null


## One request: {ok (2xx), code, body, json (or null)}.
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
	return {"ok": r[0] == HTTPRequest.RESULT_SUCCESS and r[1] >= 200 and r[1] < 300, "code": r[1], "body": r[3], "json": parsed}
