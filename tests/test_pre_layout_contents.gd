extends "res://tests/test_runner.gd"

# Codex P3 on #110 (issuecomment-6259872107): a pre-layout seeded save must not get the
# contents line. show_wing_id used to key off nonzero wing_seed alone, before apply_layout_seed
# had set layout_seed, so HELP after load advertised pockets the compatibility map lacks.


func _run() -> void:
	_run_case("a pre-layout seeded save keeps hatch timing but drops the contents line", _test_pre_layout_load)
	_run_case("HELP after that load still omits the contents line", _test_help_reopen)
	_run_case("a map_layout seeded save and NEW WING still name their contents", _test_seeded_still_shows)
	_run_case("seed 0 stays a one-line legacy title", _test_legacy_unchanged)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("PRE-LAYOUT CONTENTS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("PRE-LAYOUT CONTENTS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count
		])
		quit(1)


func _title(game: VaultGame) -> String:
	return game.player_orders.wing_briefing_title.text


func _pre_layout_snapshot(wing_seed: int = 4242) -> Dictionary:
	var game := _spawn_game()
	game.new_game(false, wing_seed)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(int(snapshot.get("map_layout", 0)), VaultGame.MAP_LAYOUT_SEEDED, "fresh seeded save records map_layout")
	_assert_true(_title(game).contains("POCKETS"), "fresh NEW WING names contents before we strip the key")
	snapshot.erase("map_layout")
	_dispose(game)
	return snapshot


func _test_pre_layout_load() -> void:
	var snapshot := _pre_layout_snapshot(4242)
	var game := _spawn_game()
	game.new_game(false, 77)
	_assert_true(game.apply_snapshot(snapshot), "pre-layout seeded save loads")
	_assert_equal(game.wing_seed, 4242, "wing_seed restored")
	_assert_equal(game.map_grid.layout_seed, 0, "compatibility map keeps layout_seed 0")
	_assert_equal(game.map_grid.get_initial_floor_count(), 120, "compatibility map is the chamber")
	var lines := _title(game).split("\n")
	_assert_equal(lines.size(), 2, "title has id and hatch test only")
	_assert_true(lines[0].begins_with("VAULT WING 07-"), "id line names the seeded wing")
	_assert_true(lines[1].begins_with("HATCH TEST AT"), "hatch timing still follows wing_seed")
	_assert_false(_title(game).contains("POCKETS"), "contents line stays off")
	_assert_false(_title(game).contains("VEINS"), "veins stay unnamed")
	_dispose(game)


func _test_help_reopen() -> void:
	var snapshot := _pre_layout_snapshot(4242)
	var game := _spawn_game()
	game.new_game(false, 77)
	_assert_equal(game.map_grid.layout_seed, 77, "start from a seeded wing so a stale layout_seed would falsely keep contents")
	_assert_true(game.apply_snapshot(snapshot), "pre-layout save loads for HELP")
	game.begin_shift()
	game.user_paused = true
	game.player_orders.open_help()
	_assert_true(game.player_orders.is_help_open(), "HELP opens")
	_assert_false(_title(game).contains("POCKETS"), "reopened HELP keeps the load title without contents")
	_assert_equal(_title(game).split("\n").size(), 2, "HELP title still has two lines")
	_dispose(game)


func _test_seeded_still_shows() -> void:
	var game := _spawn_game()
	game.new_game(true, 4242)
	var expected := PlayerOrders.wing_layout_summary(4242)
	_assert_true(_title(game).ends_with(expected), "NEW WING still names contents")
	_assert_equal(game.map_grid.layout_seed, 4242, "NEW WING applied the layout")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(int(snapshot.get("map_layout", 0)), VaultGame.MAP_LAYOUT_SEEDED, "seeded save keeps map_layout")
	game.new_game(false, 1)
	_assert_true(game.apply_snapshot(snapshot), "map_layout seeded save loads")
	_assert_equal(game.map_grid.layout_seed, 4242, "layout_seed restored with map_layout")
	_assert_true(_title(game).ends_with(expected), "loaded seeded save still names contents")
	_assert_equal(_title(game).split("\n").size(), 3, "loaded seeded title keeps three lines")
	_dispose(game)


func _test_legacy_unchanged() -> void:
	var game := _spawn_game()
	var legacy := "VAULT WING 07 // SEAL STABILIZATION"
	_assert_equal(_title(game), legacy, "boot legacy title")
	game.new_game(false, 0)
	_assert_equal(_title(game), legacy, "seed 0 NEW WING title")
	_assert_false(_title(game).contains("POCKETS"), "seed 0 names no pockets")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_false(snapshot.has("map_layout"), "legacy save has no map_layout")
	game.new_game(false, 4242)
	_assert_true(game.apply_snapshot(snapshot), "legacy save loads")
	_assert_equal(_title(game), legacy, "legacy load title unchanged")
	_dispose(game)
