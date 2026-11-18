extends SceneTree
## Coop end to end over WebRTC, the lobby of a running backend/src/lobby/lobby.service.ts
## (OCTO_SERVER, tokens "token-<role>"), driven by backend/server.test.js:
##   godot --headless --script tests/net_e2e.gd -- host
##   godot --headless --script tests/net_e2e.gd -- join CODE
##   godot --headless --script tests/net_e2e.gd -- solo   (no server)
## Prints "E2E OK" on success.

var main: Node


func until(what: String, cond: Callable, seconds := 15.0) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000
	while not cond.call():
		if Time.get_ticks_msec() > end:
			print("E2E FAIL: ", what)
			quit(1)
			await create_timer(10).timeout  # quit happens at the end of the frame
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var profile := "user://e2e_profile_%s.json" % args[0]
	root.get_node("Profile").path = profile  # never touch the real save
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var run: Node = root.get_node("Run")
	var online: Node = root.get_node("Online")
	online._refresh = "e2e"  # logged in, without Firebase
	online._token = "token-" + args[0]
	online._expires = 1e12
	if args[0] == "solo":
		main.start_run()
		await until("solo run", func(): return run.active and main.local_player().run and not get_nodes_in_group("enemies").is_empty())
		main.local_player().hurt(1e6)
		await until("death opens the end screen", func(): return not run.active and main.get_node("UI").current == "end" and paused)
		main.start_run()
		await until("new run", func(): return run.active and main.local_player().hp > 0.0 and not paused)
	elif args[0] == "host":
		main.host_game()
		await until("room code", func(): return main.net.code != "")
		print("CODE ", main.net.code)
		await until("client spawned", func(): return main.get_node_or_null("P2"))
		main.start_run()
		await until("client loadout cleaned and synced", func():
			var p := main.get_node_or_null("P2")
			return p and p.run and p.run.spells.has("primary"))
		await until("client steers its mage", func():
			var p := main.get_node_or_null("P2")
			return p and p.position.distance_to(Arena.START + Vector2(12, 5)) < 1.0)
	else:
		main.join_game(args[1])
		await until("joined and players spawned", func():
			return main.get_node_or_null("P1") and main.get_node_or_null("P2"))
		await until("run started, enemies synced", func():
			return run.active and run.wave == 1 and not get_nodes_in_group("enemies").is_empty())
		await until("loadouts synced back", func():
			return main.get_node("P1").run and main.get_node("P2").run and main.get_node("P2").run.spells.has("primary"))
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)  # fire: the host casts, peers draw it
		await until("cast drawn from the host", func(): return main.get_children().any(func(n): return n is SpellBody))
		main.get_node("P2").position = Arena.START + Vector2(12, 5)  # a free spot: zones push movers out
		await until("back to solo once the host leaves", func(): return not main.multiplayer.multiplayer_peer is WebRTCMultiplayerPeer)
	DirAccess.remove_absolute(profile)
	print("E2E OK")
	quit(0)
