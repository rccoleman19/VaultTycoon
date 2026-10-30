extends SceneTree
# Same scripted play as playtest_driver.gd, plus one response to each distinct
# resident-danger or reclamation/spend Next tip. Run externally with --path <project> --script <this>.
# Env: PT_SUB, PT_SEED, PT_MODE(engaged|idle), PT_FRAMES, PT_RELAY(1), PT_RECORDS, PT_LOG.
# Responses use player APIs. No needs, inventory, jobs or build progress are set.
const MAIN_SCENE := preload("res://scenes/main.tscn")
const NextCountdown := preload("res://scripts/next_countdown.gd")
var game: VaultGame
var frame := 0
var breach_seen_frame := -1
var mode := OS.get_environment("PT_MODE")
var total := int(OS.get_environment("PT_FRAMES"))
var logf: FileAccess
var last := {}
var ended_frame := -1
var ended_sim := -1.0
var followed_tips := {}
var death_times := {}
var observed_alive := {}

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	game = MAIN_SCENE.instantiate() as VaultGame
	if OS.get_environment("PT_RELAY") == "1":
		var path := OS.get_environment("PT_RECORDS")
		var store := WingRecords.new()
		store.path = path
		store.record(0x0B01, true, 3, 9, 7, true)
		game.records_path = path
	root.add_child(game)
	if OS.get_environment("PT_RELAY") == "1":
		game.equipped_perk = VaultGame.PERK_RELAY_LUMEN
	logf = FileAccess.open(OS.get_environment("PT_LOG"), FileAccess.WRITE)
	game.new_game(true, int(OS.get_environment("PT_SEED")), int(OS.get_environment("PT_SUB")))
	for resident: VaultResident in game.residents:
		observed_alive[resident.resident_id] = resident.alive
	_log("START perk=%s unlocked=%s" % [game.wing_perk, str(game.unlocked_perks())])

func _log(s: String) -> void:
	var t := game.day_cycle.elapsed_seconds if game and game.day_cycle else 0.0
	logf.store_line("f%05d real%6.1fs sim%6.1fs | %s" % [frame, frame / 30.0, t, s])
	logf.flush()

func _process(_d: float) -> bool:
	if game == null:
		return false
	frame += 1
	if mode == "engaged":
		_engaged()
	else:
		_idle()
	_follow_next()
	_watch()
	if frame >= total or (game.outcome == "win" and ended_frame > 0 and frame >= ended_frame + 150):
		var alive: Array[String] = []
		for resident: VaultResident in game.residents:
			if resident.alive:
				alive.append(resident.resident_name)
		_log("END reason=%s outcome=%s sim=%.1f outcome_frame=%d outcome_sim=%.1f day=%d alive=%s deaths=%s followed=%d" % [
			_end_reason(), game.outcome, game.day_cycle.elapsed_seconds, ended_frame, ended_sim,
			game.day_cycle.current_day, ",".join(alive), str(death_times), followed_tips.size()])
		quit(0)
		return true
	return false

func _any_dead() -> bool:
	for r in game.residents:
		if not r.alive:
			return true
	return false

func _end_reason() -> String:
	if game.outcome == "win" and ended_frame > 0 and ended_frame < total:
		return "win"
	if game.outcome == "loss" or _any_dead():
		return "death"
	# The frame cap is an observation limit, never evidence of a win.
	return "cap"

