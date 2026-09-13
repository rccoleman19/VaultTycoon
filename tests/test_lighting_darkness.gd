extends "res://tests/test_runner.gd"

const LIGHTING_SAVE_TEST_PATH := "user://headless_lighting_round_trip.json"


func _run() -> void:
	_run_case("lumen coverage uses the exact inclusive five-cell radius", _test_coverage_geometry_and_starting_counts)
	_run_case("lumen construction, overlap, and removal update coverage", _test_lumen_lifecycle_and_overlap)
	_run_case("paused lumen controls update the resident inspector immediately", _test_paused_lumen_control_and_inspector)
	_run_case("lit and dark residents receive exact integrated mood rates", _test_integrated_mood_rates)
	_run_case("brownout shedding removes lumen coverage until power recovers", _test_brownout_and_recovery)
	_run_case("lighting is derived across active and legacy snapshots", _test_derived_save_and_legacy_state)
	_run_case("coverage display control does not mutate the simulation", _test_display_only_control)
	await _run_layout_case()

	print("")
	if _failure_count == 0:
		print("LIGHTING AND DARKNESS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("LIGHTING AND DARKNESS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


func _run_layout_case() -> void:
	_case_count += 1
	_current_case = "lighting HUD preserves controls and roster space at 1280 by 720"
	var failures_before := _failure_count
	print("[TEST] %s" % _current_case)
	await _test_1280_by_720_layout()
	if _failure_count == failures_before:
		print("[PASS] %s" % _current_case)
	else:
		_failed_case_count += 1


func _test_1280_by_720_layout() -> void:
	root.size = Vector2i(1280, 720)
	var game := _spawn_game()
	game.begin_shift()
	game.player_orders.refresh()
	await process_frame
	await process_frame
	var viewport_rect := root.get_viewport().get_visible_rect()
	_assert_equal(viewport_rect.size, Vector2(1280, 720), "layout test uses the supported desktop viewport")
	var speed_three := _find_button_by_text(game.player_orders.root, "3x")
	_assert_true(speed_three != null, "top bar retains the 3x speed control")
	if speed_three != null:
		_assert_true(speed_three.get_global_rect().end.x <= viewport_rect.end.x, "3x speed control remains inside the viewport")
	var light_button_rect := game.player_orders.lighting_overlay_button.get_global_rect()
	_assert_true(light_button_rect.end.x <= viewport_rect.end.x, "Light Map button remains inside the viewport")
	_assert_true(game.player_orders.right_scroll.size.y >= 100.0, "right HUD preserves meaningful roster and inspector scroll space")
	_assert_true(game.player_orders.right_scroll.get_global_rect().end.y <= viewport_rect.end.y, "right HUD scroll area remains inside the viewport")
	game.player_orders.set_process(false)
	game.player_orders.lighting_label.text = "LIT 1800/1800 · L999/999 · D5"
	await process_frame
	_assert_true(game.player_orders.lighting_overlay_button.get_global_rect().end.x <= viewport_rect.end.x, "late-game lighting counts cannot displace the Light Map button")
	_dispose(game)


func _find_button_by_text(parent: Node, target_text: String) -> Button:
	for candidate: Node in parent.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button != null and button.text == target_text:
			return button
	return null


func _test_coverage_geometry_and_starting_counts() -> void:
	var game := _spawn_game()
	var lighting = game.lighting_system
	_assert_true(lighting != null, "main scene exposes the lighting system")
	_assert_true(_action_has_physical_key("lighting_overlay", KEY_L), "L is configured as the Light Map hotkey")
	_assert_equal(LightingSystem.LUMEN_RADIUS, 5, "a Lumen has a five-cell coverage radius")
	_assert_equal(lighting.get_completed_lumen_count(), 1, "new wing starts with one completed Lumen")
	_assert_equal(lighting.get_powered_lumen_count(), 1, "new wing starts with one powered Lumen")
	_assert_false(lighting.is_coverage_overlay_visible(), "coverage guides are hidden by default")

	# The starting Lumen is fixed at (22, 14). Chebyshev distance keeps the
	# diagonal corner inside coverage and rejects the immediately adjacent ring.
	_assert_true(lighting.is_cell_lit(Vector2i(22, 14)), "a powered Lumen lights its own cell")
	_assert_true(lighting.is_cell_lit(Vector2i(27, 14)), "the axial radius-five boundary is lit")
	_assert_true(lighting.is_cell_lit(Vector2i(27, 19)), "the diagonal radius-five corner is lit")
	_assert_false(lighting.is_cell_lit(Vector2i(28, 14)), "an axial cell at radius six is dark")
	_assert_false(lighting.is_cell_lit(Vector2i(28, 20)), "a diagonal cell outside radius five is dark")
	_assert_equal(lighting.get_lit_floor_count(), 99, "starting Lumen lights exactly ninety-nine chamber floor cells")
	_assert_equal(lighting.get_dark_floor_count(), 21, "twenty-one starting chamber floor cells remain dark")
	_assert_equal(
		lighting.get_lit_floor_count() + lighting.get_dark_floor_count(),
		game.map_grid.get_floor_cells().size(),
		"lit and dark counts partition all carved floor",
	)
	_assert_true(game.map_grid.z_index < lighting.z_index, "darkness renders above carved floor")
	_assert_true(lighting.z_index < game.building_root.z_index, "darkness renders below fixtures")
	_assert_true(lighting.z_index < game.resident_root.z_index, "darkness renders below residents and their status labels")
	for resident: VaultResident in game.residents:
		_assert_true(lighting.is_cell_lit(resident.get_cell(game.map_grid)), "%s starts in powered light" % resident.resident_name)

	game.player_orders.refresh()
	_assert_true("LIT 99/120" in game.player_orders.lighting_label.text, "right HUD reports exact starting floor coverage")
	_assert_true("L1/1" in game.player_orders.lighting_label.text, "right HUD reports powered and completed Lumens")
	_assert_true("D0" in game.player_orders.lighting_label.text, "right HUD reports that every starting resident is lit")
	_assert_true(game.player_orders.lighting_overlay_button.text.ends_with("OFF"), "right HUD reports the default Light Map state")
	var starting_lumen: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	game.select_building(starting_lumen.building_id)
	game.player_orders.refresh()
	_assert_true("Light: ACTIVE · 5-tile radius" in game.player_orders.inspector_state.text, "Lumen inspector names active state and exact radius")
	_assert_true("Footprint: 99 carved floor cells" in game.player_orders.inspector_state.text, "Lumen inspector names its exact starting footprint")
	_assert_true("Darkness outside coverage: -30 mood/day" in game.player_orders.inspector_state.text, "Lumen inspector explains the exact darkness pressure")

	var dark_resident: VaultResident = game.residents[0]
	dark_resident.position = game.map_grid.cell_to_world(Vector2i(28, 20))
	game.player_orders.refresh()
	_assert_true("D1" in game.player_orders.lighting_label.text, "right HUD updates when one resident enters darkness")
	_assert_true("DARKNESS · 1 CREW UNLIT" in game.player_orders.alert_label.text, "darkness alert reports the affected crew count")

	var dark_rock := Vector2i(29, 20)
	var topology_before := game.map_grid.topology_revision
	_assert_true(game.map_grid.queue_dig(dark_rock), "a dark rock cell adjacent to the chamber can be queued")
	_assert_true(game.map_grid.apply_dig_work(dark_rock, 8.0), "dark excavation completes through the map API")
	_assert_equal(game.map_grid.topology_revision, topology_before + 1, "excavation advances the topology revision")
	_assert_true(lighting.is_floor_dark(dark_rock), "new dark floor appears in the lighting cache immediately")
	_assert_equal(lighting.get_lit_floor_count(), 99, "dark excavation does not change powered coverage")
	_assert_equal(lighting.get_dark_floor_count(), 22, "dark excavation immediately expands the darkness count")
	_dispose(game)


func _test_lumen_lifecycle_and_overlap() -> void:
	var game := _spawn_game()
	var lighting = game.lighting_system
	var starting_lumen: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	var target := Vector2i(28, 20)
	_assert_true(game.toggle_building_enabled(starting_lumen.building_id), "starting Lumen can be disabled")
	_assert_equal(lighting.get_completed_lumen_count(), 1, "disabled Lumen remains a completed fixture")
	_assert_equal(lighting.get_powered_lumen_count(), 0, "disabled Lumen provides no powered source")
	_assert_false(lighting.is_cell_lit(target), "target begins dark without a powered source")

	game.begin_shift()
	game.user_paused = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, target), "Lumen blueprint accepts empty carved floor")
	var first_lumen: VaultBuilding = game.get_building_at(target)
	game.power_grid.recalculate(game.buildings)
	_assert_equal(lighting.get_completed_lumen_count(), 1, "unfinished blueprint is excluded from completed Lumen count")
	_assert_equal(lighting.get_powered_lumen_count(), 0, "unfinished blueprint cannot provide powered light")
	_assert_false(lighting.is_cell_lit(target), "unfinished Lumen does not light its own cell")

	first_lumen.add_delivery(first_lumen.get_cost())
	first_lumen.apply_build_work(first_lumen.get_build_time())
	game.power_grid.recalculate(game.buildings)
	_assert_true(first_lumen.complete and first_lumen.powered, "supplied and assembled Lumen receives power")
	_assert_equal(lighting.get_completed_lumen_count(), 2, "finished Lumen joins the completed count")
	_assert_equal(lighting.get_powered_lumen_count(), 1, "finished Lumen joins powered coverage")
	_assert_true(lighting.is_cell_lit(target), "finished powered Lumen lights its own cell")

	var second_lumen := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(26, 20))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(lighting.get_completed_lumen_count(), 3, "overlapping fixture is counted independently")
	_assert_equal(lighting.get_powered_lumen_count(), 2, "both enabled overlapping Lumens receive emergency power")
	_assert_true(lighting.is_cell_lit(target), "overlapping powered Lumens cover the target")
	_assert_true(game.toggle_building_enabled(first_lumen.building_id), "one overlapping Lumen can be disabled")
	_assert_true(lighting.is_cell_lit(target), "remaining overlapping Lumen preserves coverage")
	_assert_true(game.deconstruct_building(first_lumen.building_id), "disabled overlapping Lumen can be removed")
	_assert_true(lighting.is_cell_lit(target), "removing one source preserves the other source's light")
	_assert_true(game.deconstruct_building(second_lumen.building_id), "last overlapping Lumen can be removed")
	_assert_false(lighting.is_cell_lit(target), "target becomes dark immediately after its last source is removed")
	_assert_equal(lighting.get_completed_lumen_count(), 1, "only the disabled starting Lumen remains")
	_assert_equal(lighting.get_powered_lumen_count(), 0, "no powered Lumens remain after removal")
	_dispose(game)


