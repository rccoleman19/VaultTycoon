extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_PATH := "user://headless_snapshot_atomic.json"
const REJECTED_MESSAGE := "The save did not contain a valid vault wing."
const VERSION_MESSAGE := "The local save uses an unsupported version."

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _failed_case_count := 0
var _current_case := ""
var _active_game: VaultGame
var _source: Dictionary = {}
var _source_memory: Dictionary = {}
var _source_json := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_game := _source_game()
	_source_memory = source_game.create_snapshot()
	_source_json = JSON.stringify(_source_memory)
	_source = JSON.parse_string(_source_json)
	source_game.free()
	_run_case("fixture source snapshot covers every nested section", _test_fixture)
	for entry: Array in _malformed_cases():
		_run_case("rejects %s and keeps the live wing" % entry[0], _test_rejected.bind(entry[1]))
	_run_case("player path rejects food array", _test_load_game_rejected.bind(func(s): s.food = []))
	_run_case("player path rejects resident bed_id array", _test_load_game_rejected.bind(func(s): s.residents[0].bed_id = []))
	for entry: Array in [["array", []], ["string", "1"], ["null", null], ["unsupported number", 2]]:
		_run_case("wrapper rejects version %s" % entry[0], _test_wrapper_version.bind(entry[1]))
	_run_case("rejection then valid load applies cleanly", _test_reject_then_valid)
	_run_case("valid save round-trips through the file unchanged", _test_round_trip)
	_run_case("in-memory snapshot with integer types still applies", _test_in_memory_apply)
	_run_case("legacy snapshot without optional sections still loads with defaults", _test_legacy_optional)
	_run_case("short camera arrays stay ignored, including their value types", _test_short_camera)
	_run_case("non-array list entries stay skipped as before", _test_skipped_entries)
	if _failed_case_count > 0:
		printerr("SAVE SNAPSHOT ATOMIC FAILED CASES: %d" % _failed_case_count)
	print("SAVE SNAPSHOT ATOMIC TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _malformed_cases() -> Array:
	return [
		["map missing", func(s): s.erase("map")],
		["map array", func(s): s.map = []],
		["buildings missing", func(s): s.erase("buildings")],
		["buildings dictionary", func(s): s.buildings = {}],
		["residents dictionary", func(s): s.residents = {}],
		["food array", func(s): s.food = []],
		["food number", func(s): s.food = 5],
		["food null", func(s): s.food = null],
		["food.meals string", func(s): s.food.meals = "x"],
		["food.raw_food array", func(s): s.food.raw_food = [1]],
		["food.salvage fractional", func(s): s.food.salvage = 1.5],
		["food.meals bool", func(s): s.food.meals = true],
		["food.raw_food dictionary", func(s): s.food.raw_food = {}],
		["oxygen array", func(s): s.oxygen = []],
		["oxygen.oxygen string", func(s): s.oxygen.oxygen = "x"],
		["day array without breach", func(s): s.erase("breach"); s.day = []],
		["day array with breach", func(s): s.day = []],
		["day null without breach", func(s): s.erase("breach"); s.day = null],
		["day.elapsed_seconds string", func(s): s.day.elapsed_seconds = "x"],
		["day.current_day array", func(s): s.day.current_day = [1]],
		["day.completed string", func(s): s.day.completed = "yes"],
		["breach array", func(s): s.breach = []],
		["breach.phase string", func(s): s.breach.phase = "x"],
		["jobs array", func(s): s.jobs = []],
		["jobs.rubble string", func(s): s.jobs.rubble = "abc"],
		["jobs.rubble inner array", func(s): s.jobs.rubble = [[1, 2, [3]]]],
		["jobs.supplies string", func(s): s.jobs.supplies = "x"],
		["jobs.supplies inner dictionary", func(s): s.jobs.supplies[0][0] = {}],
		["jobs.supplies in_transit dictionary", func(s): s.jobs.supplies = [[1, 2, 3, 4, {}]]],
		["jobs.rubble short entry dictionary", func(s): s.jobs.rubble = [[{}, 1]]],
		["jobs.raw_food string", func(s): s.jobs.raw_food = "x"],
		["jobs.breach_supply string", func(s): s.jobs.breach_supply = "x"],
		["jobs.breach_patch dictionary", func(s): s.jobs.breach_patch = {}],
		["next_building_id array", func(s): s.next_building_id = []],
		["next_building_id string", func(s): s.next_building_id = "7"],
		["next_building_id fractional", func(s): s.next_building_id = 2.5],
		["camera dictionary", func(s): s.camera = {}],
		["camera null", func(s): s.camera = null],
		["camera inner string", func(s): s.camera = ["a", 1, 1]],
		["camera zoom dictionary", func(s): s.camera = [123, 456, {}]],
		["ended string", func(s): s.ended = "yes"],
		["outcome number", func(s): s.outcome = 5],
		["map.cells missing", func(s): s.map.erase("cells")],
		["map.cells string", func(s): s.map.cells = "x"],
		["map.cells inner dictionary", func(s): s.map.cells[0] = {}],
		["map.cells inner string", func(s): s.map.cells[0] = "x"],
		["map.cells unknown tile", func(s): s.map.cells[0] = 5],
		["map.cells fractional tile", func(s): s.map.cells[0] = 0.5],
		["map.dig_marks string", func(s): s.map.dig_marks = "abc"],
		["map.dig_marks progress dictionary", func(s): s.map.dig_marks[0][2] = {}],
		["map.dig_marks x string", func(s): s.map.dig_marks[0][0] = "x"],
		["map.dig_marks short entry dictionary", func(s): s.map.dig_marks.append([{}, 1])],
		["map.stockpile_cells string", func(s): s.map.stockpile_cells = "x"],
		["building id array", func(s): s.buildings[0].id = []],
		["building kind string", func(s): s.buildings[0].kind = "x"],
		["building cell strings", func(s): s.buildings[0].cell = ["a", "b"]],
		["building cell missing", func(s): s.buildings[0].erase("cell")],
		["building complete array", func(s): s.buildings[0].complete = []],
		["building delivered string", func(s): s.buildings[0].delivered = "x"],
		["building construction_left dictionary", func(s): s.buildings[0].construction_left = {}],
		["building powered string", func(s): s.buildings[0].powered = "on"],
		["building manually_disabled string", func(s): s.buildings[0].manually_disabled = "x"],
		["building is_emergency_core number", func(s): s.buildings[0].is_emergency_core = 1],
		["building production_progress array", func(s): s.buildings[0].production_progress = []],
		["resident id string", func(s): s.residents[0].id = "x"],
		["resident name array", func(s): s.residents[0].name = []],
		["resident position inner dictionary", func(s): s.residents[0].position = [{}, 0]],
		["resident position missing", func(s): s.residents[0].erase("position")],
		["resident needs array", func(s): s.residents[0].needs = []],
		["resident needs.food string", func(s): s.residents[0].needs.food = "x"],
		["resident alive string", func(s): s.residents[0].alive = "no"],
		["resident sleeping array", func(s): s.residents[0].sleeping = []],
		["resident bed_id array", func(s): s.residents[0].bed_id = []],
		["resident recreating string", func(s): s.residents[0].recreating = "x"],
		["resident recreation_id string", func(s): s.residents[0].recreation_id = "x"],
		["resident stress_break_left dictionary", func(s): s.residents[0].stress_break_left = {}],
		["resident drafted string", func(s): s.residents[0].drafted = "x"],
		["resident work_priorities array", func(s): s.residents[0].work_priorities = []],
		["resident forced_order array", func(s): s.residents[0].forced_order = []],
	]


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	_active_game = game
	return game


func _source_game() -> VaultGame:
	var game := _spawn_game()
	var dig_target := MapGrid.CHAMBER.position + Vector2i.LEFT
	game.map_grid.queue_dig(dig_target)
	game.map_grid.apply_dig_work(dig_target, 2.5)
	game.job_system.queue_dig(dig_target)
	game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12))
	game.food_system.meals = 7
	game.food_system.raw_food = 3
	game.food_system.salvage = 41
	game.day_cycle.advance(17.25)
	game.residents[0].needs.food = 54.5
	game.world_camera.position = Vector2(432.5, 321.25)
	return game