func _watch() -> void:
	var po := game.player_orders
	# Observe public resident state at the same completed-tick timestamp as
	# STATUS. The died signal fires inside step_simulation, before DayCycle
	# advances, and would report one tick (0.1 s) earlier than the visible death.
	for resident: VaultResident in game.residents:
		if bool(observed_alive.get(resident.resident_id, true)) and not resident.alive:
			death_times[resident.resident_name] = game.day_cycle.elapsed_seconds
			_log("DEATH %s sim=%.1fs" % [resident.resident_name, game.day_cycle.elapsed_seconds])
		observed_alive[resident.resident_id] = resident.alive
	var cur := {
		"NEXT": po.objective_label.text if po.objective_label else "",
		"ALSO": po.also_label.text if po.also_label else "",
		"ALERT": po.alert_label.text if po.alert_label else "",
		"STATUS": game.status_message,
		"PHASE": str(game.breach_system.phase),
		"DAY": str(game.day_cycle.current_day),
		"OUTCOME": game.outcome,
		"BRIEFING": str(po.is_briefing_open()),
		"BUILDINGS": str(game.buildings.size()),
	}
	for k in cur:
		if last.get(k) != cur[k]:
			_log("%s = %s" % [k, cur[k].replace("\n", " / ")])
	last = cur
	if game.outcome != "" and ended_frame < 0:
		ended_frame = frame
		ended_sim = game.day_cycle.elapsed_seconds
	if frame % 30 == 0:
		var busy := 0
		for r: VaultResident in game.residents:
			if r.alive and r.current_job_id >= 0:
				busy += 1
		_log("TICK salvage=%d busy=%d/%d o2=%.0f jobs=%d" % [game.food_system.salvage, busy, game.residents.size(), game.oxygen_system.oxygen, game.job_system.get_queued_count()])
	if frame % 300 == 0:
		for resident: VaultResident in game.residents:
			_log("STATE resident=%s alive=%s food=%.2f rest=%.2f mood=%.2f HP=%.2f state=%s job=%d type=%d drafted=%s" % [
				resident.resident_name, str(resident.alive), resident.needs.food,
				resident.needs.rest, resident.needs.mood, resident.needs.health,
				resident.state, resident.current_job_id, resident.current_job_type, str(resident.drafted)])
		for building: VaultBuilding in game.buildings:
			if not building.complete:
				_log("STATE blueprint=%s id=%d cell=%s delivered=%d/%d construction_left=%.2f" % [
					building.get_display_name(), building.building_id, str(building.cell),
					building.delivered, building.get_cost(), building.construction_left])

func _idle() -> void:
	# Idle player: dismiss briefing, acknowledge modal, set speed 2, otherwise nothing.
	if frame == 25:
		game.begin_shift()
		game.set_speed(2)
	_ack(2)

func _ack(speed: int) -> void:
	if game.breach_system != null and game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
		if breach_seen_frame < 0:
			breach_seen_frame = frame
		elif frame == breach_seen_frame + 75:
			if game.player_orders.breach_resume_button != null:
				game.player_orders.breach_resume_button.pressed.emit()
			game.set_speed(speed)

func _digs(cells: Array) -> void:
	game.set_tool("dig")
	for c in cells:
		game.issue_order(c)
	game.set_tool("select")

func _engaged() -> void:
	if frame == 25:
		game.begin_shift()
		game.set_speed(2)
		for c in [Vector2i(24, 11), Vector2i(25, 11), Vector2i(26, 11), Vector2i(27, 13)]:
			game.map_grid.paint_stockpile(c)
	if frame == 35:
		game.place_blueprint(VaultBuilding.Kind.LAMP, Vector2i(26, 13))
		game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 13))
		_digs([Vector2i(22, 10), Vector2i(23, 10), Vector2i(24, 10), Vector2i(25, 10), Vector2i(26, 10), Vector2i(27, 10)])
	if frame == 90:
		game.select_resident(1)
	if frame == 200:
		game.set_speed(3)
		game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 16))
		_digs([Vector2i(25, 9), Vector2i(26, 9), Vector2i(27, 9), Vector2i(26, 8), Vector2i(27, 8), Vector2i(28, 8)])
	if frame == 380:
		game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(21, 17))
		_digs([Vector2i(29, 12), Vector2i(29, 13), Vector2i(29, 14), Vector2i(29, 15)])
		game.select_resident(2)
	if frame == 520:
		game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 17))
		_digs([Vector2i(30, 12), Vector2i(30, 13), Vector2i(30, 14), Vector2i(30, 15)])
		game.select_resident(3)
	if frame == 1000:
		game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 15))
		game.select_resident(4)
	if frame == 1400:
		game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 16))
	_ack(3 if frame > 200 else 2)