func _test_paused_lumen_control_and_inspector() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.set_tool("dig")
	var resident: VaultResident = game.residents[0]
	resident.position = game.map_grid.cell_to_world(Vector2i(27, 19))
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	game.select_resident(resident.resident_id)
	game.player_orders.refresh()
	var lumen: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	_assert_true("Lit · -18 mood/day" in game.player_orders.inspector_state.text, "resident inspector reports powered light and its exact mood rate")

	_assert_true(game.toggle_building_enabled(lumen.building_id), "completed Lumen accepts manual disable while paused")
	game.player_orders.refresh()
	_assert_true(game.is_simulation_paused(), "disabling a Lumen preserves the paused state")
	_assert_equal(game.active_tool, "dig", "disabling a Lumen preserves the active map tool")
	_assert_equal(game.selected_resident_id, resident.resident_id, "disabling a Lumen preserves resident selection")
	_assert_false(game.lighting_system.is_cell_lit(resident.get_cell(game.map_grid)), "manual disable removes coverage immediately")
	_assert_true("Dark · -48 mood/day" in game.player_orders.inspector_state.text, "resident inspector reports darkness immediately")

	_assert_true(game.toggle_building_enabled(lumen.building_id), "disabled Lumen can be re-enabled while paused")
	game.player_orders.refresh()
	_assert_true(game.is_simulation_paused(), "re-enabling a Lumen preserves the paused state")
	_assert_true(game.lighting_system.is_cell_lit(resident.get_cell(game.map_grid)), "manual enable restores coverage immediately")
	_assert_true("Lit · -18 mood/day" in game.player_orders.inspector_state.text, "resident inspector returns to the lit rate")
	_dispose(game)