func _live_game() -> VaultGame:
	var game := _spawn_game()
	game.food_system.meals = 3
	game.food_system.salvage = 22
	game.day_cycle.advance(3.0)
	game.residents[1].needs.mood = 41.0
	game.world_camera.position = Vector2(100.0, 90.0)
	game.world_camera.zoom = Vector2.ONE * 1.25
	game.active_tool = "dig"
	game.selected_building_id = game.buildings[0].building_id
	game.selected_resident_id = game.residents[1].resident_id
	game._simulation_accumulator = 0.025
	return game


func _fingerprint(game: VaultGame) -> Dictionary:
	var building_nodes: Array = []
	for building in game.buildings:
		building_nodes.append([building.get_instance_id(), building.building_id, building.cell])
	var resident_nodes: Array = []
	for resident in game.residents:
		resident_nodes.append([resident.get_instance_id(), resident.resident_id, resident.needs.serialize()])
	return {
		"snapshot": game.create_snapshot(),
		"buildings": building_nodes,
		"residents": resident_nodes,
		"jobs": game.job_system.jobs.duplicate(true),
		"power": [game.power_grid.supply, game.power_grid.demand],
		"camera": [game.world_camera.position, game.world_camera.zoom],
		"ui": [game.active_tool, game.selected_building_id, game.selected_resident_id, game.user_paused, game._simulation_accumulator],
	}


