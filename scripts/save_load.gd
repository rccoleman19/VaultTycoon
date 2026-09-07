class_name SaveLoad
extends Node

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://vault_wing_save.json"


func save_snapshot(snapshot: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	var wrapped := {"version": SAVE_VERSION, "game": snapshot}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not open the local save slot."}
	file.store_string(JSON.stringify(wrapped))
	file.close()
	return {"ok": true, "message": "Wing saved locally."}


func load_snapshot(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "No local save exists yet."}
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
