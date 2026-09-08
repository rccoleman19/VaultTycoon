extends "res://scripts/game.gd"


func set_speed(speed: int) -> void:
	if breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
		return
	super.set_speed(speed)
