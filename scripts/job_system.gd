class_name JobSystem
extends Node

enum JobType { DIG, HAUL_RUBBLE, SUPPLY_BUILD, BUILD, COOK }

const JOB_NAMES := {
	JobType.DIG: "Excavating",
	JobType.HAUL_RUBBLE: "Hauling salvage",
	JobType.SUPPLY_BUILD: "Supplying blueprint",
	JobType.BUILD: "Assembling fixture",
	JobType.COOK: "Preparing meals",
}

var jobs: Array[Dictionary] = []
var next_job_id := 1
var game: Node
var map_grid: MapGrid
var food: FoodSystem
var power: PowerGrid


func setup(game_node: Node) -> void:
	game = game_node
	map_grid = game.get_node("MapGrid")
	food = game.get_node("FoodSystem")
	power = game.get_node("PowerGrid")


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
	if resident.current_job_id >= 0:
		var job := _find_job(resident.current_job_id)
		if not job.is_empty():
			job.reserved_by = -1
	resident.carrying = 0
	resident.clear_job()


func advance(delta_seconds: float) -> void:
	_ensure_state_jobs()
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		if _handle_survival(resident, delta_seconds):
			continue
		if resident.current_job_id < 0:
			_claim_best_job(resident)
		if resident.current_job_id >= 0:
			_process_job(resident, delta_seconds)
	jobs = jobs.filter(func(job: Dictionary) -> bool: return not bool(job.get("done", false)))


func rebuild_from_state(saved_data: Dictionary = {}) -> void:
	reset()
	for entry: Variant in saved_data.get("rubble", []):
		if entry is Array and entry.size() >= 3:
			queue_rubble(Vector2i(int(entry[0]), int(entry[1])), int(entry[2]))
	for cell: Vector2i in map_grid.dig_marks:
		queue_dig(cell)
	for building: VaultBuilding in game.buildings:
		queue_building(building)
	_ensure_state_jobs()


func serialize() -> Dictionary:
	var rubble: Array = []
	for job: Dictionary in jobs:
		if int(job.type) == JobType.HAUL_RUBBLE and not bool(job.get("done", false)):
			var target: Vector2i = job.target
			rubble.append([target.x, target.y, int(job.amount)])
	return {"rubble": rubble}


func get_queued_count() -> int:
	var count := 0
	for job: Dictionary in jobs:
		if not bool(job.get("done", false)):
			count += 1
	return count


func _ensure_state_jobs() -> void:
	for cell: Vector2i in map_grid.dig_marks:
		_add_job(JobType.DIG, cell)
	for building: VaultBuilding in game.buildings:
		if building.needs_supply():
			_add_job(JobType.SUPPLY_BUILD, building.cell, building.building_id, building.get_cost() - building.delivered)
		elif not building.complete:
			_add_job(JobType.BUILD, building.cell, building.building_id)
		elif building.kind == VaultBuilding.Kind.KITCHEN and food.can_cook() and food.meals < 16:
			_add_job(JobType.COOK, building.cell, building.building_id)


func _handle_survival(resident: VaultResident, delta_seconds: float) -> bool:
	if resident.needs.food <= 66.0 and food.consume_meal():
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
		if resident.needs.rest >= 86.0:
			resident.sleeping = false
			resident.bed_id = -1
			resident.state = "Idle"
			resident.clear_path()
		return true
	if resident.needs.rest <= 28.0:
		release_resident(resident)
		resident.sleeping = true
		resident.bed_id = _find_free_bed(resident)
		resident.state = "Seeking rest"
		return true
	if resident.stress_break_left > 0.0:
		resident.stress_break_left = maxf(0.0, resident.stress_break_left - delta_seconds)
		resident.state = "Stress break"
		if resident.stress_break_left <= 0.0:
			resident.needs.light_mood = minf(100.0, resident.needs.light_mood + 16.0)
			resident.state = "Idle"
		return true
	if resident.needs.light_mood <= 9.0:
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
		var priority_a := _job_priority(int(a.type))
		var priority_b := _job_priority(int(b.type))
		if priority_a != priority_b:
			return priority_a < priority_b
		var distance_a: int = _job_distance(resident, a)
		var distance_b: int = _job_distance(resident, b)
		if distance_a != distance_b:
			return distance_a < distance_b
		return int(a.id) < int(b.id)
	)
	var job := candidates[0]
	job.reserved_by = resident.resident_id
	resident.current_job_id = int(job.id)
	resident.current_job_type = int(job.type)
	resident.job_phase = "pickup" if int(job.type) == JobType.SUPPLY_BUILD else "target"
	resident.work_accumulator = 0.0
	resident.state = str(JOB_NAMES.get(int(job.type), "Working"))


func _job_available(resident: VaultResident, job: Dictionary) -> bool:
	var type := int(job.type)
	var target: Vector2i = job.target
	if type == JobType.DIG:
		return map_grid.dig_marks.has(target) and map_grid.nearest_walkable_neighbor(target, resident.get_cell(map_grid)).x >= 0
	if type == JobType.HAUL_RUBBLE:
		return map_grid.is_walkable(target) and not map_grid.find_path(resident.get_cell(map_grid), target).is_empty()
	var building: VaultBuilding = game.get_building_by_id(int(job.building_id))
	if building == null:
		return false
	if map_grid.find_path(resident.get_cell(map_grid), building.cell).is_empty():
		return false
	if type == JobType.SUPPLY_BUILD:
		return building.needs_supply() and food.salvage > 0
	if type == JobType.BUILD:
		return not building.complete and building.is_supplied()
	if type == JobType.COOK:
		return building.complete and building.kind == VaultBuilding.Kind.KITCHEN and food.can_cook()
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
			resident.state = "Waiting: station unpowered"
			return
		if not food.can_cook():
			_finish_job(job, resident)
			return
		resident.state = "Preparing meals"
		resident.work_accumulator += delta_seconds * resident.get_work_multiplier()
		if resident.work_accumulator >= 5.0:
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
		resident.carrying = mini(building.get_cost() - building.delivered, food.salvage)
		if resident.carrying <= 0:
			job.reserved_by = -1
			resident.clear_job()
			return
		resident.job_phase = "target"
		resident.clear_path()
	if not resident.move_to(building.cell, map_grid, delta_seconds):
		resident.state = "Supplying %s" % building.get_display_name()
		return
	var delivered := food.take_salvage(resident.carrying)
	building.add_delivery(delivered)
	resident.carrying = 0
	if building.needs_supply():
		job.amount = building.get_cost() - building.delivered
		job.reserved_by = -1
		resident.clear_job()
	else:
		_finish_job(job, resident)
		_add_job(JobType.BUILD, building.cell, building.building_id)


func _stockpile_cell() -> Vector2i:
	for building: VaultBuilding in game.buildings:
		if building.complete and building.kind == VaultBuilding.Kind.STOCKPILE:
			return building.cell
	return map_grid.get_chamber_center()


func _resident_allows(resident: VaultResident, type: int) -> bool:
	match type:
		JobType.DIG: return bool(resident.work_allowed.dig)
		JobType.HAUL_RUBBLE, JobType.SUPPLY_BUILD: return bool(resident.work_allowed.haul)
		JobType.BUILD: return bool(resident.work_allowed.craft)
		JobType.COOK: return bool(resident.work_allowed.cook)
	return false


func _job_priority(type: int) -> int:
	match type:
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
			resident.carrying = 0
			resident.clear_job()
		job.done = true
	jobs = jobs.filter(func(job: Dictionary) -> bool: return not bool(job.get("done", false)))
