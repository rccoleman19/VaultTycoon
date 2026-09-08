class_name ResidentNeeds
extends RefCounted

const BASE_MOOD_LOSS_PER_DAY := 18.0
const DARKNESS_MOOD_LOSS_PER_DAY := 30.0
const LOW_NEED_MOOD_LOSS_PER_DAY := 12.0
const LOW_OXYGEN_MOOD_LOSS_PER_DAY := 24.0
const RECREATION_RECOVERY_PER_SECOND := 18.0
const RECREATION_SEEK_THRESHOLD := 35.0
const RECREATION_TARGET := 85.0
const LOW_MOOD_THRESHOLD := 30.0
const BREAK_MOOD_THRESHOLD := 9.0
const SEVERE_MOOD_THRESHOLD := 5.0
const STRESS_BREAK_RECOVERY := 8.0

var food := 88.0
var rest := 78.0
var mood := 72.0
var health := 100.0

# Keep the Slice 1-4 property available to old tests and compatible code while
# treating the value as the resident's overall mood from Slice 5 onward.
var light_mood: float:
	get:
		return mood
	set(value):
		mood = value


func advance(
	day_fraction: float,
	is_lit: bool,
	sleeping: bool,
	in_bed: bool,
	recreation_active := false,
	low_oxygen := false,
) -> void:
	food = clampf(food - 60.0 * day_fraction, 0.0, 100.0)
	if sleeping:
		var recovery := 96.0 if in_bed else 48.0
		rest = clampf(rest + recovery * day_fraction, 0.0, 100.0)
	else:
		rest = clampf(rest - 34.0 * day_fraction, 0.0, 100.0)
	if not recreation_active:
		var mood_delta := _get_mood_delta_per_day(is_lit, sleeping, low_oxygen)
		mood = clampf(mood + mood_delta * day_fraction, 0.0, 100.0)
	if food <= 0.0:
		health -= 160.0 * day_fraction
	if rest <= 0.0:
		health -= 30.0 * day_fraction
	if mood <= SEVERE_MOOD_THRESHOLD:
		health -= 5.0 * day_fraction
	health = clampf(health, 0.0, 100.0)


func eat() -> void:
	food = minf(100.0, food + 60.0)


func recreate(delta_seconds: float) -> void:
	if delta_seconds > 0.0:
		mood = minf(100.0, mood + RECREATION_RECOVERY_PER_SECOND * delta_seconds)


func take_unstructured_break() -> void:
	mood = minf(100.0, mood + STRESS_BREAK_RECOVERY)


func finish_recreation() -> void:
	mood = RECREATION_TARGET


func wants_recreation() -> bool:
	return mood <= RECREATION_SEEK_THRESHOLD


func is_recreation_satisfied() -> bool:
	return mood >= RECREATION_TARGET


func get_mood_state() -> String:
	if mood >= 70.0:
		return "STEADY"
	if mood >= 40.0:
		return "STRAINED"
	if mood > BREAK_MOOD_THRESHOLD:
		return "STRESSED"
	return "BREAK RISK"


func get_mood_factors(is_lit: bool, sleeping: bool, low_oxygen := false) -> String:
	if sleeping:
		return "Resting · mood stable"
	var loss := BASE_MOOD_LOSS_PER_DAY
	var factors: Array[String] = ["Lit" if is_lit else "Dark"]
	if not is_lit:
		loss += DARKNESS_MOOD_LOSS_PER_DAY
	if food < 35.0:
		loss += LOW_NEED_MOOD_LOSS_PER_DAY
		factors.append("hungry")
	if rest < 30.0:
		loss += LOW_NEED_MOOD_LOSS_PER_DAY
		factors.append("tired")
	if low_oxygen:
		loss += LOW_OXYGEN_MOOD_LOSS_PER_DAY
		factors.append("low O2")
	return "%s · -%d mood/day" % [" · ".join(factors), roundi(loss)]


func serialize() -> Dictionary:
	return {
		"food": food,
		"rest": rest,
		"mood": mood,
		"health": health,
	}


func deserialize(data: Dictionary) -> void:
	food = clampf(float(data.get("food", 88.0)), 0.0, 100.0)
	rest = clampf(float(data.get("rest", 78.0)), 0.0, 100.0)
	# Slice 1-4 snapshots called the value "light_mood". New saves use the
	# broader canonical name while still accepting that legacy field.
	mood = clampf(float(data.get("mood", data.get("light_mood", 72.0))), 0.0, 100.0)
	health = clampf(float(data.get("health", 100.0)), 0.0, 100.0)


static func is_serialized_data_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["food", "rest", "mood", "light_mood", "health"]:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var number := float(value)
		if not is_finite(number) or number < 0.0 or number > 100.0:
			return false
	return true


func _get_mood_delta_per_day(is_lit: bool, sleeping: bool, low_oxygen: bool) -> float:
	if sleeping:
		return 0.0
	var delta := -BASE_MOOD_LOSS_PER_DAY
	if not is_lit:
		delta -= DARKNESS_MOOD_LOSS_PER_DAY
	if food < 35.0:
		delta -= LOW_NEED_MOOD_LOSS_PER_DAY
	if rest < 30.0:
		delta -= LOW_NEED_MOOD_LOSS_PER_DAY
	if low_oxygen:
		delta -= LOW_OXYGEN_MOOD_LOSS_PER_DAY
	return delta
