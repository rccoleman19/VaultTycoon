extends "res://tests/test_runner.gd"

# Wing-seed slice 3: each seeded resident gets one trait from the wing seed. Seed 0 has none.

const GOLDEN := {
	1: "CHEF,PATCHER,CALM,DIGGER,FRUGAL",
	8: "FRUGAL,CALM,DIGGER,PATCHER,CHEF",
	4242: "CALM,PATCHER,DIGGER,CHEF,FRUGAL",
	65535: "PATCHER,DIGGER,FRUGAL,CHEF,CALM",
}


func _run() -> void:
	_run_case("seed 0 and seedless wings have no traits and no key", _test_legacy)
	_run_case("every seed deals a frozen 5-slot permutation; all 120 crews occur", _test_all_seeds)
	_run_case("a new seeded wing gives resident N slot N-1 and writes the marker", _test_new_wing)
	_run_case("each trait changes only its own number", _test_effects)
	_run_case("dig, cook and patch work use the trait at the job", _test_job_effects)
	_run_case("traits are derived on load by resident id, never saved", _test_save_load)
	_run_case("pre-trait seeded saves stay trait-free; bad markers are rejected", _test_compat)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("CREW TRAITS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("CREW TRAITS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _traits(game: VaultGame) -> Array[String]:
	var out: Array[String] = []
	for resident: VaultResident in game.residents:
		out.append(resident.trait_id)
	return out


func _seeded(wing_seed: int) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, wing_seed)
	return game


func _test_legacy() -> void:
	_assert_equal(VaultResident.crew_traits_for_seed(0).size(), 0, "seed 0 deals no traits")
	var game := _spawn_game()
	_assert_equal(_traits(game), ["", "", "", ""] as Array[String], "boot wing has no traits")
	game.new_game(false, 0)
	_assert_equal(_traits(game), ["", "", "", ""] as Array[String], "seed 0 has no traits")
	_assert_false(game.create_snapshot().has("crew_traits"), "seed 0 writes no marker")
	for resident: VaultResident in game.residents:
		_assert_equal(resident.needs.food_drain_scale, 1.0, "%s eats at the legacy rate" % resident.resident_name)
		_assert_equal(resident.needs.base_mood_loss_scale, 1.0, "%s loses mood at the legacy rate" % resident.resident_name)
		_assert_false(resident.needs.serialize().has("food_drain_scale"), "needs saves no trait scale")
	_assert_false(JSON.stringify(game.create_snapshot()).contains("trait"), "no trait text in a legacy save")
	_dispose(game)


func _test_all_seeds() -> void:
	var bad := 0
	var crews := {}
	for wing_seed in range(1, 65536):
		var crew := VaultResident.crew_traits_for_seed(wing_seed)
		var unique := {}
		for t: String in crew:
			unique[t] = true
		if crew.size() != 5 or unique.size() != 5:
			bad += 1
		crews[",".join(crew.slice(0, 4))] = true
	_assert_equal(bad, 0, "every seed deals all five traits once")
	_assert_equal(crews.size(), 120, "all 120 ordered four-resident crews occur")
	_assert_equal(VaultResident.crew_traits_for_seed(4242), VaultResident.crew_traits_for_seed(4242), "same seed, same crew")
	for wing_seed: int in GOLDEN:
		_assert_equal(",".join(VaultResident.crew_traits_for_seed(wing_seed)), GOLDEN[wing_seed], "golden crew for seed %d" % wing_seed)


func _test_new_wing() -> void:
	for wing_seed in [1, 4242, 65535]:
		var game := _seeded(wing_seed)
		var crew := VaultResident.crew_traits_for_seed(wing_seed)
		for resident: VaultResident in game.residents:
			_assert_equal(resident.trait_id, crew[resident.resident_id - 1], "seed %d %s gets slot %d" % [wing_seed, resident.resident_name, resident.resident_id - 1])
		_assert_equal(int(game.create_snapshot().get("crew_traits", 0)), 1, "seed %d writes crew_traits 1" % wing_seed)
		game.new_game(false, 0)
		_assert_equal(_traits(game), ["", "", "", ""] as Array[String], "a later seed-0 wing clears traits")
		_dispose(game)


func _test_effects() -> void:
	for t: String in VaultResident.TRAIT_POOL + [""]:
		var resident := VaultResident.new()
		resident.set_trait(t)
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.advance(0.1, true, false, false)
		_assert_almost(100.0 - resident.needs.food, 5.1 if t == "FRUGAL" else 6.0, "%s food drain" % t)
		_assert_almost(100.0 - resident.needs.mood, 1.35 if t == "CALM" else 1.8, "%s mood loss (base term only)" % t)
		resident.needs.food = 10.0
		resident.needs.mood = 50.0
		resident.needs.advance(0.1, false, false, false)
		_assert_almost(50.0 - resident.needs.mood, (13.5 if t == "CALM" else 18.0) * 0.1 + 3.0 + 1.2, "%s keeps dark and hunger penalties whole" % t)
		resident.needs.food = 100.0
		resident.needs.mood = 100.0
		_assert_equal(resident.needs.get_mood_factors(true, false), "Lit · -%d mood/day" % (14 if t == "CALM" else 18), "%s mood readout matches" % t)
		_assert_equal(resident.get_trait_factor("dig"), 1.25 if t == "DIGGER" else 1.0, "%s dig factor" % t)
		_assert_equal(resident.get_trait_factor("cook"), 1.25 if t == "CHEF" else 1.0, "%s cook factor" % t)
		_assert_equal(resident.get_trait_factor("patch"), 1.15 if t == "PATCHER" else 1.0, "%s patch factor" % t)
		_assert_equal(resident.get_trait_factor("haul"), 1.0, "%s does not touch other work" % t)
		_assert_equal(resident.get_work_multiplier(), 1.0, "%s leaves the general work multiplier alone" % t)
		resident.free()


