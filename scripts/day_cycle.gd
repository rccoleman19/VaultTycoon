class_name DayCycle
extends Node

signal day_started(day: int)
signal seven_days_completed

const SECONDS_PER_DAY := 40.0
const DAYS_TO_SURVIVE := 7

var elapsed_seconds := 0.0
var current_day := 1
var completed := false


func reset() -> void:
	elapsed_seconds = 0.0
	current_day = 1
	completed = false


func advance(delta_seconds: float) -> void:
	if completed:
		return
	var previous_day := current_day
	elapsed_seconds = minf(elapsed_seconds + delta_seconds, SECONDS_PER_DAY * DAYS_TO_SURVIVE)
	current_day = mini(DAYS_TO_SURVIVE, floori(elapsed_seconds / SECONDS_PER_DAY) + 1)
	if current_day != previous_day:
		day_started.emit(current_day)
	if elapsed_seconds >= SECONDS_PER_DAY * DAYS_TO_SURVIVE:
		completed = true
		seven_days_completed.emit()


func get_day_fraction() -> float:
	return fmod(elapsed_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY


func get_clock_text() -> String:
	if completed:
		return "DAY 7 COMPLETE"
	var hours := floori(get_day_fraction() * 24.0)
	var minutes := floori(fmod(get_day_fraction() * 24.0, 1.0) * 60.0)
	return "DAY %d/7  ·  %02d:%02d" % [current_day, hours, minutes]


func serialize() -> Dictionary:
	return {"elapsed_seconds": elapsed_seconds, "current_day": current_day, "completed": completed}


func deserialize(data: Dictionary) -> void:
	elapsed_seconds = clampf(float(data.get("elapsed_seconds", 0.0)), 0.0, SECONDS_PER_DAY * DAYS_TO_SURVIVE)
	current_day = clampi(int(data.get("current_day", 1)), 1, DAYS_TO_SURVIVE)
	completed = bool(data.get("completed", false)) or elapsed_seconds >= SECONDS_PER_DAY * DAYS_TO_SURVIVE

