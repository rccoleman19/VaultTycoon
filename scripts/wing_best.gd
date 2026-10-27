class_name WingBest
extends RefCounted

# Independent of saves, checkpoints and the cumulative wing records. A failed sidecar
# never blocks play; replacement keeps the last valid copy until promotion succeeds.
const VERSION := 1
const DEFAULT_PATH := "user://wing_best.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const QUARANTINE_SUFFIX := ".corrupt"
enum Status { MISSING, VALID, RECOVERED, CORRUPT, UNSUPPORTED }

var path := DEFAULT_PATH
# Test hook: "open", "write", "rotate", "promote".
var fail_step := ""


static func run_from(outcome: String, day: Variant, elapsed: Variant, survivors: Variant) -> Dictionary:
	return {"won": outcome == "win", "day": day, "elapsed": elapsed, "survivors": survivors}


static func is_better(candidate: Dictionary, previous: Dictionary) -> bool:
	if previous.is_empty():
		return true
	if candidate.won != previous.won:
		return candidate.won
	if candidate.won:
		return candidate.survivors.size() > previous.survivors.size()
	if candidate.day != previous.day:
		return candidate.day > previous.day
	return candidate.elapsed > previous.elapsed


func read() -> Dictionary:
	var primary := _read_file(path)
	if int(primary.status) == Status.VALID:
		return primary
	var backup := _read_file(path + BACKUP_SUFFIX)
	if int(backup.status) == Status.VALID:
		return {"status": Status.RECOVERED, "wings": backup.wings}
	if int(primary.status) == Status.UNSUPPORTED or int(backup.status) == Status.UNSUPPORTED:
		return {"status": Status.UNSUPPORTED, "wings": {}}
	if int(primary.status) == Status.MISSING and int(backup.status) == Status.MISSING:
		return {"status": Status.MISSING, "wings": {}}
	return {"status": Status.CORRUPT, "wings": {}}


func get_best(seed_value: int, sublevel := WingRecords.BASE_SUBLEVEL) -> Dictionary:
	if seed_value <= 0 or seed_value > 0xFFFF or sublevel < WingRecords.DEEPEST_SUBLEVEL or sublevel > WingRecords.BASE_SUBLEVEL:
		return {}
	return read().wings.get(WingRecords.key_for_seed(seed_value, sublevel), {}).duplicate(true)


# Invalid submissions do no I/O. new_best means the better entry was actually promoted;
# on a write failure current remains the last readable best (or empty for a first run).
func submit(seed_value: Variant, sublevel: Variant, run: Variant) -> Dictionary:
	if typeof(seed_value) != TYPE_INT or seed_value <= 0 or seed_value > 0xFFFF:
		return {}
	if typeof(sublevel) != TYPE_INT or sublevel < WingRecords.DEEPEST_SUBLEVEL or sublevel > WingRecords.BASE_SUBLEVEL or not _valid_run(run):
		return {}
	var state := read()
	var wings: Dictionary = state.wings.duplicate(true)
	var key := WingRecords.key_for_seed(seed_value, sublevel)
	var previous: Dictionary = wings.get(key, {}).duplicate(true)
	var current := previous.duplicate(true)
	var new_best := false
	if is_better(run, previous) and int(state.status) != Status.UNSUPPORTED:
		wings[key] = _clean_run(run)
		if _write({"version": VERSION, "wings": wings}, int(state.status)):
			current = wings[key].duplicate(true)
			new_best = true
	return {"previous": previous, "current": current, "new_best": new_best}


func _read_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"status": Status.MISSING, "wings": {}}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"status": Status.CORRUPT, "wings": {}}
	var content := file.get_as_text()
	var error := file.get_error()
	file.close()
	var parser := JSON.new()
	if error != OK or parser.parse(content) != OK:
		return {"status": Status.CORRUPT, "wings": {}}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.size() != 2:
		return {"status": Status.CORRUPT, "wings": {}}
	var version: Variant = parsed.get("version")
	if not WingRecords._is_integral(version):
		return {"status": Status.CORRUPT, "wings": {}}
	if version != VERSION:
		return {"status": Status.UNSUPPORTED, "wings": {}}
	var wings: Variant = parsed.get("wings")
	if not wings is Dictionary:
		return {"status": Status.CORRUPT, "wings": {}}
	var clean := {}
	for key: Variant in wings:
		if not WingRecords._is_valid_key(key, false) or not _valid_run(wings[key]):
			return {"status": Status.CORRUPT, "wings": {}}
		clean[key] = _clean_run(wings[key])
	return {"status": Status.VALID, "wings": clean}


static func _valid_run(run: Variant) -> bool:
	if not run is Dictionary or run.size() != 4 or typeof(run.get("won")) != TYPE_BOOL:
		return false
	var day: Variant = run.get("day")
	if not WingRecords._is_integral(day) or day < 1 or day > WingRecords.MAX_DAY:
		return false
	var elapsed: Variant = run.get("elapsed")
	if (typeof(elapsed) != TYPE_FLOAT and typeof(elapsed) != TYPE_INT) or not is_finite(float(elapsed)) or elapsed < 0:
		return false
	var survivors: Variant = run.get("survivors")
	if not survivors is Array:
		return false
	for name: Variant in survivors:
		if typeof(name) != TYPE_STRING:
			return false
	return true


static func _clean_run(run: Dictionary) -> Dictionary:
	return {"won": run.won, "day": int(run.day), "elapsed": float(run.elapsed), "survivors": run.survivors.duplicate()}


func _write(document: Dictionary, status: int) -> bool:
	var temporary := path + TEMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE) if fail_step != "open" else null
	if file == null:
		return false
	file.store_string(JSON.stringify(document))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or fail_step == "write":
		_remove(temporary)
		return false
	var backup := path + BACKUP_SUFFIX
	var rotated := false
	if FileAccess.file_exists(path):
		if status == Status.VALID:
			# The primary is good: it becomes the backup until the new file is in place.
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(_abs(backup)) != OK:
				_remove(temporary)
				return false
			if fail_step == "rotate" or DirAccess.rename_absolute(_abs(path), _abs(backup)) != OK:
				_remove(temporary)
				return false
			rotated = true
		else:
			# Damaged primary: move it aside under a fresh name. A valid .bak (RECOVERED) stays put.
			if fail_step == "rotate" or DirAccess.rename_absolute(_abs(path), _abs(_quarantine_path())) != OK:
				_remove(temporary)
				return false
	if fail_step == "promote" or DirAccess.rename_absolute(_abs(temporary), _abs(path)) != OK:
		if rotated:
			DirAccess.rename_absolute(_abs(backup), _abs(path))
		_remove(temporary)
		return false
	if FileAccess.file_exists(backup):
		_remove(backup)
	return true


func _quarantine_path() -> String:
	var base := "%s%s-%d" % [path, QUARANTINE_SUFFIX, Time.get_unix_time_from_system()]
	var candidate := base
	var counter := 1
	while FileAccess.file_exists(candidate):
		candidate = "%s-%d" % [base, counter]
		counter += 1
	return candidate


static func _abs(file_path: String) -> String:
	return ProjectSettings.globalize_path(file_path)


static func _remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(_abs(file_path))
