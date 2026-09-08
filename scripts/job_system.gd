class_name JobSystem
extends Node

enum JobType { DIG, HAUL_RUBBLE, SUPPLY_BUILD, BUILD, COOK, SUPPLY_BREACH, PATCH_BREACH }

const JOB_NAMES := {
	JobType.DIG: "Excavating",
	JobType.HAUL_RUBBLE: "Hauling salvage",
	JobType.SUPPLY_BUILD: "Supplying blueprint",
	JobType.BUILD: "Assembling fixture",
	JobType.COOK: "Preparing meals",
	JobType.SUPPLY_BREACH: "Hauling emergency patch",
	JobType.PATCH_BREACH: "Patching pressure breach",
}

var jobs: Array[Dictionary] = []
var next_job_id := 1
var game: Node
var map_grid: MapGrid
var food: FoodSystem
var power: PowerGrid
var breach: BreachSystem


func setup(game_node: Node) -> void:
	game = game_node
	map_grid = game.get_node("MapGrid")
	food = game.get_node("FoodSystem")
	power = game.get_node("PowerGrid")
	breach = game.get_node("BreachSystem")


func reset() -> void:
	jobs.clear()
	next_job_id = 1


func queue_dig(cell: Vector2i) -> void:
	_add_job(JobType.DIG, cell)


func queue_rubble(cell: Vector2i, amount: int) -> void:
	_add_job(JobType.HAUL_RUBBLE, cell, -1, amount)


func queue_building(building: VaultBuilding) -> void:
	if building.needs_supply():
		_add_job(JobType.SUPPLY_BUILD, building.cell, building.building_id, building.get_cost() - building.delivered)
	elif not building.complete:
		_add_job(JobType.BUILD, building.cell, building.building_id)


func cancel_dig(cell: Vector2i) -> void:
	_cancel_matching(func(job: Dictionary) -> bool: return int(job.type) == JobType.DIG and job.target == cell)


func cancel_building(building_id: int) -> void:
	_cancel_matching(func(job: Dictionary) -> bool: return int(job.building_id) == building_id)


func release_resident(resident: VaultResident) -> void:
	_release_recreation(resident)
	if resident.current_job_id >= 0:
		var job := _find_job(resident.current_job_id)
		if not job.is_empty():
			if int(job.type) in [JobType.SUPPLY_BUILD, JobType.SUPPLY_BREACH] and int(job.get("in_transit", 0)) > 0:
				food.add_salvage(int(job.in_transit))
				job.in_transit = 0
			job.reserved_by = -1
	resident.carrying = 0
	resident.clear_job()


func advance(delta_seconds: float) -> void:
	_ensure_state_jobs()
	var ordered_residents: Array[VaultResident] = game.residents.duplicate()
	ordered_residents.sort_custom(_resident_claims_before)
	for resident: VaultResident in ordered_residents:
		if not resident.alive:
			continue
		if _handle_survival(resident, delta_seconds):
			continue
		if resident.current_job_id >= 0 and _has_claimable_breach_job(resident):
			release_resident(resident)
		if resident.current_job_id < 0:
			_claim_best_job(resident)
		if resident.current_job_id >= 0:
			_process_job(resident, delta_seconds)
	jobs = jobs.filter(func(job: Dictionary) -> bool: return not bool(job.get("done", false)))


func start_breach_response() -> void:
	for resident: VaultResident in game.residents:
		if resident.alive and (resident.current_job_id >= 0 or resident.recreating or resident.stress_break_left > 0.0):
			resident.stress_break_left = 0.0
			release_resident(resident)
	_ensure_state_jobs()


func reconcile_recreation_state() -> void:
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.RECREATION_CONSOLE:
			building.reserved_by = -1
			building.queue_redraw()
	var ordered_residents: Array[VaultResident] = game.residents.duplicate()
	ordered_residents.sort_custom(func(a: VaultResident, b: VaultResident) -> bool:
		return a.resident_id < b.resident_id
	)
	for resident: VaultResident in ordered_residents:
		if not resident.recreating:
			continue
		if resident.needs.is_recreation_satisfied():
			resident.stop_recreation()
			continue
		var console := game.get_building_by_id(resident.recreation_id) as VaultBuilding
		if not _can_use_recreation_console(resident, console):
			resident.stop_recreation()
			continue
		console.reserved_by = resident.resident_id
		console.queue_redraw()