func _follow_next() -> void:
	if game.ended or game.tutorial_open or game.player_orders.objective_label == null:
		return
	# Keep the base driver's 75-frame acknowledgement delay. A modal blocks the
	# player's commands, and the same tip can be followed once it is dismissed.
	if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
		return
	var tip := game.player_orders.objective_label.text
	var action := followed_action(tip, game.residents)
	if action.is_empty():
		return
	var lower := action.to_lower()
	# The air step's clock ticks every second; the same step is followed once.
	var tip_key := NextCountdown.strip_clock(tip)
	if lower.begins_with("you spend") and "fit " in lower and "mk ii" in lower:
		var building := _upgrade_target(action)
		if building != null:
			tip_key = "%s id=%d" % [tip, building.building_id]
	if followed_tips.has(tip_key):
		return
	followed_tips[tip_key] = true
	_log("FOLLOW tip=%s" % tip)
	if lower.begins_with("you begin reclamation"):
		var ok := game.start_reclamation()
		_log("FOLLOW begin reclamation success=%s" % str(ok))
		return
	if lower.begins_with("you spend"):
		if "fit " in lower and "mk ii" in lower:
			_upgrade_named(action)
		else:
			var kind := _kind_named(action)
			if kind >= 0:
				_place_named(kind)
			else:
				_log("FOLLOW unsupported spend: %s" % action)
		return
	if lower.begins_with("you undraft"):
		for resident: VaultResident in game.residents:
			if resident.alive and resident.drafted and (resident.resident_name.to_lower() in lower or "crew" in lower):
				game.toggle_resident_draft(resident.resident_id)
				_log("FOLLOW undraft %s success=%s" % [resident.resident_name, str(not resident.drafted)])
		return
	if lower.begins_with("you place"):
		var kind := _kind_named(action)
		if kind >= 0:
			_place_named(kind)
		else:
			_log("FOLLOW unsupported placement: %s" % action)
		return
	if lower.begins_with("you prioritize"):
		_prioritize_named_work(action)
		return
	if lower.begins_with("you enable") or lower.begins_with("you power"):
		var kind := _kind_named(action)
		if kind >= 0:
			_enable_or_power(kind)
			return
		_enable_named_work(action)
		return
	if lower.begins_with("you disable"):
		var kind := _kind_named(action)
		for building: VaultBuilding in game.buildings:
			if building.kind == kind and building.complete and building.powered and not building.manually_disabled:
				var ok := game.toggle_building_enabled(building.building_id)
				_log("FOLLOW disable %s id=%d success=%s" % [building.get_display_name(), building.building_id, str(ok)])
				return
		_log("FOLLOW disable failed: no enabled powered fixture named by %s" % action)
		return
	if lower.begins_with("you leave") or lower.begins_with("you keep"):
		_enable_named_work(action)
		return
	if lower.begins_with("you mark"):
		if "food" in lower or "forage" in lower or "harvest" in lower:
			# This project has no forage/harvest tool or food-bearing map cells:
			# food comes from Grow Tray -> Haul -> Cook. Do not invent a cheat.
			_log("FOLLOW unavailable mark-food action: game has no forage/harvest designation API")
		else:
			_mark_rock(action)
		return
	if lower.begins_with("you cancel"):
		var kind := _kind_named(action)
		for building: VaultBuilding in game.buildings:
			if not building.complete and (kind < 0 or building.kind == kind):
				var building_name := building.get_display_name()
				var building_cell := building.cell
				game.set_tool("cancel")
				var ok := game.issue_order(building_cell)
				game.set_tool("select")
				_log("FOLLOW cancel %s at %s success=%s" % [building_name, str(building_cell), str(ok)])
				return
	_log("FOLLOW observe action=%s" % action)


# The action this driver takes for a Next tip ("" when it only observes): the YOU clause
# after a resident-danger prefix, or a reclamation/spend tip.
static func followed_action(tip: String, residents: Array[VaultResident]) -> String:
	if has_resident_danger_prefix(tip, residents):
		return tip.get_slice(" · ", 1)
	if tip.begins_with("Next: YOU begin reclamation") or tip.begins_with("Next: YOU spend"):
		return tip.get_slice(" · ", 0).trim_prefix("Next: ")
	return ""


static func has_resident_danger_prefix(tip: String, residents: Array[VaultResident]) -> bool:
	var prefix := tip.get_slice(" · ", 0)
	if prefix == "Next: food runway short":
		return true
	for resident: VaultResident in residents:
		if not resident.alive or not prefix.begins_with("Next: %s " % resident.resident_name):
			continue
		for condition: String in PlayerOrders.NEXT_DANGER_CONDITIONS:
			if prefix == "Next: %s %s" % [resident.resident_name, condition]:
				return true
	return false


