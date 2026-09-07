class_name ResidentNeeds
extends RefCounted

var food := 88.0
var rest := 78.0
var light_mood := 72.0
var health := 100.0


func advance(day_fraction: float, is_lit: bool, sleeping: bool, in_bed: bool) -> void:
	food = clampf(food - 36.0 * day_fraction, 0.0, 100.0)
	if sleeping:
		var recovery := 96.0 if in_bed else 48.0
		rest = clampf(rest + recovery * day_fraction, 0.0, 100.0)
	else:
		rest = clampf(rest - 34.0 * day_fraction, 0.0, 100.0)
	var mood_delta := 0.0 if sleeping else (42.0 if is_lit else -30.0)
	light_mood = clampf(light_mood + mood_delta * day_fraction, 0.0, 100.0)
	if food <= 0.0:
		health -= 58.0 * day_fraction
	if rest <= 0.0:
		health -= 30.0 * day_fraction
	if light_mood <= 5.0:
		health -= 5.0 * day_fraction
	health = clampf(health, 0.0, 100.0)


func eat() -> void:
	food = minf(100.0, food + 42.0)


func serialize() -> Dictionary:
	return {"food": food, "rest": rest, "light_mood": light_mood, "health": health}


func deserialize(data: Dictionary) -> void:
	food = clampf(float(data.get("food", 88.0)), 0.0, 100.0)
	rest = clampf(float(data.get("rest", 78.0)), 0.0, 100.0)
	light_mood = clampf(float(data.get("light_mood", 72.0)), 0.0, 100.0)
	health = clampf(float(data.get("health", 100.0)), 0.0, 100.0)
