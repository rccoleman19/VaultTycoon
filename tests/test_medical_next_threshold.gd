extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEEK_HP := 95.0
const JUST_ABOVE := 95.0001
const DIG := ["Next: YOU mark rock [E] · THEY dig on Dig defaults", "dig", "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional."]
const PLACE := ["Next: YOU place a Med Bed · THEY treat", "medical", "Place a Med Bed so the injured can be treated."]
const ENABLE := ["Next: YOU enable a Med Bed · THEY treat", "select", "Select a completed Med Bed and click ENABLE so the injured can be treated."]
const FINISH := ["Next: YOU leave Haul + Craft on · THEY finish the Med Bed", "select", "Keep Haul + Craft above OFF so crew supply and finish the Med Bed blueprint."]
const BUNKS := ["Next: YOU place bunks · THEY craft", "bed", "Place bunks so tired undrafted crew have a bed."]

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("predicate shares the inclusive seek threshold", _test_predicate)
	for hp in [94.999, SEEK_HP, JUST_ABOVE, 96.0, 99.0, 99.999, 100.0]:
		_run_case("place boundary HP %s" % str(hp), _test_place.bind(hp))
	_run_case("enable boundary", _test_enable)
	_run_case("finish boundary", _test_finish)
	_run_case("occupied bed only needs a spare for an eligible injury", _test_occupied)
	_run_case("above-threshold injury falls through to bunks", _test_fallthrough)
	for hp in [94.999, SEEK_HP, JUST_ABOVE, 99.0, 100.0]:
		_run_case("guidance admission parity HP %s" % str(hp), _test_parity.bind(hp))
	_run_case("admitted patient heals past threshold to full health", _test_heals)
	_run_case("stranded at 97 remains injured without seeking care", _test_stranded)
	_run_case("food gate stays admission-only", _test_food)
	_run_case("dead resident does not request care", _test_dead)
	_run_case("inspector and build-card strings retain threshold", _test_strings)
	_run_case("refresh preserves dig tool across the threshold", _test_refresh)
	print("MEDICAL NEXT THRESHOLD TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	game.food_system.meals = game.get_alive_count()
	_assert_step(game, DIG)
	return game


func _add_completed(game: VaultGame, kind: int, cell: Vector2i) -> VaultBuilding:
	var building := VaultBuilding.new()
	game.building_root.add_child(building)
	building.configure(game.next_building_id, kind as VaultBuilding.Kind, cell, true)
	game.next_building_id += 1
	game.buildings.append(building)
	return building


func _test_predicate() -> void:
	var game := _spawn_game()
	var needs = game.residents[0].needs
	_assert_equal(needs.get_script().get_script_constant_map().get("MEDICAL_SEEK_THRESHOLD"), SEEK_HP, "shared threshold constant")
	var has_predicate: bool = needs.has_method("wants_medical_care")
	_assert_equal(has_predicate, true, "medical predicate exists")
	# Pre-fix production must report missing API as failures without calling it.
	if has_predicate:
		for hp in [0.0, 94.999, SEEK_HP, JUST_ABOVE, 99.999, 100.0]:
			needs.health = hp
			_assert_equal(needs.call("wants_medical_care"), hp <= SEEK_HP, "predicate at HP %s" % str(hp))
	game.free()


func _test_place(hp: float) -> void:
	var game := _spawn_game()
	game.residents[0].needs.health = hp
	_assert_step(game, PLACE if hp <= SEEK_HP else DIG)
	game.free()


func _test_enable() -> void:
	var game := _spawn_game()
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	bed.manually_disabled = true
	game.residents[0].needs.health = SEEK_HP
	_assert_step(game, ENABLE)
	game.residents[0].needs.health = JUST_ABOVE
	_assert_step(game, DIG)
	game.free()


func _test_finish() -> void:
	var game := _spawn_game()
	var cell := Vector2i(20, 12)
	var placed := game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, cell)
	_assert_equal(placed, true, "Med Bed blueprint placed")
	var bed := game.get_building_at(cell)
	_assert_equal(bed != null and not bed.complete, true, "Med Bed remains a blueprint")
	game.residents[0].needs.health = SEEK_HP
	_assert_step(game, FINISH)
	game.residents[0].needs.health = JUST_ABOVE
	_assert_step(game, DIG)
	game.free()


func _test_occupied() -> void:
	var game := _spawn_game()
	var patient: VaultResident = game.residents[0]
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, patient.get_cell(game.map_grid))
	patient.needs.health = 50.0
	patient.medical_bed_id = bed.building_id
	bed.reserved_by = patient.resident_id
	_assert_step(game, DIG)
	game.residents[1].needs.health = JUST_ABOVE
	_assert_step(game, DIG)
	game.residents[1].needs.health = SEEK_HP
	_assert_step(game, PLACE)
	game.free()


func _test_fallthrough() -> void:
	var game := _spawn_game()
	game.residents[0].needs.rest = 28.0
	game.residents[0].needs.health = JUST_ABOVE
	_assert_step(game, BUNKS)
	game.residents[0].needs.health = SEEK_HP
	_assert_step(game, PLACE)
	game.free()