static func _kind_named(action: String) -> int:
	var lower := action.to_lower()
	if "charge node" in lower:
		return VaultBuilding.Kind.GENERATOR
	if "nutrient station" in lower or "kitchen" in lower:
		return VaultBuilding.Kind.KITCHEN
	if "grow tray" in lower:
		return VaultBuilding.Kind.GROW_TRAY
	if "air recycler" in lower:
		return VaultBuilding.Kind.AIR_RECYCLER
	if "rec console" in lower:
		return VaultBuilding.Kind.RECREATION_CONSOLE
	if "medical bed" in lower or "med bed" in lower:
		return VaultBuilding.Kind.MEDICAL_BED
	if "bunk" in lower:
		return VaultBuilding.Kind.BED
	if "lumen" in lower or "lamp" in lower:
		return VaultBuilding.Kind.LAMP
	if "salvage bay" in lower:
		return VaultBuilding.Kind.STOCKPILE
	return -1


func _upgrade_target(action: String) -> VaultBuilding:
	var lower := action.to_lower()
	var kind := _kind_named(action)
	# The Next offer uses the short fixture labels used by the Mk II UI.
	if "fit charge mk ii" in lower:
		kind = VaultBuilding.Kind.GENERATOR
	elif "fit air mk ii" in lower:
		kind = VaultBuilding.Kind.AIR_RECYCLER
	for building: VaultBuilding in game.buildings:
		if building.kind != kind or not game.can_upgrade_building(building.building_id):
			continue
		return building
	return null


func _upgrade_named(action: String) -> void:
	var building := _upgrade_target(action)
	if building != null:
		var ok := game.upgrade_building(building.building_id)
		_log("FOLLOW fit %s id=%d success=%s" % [VaultBuilding.KIND_NAMES[building.kind], building.building_id, str(ok)])
		return
	_log("FOLLOW fit failed: no affordable fixture named by %s" % action)


func _base_cells() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var scores := {}
	# Preserve the scripted blueprint cells, so the driver continues to execute
	# the same engaged actions even when a tip appears before their action frame.
	var scripted := [Vector2i(26, 13), Vector2i(20, 13), Vector2i(25, 16),
		Vector2i(21, 17), Vector2i(23, 17), Vector2i(20, 15), Vector2i(19, 16)]
	for y in range(MapGrid.CHAMBER.position.y, MapGrid.CHAMBER.end.y):
		for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
			var cell := Vector2i(x, y)
			if cell == BreachSystem.HATCH_CELL or cell in scripted:
				continue
			if not game.map_grid.is_walkable(cell) or game.get_building_at(cell) != null or game.map_grid.stockpile_cells.has(cell):
				continue
			candidates.append(cell)
			# A player placing a survival fixture can see light and stockpiles.
			# Keep work on lit floor, then minimize the actual walk to its drop-off.
			# Both choices depend only on the current map, never level or seed.
			scores[cell] = [0 if game.lighting_system.is_cell_lit(cell) else 1, _dropoff_distance(cell)]
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa: Array = scores[a]
		var sb: Array = scores[b]
		if sa[0] != sb[0]:
			return sa[0] < sb[0]
		if sa[1] != sb[1]:
			return sa[1] < sb[1]
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return candidates


func _dropoff_distance(cell: Vector2i) -> int:
	# Stockpile zones are the game's preferred food-delivery destinations.
	var zone := game.map_grid.nearest_stockpile(cell)
	if zone.x >= 0:
		var zone_path := game.map_grid.find_path(cell, zone)
		if not zone_path.is_empty():
			return zone_path.size() - 1
	var nearest := MapGrid.WIDTH * MapGrid.HEIGHT
	for building: VaultBuilding in game.buildings:
		if not building.complete or building.kind != VaultBuilding.Kind.STOCKPILE:
			continue
		var path := game.map_grid.find_path(cell, building.cell)
		if not path.is_empty():
			nearest = mini(nearest, path.size() - 1)
	return nearest


func _place_named(kind: int) -> void:
	for cell: Vector2i in _base_cells():
		if not game.map_grid.is_walkable(cell) or game.get_building_at(cell) != null:
			continue
		var reachable := false
		for resident: VaultResident in game.residents:
			if resident.alive and not game.map_grid.find_path(resident.get_cell(game.map_grid), cell).is_empty():
				reachable = true
				break
		if reachable and game.place_blueprint(kind, cell):
			_log("FOLLOW place %s at %s" % [VaultBuilding.KIND_NAMES[kind], str(cell)])
			return
	_log("FOLLOW place %s failed: no reachable free base cell" % VaultBuilding.KIND_NAMES[kind])