func _assert_unchanged(before: Dictionary, after: Variant) -> void:
	for key: String in before:
		_assert_true(after is Dictionary and after.has(key) and before[key] == after[key], "live %s unchanged" % key)


func _test_fixture() -> bool:
	for key: String in ["map", "buildings", "residents", "food", "oxygen", "day", "breach", "jobs", "next_building_id", "camera", "ended", "outcome"]:
		_assert_true(_source.has(key), "source has %s" % key)
	_assert_true(not (_source.map.dig_marks as Array).is_empty(), "source has a dig mark")
	_assert_true(not (_source.jobs.supplies as Array).is_empty(), "source has a supply job")
	var live := _live_game()
	_assert_equal(_source.buildings.size(), live.buildings.size() + 1, "source has one extra blueprint")
	_assert_true(live.create_snapshot() != _source, "live wing differs from source")
	return true


func _test_rejected(mutate: Callable) -> bool:
	var live := _live_game()
	var before := _fingerprint(live)
	var snapshot: Dictionary = _source.duplicate(true)
	mutate.call(snapshot)
	# Keep an aborted pre-fix call's result untyped so it becomes a counted
	# assertion failure instead of aborting the harness on a bool conversion.
	var result: Variant = live.apply_snapshot.call(snapshot)
	_assert_equal(result, false, "apply_snapshot reports failure")
	_assert_unchanged(before, _fingerprint.call(live))
	return true


func _write_save(snapshot: Dictionary, version: Variant = SaveLoad.SAVE_VERSION) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": version, "game": snapshot}))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _remove_save() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_load_game_rejected(mutate: Callable) -> bool:
	var snapshot: Dictionary = _source.duplicate(true)
	mutate.call(snapshot)
	_assert_true(_write_save(snapshot), "malformed player save writes")
	var live := _live_game()
	live.user_paused = false
	var before := _fingerprint(live)
	var result: Variant = live.load_game.call(SAVE_PATH)
	_assert_equal(result, false, "load_game reports failure")
	_assert_equal(live.status_message, REJECTED_MESSAGE, "existing rejected-load message")
	_assert_equal(live.user_paused, false, "rejected player load stays unpaused")
	_assert_unchanged(before, _fingerprint.call(live))
	return true


func _test_wrapper_version(version: Variant) -> bool:
	_assert_true(_write_save(_source, version), "malformed wrapper writes")
	var live := _live_game()
	var before := _fingerprint(live)
	var result: Variant = live.load_game.call(SAVE_PATH)
	_assert_equal(result, false, "wrapper version rejected")
	_assert_equal(live.status_message, VERSION_MESSAGE, "existing version message")
	_assert_unchanged(before, _fingerprint.call(live))
	return true