func _test_integrated_mood_rates() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_prepare_stable_residents(game)
	var lit_resident: VaultResident = game.residents[0]
	var dark_resident: VaultResident = game.residents[1]
	lit_resident.position = game.map_grid.cell_to_world(Vector2i(27, 19))
	dark_resident.position = game.map_grid.cell_to_world(Vector2i(28, 20))
	_assert_true(game.lighting_system.is_cell_lit(lit_resident.get_cell(game.map_grid)), "integration fixture places one resident at the lit boundary")
	_assert_false(game.lighting_system.is_cell_lit(dark_resident.get_cell(game.map_grid)), "integration fixture places one resident just outside coverage")

	game.step_simulation(1.0)
	_assert_approximately(lit_resident.needs.mood, 79.55, 0.0001, "one lit second applies eighteen mood points per day")
	_assert_approximately(dark_resident.needs.mood, 78.8, 0.0001, "one dark second applies baseline plus thirty darkness points per day")
	_assert_approximately(lit_resident.needs.mood - dark_resident.needs.mood, 0.75, 0.0001, "darkness costs exactly thirty additional mood points per day")
	_dispose(game)


func _test_brownout_and_recovery() -> void:
	var game := _spawn_game()
	var lumen: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var first_recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "brownout fixture has nine available power")
	_assert_equal(game.power_grid.demand, 10, "three critical recyclers and one Lumen demand ten power")
	_assert_true(game.power_grid.is_building_shed(lumen.building_id), "critical recycler load sheds the lower-priority Lumen")
	_assert_false(lumen.powered, "shed Lumen is not powered")
	_assert_equal(game.lighting_system.get_powered_lumen_count(), 0, "shed Lumen is absent from powered source count")
	_assert_equal(game.lighting_system.get_lit_floor_count(), 0, "shed last Lumen leaves no lit floor")
	_assert_equal(game.lighting_system.get_dark_floor_count(), 120, "shed last Lumen leaves every chamber tile dark")

	var resident: VaultResident = game.residents[0]
	resident.position = game.map_grid.cell_to_world(Vector2i(22, 14))
	game.select_resident(resident.resident_id)
	game.player_orders.refresh()
	_assert_true("Dark" in game.player_orders.inspector_state.text, "resident inspector reflects brownout darkness")
	_assert_true(game.toggle_building_enabled(first_recycler.building_id), "disabling one critical load frees power")
	_assert_true(lumen.powered, "Lumen is restored immediately after power recovery")
	_assert_false(game.power_grid.brownout_active, "freeing critical demand clears the brownout")
	_assert_equal(game.lighting_system.get_powered_lumen_count(), 1, "recovered Lumen returns to powered source count")
	_assert_equal(game.lighting_system.get_lit_floor_count(), 99, "recovered Lumen restores its exact floor coverage")
	game.player_orders.refresh()
	_assert_true("Lit" in game.player_orders.inspector_state.text, "resident inspector reflects recovered light")
	_dispose(game)