func is_actively_recreating(resident: VaultResident) -> bool:
	if resident == null or not resident.alive or not resident.recreating:
		return false
	var console := game.get_building_by_id(resident.recreation_id) as VaultBuilding
	return (
		_can_use_recreation_console(resident, console)
		and console.reserved_by == resident.resident_id
		and resident.get_cell(map_grid) == console.cell
	)


func is_recreation_running(resident: VaultResident) -> bool:
	return is_actively_recreating(resident) and not game.is_simulation_paused()


func rebuild_from_state(saved_data: Dictionary = {}) -> void:
	reset()
	for entry: Variant in saved_data.get("rubble", []):
		if entry is Array and entry.size() >= 3:
			queue_rubble(Vector2i(int(entry[0]), int(entry[1])), int(entry[2]))
	for entry: Variant in saved_data.get("supplies", []):
		if entry is Array and entry.size() >= 5:
			var target := Vector2i(int(entry[1]), int(entry[2]))
			_add_job(JobType.SUPPLY_BUILD, target, int(entry[0]), int(entry[3]))
			for job: Dictionary in jobs:
				if int(job.type) == JobType.SUPPLY_BUILD and int(job.building_id) == int(entry[0]):
					job.in_transit = int(entry[4])
					break
	var saved_breach_supply: Variant = saved_data.get("breach_supply", [])
	if breach.is_response_active() and breach.needs_supply() and saved_breach_supply is Array and saved_breach_supply.size() >= 2:
		_add_job(JobType.SUPPLY_BREACH, BreachSystem.HATCH_CELL, -1, int(saved_breach_supply[0]))
		for job: Dictionary in jobs:
			if int(job.type) == JobType.SUPPLY_BREACH:
				job.in_transit = maxi(0, int(saved_breach_supply[1]))
				var carrier_id := int(saved_breach_supply[2]) if saved_breach_supply.size() >= 3 else -1
				var carrier := game.get_resident_by_id(carrier_id) as VaultResident
				if carrier == null and job.in_transit > 0:
					carrier = _first_allowed_resident(JobType.SUPPLY_BREACH)
				if carrier != null and carrier.alive and _resident_allows(carrier, JobType.SUPPLY_BREACH):
					_restore_breach_assignment(carrier, job, JobType.SUPPLY_BREACH, "target" if job.in_transit > 0 else "pickup")
				elif job.in_transit > 0:
					food.add_salvage(int(job.in_transit))
					job.in_transit = 0
				break
	var saved_breach_patch: Variant = saved_data.get("breach_patch", [])
	if breach.is_response_active() and breach.is_supplied() and saved_breach_patch is Array:
		_add_job(JobType.PATCH_BREACH, BreachSystem.HATCH_CELL)
		if saved_breach_patch.size() >= 1 and int(saved_breach_patch[0]) > 0:
			var patch_carrier := game.get_resident_by_id(int(saved_breach_patch[0])) as VaultResident
			if patch_carrier != null and patch_carrier.alive and _resident_allows(patch_carrier, JobType.PATCH_BREACH):
				for job: Dictionary in jobs:
					if int(job.type) == JobType.PATCH_BREACH:
						_restore_breach_assignment(patch_carrier, job, JobType.PATCH_BREACH, "target")
						break
	for cell: Vector2i in map_grid.dig_marks:
		queue_dig(cell)
	for building: VaultBuilding in game.buildings:
		queue_building(building)
	_ensure_state_jobs()


func serialize() -> Dictionary:
	var rubble: Array = []
	var supplies: Array = []
	var breach_supply: Array = []
	var breach_patch: Array = []
	for job: Dictionary in jobs:
		if int(job.type) == JobType.HAUL_RUBBLE and not bool(job.get("done", false)):
			var target: Vector2i = job.target
			rubble.append([target.x, target.y, int(job.amount)])
		elif int(job.type) == JobType.SUPPLY_BUILD and not bool(job.get("done", false)):
			var target: Vector2i = job.target
			supplies.append([int(job.building_id), target.x, target.y, int(job.amount), int(job.get("in_transit", 0))])
		elif int(job.type) == JobType.SUPPLY_BREACH and not bool(job.get("done", false)):
			var in_transit := int(job.get("in_transit", 0))
			breach_supply = [
				int(job.amount),
				in_transit,
				int(job.get("reserved_by", -1)),
			]
		elif int(job.type) == JobType.PATCH_BREACH and not bool(job.get("done", false)):
			breach_patch = [int(job.get("reserved_by", -1))]
	return {
		"rubble": rubble,
		"supplies": supplies,
		"breach_supply": breach_supply,
		"breach_patch": breach_patch,
	}