func _enable_or_power(kind: int) -> void:
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and building.complete and building.manually_disabled:
			var ok := game.toggle_building_enabled(building.building_id)
			_log("FOLLOW enable %s id=%d success=%s" % [building.get_display_name(), building.building_id, str(ok)])
			return
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and building.complete and building.powered:
			_log("FOLLOW leave %s enabled and powered" % building.get_display_name())
			return
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR and not building.complete:
			_enable_named_work("Haul + Craft")
			_log("FOLLOW leave Haul + Craft on for existing Charge Node")
			return
	_place_named(VaultBuilding.Kind.GENERATOR)


func _enable_named_work(action: String) -> void:
	var lower := action.to_lower()
	var found := false
	for work_type: String in VaultResident.WORK_TYPES:
		if work_type not in lower:
			continue
		found = true
		var worker: VaultResident
		for resident: VaultResident in game.residents:
			if not resident.alive or resident.drafted:
				continue
			if resident.get_work_priority(work_type) > VaultResident.PRIORITY_DISABLED:
				worker = resident
				break
			if worker == null:
				worker = resident
		if worker == null:
			_log("FOLLOW enable %s failed: no living undrafted resident" % work_type.capitalize())
			continue
		if worker.get_work_priority(work_type) == VaultResident.PRIORITY_DISABLED:
			var ok := game.set_work_priority(worker.resident_id, work_type, VaultResident.DEFAULT_WORK_PRIORITY)
			_log("FOLLOW enable %s on %s priority=%d success=%s" % [work_type.capitalize(),
				worker.resident_name, VaultResident.DEFAULT_WORK_PRIORITY, str(ok)])
		else:
			_log("FOLLOW leave %s on for %s priority=%d" % [work_type.capitalize(),
				worker.resident_name, worker.get_work_priority(work_type)])
	if not found:
		_log("FOLLOW unsupported work action: %s" % action)


func _prioritize_named_work(action: String) -> void:
	var lower := action.to_lower()
	# Match whole words and the explicit "on <Name>" clause; Ari must not
	# accidentally match a longer resident name containing the same letters.
	var words := lower.replace("[p]", "").strip_edges().split(" ", false)
	var on_index := words.find("on")
	if on_index < 0:
		_log("FOLLOW prioritize failed: action has no named resident: %s" % action)
		return
	var named_words: Array[String] = []
	for index in range(on_index + 1, words.size()):
		named_words.append(words[index])
	var resident_name := " ".join(named_words)
	var worker: VaultResident
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and resident.resident_name.to_lower() == resident_name:
			worker = resident
			break
	if worker == null:
		_log("FOLLOW prioritize failed: no living undrafted resident named %s" % resident_name)
		return
	var found := false
	for work_type: String in VaultResident.WORK_TYPES:
		if work_type not in words:
			continue
		found = true
		var ok := game.set_work_priority(worker.resident_id, work_type, VaultResident.PRIORITY_HIGHEST)
		_log("FOLLOW prioritize %s on %s priority=%d success=%s" % [
			work_type.capitalize(), worker.resident_name, VaultResident.PRIORITY_HIGHEST, str(ok)])
	if not found:
		_log("FOLLOW prioritize failed: no named work type: %s" % action)


func _mark_rock(action: String) -> void:
	var count := 6
	for word: String in action.split(" "):
		if word.is_valid_int():
			count = maxi(1, int(word))
			break
	var marked := 0
	game.set_tool("dig")
	# Connected rock around the base: try every neighboring cell in distance
	# order, using the same public designation API as the scripted actions.
	for floor_cell: Vector2i in _base_cells():
		for cell: Vector2i in game.map_grid.get_neighbors(floor_cell):
			if game.map_grid.can_queue_dig(cell) and game.issue_order(cell):
				marked += 1
				_log("FOLLOW mark rock at %s" % str(cell))
				if marked >= count:
					game.set_tool("select")
					return
	game.set_tool("select")
	_log("FOLLOW marked %d/%d rock" % [marked, count])
