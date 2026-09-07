class_name SaveLoad
extends Node

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://vault_wing_save.json"
const _TEMP_SUFFIX := ".tmp"
const _BACKUP_SUFFIX := ".bak"


func save_snapshot(snapshot: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	var wrapped := {"version": SAVE_VERSION, "game": snapshot}
	var temporary_path := path + _TEMP_SUFFIX
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not prepare the local save slot."}
	file.store_string(JSON.stringify(wrapped))
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
	if int(parsed.get("version", -1)) != SAVE_VERSION or not parsed.get("game", null) is Dictionary:
		return {"ok": false, "message": "The local save uses an unsupported version."}
	return {"ok": true, "message": "Wing loaded.", "snapshot": parsed["game"]}


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