func is_serialized_breach_data_valid(
	saved_data: Variant,
	saved_breach: Variant,
	saved_residents: Variant,
) -> bool:
	if not saved_data is Dictionary or not saved_residents is Array:
		return false
	var supply: Variant = saved_data.get("breach_supply", [])
	var patch: Variant = saved_data.get("breach_patch", [])
	if not supply is Array or not patch is Array:
		return false
	if supply.is_empty() and patch.is_empty():
		return true
	if not saved_breach is Dictionary or saved_breach.is_empty():
		return false
	var saved_phase := int(saved_breach.get("phase", BreachSystem.Phase.DORMANT))
	var delivered := int(saved_breach.get("patch_delivered", 0))
	if saved_phase not in [BreachSystem.Phase.WARNING, BreachSystem.Phase.OPEN]:
		return false
	if not supply.is_empty():
		if supply.size() < 2 or supply.size() > 3:
			return false
		if not _is_integer_in_range(supply[0], 1, BreachSystem.PATCH_COST) or not _is_integer_in_range(supply[1], 0, BreachSystem.PATCH_COST):
			return false
		var amount := int(supply[0])
		var in_transit := int(supply[1])
		if delivered < 0 or delivered >= BreachSystem.PATCH_COST:
			return false
		if amount != BreachSystem.PATCH_COST - delivered or in_transit > amount:
			return false
		# Two-field payloads came from the first Slice 2 snapshot draft. On load,
		# carried salvage is bound to a valid hauler or refunded for safe retry.
		if supply.size() == 3:
			if not _is_integer_in_range(supply[2], -1, 2_147_483_647):
				return false
			var supply_carrier_id := int(supply[2])
			if supply_carrier_id < 0 and in_transit > 0:
				return false
			if supply_carrier_id == 0 or (supply_carrier_id > 0 and not _saved_resident_can_work(saved_residents, supply_carrier_id, "haul")):
				return false
	if not patch.is_empty():
		if patch.size() != 1 or delivered != BreachSystem.PATCH_COST:
			return false
		if not _is_integer_in_range(patch[0], -1, 2_147_483_647):
			return false
		var patch_carrier_id := int(patch[0])
		if patch_carrier_id == 0 or (patch_carrier_id > 0 and not _saved_resident_can_work(saved_residents, patch_carrier_id, "craft")):
			return false
	return true


func get_queued_count() -> int:
	var count := 0
	for job: Dictionary in jobs:
		if not bool(job.get("done", false)):
			count += 1
	return count


func get_breach_response_status() -> String:
	if breach == null or breach.phase == BreachSystem.Phase.DORMANT:
		return "Automated seal watch active."
	if breach.is_sealed():
		return "PATCH COMPLETE · HATCH STABLE"
	if breach.needs_supply():
		var remaining := maxi(0, BreachSystem.PATCH_COST - breach.patch_delivered - _breach_supply_in_transit())
		if not _has_allowed_worker(JobType.SUPPLY_BREACH):
			return "BLOCKED · ENABLE HAUL"
		if not _has_worker_path(JobType.SUPPLY_BREACH):
			return "BLOCKED · NO PATH TO HATCH"
		if food.salvage < remaining:
			return "BLOCKED · NEEDS %d SALVAGE" % (remaining - food.salvage)
		if _has_reserved_job(JobType.SUPPLY_BREACH):
			return "HAUL RESPONSE EN ROUTE"
		return "AWAITING HAUL RESPONSE"
	if not _has_allowed_worker(JobType.PATCH_BREACH):
		return "BLOCKED · ENABLE CRAFT"
	if not _has_worker_path(JobType.PATCH_BREACH):
		return "BLOCKED · NO PATH TO HATCH"
	if _has_reserved_job(JobType.PATCH_BREACH):
		return "PATCH CREW RESPONDING"
	return "AWAITING PATCH CREW"


func get_breach_supply_in_transit() -> int:
	return _breach_supply_in_transit()


