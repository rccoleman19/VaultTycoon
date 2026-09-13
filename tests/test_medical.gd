extends "res://tests/test_runner.gd"
var failures := 0
func _init() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr(message)
func _run() -> void:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	var resident: VaultResident = game.residents[0]
	resident.apply_damage(40.0)
	game.job_system.advance(1.0)
	check(resident.needs.health == 60.0, "No bed must not heal")
	game.set_tool("medical")
	check(game.issue_order(Vector2i(20, 12)), "Medical blueprint accepts player order")
	var bed := game.get_building_at(Vector2i(20, 12))
	check(bed.get_cost() == 8 and bed.get_build_time() == 8.0, "Medical construction contract")
	check(not bed.complete, "Blueprint starts unfinished")
	game.job_system.advance(1.0)
	check(resident.needs.health == 60.0, "Unfinished bed must not heal")
	bed.add_delivery(8)
	bed.apply_build_work(8.0)
	resident.position = game.map_grid.cell_to_world(bed.cell)
	game.job_system.advance(1.0)
	check(resident.needs.health == 62.0 and resident.state == "Rest-Medical", "Injury recovers only in bed")
	var second: VaultResident = game.residents[1]
	second.apply_damage(20.0)
	game.job_system.advance(1.0)
	check(second.needs.health == 80.0, "Bed has one patient capacity")
	check(game.toggle_building_enabled(bed.building_id), "Care can be denied")
	var hp := resident.needs.health
	game.job_system.advance(1.0)
	check(resident.needs.health == hp and bed.reserved_by == -1, "Disabled bed releases patient without healing")
	check(game.toggle_building_enabled(bed.building_id), "Care can resume")
	game.job_system.advance(1.0)
	game.select_building(bed.building_id)
	game.player_orders.refresh()
	check("Recovery: +2 HP/s" in game.player_orders.inspector_state.text, "Inspector explains recovery")
	check("INJURED 2" in game.player_orders.alert_label.text, "HUD counts injuries")
	var snapshot := game.create_snapshot()
	check(game.apply_snapshot(snapshot), "Medical fixture and health snapshot loads")
	resident = game.residents[0]
	bed = game.get_building_at(Vector2i(20, 12))
	game.job_system.advance(1.0)
	check(resident.medical_bed_id == bed.building_id, "Loaded patient reclaims care")
	for i in 60:
		game.job_system.advance(1.0)
	check(resident.needs.health == 100.0, "Care reaches full health without overflow")
	resident.apply_damage(20.0)
	game.job_system.advance(1.0)
	check(game.deconstruct_building(bed.building_id), "Occupied bed can be removed")
	check(resident.medical_bed_id == -1, "Removal releases care")
	hp = resident.needs.health
	game.job_system.advance(1.0)
	check(resident.needs.health == hp, "Removed bed cannot heal")
	# A new distant bed does not heal until the patient physically arrives.
	check(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12)), "replacement blueprint accepted")
	bed = game.get_building_at(Vector2i(27, 12))
	bed.add_delivery(8)
	bed.apply_build_work(8.0)
	resident.position = game.map_grid.cell_to_world(Vector2i(18, 12))
	game.job_system.advance(0.01)
	check(resident.needs.health == hp, "Walking to care does not heal")
	resident.kill()
	check(bed.reserved_by == -1, "Death releases medical reservation")
	game.free()
	_test_managed_day_seven_win(true)
	failures += _failure_count
	print("Medical tests: %d failures" % failures)
	quit(1 if failures else 0)
