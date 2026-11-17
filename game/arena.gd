class_name Arena
extends Node2D
## The run's map, empty for now (objects come with task #92): only its edge is drawn.

const MAPS := ["crypt", "cave", "ruins"]  # one per run: its music for now
const RECT := Rect2(0, 0, 4800, 3200)  # about 4x4 screens: the camera shows a part of it


func _ready() -> void:
	z_index = -1  # under the player, enemies and spells


func _draw() -> void:
	draw_rect(RECT, Color(0, 0, 0, 0.6), false, 4.0)