func _ensure_state_jobs() -> void:
	if breach != null and breach.is_response_active():
		if breach.needs_supply():
			_add_job(JobType.SUPPLY_BREACH, BreachSystem.HATCH_CELL, -1, BreachSystem.PATCH_COST - breach.patch_delivered)
		elif not breach.is_sealed():
			_add_job(JobType.PATCH_BREACH, BreachSystem.HATCH_CELL)
	for cell: Vector2i in map_grid.dig_marks:
		_add_job(JobType.DIG, cell)
	for building: VaultBuilding in game.buildings:
		if building.needs_supply():
			_add_job(JobType.SUPPLY_BUILD, building.cell, building.building_id, building.get_cost() - building.delivered)
		elif not building.complete:
			_add_job(JobType.BUILD, building.cell, building.building_id)
		elif building.kind == VaultBuilding.Kind.KITCHEN and building.powered and food.can_cook():
			_add_job(JobType.COOK, building.cell, building.building_id)


func _handle_survival(resident: VaultResident, delta_seconds: float) -> bool:
	if resident.needs.food <= 35.0 and food.consume_meal():
		release_resident(resident)
		resident.needs.eat()
		resident.state = "Eating ration"
		return true
	if resident.sleeping:
		var sleep_cell := resident.get_cell(map_grid)
		var bed: VaultBuilding = game.get_building_by_id(resident.bed_id)
		if bed != null and bed.complete:
			sleep_cell = bed.cell
		if not resident.move_to(sleep_cell, map_grid, delta_seconds):
			resident.state = "Going to bunk"
		else:
			resident.state = "Sleeping"
		var wake_threshold := 86.0 if resident.bed_id >= 0 else 44.0
		if resident.needs.rest >= wake_threshold:
			if resident.bed_id < 0:
				resident.needs.mood = maxf(0.0, resident.needs.mood - 12.0)
			resident.sleeping = false
			resident.bed_id = -1
			resident.state = "Idle"
			resident.clear_path()
		return true
	if resident.needs.rest <= 28.0:
		var available_bed := _find_free_bed(resident)
		if available_bed >= 0:
			release_resident(resident)
			resident.sleeping = true
			resident.bed_id = available_bed
			resident.state = "Seeking rest"
			return true
	if resident.needs.rest <= 0.0:
		release_resident(resident)
		resident.sleeping = true
		resident.bed_id = -1
		resident.state = "Collapsed on floor"
		return true
	# Emergency hatch work outranks recreation and a nonessential stress break.
	if breach != null and breach.is_response_active():
		if resident.recreating:
			release_resident(resident)
		if resident.stress_break_left > 0.0:
			resident.stress_break_left = 0.0
			resident.state = "Idle"
		return false
	if resident.recreating:
		var recreation_console := game.get_building_by_id(resident.recreation_id) as VaultBuilding
		if not _can_use_recreation_console(resident, recreation_console):
			release_resident(resident)
		else:
			recreation_console.reserved_by = resident.resident_id
			if not resident.move_to(recreation_console.cell, map_grid, delta_seconds):
				resident.state = "Seeking recreation"
				return true
			resident.state = "Recreating"
			resident.needs.recreate(delta_seconds)
			if resident.needs.is_recreation_satisfied():
				resident.needs.finish_recreation()
				resident.recreation_sessions += 1
				_release_recreation(resident)
			return true
	if resident.needs.wants_recreation():
		var available_console := _find_free_recreation_console(resident)
		if available_console != null:
			release_resident(resident)
			available_console.reserved_by = resident.resident_id
			resident.begin_recreation(available_console.building_id)
			return true
	if resident.stress_break_left > 0.0:
		resident.stress_break_left = maxf(0.0, resident.stress_break_left - delta_seconds)
		resident.state = "Stress break"
		if resident.stress_break_left <= 0.0:
			resident.needs.take_unstructured_break()
			resident.state = "Idle"
		return true
	if resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD:
		release_resident(resident)
		resident.stress_break_left = 7.0
		resident.state = "Stress break"
		return true
	return false


func _find_free_bed(resident: VaultResident) -> int:
	for building: VaultBuilding in game.buildings:
		if not building.complete or building.kind != VaultBuilding.Kind.BED:
			continue
		var occupied := false
		for other: VaultResident in game.residents:
			if other != resident and other.alive and other.sleeping and other.bed_id == building.building_id:
				occupied = true
				break
		if not occupied:
			return building.building_id
	return -1


func _find_free_recreation_console(resident: VaultResident) -> VaultBuilding:
	var best: VaultBuilding = null
	var best_distance := 1_000_000
	for building: VaultBuilding in game.buildings:
		if not _can_use_recreation_console(resident, building) or building.reserved_by >= 0:
			continue
		var path := map_grid.find_path(resident.get_cell(map_grid), building.cell)
		var distance := path.size()
		if best == null or distance < best_distance or (distance == best_distance and building.building_id < best.building_id):
			best = building
			best_distance = distance
	return best


