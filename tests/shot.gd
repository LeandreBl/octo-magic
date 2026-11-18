extends SceneTree
## Screenshot of a run start: godot --script tests/shot.gd -- out.png
## Needs a display (not --headless).


func _initialize() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.start_run()
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