func _test_parity(hp: float) -> void:
	var game := _spawn_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = hp
	var tip: Array = _next_tuple(game)
	var tip_fired: bool = tip == PLACE
	_assert_equal(tip, PLACE if hp <= SEEK_HP else DIG, "exact boundary Next tuple before admission")
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, resident.get_cell(game.map_grid))
	game.job_system.advance(0.0)
	var admitted: bool = resident.medical_bed_id == bed.building_id
	_assert_equal(admitted, hp <= SEEK_HP and hp < 100.0, "admission uses the inclusive HP gate")
	_assert_equal(tip_fired, admitted, "guidance matches actual admission")
	_assert_equal(bed.reserved_by, resident.resident_id if admitted else -1, "bed reservation matches admission")
	game.free()


func _test_heals() -> void:
	var game := _spawn_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = SEEK_HP
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, resident.get_cell(game.map_grid))
	game.job_system.advance(0.0)
	_assert_equal(resident.medical_bed_id, bed.building_id, "threshold patient admitted")
	_assert_equal(bed.reserved_by, resident.resident_id, "threshold patient owns bed")
	_assert_equal(resident.needs.health, SEEK_HP, "zero-delta admission preserves boundary HP")
	game.job_system.advance(1.0)
	_assert_equal(resident.needs.health > SEEK_HP and resident.needs.health < 100.0, true, "patient heals past threshold")
	_assert_equal(resident.medical_bed_id, bed.building_id, "patient retains reservation past threshold")
	_assert_equal(bed.reserved_by, resident.resident_id, "bed remains reserved past threshold")
	_assert_step(game, DIG)
	game.job_system.advance(3.0)
	_assert_equal(resident.needs.health, 100.0, "patient heals to full health")
	_assert_equal(resident.medical_bed_id, -1, "full-health patient released")
	_assert_equal(bed.reserved_by, -1, "full-health patient frees bed")
	game.free()


func _test_stranded() -> void:
	var game := _spawn_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 97.0
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, resident.get_cell(game.map_grid))
	bed.manually_disabled = true
	_assert_step(game, DIG)
	_assert_equal(game.toggle_building_enabled(bed.building_id), true, "disabled bed can be enabled")
	game.job_system.advance(1.0)
	_assert_equal(resident.medical_bed_id, -1, "97 HP resident remains unreserved")
	_assert_equal(bed.reserved_by, -1, "enabled bed remains free")
	_assert_equal(resident.needs.health, 97.0, "97 HP does not heal passively")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.alert_label.text.contains("INJURED 1"), true, "HUD still counts damage above seek threshold")
	game.free()


func _test_food() -> void:
	var game := _spawn_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = SEEK_HP
	resident.needs.food = 35.0
	game.food_system.meals = 0
	_assert_step(game, PLACE)
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, resident.get_cell(game.map_grid))
	game.job_system.advance(0.0)
	_assert_equal(resident.medical_bed_id, -1, "food at 35 blocks admission")
	_assert_equal(bed.reserved_by, -1, "food-blocked resident leaves bed free")
	_assert_equal(resident.needs.health, SEEK_HP, "food-blocked resident does not heal")
	resident.needs.food = 35.0001
	game.job_system.advance(0.0)
	_assert_equal(resident.medical_bed_id, bed.building_id, "food above 35 permits admission")
	_assert_equal(bed.reserved_by, resident.resident_id, "fed patient reserves bed")
	game.free()


func _test_dead() -> void:
	var game := _spawn_game()
	game.residents[0].needs.health = SEEK_HP
	game.residents[0].alive = false
	_assert_step(game, DIG)
	game.free()


func _test_strings() -> void:
	var game := _spawn_game()
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	game.select_building(bed.building_id)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.inspector_state.text.contains("seek at HP <= %d" % int(SEEK_HP)), true, "inspector retains canonical seek threshold")
	_assert_equal(game._tool_help("medical").contains("Residents at %d HP or below claim care" % int(SEEK_HP)), true, "build card retains canonical seek threshold")
	game.free()


func _test_refresh() -> void:
	var game := _spawn_game()
	game.set_tool("dig")
	game.residents[0].needs.health = JUST_ABOVE
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "above-threshold refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, DIG[0], "above-threshold objective shows dig")
	game.residents[0].needs.health = SEEK_HP
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "threshold refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, PLACE[0], "threshold objective shows place Med Bed")
	_assert_step(game, PLACE)
	game.free()


func _next_tuple(game: VaultGame) -> Array:
	var step: Dictionary = game.player_orders._primary_next_step()
	return [step.get("text"), step.get("tool"), step.get("help")]


func _assert_step(game: VaultGame, expected: Array) -> void:
	_assert_equal(_next_tuple(game), expected, "exact Next (text, tool, help) tuple")


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_failure_count += 1
		printerr("[FAIL] %s :: %s — expected %s, got %s" % [_current_case, message, str(expected), str(actual)])