func _can_use_recreation_console(resident: VaultResident, building: VaultBuilding) -> bool:
	if building == null or not building.complete or building.kind != VaultBuilding.Kind.RECREATION_CONSOLE or not building.powered:
		return false
	if building.reserved_by >= 0 and building.reserved_by != resident.resident_id:
		return false
	return not map_grid.find_path(resident.get_cell(map_grid), building.cell).is_empty()


func _release_recreation(resident: VaultResident) -> void:
	if not resident.recreating:
		return
	var building := game.get_building_by_id(resident.recreation_id) as VaultBuilding
	if building != null and building.reserved_by == resident.resident_id:
		building.reserved_by = -1
		building.queue_redraw()
	resident.stop_recreation()


func _claim_best_job(resident: VaultResident) -> void:
	var candidates: Array[Dictionary] = []
	for job: Dictionary in jobs:
		if int(job.reserved_by) >= 0 or bool(job.get("done", false)):
			continue
		if not _resident_allows(resident, int(job.type)) or not _job_available(resident, job):
			continue
		candidates.append(job)
	if candidates.is_empty():
		resident.state = "Idle"
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _job_claims_before(resident, a, b)
	)
	var job := candidates[0]
	job.reserved_by = resident.resident_id
	resident.current_job_id = int(job.id)
	resident.current_job_type = int(job.type)
	resident.job_phase = "pickup" if int(job.type) in [JobType.SUPPLY_BUILD, JobType.SUPPLY_BREACH] else "target"
	if int(job.type) in [JobType.SUPPLY_BUILD, JobType.SUPPLY_BREACH] and int(job.get("in_transit", 0)) > 0:
		resident.job_phase = "target"
		resident.carrying = int(job.in_transit)
	resident.work_accumulator = 0.0
	resident.state = str(JOB_NAMES.get(int(job.type), "Working"))


func _resident_claims_before(a: VaultResident, b: VaultResident) -> bool:
	var key_a := _best_claim_key(a)
	var key_b := _best_claim_key(b)
	for index in key_a.size():
		if int(key_a[index]) != int(key_b[index]):
			return int(key_a[index]) < int(key_b[index])
	return a.resident_id < b.resident_id


func _best_claim_key(resident: VaultResident) -> Array[int]:
	var best: Array[int] = [9, 99]
	if not resident.alive:
		return best
	if resident.current_job_id >= 0 and resident.current_job_type not in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH]:
		best = [1, resident.get_work_priority(_work_type_for_job(resident.current_job_type))]
	for job: Dictionary in jobs:
		if int(job.reserved_by) >= 0 or bool(job.get("done", false)):
			continue
		var type := int(job.type)
		if resident.current_job_id >= 0 and type not in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH]:
			continue
		if not _resident_allows(resident, type) or not _job_available(resident, job):
			continue
		var candidate: Array[int] = [
			0 if type in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH] else 1,
			resident.get_work_priority(_work_type_for_job(type)),
		]
		if _claim_key_before(candidate, best):
			best = candidate
	return best


func _claim_key_before(a: Array[int], b: Array[int]) -> bool:
	for index in a.size():
		if a[index] != b[index]:
			return a[index] < b[index]
	return false


func _job_claims_before(resident: VaultResident, a: Dictionary, b: Dictionary) -> bool:
	var type_a := int(a.type)
	var type_b := int(b.type)
	var emergency_a := 0 if type_a in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH] else 1
	var emergency_b := 0 if type_b in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH] else 1
	if emergency_a != emergency_b:
		return emergency_a < emergency_b
	var work_priority_a := resident.get_work_priority(_work_type_for_job(type_a))
	var work_priority_b := resident.get_work_priority(_work_type_for_job(type_b))
	if work_priority_a != work_priority_b:
		return work_priority_a < work_priority_b
	var kind_priority_a := _job_priority(type_a)
	var kind_priority_b := _job_priority(type_b)
	if kind_priority_a != kind_priority_b:
		return kind_priority_a < kind_priority_b
	var distance_a := _job_distance(resident, a)
	var distance_b := _job_distance(resident, b)
	if distance_a != distance_b:
		return distance_a < distance_b
	return int(a.id) < int(b.id)


