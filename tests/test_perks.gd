extends "res://tests/test_runner.gd"

# Meta perks P1: one trade-off perk per wing, unlocked by the first win on a sublevel (derived from
# WingRecords), NONE by default and always for seed 0 / records-off runs, applied once, saved additively.

var _path := ""


func _run() -> void:
	_path = "user://test_perks_%d.json" % OS.get_process_id()
	_run_case("records off and seed 0 always start on NONE", _test_none_default)
	_run_case("the first win on 07 unlocks PROVISIONING", _test_unlock)
	_run_case("PROVISIONING trades salvage for meals once, and LOAD never re-grants it", _test_apply_once)
	_run_case("only a perk wing writes the perk key; bad perk data is refused", _test_save_shape)
	_run_case("NEW WING and REPLAY re-apply the equipped perk once; unequipping returns to NONE", _test_replay)
	print("")
	if _failure_count == 0:
		print("PERKS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("PERKS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _store() -> WingRecords:
	var store := WingRecords.new()
	store.path = _path
	return store


func _guard(game: VaultGame) -> bool:
	var ok := game.has_method("unlocked_perks") and "equipped_perk" in game
	_assert_true(ok, "VaultGame has perks")
	return ok


# A seeded game with records on and a win on 07 recorded.
func _unlocked_game() -> VaultGame:
	_clean()
	_store().record(1, true, 2, 7, 7)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _stores(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage]


func _test_none_default() -> void:
	_clean()
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	_store().record(1, true, 2, 7, 7)
	game.equipped_perk = VaultGame.PERK_PROVISIONING
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), [], "records off (test run): nothing unlocked")
	_assert_equal(game.wing_perk, "", "so the wing starts on NONE")
	_assert_equal(_stores(game), [FoodSystem.STARTING_MEALS, FoodSystem.STARTING_SALVAGE], "with the usual stores")
	game.records_path = _path
	game.new_game(false, 0)
	_assert_equal(game.unlocked_perks(), [], "seed 0: nothing unlocked even with records injected")
	_assert_equal([game.wing_perk, _stores(game)], ["", [FoodSystem.STARTING_MEALS, FoodSystem.STARTING_SALVAGE]], "seed 0 stays on NONE")
	_assert_false(game.create_snapshot().has("perk"), "and writes no perk key")
	_dispose(game)
	_clean()


func _test_unlock() -> void:
	_clean()
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.records_path = _path
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), [], "no wins: nothing unlocked")
	_store().record(9, false, null, 5, 7)
	_assert_equal(game.unlocked_perks(), [], "a loss on 07 unlocks nothing")
	_store().record(9, true, 1, 7, 6)
	_assert_equal(game.unlocked_perks(), [], "a win on 06 alone does not unlock the 07 perk")
	_store().record(11, true, 1, 7, 7)
	_assert_equal(game.unlocked_perks(), [VaultGame.PERK_PROVISIONING], "a win on 07 unlocks PROVISIONING")
	_assert_equal(VaultGame.perk_name(VaultGame.PERK_PROVISIONING), "PROVISIONING", "named")
	_assert_equal(VaultGame.perk_name(""), "NONE", "NONE is named")
	_dispose(game)
	_clean()


func _test_apply_once() -> void:
	var game := _unlocked_game()
	if not _guard(game):
		_dispose(game)
		return
	game.equipped_perk = VaultGame.PERK_PROVISIONING
	game.new_game(false, 4242)
	var perk_stores := [FoodSystem.STARTING_MEALS + VaultGame.PROVISIONING_MEALS, FoodSystem.STARTING_SALVAGE - VaultGame.PROVISIONING_SALVAGE_COST]
	_assert_equal(game.wing_perk, VaultGame.PERK_PROVISIONING, "the wing starts with PROVISIONING")
	_assert_equal(_stores(game), perk_stores, "more meals, less salvage")
	_assert_true(VaultGame.PROVISIONING_MEALS > 0 and VaultGame.PROVISIONING_SALVAGE_COST > 0, "a trade-off, not a gift")
	game.new_game(false, 4242, 5)
	_assert_equal(_stores(game), [perk_stores[0], VaultGame.LEAN_STORES_SALVAGE - VaultGame.PROVISIONING_SALVAGE_COST], "on 05 it comes out of the lean stores")
	game.new_game(false, 4242)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, _stores(game)], ["", [FoodSystem.STARTING_MEALS, FoodSystem.STARTING_SALVAGE]], "a NONE wing")
	_assert_true(game.apply_snapshot(saved), "the PROVISIONING save loads over it")
	_assert_equal(game.wing_perk, VaultGame.PERK_PROVISIONING, "LOAD restores the wing's perk")
	_assert_equal(_stores(game), perk_stores, "and the saved stores, granted once")
	_assert_equal(game.equipped_perk, "", "LOAD leaves the player's choice alone")
	_dispose(game)
	_clean()


func _test_save_shape() -> void:
	var game := _unlocked_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_false(game.create_snapshot().has("perk"), "a NONE wing writes no perk key")
	game.equipped_perk = VaultGame.PERK_PROVISIONING
	game.new_game(false, 4242)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(game.create_snapshot().get("perk"), {"version": 1, "id": "provisioning"}, "a perk wing writes {version 1, id}")
	_assert_true(game._is_snapshot_shape_valid(snapshot), "and is valid")
	for bad: Variant in [{"version": 2, "id": "provisioning"}, {"version": 1, "id": "jetpack"}, {"version": 1, "id": 3}, {"version": 1, "id": "provisioning", "x": 1}, "provisioning"]:
		var broken := snapshot.duplicate(true)
		broken["perk"] = bad
		_assert_false(game._is_snapshot_shape_valid(broken), "refused: %s" % [bad])
	_assert_false(game._is_perk_data_valid(snapshot.perk, 0), "refused on seed 0")
	_dispose(game)
	_clean()


func _test_replay() -> void:
	var game := _unlocked_game()
	if not _guard(game):
		_dispose(game)
		return
	game.equipped_perk = VaultGame.PERK_PROVISIONING
	game.new_game(false, 4242)
	game.food_system.meals = 3
	game.new_game(false, game.wing_seed)
	_assert_equal(_stores(game), [FoodSystem.STARTING_MEALS + VaultGame.PROVISIONING_MEALS, FoodSystem.STARTING_SALVAGE - VaultGame.PROVISIONING_SALVAGE_COST], "REPLAY starts fresh with the perk once")
	game.equipped_perk = "jetpack"
	game.new_game(false, 4242)
	_assert_equal(game.wing_perk, "", "an unknown perk falls back to NONE")
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, _stores(game)], ["", [FoodSystem.STARTING_MEALS, FoodSystem.STARTING_SALVAGE]], "unequipped: NONE")
	_dispose(game)
	_clean()
