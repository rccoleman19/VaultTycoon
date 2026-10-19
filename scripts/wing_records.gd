class_name WingRecords
extends RefCounted

# Wing-seed slice 4 (store): a small local record per seeded wing, kept in its own sidecar file
# beside the save. The save format is untouched. Replacement follows #83's snapshot pattern:
# write a sibling .tmp, flush and check it, keep the last valid copy as .bak until the new file
# is promoted, and recover from .bak on read. Missing, damaged or future-version sidecars never
# stop the game: reads return no records, and writes refuse to replace data they cannot read.

# Version 2 (records + ladder): keys name the sublevel ("06-1092"), best_day is the furthest day
# reached (Keep Running days count past 7, capped at 999) and "annex" marks a finished Annex.
# Version 1 files are migrated in memory on read and upgraded on the next write.
const VERSION := 2
const LEGACY_VERSION := 1
const BASE_SUBLEVEL := 7
const DEEPEST_SUBLEVEL := 3
const DEFAULT_PATH := "user://wing_records.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const QUARANTINE_SUFFIX := ".corrupt"
const LEGACY_MAX_DAY := DayCycle.DAYS_TO_SURVIVE
const MAX_DAY := 999

enum Status { MISSING, VALID, RECOVERED, CORRUPT, UNSUPPORTED }

var path := DEFAULT_PATH
# Test hook only: name a step ("open", "write", "rotate", "promote") to make it fail.
var fail_step := ""


static func key_for_seed(wing_seed: int, sublevel := BASE_SUBLEVEL) -> String:
	return "%02d-%04X" % [sublevel, wing_seed]


# Read-only. Returns {"status": Status, "wings": {key: entry}}; wings is empty unless VALID/RECOVERED.
func read() -> Dictionary:
	var primary := _read_file(path)
	if int(primary.status) == Status.VALID or int(primary.status) == Status.UNSUPPORTED:
		return primary
	var backup := _read_file(path + BACKUP_SUFFIX)
	if int(backup.status) == Status.VALID:
		return {"status": Status.RECOVERED, "wings": backup.wings}
	if int(backup.status) == Status.UNSUPPORTED:
		return backup
	if int(primary.status) == Status.MISSING and int(backup.status) == Status.MISSING:
		return {"status": Status.MISSING, "wings": {}}
	return {"status": Status.CORRUPT, "wings": {}}


func get_record(wing_seed: int, sublevel := BASE_SUBLEVEL) -> Dictionary:
	if wing_seed <= 0:
		return {}
	var wings: Dictionary = read().wings
	return (wings.get(key_for_seed(wing_seed, sublevel), {}) as Dictionary).duplicate()


# The deepest sublevel a player may start: a win on sublevel N opens N-1 (never below 3).
func unlocked_sublevel() -> int:
	var wings: Dictionary = read().wings
	var deepest := BASE_SUBLEVEL
	for key: String in wings:
		if bool(wings[key].ever_won):
			deepest = mini(deepest, maxi(DEEPEST_SUBLEVEL, int(key.substr(0, 2)) - 1))
	return deepest


# Meta perks P1: true once any wing has been won on this sublevel (derived, no schema change).
# Annex blueprints: any wing whose record carries the Annex badge (only ever set on a win).
func has_annex_badge() -> bool:
	var wings: Dictionary = read().wings
	for key: String in wings:
		if bool(wings[key].annex):
			return true
	return false


func has_win_on(sublevel: int) -> bool:
	var wings: Dictionary = read().wings
	for key: String in wings:
		if int(key.substr(0, 2)) == sublevel and bool(wings[key].ever_won):
			return true
	return false