func _job_available(resident: VaultResident, job: Dictionary) -> bool:
	var type := int(job.type)
	var target: Vector2i = job.target
	if type == JobType.DIG:
		return map_grid.dig_marks.has(target) and map_grid.nearest_walkable_neighbor(target, resident.get_cell(map_grid)).x >= 0
	if type == JobType.HAUL_RUBBLE:
		return map_grid.is_walkable(target) and not map_grid.find_path(resident.get_cell(map_grid), target).is_empty()
	if type == JobType.SUPPLY_BREACH:
		return breach.is_response_active() and breach.needs_supply() and (int(job.get("in_transit", 0)) > 0 or food.salvage > 0) and not map_grid.find_path(resident.get_cell(map_grid), target).is_empty()
	if type == JobType.PATCH_BREACH:
		return breach.is_response_active() and breach.is_supplied() and not map_grid.find_path(resident.get_cell(map_grid), target).is_empty()
	var building: VaultBuilding = game.get_building_by_id(int(job.building_id))
	if building == null:
		return false
	if map_grid.find_path(resident.get_cell(map_grid), building.cell).is_empty():
		return false
	if type == JobType.SUPPLY_BUILD:
		return building.needs_supply() and food.salvage > _breach_salvage_reserve()
	if type == JobType.BUILD:
		return not building.complete and building.is_supplied()
	if type == JobType.COOK:
		return building.complete and building.kind == VaultBuilding.Kind.KITCHEN and building.powered and food.can_cook()
	return false


func _process_job(resident: VaultResident, delta_seconds: float) -> void:
	var job := _find_job(resident.current_job_id)
	if job.is_empty() or bool(job.get("done", false)):
		resident.clear_job()
		return
	var type := int(job.type)
	var target: Vector2i = job.target
	if type == JobType.DIG:
		var work_cell := map_grid.nearest_walkable_neighbor(target, resident.get_cell(map_grid))
		if work_cell.x < 0 or not resident.move_to(work_cell, map_grid, delta_seconds):
			resident.state = "Walking to excavation"
			return
		resident.state = "Excavating rock"
		if map_grid.apply_dig_work(target, delta_seconds * resident.get_work_multiplier()):
			_finish_job(job, resident)
		return
	if type == JobType.HAUL_RUBBLE:
		_process_rubble_job(resident, job, delta_seconds)
		return
	if type == JobType.SUPPLY_BREACH:
		_process_breach_supply_job(resident, job, delta_seconds)
		return
	if type == JobType.PATCH_BREACH:
		if not resident.move_to(BreachSystem.HATCH_CELL, map_grid, delta_seconds):
			resident.state = "Rushing to pressure hatch"
			return
		resident.state = "Patching pressure breach"
		if breach.apply_patch_work(delta_seconds):
			_finish_job(job, resident)
		return
	var building: VaultBuilding = game.get_building_by_id(int(job.building_id))
	if building == null:
		_finish_job(job, resident)
		return
	if type == JobType.SUPPLY_BUILD:
		_process_supply_job(resident, job, building, delta_seconds)
	elif type == JobType.BUILD:
		if not resident.move_to(building.cell, map_grid, delta_seconds):
			resident.state = "Walking to blueprint"
			return
		resident.state = "Assembling %s" % building.get_display_name()
		if building.apply_build_work(delta_seconds * resident.get_work_multiplier()):
			_finish_job(job, resident)
	elif type == JobType.COOK:
		if not resident.move_to(building.cell, map_grid, delta_seconds):
			resident.state = "Walking to nutrient station"
			return
		if not building.powered:
			_finish_job(job, resident)
			return
		if not food.can_cook():
			_finish_job(job, resident)
			return
		resident.state = "Preparing meals"
		resident.work_accumulator += delta_seconds * resident.get_work_multiplier()
		if resident.work_accumulator >= 4.0:
			food.finish_cooking()
			_finish_job(job, resident)


func _process_rubble_job(resident: VaultResident, job: Dictionary, delta_seconds: float) -> void:
	if resident.job_phase == "target":
		if not resident.move_to(job.target, map_grid, delta_seconds):
			resident.state = "Walking to rubble"
			return
		resident.carrying = int(job.amount)
		resident.job_phase = "deposit"
		resident.clear_path()
	var stockpile_cell := _stockpile_cell()
	if not resident.move_to(stockpile_cell, map_grid, delta_seconds):
		resident.state = "Carrying salvage"
		return
	food.add_salvage(int(job.amount))
	resident.carrying = 0
	_finish_job(job, resident)