func _test_derived_save_and_legacy_state() -> void:
	_remove_test_save(LIGHTING_SAVE_TEST_PATH)
	var original := _spawn_game()
	var lumen: VaultBuilding = original.get_building_at(Vector2i(22, 14))
	_assert_true(original.toggle_building_enabled(lumen.building_id), "save fixture disables its Lumen")
	_assert_true(original.toggle_lighting_overlay(), "transient coverage guides can be on while saving")
	_assert_true(original.save_game(false, LIGHTING_SAVE_TEST_PATH), "disabled-Lumen snapshot writes to an isolated save")
	var disabled_snapshot: Dictionary = original.create_snapshot()
	for transient_key in ["lighting", "light_map", "lighting_overlay", "coverage_overlay_visible"]:
		_assert_false(disabled_snapshot.has(transient_key), "snapshot omits transient %s state" % transient_key)
	var saved_lumen := _building_snapshot(disabled_snapshot, lumen.building_id)
	_assert_false(saved_lumen.is_empty(), "snapshot contains the starting Lumen")
	# Powered flags are cached output. A load must derive lighting from the
	# restored fixture and a fresh power allocation instead of trusting this.
	saved_lumen.powered = true

	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(disabled_snapshot), "disabled-Lumen snapshot loads")
	var loaded_lumen: VaultBuilding = loaded.get_building_by_id(lumen.building_id)
	_assert_true(loaded_lumen.manually_disabled, "manual Lumen control survives the round trip")
	_assert_false(loaded_lumen.powered, "load corrects a stale powered flag on a disabled Lumen")
	_assert_equal(loaded.lighting_system.get_completed_lumen_count(), 1, "loaded completed Lumen count is derived from fixtures")
	_assert_equal(loaded.lighting_system.get_powered_lumen_count(), 0, "loaded powered Lumen count is derived after grid allocation")
	_assert_equal(loaded.lighting_system.get_lit_floor_count(), 0, "loaded disabled Lumen supplies no coverage")
	_assert_equal(loaded.lighting_system.get_dark_floor_count(), 120, "loaded disabled Lumen leaves all floor dark")

	var legacy_snapshot: Dictionary = disabled_snapshot.duplicate(true)
	var legacy_lumen := _building_snapshot(legacy_snapshot, lumen.building_id)
	legacy_lumen.erase("manually_disabled")
	_assert_true(loaded.apply_snapshot(legacy_snapshot), "legacy snapshot without manual-disable state loads")
	loaded_lumen = loaded.get_building_by_id(lumen.building_id)
	_assert_false(loaded_lumen.manually_disabled, "legacy Lumen defaults to enabled")
	_assert_true(loaded_lumen.powered, "legacy enabled Lumen receives recomputed power")
	_assert_equal(loaded.lighting_system.get_powered_lumen_count(), 1, "legacy load rebuilds the powered source count")
	_assert_equal(loaded.lighting_system.get_lit_floor_count(), 99, "legacy load rebuilds exact coverage")
	_assert_equal(loaded.lighting_system.get_dark_floor_count(), 21, "legacy load rebuilds the complementary dark count")
	_assert_true(loaded.toggle_lighting_overlay(), "coverage can be shown before a rejected load")
	var invalid_snapshot: Dictionary = legacy_snapshot.duplicate(true)
	invalid_snapshot.map.cells.pop_back()
	_assert_false(loaded.apply_snapshot(invalid_snapshot), "structurally invalid snapshot is rejected")
	_assert_true(loaded.lighting_system.is_coverage_overlay_visible(), "rejected load preserves transient coverage visibility")
	_assert_equal(loaded.lighting_system.get_lit_floor_count(), 99, "rejected load preserves derived lit coverage")
	_assert_equal(loaded.lighting_system.get_dark_floor_count(), 21, "rejected load preserves derived dark coverage")

	var file_loaded := _spawn_game()
	_assert_true(file_loaded.toggle_lighting_overlay(), "fresh load target can show transient coverage guides")
	_assert_true(file_loaded.load_game(LIGHTING_SAVE_TEST_PATH), "saved disabled-Lumen state loads through the public file path")
	_assert_false(file_loaded.lighting_system.is_coverage_overlay_visible(), "file load resets transient coverage guides to off")
	_assert_false(file_loaded.get_building_by_id(lumen.building_id).powered, "file load recomputes the disabled Lumen offline")
	_assert_equal(file_loaded.lighting_system.get_dark_floor_count(), 120, "file load derives a fully dark chamber")
	_dispose(file_loaded)
	_dispose(loaded)
	_dispose(original)
	_remove_test_save(LIGHTING_SAVE_TEST_PATH)


