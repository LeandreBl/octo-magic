extends SceneTree
## Not a test: the host's physics time per frame with a full crowd of real
## enemies (main.gd ALIVE_MAX) chasing a still mage, half of them around it.
## Run: godot --headless --script tests/bench_mobs.gd

const RunState := preload("res://game/run.gd")
const ProfileState := preload("res://game/profile.gd")
const Enemy := preload("res://game/enemy.gd")
const Player := preload("res://game/player.gd")

var frame := 0
var total := 0.0


func _initialize() -> void:
	Arena.walk_all()
	var world := Node2D.new()
	root.add_child(world)
	var run := RunState.new()
	var spells := {}
	for e in ProfileState.new().base_spells:
		spells[e.id] = e.spell
	run.start(spells)
	var player := Player.new()
	player.run = run
	player.position = Arena.START
	world.add_child(player)
	player.set_physics_process(false)
	var ground: Array = Arena.walkable(24.0)
	for i in 220:
		var e := Enemy.new()
		e.setup("skeleton", RunState.enemy_stats("skeleton", 1))
		e.hp = 1e6
		e.target = player
		e.position = ground.pick_random() if i % 2 else Arena.START + Vector2.from_angle(randf() * TAU) * randf_range(40, 200)
		world.add_child(e)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 30:  # once they are all in and spread a bit
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	if frame < 150:
		return false
	print("physics: %.2f ms/frame" % (total / 120.0 * 1000.0))
	return true
