class_name OxygenSystem
extends Node

signal oxygen_changed

const MAX_OXYGEN := 100.0
const STARTING_OXYGEN := 100.0
const CONSUMPTION_PER_RESIDENT_PER_SECOND := 0.08
const RECYCLER_OUTPUT_PER_SECOND := 0.8
const OPEN_BREACH_LOSS_PER_SECOND := 2.5
const LOW_OXYGEN_THRESHOLD := 35.0
const CRITICAL_OXYGEN_THRESHOLD := 15.0
const SUFFOCATION_DAMAGE_PER_SECOND := 4.0

var oxygen := STARTING_OXYGEN
var living_resident_count := 0
var powered_recycler_count := 0
var consumption_rate := 0.0
var recycler_output_rate := 0.0
var breach_loss_rate := 0.0
var net_rate := 0.0
var status_text := "NOMINAL"


func reset() -> void:
	oxygen = STARTING_OXYGEN
	living_resident_count = 0
	powered_recycler_count = 0
	consumption_rate = 0.0
	recycler_output_rate = 0.0
	breach_loss_rate = 0.0
	net_rate = 0.0
	_update_status()
	oxygen_changed.emit()


func refresh_rates(residents: Array, buildings: Array, breach_open: bool) -> void:
	living_resident_count = 0
	for entry: Variant in residents:
		if entry is VaultResident and entry.alive:
			living_resident_count += 1

	powered_recycler_count = 0
	for entry: Variant in buildings:
		if not entry is VaultBuilding:
			continue
		var building := entry as VaultBuilding
		if (
			building.complete
			and building.powered
			and building.kind == VaultBuilding.Kind.AIR_RECYCLER
		):
			powered_recycler_count += 1

	consumption_rate = float(living_resident_count) * CONSUMPTION_PER_RESIDENT_PER_SECOND
	recycler_output_rate = float(powered_recycler_count) * RECYCLER_OUTPUT_PER_SECOND
	breach_loss_rate = OPEN_BREACH_LOSS_PER_SECOND if breach_open else 0.0
	net_rate = recycler_output_rate - consumption_rate - breach_loss_rate
	_update_status()


func advance(delta_seconds: float, residents: Array, buildings: Array, breach_open: bool) -> void:
	refresh_rates(residents, buildings, breach_open)
	var safe_delta := _finite_nonnegative(delta_seconds)
	if safe_delta <= 0.0:
		return

	var oxygen_before := clampf(_finite_or_default(oxygen, STARTING_OXYGEN), 0.0, MAX_OXYGEN)
	var critical_seconds := _seconds_at_or_below_critical(oxygen_before, net_rate, safe_delta)
	oxygen = clampf(oxygen_before + net_rate * safe_delta, 0.0, MAX_OXYGEN)

	if critical_seconds > 0.0:
		var damage := critical_seconds * SUFFOCATION_DAMAGE_PER_SECOND
		for entry: Variant in residents:
			if entry is VaultResident and entry.alive:
				entry.apply_damage(damage)

	# Damage can change the living count. Keep the derived HUD rates truthful
	# even when the final resident dies and the simulation ends this tick.
	refresh_rates(residents, buildings, breach_open)
	if not is_equal_approx(oxygen, oxygen_before):
		oxygen_changed.emit()


func is_low() -> bool:
	return oxygen <= LOW_OXYGEN_THRESHOLD


func is_critical() -> bool:
	return oxygen <= CRITICAL_OXYGEN_THRESHOLD


func is_breathable() -> bool:
	return oxygen >= CRITICAL_OXYGEN_THRESHOLD


func get_status_text() -> String:
	return status_text


func serialize() -> Dictionary:
	return {"oxygen": oxygen}


func deserialize(data: Dictionary) -> void:
	var restored_oxygen := STARTING_OXYGEN
	if not data.is_empty() and _is_number(data.get("oxygen")):
		restored_oxygen = _finite_or_default(float(data.oxygen), STARTING_OXYGEN)
	oxygen = clampf(restored_oxygen, 0.0, MAX_OXYGEN)
	living_resident_count = 0
	powered_recycler_count = 0
	consumption_rate = 0.0
	recycler_output_rate = 0.0
	breach_loss_rate = 0.0
	net_rate = 0.0
	_update_status()
	oxygen_changed.emit()


func is_serialized_data_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var saved: Dictionary = data
	if saved.size() != 1 or not saved.has("oxygen") or not _is_number(saved.oxygen):
		return false
	var saved_oxygen := float(saved.oxygen)
	return is_finite(saved_oxygen) and saved_oxygen >= 0.0 and saved_oxygen <= MAX_OXYGEN


func _seconds_at_or_below_critical(starting_oxygen: float, rate: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	if is_zero_approx(rate):
		return seconds if starting_oxygen <= CRITICAL_OXYGEN_THRESHOLD else 0.0

	if rate < 0.0:
		if starting_oxygen <= CRITICAL_OXYGEN_THRESHOLD:
			return seconds
		var time_to_critical := (starting_oxygen - CRITICAL_OXYGEN_THRESHOLD) / -rate
		return clampf(seconds - time_to_critical, 0.0, seconds)

	if starting_oxygen >= CRITICAL_OXYGEN_THRESHOLD:
		return 0.0
	var time_to_breathable := (CRITICAL_OXYGEN_THRESHOLD - starting_oxygen) / rate
	return clampf(time_to_breathable, 0.0, seconds)


func _update_status() -> void:
	if is_critical():
		status_text = "CRITICAL"
	elif is_low():
		status_text = "LOW"
	else:
		status_text = "NOMINAL"


func _finite_nonnegative(value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return 0.0
	return value


func _finite_or_default(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
