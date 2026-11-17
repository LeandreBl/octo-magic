extends SceneTree
func _initialize() -> void:
	await process_frame
	var o: Node = root.get_node("Online")
	o.server = "http://127.0.0.1:9911"
	o.identity = "http://127.0.0.1:9911/v1/accounts:"
	var err: String = await o.login_google()
	print("ERR=", err, " EMAIL=", o.email, " IN=", o.logged_in())
	quit()