func _test_display_only_control() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.set_speed(3)
	game.set_tool("dig")
	var resident: VaultResident = game.residents[0]
	game.select_resident(resident.resident_id)
	game.world_camera.position = Vector2(512.0, 408.0)
	var elapsed_before := game.day_cycle.elapsed_seconds
	var mood_before := resident.needs.mood
	var camera_before := game.world_camera.position
	var lit_before := game.lighting_system.is_cell_lit(resident.get_cell(game.map_grid))
	var lit_count_before := game.lighting_system.get_lit_floor_count()
	var dark_count_before := game.lighting_system.get_dark_floor_count()

	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "coverage display starts hidden")
	var lighting_event := InputEventKey.new()
	lighting_event.physical_keycode = KEY_L
	lighting_event.pressed = true
	lighting_event.echo = true
	game._unhandled_input(lighting_event)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "repeated L key events do not flicker the coverage view")
	lighting_event.echo = false
	game.player_orders.show_work_priorities(true)
	game._unhandled_input(lighting_event)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "work-priority modal blocks the Light Map shortcut")
	game.player_orders.show_work_priorities(false)
	game.player_orders.show_briefing(true, false)
	game._unhandled_input(lighting_event)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "Help blocks the Light Map shortcut")
	game.player_orders.show_briefing(false)
	game.breach_system.phase = BreachSystem.Phase.WARNING
	game.breach_system.warning_acknowledged = false
	game._unhandled_input(lighting_event)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "unacknowledged breach warning blocks the Light Map shortcut")
	game.breach_system.phase = BreachSystem.Phase.DORMANT
	game.ended = true
	game._unhandled_input(lighting_event)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "outcome state blocks the Light Map shortcut")
	game.ended = false
	game._unhandled_input(lighting_event)
	_assert_true(game.lighting_system.is_coverage_overlay_visible(), "dispatching L shows powered-Lumen coverage")
	_assert_false(game.is_simulation_paused(), "showing coverage does not pause a running shift")
	_assert_equal(game.simulation_speed, 3, "showing coverage preserves simulation speed")
	_assert_equal(game.active_tool, "dig", "showing coverage preserves the active tool")
	_assert_equal(game.selected_resident_id, resident.resident_id, "showing coverage preserves selection")
	_assert_equal(game.world_camera.position, camera_before, "showing coverage preserves the camera")
	_assert_equal(game.day_cycle.elapsed_seconds, elapsed_before, "display control does not advance simulation time")
	_assert_approximately(resident.needs.mood, mood_before, 0.0001, "display control does not alter mood")
	_assert_equal(game.lighting_system.is_cell_lit(resident.get_cell(game.map_grid)), lit_before, "display visibility does not alter simulated lighting")
	_assert_equal(game.lighting_system.get_lit_floor_count(), lit_count_before, "display visibility does not alter lit coverage")
	_assert_equal(game.lighting_system.get_dark_floor_count(), dark_count_before, "display visibility does not alter dark coverage")

	game.user_paused = true
	game.toggle_lighting_overlay()
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "display control hides coverage while paused")
	_assert_true(game.is_simulation_paused(), "hiding coverage preserves a paused shift")
	_assert_equal(game.simulation_speed, 3, "hiding coverage preserves speed")
	_assert_equal(game.active_tool, "dig", "hiding coverage preserves the active tool")
	_assert_equal(game.selected_resident_id, resident.resident_id, "hiding coverage preserves selection")
	_assert_equal(game.world_camera.position, camera_before, "hiding coverage preserves the camera")
	_assert_equal(game.day_cycle.elapsed_seconds, elapsed_before, "hiding coverage does not advance simulation time")
	_assert_approximately(resident.needs.mood, mood_before, 0.0001, "hiding coverage does not alter mood")
	_assert_equal(game.lighting_system.is_cell_lit(resident.get_cell(game.map_grid)), lit_before, "hiding coverage does not alter simulated lighting")

	game.toggle_lighting_overlay()
	_assert_true(game.lighting_system.is_coverage_overlay_visible(), "coverage can be shown before resetting the wing")
	game.new_game(false)
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "New Wing resets transient coverage guides to off")
	var snapshot := game.create_snapshot()
	game.toggle_lighting_overlay()
	_assert_true(game.lighting_system.is_coverage_overlay_visible(), "coverage can be shown before applying a snapshot")
	_assert_true(game.apply_snapshot(snapshot), "display-reset fixture snapshot loads")
	_assert_false(game.lighting_system.is_coverage_overlay_visible(), "applying a snapshot resets transient coverage guides to off")
	_dispose(game)


func _prepare_stable_residents(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 80.0
		resident.needs.health = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.recreating = false
		resident.recreation_id = -1
		resident.stress_break_left = 0.0
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
		game.job_system.release_resident(resident)


func _building_snapshot(snapshot: Dictionary, building_id: int) -> Dictionary:
	for entry: Variant in snapshot.get("buildings", []):
		if entry is Dictionary and int(entry.get("id", -1)) == building_id:
			return entry
	return {}
