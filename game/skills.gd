class_name Skills
## Skills: one equipped next to the spell (right click / RB / space / LB).
## Not spells: fixed effects on the mages, not on the enemies. The host
## applies them; peers only draw (see Player.use_skill).

const LIST := {
	"shield": {"name": "Bouclier", "desc": "Aucun dégât subi pendant 3 s.", "unlock": "",
		"mana": 30, "cooldown": 12.0, "duration": 3.0, "color": "#7fd6ff"},
	"heal_zone": {"name": "Cercle de soin", "desc": "Une zone qui soigne les mages de 12 PV/s pendant 6 s.", "unlock": "boss3",
		"mana": 40, "cooldown": 15.0, "duration": 6.0, "radius": 90.0, "hp": 12.0, "color": "#6dff8a"},
	"mana_zone": {"name": "Puits de mana", "desc": "Une zone qui rend 40 mana/s aux mages pendant 6 s.", "unlock": "rich",
		"mana": 0, "cooldown": 18.0, "duration": 6.0, "radius": 90.0, "mana_regen": 40.0, "color": "#6d8aff"},
}


## A lingering circle: every mage standing in it gets hp / mana per second.
class Zone extends Node2D:
	var skill: Dictionary
	var age := 0.0

	func _physics_process(delta: float) -> void:
		age += delta
		if age >= skill.duration:
			queue_free()
			return
		if multiplayer.is_server():
			for p in get_tree().get_nodes_in_group("players"):
				if p.hp > 0.0 and p.global_position.distance_to(global_position) <= skill.radius + p.radius:
					p.heal(skill.get("hp", 0.0) * delta)
					p.mana = minf(p.max_mana, p.mana + skill.get("mana_regen", 0.0) * delta)
		queue_redraw()

	func _draw() -> void:
		var c := Color(skill.color)
		draw_circle(Vector2.ZERO, skill.radius, Color(c, 0.18))
		draw_arc(Vector2.ZERO, skill.radius, 0, TAU, 48, c, 2.0)
