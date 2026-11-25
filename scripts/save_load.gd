class_name SaveLoad
extends Node

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://vault_wing_save.json"
const CHECKPOINT_PATH := "user://vault_wing_checkpoint.json"
const _TEMP_SUFFIX := ".tmp"
const _BACKUP_SUFFIX := ".bak"


func save_snapshot(snapshot: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	var wrapped := {"version": SAVE_VERSION, "game": snapshot}
	var float64: Array = []
	_collect_float64(snapshot, [], float64)
	if not float64.is_empty():
		wrapped["float64"] = float64
	var temporary_path := path + _TEMP_SUFFIX
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not prepare the local save slot."}
	# Full precision supplies the decimal digits; float64 preserves values that
	# Godot's decimal parser still rounds to a neighboring double.
	file.store_string(JSON.stringify(wrapped, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temporary_path)
		return {"ok": false, "message": "Could not finish writing the local save."}
	if not _promote_temporary_save(temporary_path, path):
		_remove_file(temporary_path)
		return {"ok": false, "message": "Could not replace the local save slot."}
	return {"ok": true, "message": "Wing saved locally."}


func load_snapshot(path := DEFAULT_PATH) -> Dictionary:
	var backup_path := path + _BACKUP_SUFFIX
	if not FileAccess.file_exists(path) and FileAccess.file_exists(backup_path):
		var recovered := _read_snapshot(backup_path)
		if bool(recovered.ok):
			recovered.message = "Wing loaded from the previous intact save."
			return recovered
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "No local save exists yet."}
	var result := _read_snapshot(path)
	if bool(result.ok) or not FileAccess.file_exists(backup_path):
		return result
	var recovered := _read_snapshot(backup_path)
	if bool(recovered.ok):
		recovered.message = "Wing loaded from the previous intact save."
		return recovered
	return result


func _read_snapshot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Could not open the local save slot."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "message": "The local save is damaged."}
	var version: Variant = parsed.get("version", -1)
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or float(version) != SAVE_VERSION or not parsed.get("game", null) is Dictionary:
		return {"ok": false, "message": "The local save uses an unsupported version."}
	if parsed.has("float64") and not _restore_float64(parsed.game, parsed.float64):
		return {"ok": false, "message": "The local save is damaged."}
	return {"ok": true, "message": "Wing loaded.", "snapshot": parsed["game"]}


# Keep the ordinary JSON schema and old saves readable. Only numbers that fail
# a full-precision JSON round trip need an additive wrapper entry: [path, bits].
func _collect_float64(value: Variant, path: Array, entries: Array) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_collect_float64(value[key], path + [key], entries)
	elif value is Array:
		for index in range(value.size()):
			_collect_float64(value[index], path + [index], entries)
	elif typeof(value) == TYPE_FLOAT and is_finite(value):
		var decimal := JSON.stringify(value, "", true, true)
		var rounded: float = JSON.parse_string(decimal)
		var bits := PackedFloat64Array([value]).to_byte_array()
		if bits != PackedFloat64Array([rounded]).to_byte_array():
			entries.append([path, bits.hex_encode()])


func _restore_float64(snapshot: Dictionary, entries: Variant) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if not entry is Array or entry.size() != 2 or not entry[0] is Array or entry[0].is_empty():
			return false
		if not entry[1] is String or entry[1].length() != 16 or not entry[1].is_valid_hex_number(false):
			return false
		if entry[1].begins_with("+") or entry[1].begins_with("-"):
			return false
		var exact: float = entry[1].hex_decode().decode_double(0)
		if not is_finite(exact):
			return false
		var target: Variant = snapshot
		var path: Array = entry[0]
		for depth in range(path.size()):
			var key: Variant = path[depth]
			if target is Dictionary:
				if not key is String or not target.has(key):
					return false
			elif target is Array:
				if typeof(key) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(key)):
					return false
				if float(key) != floorf(float(key)) or key < 0 or key >= target.size():
					return false
				key = int(key)
			else:
				return false
			if depth == path.size() - 1:
				# Never let precision metadata repair a missing, malformed or edited
				# gameplay field. It must describe this exact JSON number.
				if typeof(target[key]) != TYPE_FLOAT or target[key] != JSON.parse_string(JSON.stringify(exact, "", true, true)):
					return false
				target[key] = exact
			else:
				target = target[key]
	return true


func _promote_temporary_save(temporary_path: String, target_path: String) -> bool:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var backup_path := target_path + _BACKUP_SUFFIX
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var had_target := FileAccess.file_exists(target_path)

	# Keep the previous complete file recoverable until the new file has been
	# fully written and moved into place. The backup also covers platforms that
	# cannot rename over an existing destination.
	if had_target:
		if FileAccess.file_exists(backup_path):
			if DirAccess.remove_absolute(backup_absolute) != OK:
				return false
		if DirAccess.rename_absolute(target_absolute, backup_absolute) != OK:
			return false

	if DirAccess.rename_absolute(temporary_absolute, target_absolute) != OK:
		if had_target:
			DirAccess.rename_absolute(backup_absolute, target_absolute)
		return false

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_absolute)
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