func _test_reject_then_valid() -> bool:
	var live := _live_game()
	var before := _fingerprint(live)
	var bad: Dictionary = _source.duplicate(true)
	bad.food = []
	var rejected: Variant = live.apply_snapshot.call(bad)
	_assert_equal(rejected, false, "bad snapshot rejected")
	_assert_unchanged(before, _fingerprint.call(live))
	var accepted: Variant = live.apply_snapshot.call(_source.duplicate(true))
	_assert_equal(accepted, true, "valid snapshot then applies")
	_assert_equal(JSON.stringify(live.create_snapshot()), _source_json, "valid load equals the source wing")
	return true


func _test_round_trip() -> bool:
	var original := _source_game()
	_assert_true(original.save_game(false, SAVE_PATH), "save writes")
	var saved_json := JSON.stringify(original.create_snapshot())
	original.step_simulation(5.0)
	var advanced_json := JSON.stringify(original.create_snapshot())
	original.free()
	# Compare the two wings sequentially, keeping only one wing alive at a time.
	var loaded := _live_game()
	var result: Variant = loaded.load_game.call(SAVE_PATH)
	_assert_equal(result, true, "valid save loads")
	_assert_equal(JSON.stringify(loaded.create_snapshot()), saved_json, "round-trip snapshot identical")
	loaded.step_simulation(5.0)
	_assert_equal(JSON.stringify(loaded.create_snapshot()), advanced_json, "round-trip stays deterministic")
	return true


func _test_in_memory_apply() -> bool:
	var live := _live_game()
	var result: Variant = live.apply_snapshot.call(_source_memory.duplicate(true))
	_assert_equal(result, true, "integer-typed snapshot applies")
	_assert_equal(JSON.stringify(live.create_snapshot()), _source_json, "in-memory apply identical")
	return true


func _test_legacy_optional() -> bool:
	var snapshot: Dictionary = _source.duplicate(true)
	for key: String in ["food", "oxygen", "day", "breach", "jobs", "next_building_id", "camera", "ended", "outcome"]:
		snapshot.erase(key)
	var live := _live_game()
	var result: Variant = live.apply_snapshot.call(snapshot)
	_assert_equal(result, true, "legacy snapshot loads")
	_assert_equal(live.food_system.meals, FoodSystem.STARTING_MEALS, "missing food uses meal default")
	_assert_equal(live.food_system.raw_food, FoodSystem.STARTING_RAW_FOOD, "missing food uses raw food default")
	_assert_equal(live.food_system.salvage, FoodSystem.STARTING_SALVAGE, "missing food uses salvage default")
	_assert_equal(live.buildings.size(), _source.buildings.size(), "legacy buildings applied")
	return true


func _test_short_camera() -> bool:
	var live := _live_game()
	var position_before := live.world_camera.position
	var zoom_before := live.world_camera.zoom
	for camera: Array in [[1, 2], [], [1], ["ignored"], [{}, null]]:
		var snapshot: Dictionary = _source.duplicate(true)
		snapshot.camera = camera
		var result: Variant = live.apply_snapshot.call(snapshot)
		_assert_equal(result, true, "short camera %s still loads" % str(camera))
		_assert_equal(live.world_camera.position, position_before, "short camera position ignored")
		_assert_equal(live.world_camera.zoom, zoom_before, "short camera zoom ignored")
	return true


func _test_skipped_entries() -> bool:
	var snapshot: Dictionary = _source.duplicate(true)
	snapshot.map.dig_marks.append(5)
	snapshot.jobs.rubble = ["legacy", [1]]
	var live := _live_game()
	var result: Variant = live.apply_snapshot.call(snapshot)
	_assert_equal(result, true, "skipped entries still load")
	_assert_equal(JSON.stringify(live.create_snapshot()), _source_json, "skipped entries ignored")
	return true


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	_remove_save()
	print("[TEST] %s" % label)
	var completed: Variant = test.call()
	if typeof(completed) != TYPE_BOOL or completed != true:
		_assert_true(false, "case reaches its final assertion without aborting")
	# Even a pre-fix production script error must not leak a live wing into
	# the next case or prevent the suite from reporting its counted failures.
	if is_instance_valid(_active_game):
		_active_game.free()
	_active_game = null
	_remove_save()
	if before != _failure_count:
		_failed_case_count += 1
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _assert_true(condition: bool, message: String) -> void:
	_assert_equal(condition, true, message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		_failure_count += 1
		printerr("[FAIL] %s :: %s — expected %s, got %s" % [_current_case, message, str(expected), str(actual)])