# Merges one finished run into the wing's record: ever_won ORs, best_stars keeps the highest known
# grade (null = no graded win yet), best_day keeps the highest day reached and annex ORs. Seed 0
# does no I/O.
# Returns true only when the new record was written and promoted.
func record(wing_seed: int, won: bool, stars: Variant, day: int, sublevel := BASE_SUBLEVEL, annex := false) -> bool:
	if wing_seed <= 0 or wing_seed > 0xFFFF:
		return false
	if sublevel < DEEPEST_SUBLEVEL or sublevel > BASE_SUBLEVEL:
		return false
	if day < 1 or day > MAX_DAY:
		return false
	if stars != null and (typeof(stars) != TYPE_INT or int(stars) < 1 or int(stars) > 3 or not won):
		return false
	if annex and not won:
		return false
	var current := read()
	var status := int(current.status)
	if status == Status.UNSUPPORTED:
		return false
	var wings: Dictionary = (current.wings as Dictionary).duplicate(true)
	var key := key_for_seed(wing_seed, sublevel)
	var entry: Dictionary = wings.get(key, {"ever_won": false, "best_stars": null, "best_day": 0, "annex": false})
	var best_stars: Variant = entry.best_stars
	if stars != null and (best_stars == null or int(stars) > int(best_stars)):
		best_stars = int(stars)
	wings[key] = {
		"ever_won": bool(entry.ever_won) or won,
		"best_stars": best_stars,
		"best_day": maxi(int(entry.best_day), day),
		"annex": bool(entry.annex) or annex,
	}
	return _write({"version": VERSION, "wings": wings}, status)


func _read_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"status": Status.MISSING, "wings": {}}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"status": Status.CORRUPT, "wings": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"status": Status.CORRUPT, "wings": {}}
	var version: Variant = parsed.get("version", null)
	if not _is_integral(version):
		return {"status": Status.CORRUPT, "wings": {}}
	if int(version) != VERSION and int(version) != LEGACY_VERSION:
		return {"status": Status.UNSUPPORTED if int(version) > VERSION else Status.CORRUPT, "wings": {}}
	var legacy := int(version) == LEGACY_VERSION
	var wings: Variant = parsed.get("wings", null)
	if not wings is Dictionary:
		return {"status": Status.CORRUPT, "wings": {}}
	var clean := {}
	for key: Variant in wings:
		var entry: Variant = wings[key]
		if not (_is_valid_legacy_entry(key, entry) if legacy else _is_valid_entry(key, entry)):
			return {"status": Status.CORRUPT, "wings": {}}
		clean[key] = {
			"ever_won": entry.ever_won,
			"best_stars": null if entry.best_stars == null else int(entry.best_stars),
			"best_day": int(entry.best_day),
			"annex": false if legacy else bool(entry.annex),
		}
	return {"status": Status.VALID, "wings": clean}


static func _is_integral(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)


# Version 1: "07-XXXX" keys, 3 fields, best_day 1..7.
static func _is_valid_legacy_entry(key: Variant, entry: Variant) -> bool:
	if not entry is Dictionary or (entry as Dictionary).size() != 3 or not _is_valid_key(key, true):
		return false
	return _is_valid_fields(entry, LEGACY_MAX_DAY)


# Version 2: "SS-XXXX" keys (SS = sublevel 03..07), 4 fields, best_day 1..999, annex only on a win.
static func _is_valid_entry(key: Variant, entry: Variant) -> bool:
	if not entry is Dictionary or (entry as Dictionary).size() != 4 or not _is_valid_key(key, false):
		return false
	if typeof(entry.get("annex", null)) != TYPE_BOOL or (bool(entry.annex) and not bool(entry.get("ever_won", false))):
		return false
	return _is_valid_fields(entry, MAX_DAY)


static func _is_valid_key(key: Variant, legacy: bool) -> bool:
	if typeof(key) != TYPE_STRING:
		return false
	var text := String(key)
	if text.length() != 7 or text[2] != "-" or not text.substr(3).is_valid_hex_number() or text != text.to_upper() or text.substr(3).hex_to_int() == 0:
		return false
	var level := text.substr(0, 2)
	if legacy:
		return level == "07"
	return level.is_valid_int() and int(level) >= DEEPEST_SUBLEVEL and int(level) <= BASE_SUBLEVEL and level == "%02d" % int(level)


static func _is_valid_fields(entry: Dictionary, max_day: int) -> bool:
	if typeof(entry.get("ever_won", null)) != TYPE_BOOL:
		return false
	var day: Variant = entry.get("best_day", null)
	if not _is_integral(day) or int(day) < 1 or int(day) > max_day:
		return false
	if not entry.has("best_stars"):
		return false
	var stars: Variant = entry.best_stars
	if stars == null:
		return true
	return _is_integral(stars) and int(stars) >= 1 and int(stars) <= 3 and bool(entry.ever_won)


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
