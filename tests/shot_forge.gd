extends SceneTree
## Screenshots of the spell forge: godot --script tests/shot_forge.gd -- out
## -> out.png (words written), out_forging.png (two spells being forged),
## out_front.png (the first one in the foreground).
## Needs a display (not --headless).


func _initialize() -> void:
	await process_frame  # the autoloads come after _initialize
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	root.get_node("/root/Profile").blank_scrolls = 5
	main.get_node("UI").show_screen("forge")
	var forge: Control = main.get_node("UI").screens.forge
	var edit: LineEdit = forge.get_meta("focus")
	edit.text = "ignis umbra πῦρ fulminis"
	var out: String = OS.get_cmdline_user_args()[0]
	for i in 60:
		await process_frame
	root.get_texture().get_image().save_png(out + ".png")
	for i in 2:  # two spells being forged, the first one for longer
		var job := {"id": "shot%d" % i, "slot": "primary", "spell": Spell.base(),
			"started": Time.get_ticks_msec() - 60000 / (i + 1), "text": "ignis umbra"}
		main.forge_jobs.append(job)
		forge._on_started(job)
	for i in 2:
		await process_frame
	root.get_texture().get_image().save_png(out + "_forging.png")
	forge._focus = "shot0"
	for i in 2:
		await process_frame
	root.get_texture().get_image().save_png(out + "_front.png")
	quit()