func _process_supply_job(resident: VaultResident, job: Dictionary, building: VaultBuilding, delta_seconds: float) -> void:
	if resident.job_phase == "pickup":
		if not resident.move_to(_stockpile_cell(), map_grid, delta_seconds):
			resident.state = "Collecting salvage"
			return
		var available_for_build := maxi(0, food.salvage - _breach_salvage_reserve())
		resident.carrying = food.take_salvage(mini(building.get_cost() - building.delivered, available_for_build))
		if resident.carrying <= 0:
			job.reserved_by = -1
			resident.clear_job()
			return
		job.in_transit = resident.carrying
		resident.job_phase = "target"
		resident.clear_path()
	if not resident.move_to(building.cell, map_grid, delta_seconds):
		resident.state = "Supplying %s" % building.get_display_name()
		return
	building.add_delivery(resident.carrying)
	job.in_transit = 0
	resident.carrying = 0
	if building.needs_supply():
		job.amount = building.get_cost() - building.delivered
		job.reserved_by = -1
		resident.clear_job()
	else:
		_finish_job(job, resident)
		_add_job(JobType.BUILD, building.cell, building.building_id)


func _process_breach_supply_job(resident: VaultResident, job: Dictionary, delta_seconds: float) -> void:
	if not breach.is_response_active() or not breach.needs_supply():
		_finish_job(job, resident)
		return
	if resident.job_phase == "pickup":
		if not resident.move_to(_stockpile_cell(), map_grid, delta_seconds):
			resident.state = "Collecting patch salvage"
			return
		resident.carrying = food.take_salvage(BreachSystem.PATCH_COST - breach.patch_delivered)
		if resident.carrying <= 0:
			job.reserved_by = -1
			resident.clear_job()
			return
		job.in_transit = resident.carrying
		resident.job_phase = "target"
		resident.clear_path()
	if not resident.move_to(BreachSystem.HATCH_CELL, map_grid, delta_seconds):
		resident.state = "Hauling emergency patch"
		return
	breach.add_delivery(resident.carrying)
	job.in_transit = 0
	resident.carrying = 0
	if breach.needs_supply():
		job.amount = BreachSystem.PATCH_COST - breach.patch_delivered
		job.reserved_by = -1
		resident.clear_job()
	else:
		_finish_job(job, resident)
		_add_job(JobType.PATCH_BREACH, BreachSystem.HATCH_CELL)


func _stockpile_cell() -> Vector2i:
	for building: VaultBuilding in game.buildings:
		if building.complete and building.kind == VaultBuilding.Kind.STOCKPILE:
			return building.cell
	return map_grid.get_chamber_center()


func _resident_allows(resident: VaultResident, type: int) -> bool:
	var work_type := _work_type_for_job(type)
	return not work_type.is_empty() and resident.get_work_priority(work_type) != VaultResident.PRIORITY_DISABLED


func _work_type_for_job(type: int) -> String:
	match type:
		JobType.DIG: return "dig"
		JobType.HAUL_RUBBLE, JobType.SUPPLY_BUILD, JobType.SUPPLY_BREACH: return "haul"
		JobType.BUILD, JobType.PATCH_BREACH: return "craft"
		JobType.COOK: return "cook"
	return ""


func get_work_type_for_job(type: int) -> String:
	return _work_type_for_job(type)


func _job_priority(type: int) -> int:
	match type:
		JobType.SUPPLY_BREACH: return 0
		JobType.PATCH_BREACH: return 1
		JobType.SUPPLY_BUILD: return 10
		JobType.BUILD: return 15
		JobType.COOK: return 20
		JobType.HAUL_RUBBLE: return 30
		JobType.DIG: return 40
	return 99


func _job_distance(resident: VaultResident, job: Dictionary) -> int:
	var target: Vector2i = job.target
	var current := resident.get_cell(map_grid)
	return absi(current.x - target.x) + absi(current.y - target.y)


func _breach_supply_in_transit() -> int:
	for job: Dictionary in jobs:
		if int(job.type) == JobType.SUPPLY_BREACH and not bool(job.get("done", false)):
			return maxi(0, int(job.get("in_transit", 0)))
	return 0


func _breach_salvage_reserve() -> int:
	if breach == null or not breach.needs_supply():
		return 0
	return maxi(0, BreachSystem.PATCH_COST - breach.patch_delivered - _breach_supply_in_transit())