func _assert_almost(actual: float, expected: float, label: String) -> void:
	_assert_true(absf(actual - expected) < 0.0001, "%s — expected %.4f, got %.4f" % [label, expected, actual])


func _job(game: VaultGame, resident: VaultResident, type: int, target: Vector2i, building_id := -1) -> void:
	var js := game.job_system
	js.jobs.clear()
	js._add_job(type, target, building_id)
	var job: Dictionary = js.jobs[-1]
	job.reserved_by = resident.resident_id
	resident.current_job_id = int(job.id)
	resident.current_job_type = type


func _fresh(resident: VaultResident, t: String, cell: Vector2i, game: VaultGame) -> void:
	resident.set_trait(t)
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 100.0
	resident.position = game.map_grid.cell_to_world(cell)
	resident.clear_path()


func _test_job_effects() -> void:
	for t: String in ["", "DIGGER", "CHEF", "PATCHER"]:
		var game := _seeded(4242)
		var resident: VaultResident = game.residents[0]
		# DIG: rock just west of the chamber, worked from the chamber edge.
		var rock := Vector2i(16, 15)
		game.map_grid.dig_marks[rock] = true
		_fresh(resident, t, game.map_grid.nearest_walkable_neighbor(rock, Vector2i(17, 15)), game)
		_job(game, resident, JobSystem.JobType.DIG, rock)
		game.job_system._process_job(resident, 0.1)
		_assert_almost(float(game.map_grid.dig_progress.get(rock, 0.0)), 0.1 * (1.25 if t == "DIGGER" else 1.0), "%s digs at its rate" % t)
		# COOK: a powered kitchen with raw food.
		var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 13))
		kitchen.powered = true
		game.food_system.raw_food = 20
		_fresh(resident, t, kitchen.cell, game)
		resident.work_accumulator = 0.0
		_job(game, resident, JobSystem.JobType.COOK, kitchen.cell, kitchen.building_id)
		game.job_system._process_job(resident, 0.1)
		_assert_almost(resident.work_accumulator, 0.1 * (1.25 if t == "CHEF" else 1.0), "%s cooks at its rate" % t)
		# PATCH: a supplied hatch during WARNING.
		game.breach_system.phase = BreachSystem.Phase.WARNING
		game.breach_system.patch_delivered = BreachSystem.PATCH_COST
		_fresh(resident, t, BreachSystem.HATCH_CELL, game)
		_job(game, resident, JobSystem.JobType.PATCH_BREACH, BreachSystem.HATCH_CELL)
		game.job_system._process_job(resident, 0.1)
		_assert_almost(BreachSystem.PATCH_WORK_SECONDS - game.breach_system.patch_work_left, 0.1 * (1.15 if t == "PATCHER" else 1.0), "%s patches at its rate" % t)
		_dispose(game)


func _test_save_load() -> void:
	var a := _seeded(4242)
	var b := _seeded(1)
	var snap_b := b.create_snapshot()
	_assert_false(JSON.stringify(snap_b.residents).contains("trait"), "residents save no trait")
	_assert_true(a.apply_snapshot(snap_b.duplicate(true)), "seed 1 loads over seed 4242")
	_assert_equal(_traits(a), _traits(b), "loaded crew is seed 1's, not stale")
	var reordered: Dictionary = snap_b.duplicate(true)
	reordered.residents.reverse()
	reordered.residents.remove_at(1)
	_assert_true(a.apply_snapshot(reordered), "reordered save with a missing resident loads")
	var crew := VaultResident.crew_traits_for_seed(1)
	for resident: VaultResident in a.residents:
		_assert_equal(resident.trait_id, crew[resident.resident_id - 1], "%s keeps its id slot after reorder" % resident.resident_name)
	var legacy := _spawn_game()
	_assert_true(a.apply_snapshot(legacy.create_snapshot()), "legacy loads over a traited wing")
	_assert_equal(_traits(a), ["", "", "", ""] as Array[String], "and clears every trait")
	for resident: VaultResident in a.residents:
		_assert_equal(resident.needs.food_drain_scale, 1.0, "%s scales reset" % resident.resident_name)
	_dispose(legacy)
	_dispose(a)
	_dispose(b)


func _test_compat() -> void:
	var game := _seeded(4242)
	var pre: Dictionary = game.create_snapshot()
	pre.erase("crew_traits")
	_assert_true(game.apply_snapshot(pre.duplicate(true)), "a #110 seeded save without the marker loads")
	_assert_equal(_traits(game), ["", "", "", ""] as Array[String], "and gains no traits")
	_assert_false(game.create_snapshot().has("crew_traits"), "re-saving keeps it marker-free")
	var bad: Dictionary = pre.duplicate(true)
	bad["crew_traits"] = 2
	_assert_false(game.apply_snapshot(bad), "an unknown marker version is rejected")
	bad["crew_traits"] = "1"
	_assert_false(game.apply_snapshot(bad), "a non-integer marker is rejected")
	var seedless: Dictionary = pre.duplicate(true)
	seedless["crew_traits"] = 1
	seedless["wing_seed"] = 0
	seedless.erase("map_layout")
	if game.apply_snapshot(seedless):
		_assert_equal(_traits(game), ["", "", "", ""] as Array[String], "a seedless save with a marker stays trait-free")
	_dispose(game)