func _has_claimable_breach_job(resident: VaultResident) -> bool:
	if breach == null or not breach.is_response_active() or resident.current_job_type in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH]:
		return false
	for job: Dictionary in jobs:
		var type := int(job.type)
		if type not in [JobType.SUPPLY_BREACH, JobType.PATCH_BREACH]:
			continue
		if int(job.reserved_by) < 0 and not bool(job.get("done", false)) and _resident_allows(resident, type) and _job_available(resident, job):
			return true
	return false


func _first_allowed_resident(type: int) -> VaultResident:
	var candidates: Array[VaultResident] = []
	for resident: VaultResident in game.residents:
		if resident.alive and _resident_allows(resident, type):
			candidates.append(resident)
	if candidates.is_empty():
		return null
	var work_type := _work_type_for_job(type)
	candidates.sort_custom(func(a: VaultResident, b: VaultResident) -> bool:
		var priority_a := a.get_work_priority(work_type)
		var priority_b := b.get_work_priority(work_type)
		return priority_a < priority_b if priority_a != priority_b else a.resident_id < b.resident_id
	)
	return candidates[0]


func _restore_breach_assignment(
	resident: VaultResident,
	job: Dictionary,
	type: int,
	phase_name: String,
) -> void:
	_release_recreation(resident)
	job.reserved_by = resident.resident_id
	resident.current_job_id = int(job.id)
	resident.current_job_type = type
	resident.job_phase = phase_name
	resident.carrying = int(job.get("in_transit", 0)) if type == JobType.SUPPLY_BREACH else 0
	resident.work_accumulator = 0.0
	resident.state = str(JOB_NAMES[type])


func _has_allowed_worker(type: int) -> bool:
	for resident: VaultResident in game.residents:
		if resident.alive and _resident_allows(resident, type):
			return true
	return false


func _has_worker_path(type: int) -> bool:
	for resident: VaultResident in game.residents:
		if resident.alive and _resident_allows(resident, type):
			if not map_grid.find_path(resident.get_cell(map_grid), BreachSystem.HATCH_CELL).is_empty():
				return true
	return false


func _has_reserved_job(type: int) -> bool:
	for job: Dictionary in jobs:
		if int(job.type) == type and int(job.reserved_by) >= 0 and not bool(job.get("done", false)):
			return true
	return false


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum


func _saved_resident_can_work(saved_residents: Array, resident_id: int, permission: String) -> bool:
	for entry: Variant in saved_residents:
		if not entry is Dictionary or not _is_integer_in_range(entry.get("id"), 1, 2_147_483_647):
			continue
		if int(entry.id) != resident_id:
			continue
		if not bool(entry.get("alive", true)):
			return false
		var priorities: Variant = entry.get("work_priorities", {})
		if priorities is Dictionary and priorities.has(permission):
			var saved_priority: Variant = priorities[permission]
			if _is_integer_in_range(saved_priority, VaultResident.PRIORITY_DISABLED, VaultResident.PRIORITY_LOWEST):
				return int(saved_priority) != VaultResident.PRIORITY_DISABLED
		var work: Variant = entry.get("work_allowed", {})
		return work is Dictionary and bool(work.get(permission, true))
	return false


func _add_job(type: int, target: Vector2i, building_id := -1, amount := 0) -> void:
	for existing: Dictionary in jobs:
		if not bool(existing.get("done", false)) and int(existing.type) == type and existing.target == target and int(existing.building_id) == building_id:
			if amount > 0:
				existing.amount = amount
			return
	jobs.append({
		"id": next_job_id,
		"type": type,
		"target": target,
		"building_id": building_id,
		"amount": amount,
		"reserved_by": -1,
		"in_transit": 0,
		"done": false,
	})
	next_job_id += 1


func _find_job(job_id: int) -> Dictionary:
	for job: Dictionary in jobs:
		if int(job.id) == job_id:
			return job
	return {}


func _finish_job(job: Dictionary, resident: VaultResident) -> void:
	job.done = true
	job.reserved_by = -1
	resident.carrying = 0
	resident.clear_job()


func _cancel_matching(predicate: Callable) -> void:
	for job: Dictionary in jobs:
		if bool(job.get("done", false)) or not predicate.call(job):
			continue
		var resident: VaultResident = game.get_resident_by_id(int(job.reserved_by))
		if resident != null:
			release_resident(resident)
		job.done = true
	jobs = jobs.filter(func(job: Dictionary) -> bool: return not bool(job.get("done", false)))
