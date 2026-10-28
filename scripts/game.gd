class_name VaultGame
extends Node2D

signal game_started
signal game_won(survivors: int)
signal game_lost

const SIMULATION_TICK := 0.1
const RIGHT_PANEL_WIDTH := 310.0
const LEGACY_WING_SEED := 0
const MAX_WING_SEED := 0xFFFF
var wing_seed := LEGACY_WING_SEED
# Records + ladder C4: the sublevel this wing runs on (07 base, down to 03). Seed 0 is always 07.
# Saved only below 07, as the additive "sublevel" key, so 07 and legacy saves keep their bytes.
var sublevel := WingRecords.BASE_SUBLEVEL
const SUBLEVEL_SAVE_VERSION := 1
# Meta perks P1: one trade-off perk per wing, unlocked by the first win on a sublevel (derived from
# WingRecords, so records keep their format). "" is NONE: the default, and the only choice for seed 0
# and test runs (records off). The perk is applied once by new_game and saved as an additive key.
const PERK_SAVE_VERSION := 1
const PERK_PROVISIONING := "provisioning"
const PROVISIONING_MEALS := 4
const PROVISIONING_SALVAGE_COST := 8
# Meta perks P3: FLOODLIGHT (power/light) buys a second lit starter Lumen with salvage; it takes the
# core's last spare power but sheds first, so food and air still get power. It does not touch the
# hatch clock or work rates. Ladder QA: v1 (Lumen at HIGH, free) cost idle 05/03 2-3 wins in 6.
# VOLUNTEER (crew/labor) adds one more hand who eats from the stores; outfitting Gil costs 8 salvage.
# Work rates and the hatch clock are untouched. QA: -6 / -2 meals wiped 05 (2/6); -8 salvage keeps 4/6+.
const PERK_FLOODLIGHT := "floodlight"
const FLOODLIGHT_CELL := Vector2i(20, 14)
# The starter's deterministic id (core 1, starter Lumen 2, FLOODLIGHT 3); ids are never reused.
const FLOODLIGHT_BUILDING_ID := 3
const PERK_VOLUNTEER := "volunteer"
const FLOODLIGHT_SALVAGE_COST := 6
const VOLUNTEER_SALVAGE_COST := 8
# Annex blueprints C1/B1: BUNKROOM, earned by a first Annex badge (any record with annex), takes the
# same single slot as the perks: one built Bunk at the start, paid 14 salvage (a Bunk is 8 to build).
const PERK_BUNKROOM := "bunkroom"
const BUNKROOM_CELL := Vector2i(25, 17)
const BUNKROOM_SALVAGE_COST := 14
# B2 GROW NOOK, earned by Annex badges on 2 different sublevels: a Grow Tray blueprint placed at the
# start with its materials on site (the crew still build it), paid with meals. Ladder QA: an unsupplied
# plan hauled the opening salvage away from the Nutrient Station (05: 0/6), so it comes supplied; the
# nook cell sits in the Annex corner, off the recommended-start cells (23,12 blocked the idle start).
const PERK_GROW_NOOK := "grow_nook"
const GROW_NOOK_CELL := Vector2i(26, 17)
const GROW_NOOK_MEALS_COST := 2
const GROW_NOOK_BADGES := 2
# B3 RELAY LUMEN, earned by an Annex badge on a 3-star win (a record with best_stars 3 and annex): one
# built Lumen on a far corner tile of the start room that lights the dig front, at no cost or power load.
# Ladder QA vs NONE: built for 10 salvage
# it lost 1 game on 05 and 2 on 04; for 5 salvage it lost 2 on 03; as a free unbuilt plan it lost 2 on 05.
const PERK_RELAY_LUMEN := "relay_lumen"
const RELAY_LUMEN_CELL := Vector2i(18, 13)
const RELAY_LUMEN_STARS := 3
const PERKS := {
	PERK_PROVISIONING: {"name": "PROVISIONING", "unlock_level": 7, "detail": "+4 meals, -8 salvage"},
	PERK_FLOODLIGHT: {"name": "FLOODLIGHT", "unlock_level": 5, "detail": "+1 lit Lumen (sheds first), -6 salvage"},
	PERK_VOLUNTEER: {"name": "VOLUNTEER", "unlock_level": 3, "detail": "+1 resident, -8 salvage"},
	PERK_BUNKROOM: {"name": "BUNKROOM", "unlock_annex": 1, "detail": "blueprint: +1 Bunk, -14 salvage"},
	PERK_GROW_NOOK: {"name": "GROW NOOK", "unlock_annex": GROW_NOOK_BADGES, "detail": "blueprint: Grow Tray plan, -2 meals"},
	PERK_RELAY_LUMEN: {"name": "RELAY LUMEN", "unlock_annex_stars": RELAY_LUMEN_STARS, "detail": "blueprint: +1 low Lumen, free"},
}
const PERK_ORDER := [PERK_PROVISIONING, PERK_FLOODLIGHT, PERK_VOLUNTEER, PERK_BUNKROOM, PERK_GROW_NOOK, PERK_RELAY_LUMEN]
# The player's choice for the next wings (kept across NEW WING / REPLAY / stepping).
var equipped_perk := ""
# The perk this wing started with ("" = NONE); saved, shown on the outcome.
var wing_perk := ""
# Records + ladder C5: each sublevel below 07 carries one named modifier (not cumulative), applied
# at NEW WING and, for the rule-based ones, restored on LOAD from the saved sublevel.
# Ladder QA: 10, not 15, so the earliest seeded hatch (45 s) still warns after #111's 30 s idle-start
# card (45 - 15 = 30 hid the card for good on the merged game: no bunks, no Air, the crew died).
const EARLY_HATCH_ADVANCE_SECONDS := 10.0
# Ladder QA: 05 starts lean instead of with thin veins (the default digs never reach a vein, so
# THIN VEINS played exactly like 07). 30 of the usual 48 lands 05 between 06 and 04.
const LEAN_STORES_SALVAGE := 30
# Crew size, shared by NEW WING and the LOAD validator: 4, +1 on 03 (Fen), +1 for VOLUNTEER (Gil),
# and LOAD also leaves room for the Annex resident (Eko) that Keep Running can add later.
const BASE_CREW_SIZE := 4
const ANNEX_RESIDENT_ROOM := 1
const SUBLEVEL_MODIFIERS := {
	6: {"name": "EARLY HATCH", "detail": "hatch test 10 s earlier"},
	5: {"name": "LEAN STORES", "detail": "start with 30 salvage"},
	4: {"name": "DARK START", "detail": "starter Lumen unbuilt (5 salvage)"},
	3: {"name": "FIFTH MOUTH", "detail": "a fifth resident to feed"},
}
# Records + ladder: the per-wing sidecar store (scripts/wing_records.gd). Off for seed 0, and off
# whenever the main loop runs a script (tests, QA drivers) unless records_path is injected, so no
# test or tool ever touches the player's user://wing_records.json.
var records_path := ""
var best_path := ""
var _wing_best: WingBest = null
# Transient finish result; never part of a save or checkpoint.
var finish_best := {}
var save_path := SaveLoad.DEFAULT_PATH
# Day recovery uses its own atomic slot, never the player's manual/autosave slot.
var checkpoint_path := SaveLoad.CHECKPOINT_PATH
var _wing_records: WingRecords = null
# Records + ladder C3: this run's record as written at the finish transition, for the outcome
# panel's NEW RECORD mark. Transient: never saved, cleared by NEW WING and LOAD.
var finish_record := {}
const BUILD_KIND_BY_TOOL := {
	"bed": VaultBuilding.Kind.BED,
	"lamp": VaultBuilding.Kind.LAMP,
	"generator": VaultBuilding.Kind.GENERATOR,
	"grow": VaultBuilding.Kind.GROW_TRAY,
	"kitchen": VaultBuilding.Kind.KITCHEN,
	"stockpile": VaultBuilding.Kind.STOCKPILE,
	"air": VaultBuilding.Kind.AIR_RECYCLER,
	"rec": VaultBuilding.Kind.RECREATION_CONSOLE,
	"medical": VaultBuilding.Kind.MEDICAL_BED,
}

const _SNAPSHOT_INT := 0
const _SNAPSHOT_NUMBER := 1
const _SNAPSHOT_BOOL := 2
const _SNAPSHOT_STRING := 3
const _SNAPSHOT_BUILDING_FIELDS := {
	"id": _SNAPSHOT_INT,
	"kind": _SNAPSHOT_INT,
	"complete": _SNAPSHOT_BOOL,
	"delivered": _SNAPSHOT_INT,
	"construction_left": _SNAPSHOT_NUMBER,
	"powered": _SNAPSHOT_BOOL,
	"manually_disabled": _SNAPSHOT_BOOL,
	"is_emergency_core": _SNAPSHOT_BOOL,
	"production_progress": _SNAPSHOT_NUMBER,
}
const _SNAPSHOT_RESIDENT_FIELDS := {
	"id": _SNAPSHOT_INT,
	"name": _SNAPSHOT_STRING,
	"alive": _SNAPSHOT_BOOL,
	"sleeping": _SNAPSHOT_BOOL,
	"bed_id": _SNAPSHOT_INT,
	"recreating": _SNAPSHOT_BOOL,
	"recreation_id": _SNAPSHOT_INT,
	"recreation_sessions": _SNAPSHOT_INT,
	"stress_break_left": _SNAPSHOT_NUMBER,
	"drafted": _SNAPSHOT_BOOL,
}

@onready var map_grid: MapGrid = $MapGrid
@onready var building_root: Node2D = $Buildings
@onready var resident_root: Node2D = $Colonists
@onready var job_system: JobSystem = $JobSystem
@onready var power_grid: PowerGrid = $PowerGrid
@onready var lighting_system: LightingSystem = $LightingSystem
@onready var food_system: FoodSystem = $FoodSystem
@onready var oxygen_system: OxygenSystem = $OxygenSystem
@onready var day_cycle: DayCycle = $DayCycle
@onready var breach_system: BreachSystem = $BreachSystem
@onready var save_load: SaveLoad = $SaveLoad
@onready var world_camera: Camera2D = $Camera2D
@onready var map_view_3d: MapView3D = $MapView3D
@onready var player_orders: PlayerOrders = $PlayerOrders

var buildings: Array[VaultBuilding] = []
var residents: Array[VaultResident] = []
var next_building_id := 1
var active_tool := "select"
var selected_resident_id := -1
var selected_building_id := -1
var selected_breach := false
var simulation_speed := 1
var user_paused := true
var tutorial_open := true
var ended := false
var outcome := "":
	set(value):
		outcome = value
		if day_cycle != null:
			day_cycle.wing_lost = value == "loss"
const DEATH_RECAP_KEY := "death_recap"
const DEATH_RECAP_VERSION := 1
var death_recap := {}
var status_message := "Select DIG and mark rock beside the chamber."
var status_message_left := 0.0

# Wing orders (QA 2026-10-18c #3, slice 2): post-seal goals whose rewards unlock Mk II fits.
# A claim latches for the wing and is saved, so a reload never pays twice.
const ORDER_FIT_GROW_MK2 := "fit_grow_mk2"
const ORDER_STOCK_MEALS := "stock_meals"
const WING_ORDER_IDS := [ORDER_FIT_GROW_MK2, ORDER_STOCK_MEALS]
const ORDER_STOCK_MEALS_TARGET := 16
var wing_orders_claimed: Array[String] = []
# Post-seal reclamation (QA-d #2): a player-started, finite salvage income after the seal.
const RECLAIM_KEY := "post_seal_reclamation"
# One finite expedition; the existing Dig and rubble-haul jobs pay its labor cost.
const SUPPLY_CACHE_KEY := "day4_supply_cache"
const SUPPLY_CACHE_AT := 3.0 * DayCycle.SECONDS_PER_DAY
const SUPPLY_CACHE_SALVAGE := 6
const SUPPLY_CACHE_MEALS := 2
var supply_cache_enabled := false
var supply_cache_announced := false
var supply_cache_claimed := false
# QA-d #8 idle start: a two-step card for a wing nobody has touched by 30 s. Step 1 queues the standard
# opening (digs, two bunks, Charge Node, Nutrient Station, Grow Tray); step 2 is the Air Recycler.
const IDLE_START_KEY := "idle_start"
# Keep running (north star slice 1): after a win the player may continue the same vault. The win is
# recorded in this additive, versioned key, so the live wing itself is no longer "ended".
const KEEP_RUNNING_KEY := "keep_running"
const KEEP_RUNNING_VERSION := 1
const IDLE_START_VERSION := 1
const IDLE_START_VERSION_STEP3 := 2 # written only while step 3 is pending (stage 2); stage-1 saves stay version 1
const IDLE_START_DELAY := 30.0
const IDLE_START_DIG_COLUMNS := [16, 15, 14, 13, 12]
const IDLE_START_DIG_ROWS := [13, 14, 15, 16, 17]
const IDLE_START_PIECES := [
	[VaultBuilding.Kind.BED, Vector2i(27, 12)],
	[VaultBuilding.Kind.BED, Vector2i(26, 12)],
	[VaultBuilding.Kind.GENERATOR, Vector2i(21, 12)],
	[VaultBuilding.Kind.KITCHEN, Vector2i(22, 12)],
	[VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)],
]
const IDLE_START_AIR_CELL := Vector2i(24, 12)
const IDLE_START_BUNK_CELLS := [Vector2i(28, 12), Vector2i(25, 12), Vector2i(28, 13), Vector2i(25, 13), Vector2i(27, 13), Vector2i(26, 13)]
const IDLE_START_BUNK_TARGET := 4
const IDLE_START_PREFS_SECTION := "idle_start"
const RECLAIM_VERSION := 1
const RECLAIM_START_SALVAGE := 18
const RECLAIM_DELIVERY := 18
const RECLAIM_INTERVAL := 30.0
const RECLAIM_DELIVERIES := 6
var reclaim_active := false
var keep_running := false
var keep_running_seconds := 0.0
# Annex (north star slice 2): one keep-running project fed with meals above a reserve plus salvage.
const ANNEX_KEY := "annex"
const ANNEX_VERSION := 1
const ANNEX_MEALS := 30
const ANNEX_SALVAGE := 150
const ANNEX_TICK := 5.0
const ANNEX_HUNGRY_FOOD := 30.0
const ANNEX_RESERVE_DEFAULT := 8
const ANNEX_RESERVE_MIN := 4
const ANNEX_RESERVE_MAX := 20
const ANNEX_RESERVE_STEP := 2
const ANNEX_TRICKLE_INTERVAL := 20.0
var annex_meals := 0
var annex_salvage := 0
var annex_reserve := ANNEX_RESERVE_DEFAULT
var annex_done := false
var _annex_tick_left := ANNEX_TICK
var _annex_trickle_left := ANNEX_TRICKLE_INTERVAL
var reclaim_elapsed := 0.0
var reclaim_paid := 0
var idle_start_prefs_path := "user://vault_prefs.cfg"
var idle_start_stage := 0 # 0 not taken, 1 start queued (Air pending), 2 Air placed (step 3 waits for the seal), 3 done
var _idle_start_next_id := -1
var _idle_start_floor_count := -1
var _idle_start_dismissed_cache := {}
var _simulation_accumulator := 0.0
var _dragging_camera := false


func _ready() -> void:
	var designed := Vector2i(1280, 720)
	if DisplayServer.window_get_size() != designed:
		DisplayServer.window_set_size(designed)
	map_grid.setup(
		Callable(self, "_has_cancelable_blueprint_at"),
		Callable(self, "_is_reserved_cell"),
		Callable(self, "_is_stockpile_floor"),
	)
	lighting_system.setup(map_grid)
	breach_system.setup(self)
	job_system.setup(self)
	map_grid.tile_changed.connect(_on_map_topology_changed)
	map_grid.rubble_created.connect(_on_rubble_created)
	map_grid.dig_orders_removed.connect(_on_dig_orders_removed)
	food_system.raw_food_produced.connect(_on_raw_food_produced)
	day_cycle.day_started.connect(_on_day_started)
	power_grid.brownout_started.connect(_on_power_brownout_started)
	power_grid.brownout_cleared.connect(_on_power_brownout_cleared)
	power_grid.allocation_changed.connect(_on_power_allocation_changed)
	breach_system.warning_started.connect(_on_breach_warning_started)
	breach_system.breach_opened.connect(_on_breach_opened)
	breach_system.breach_sealed.connect(_on_breach_sealed)
	player_orders.setup(self)
	_enable_3d_play_view()
	new_game(true)


func _process(delta: float) -> void:
	_update_camera(delta)
	_sync_3d_play_view(false)
	status_message_left = maxf(0.0, status_message_left - delta)
	if not is_simulation_paused():
		_simulation_accumulator += delta * float(simulation_speed)
		var steps := 0
		while _simulation_accumulator >= SIMULATION_TICK and steps < 40:
			_simulation_step(SIMULATION_TICK)
			_simulation_accumulator -= SIMULATION_TICK
			steps += 1
			if is_simulation_paused():
				_simulation_accumulator = 0.0
				break
	player_orders.refresh()


func records_enabled() -> bool:
	return _records_enabled_for(wing_seed)


func _records_enabled_for(seed_value: int) -> bool:
	if seed_value == LEGACY_WING_SEED:
		return false
	if records_path != "":
		return true
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() == null


# Records + ladder C6: NEW WING starts on the deepest unlocked sublevel (07 when records are off).
# new_game() itself still defaults to 07.
func start_sublevel_for(seed_value: int) -> int:
	return wing_records().unlocked_sublevel() if _records_enabled_for(seed_value) else WingRecords.BASE_SUBLEVEL


func unlocked_sublevel() -> int:
	return wing_records().unlocked_sublevel() if records_enabled() else WingRecords.BASE_SUBLEVEL


func new_wing() -> void:
	var rolled := roll_wing_seed()
	new_game(true, rolled, start_sublevel_for(rolled))


func wing_records() -> WingRecords:
	if _wing_records == null:
		_wing_records = WingRecords.new()
	_wing_records.path = records_path if records_path != "" else WingRecords.DEFAULT_PATH
	return _wing_records


func wing_best() -> WingBest:
	if _wing_best == null:
		_wing_best = WingBest.new()
	_wing_best.path = best_path
	if _wing_best.path.is_empty():
		_wing_best.path = records_path.get_base_dir().path_join("wing_best.json") if records_path != "" else WingBest.DEFAULT_PATH
	return _wing_best


func best_enabled() -> bool:
	if not records_enabled():
		return false
	# Root-level injected record filenames would otherwise resolve to the real sidecar.
	# Scripted tests/tools must inject best_path or use a dedicated records directory.
	var loop := Engine.get_main_loop()
	return loop == null or loop.get_script() == null or ProjectSettings.globalize_path(wing_best().path) != ProjectSettings.globalize_path(WingBest.DEFAULT_PATH)


func new_game(show_tutorial := false, start_seed := LEGACY_WING_SEED, start_sublevel := WingRecords.BASE_SUBLEVEL) -> void:
	var seed_value := clampi(start_seed, LEGACY_WING_SEED, MAX_WING_SEED)
	var level := WingRecords.BASE_SUBLEVEL if seed_value == LEGACY_WING_SEED else clampi(start_sublevel, WingRecords.DEEPEST_SUBLEVEL, WingRecords.BASE_SUBLEVEL)
	player_orders.show_work_priorities(false)
	for building in buildings:
		building.free()
	for resident in residents:
		resident.free()
	buildings.clear()
	residents.clear()
	next_building_id = 1
	map_grid.new_wing(seed_value)
	job_system.reset()
	_reset_supply_cache(true, seed_value)
	power_grid.reset()
	lighting_system.reset()
	food_system.reset()
	oxygen_system.reset()
	day_cycle.reset()
	wing_seed = seed_value
	sublevel = level
	_apply_sublevel_rules()
	breach_system.reset()
	player_orders.show_wing_id(wing_seed)
	ended = false
	outcome = ""
	death_recap = {}
	player_orders.clear_survival_tips()
	finish_record = {}
	finish_best = {}
	active_tool = "select"
	map_grid.preview_tool = active_tool
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	_simulation_accumulator = 0.0
	wing_orders_claimed.clear()
	_reset_reclamation()
	_reset_keep_running()
	_spawn_starting_fixture(VaultBuilding.Kind.GENERATOR, Vector2i(24, 15), true)
	# Ladder QA: 04 DARK START with no Lumen at all was 1/6 (mood 0 by 60 s); an unbuilt one is 6/6.
	if sublevel == 4:
		_spawn_starting_blueprint(VaultBuilding.Kind.LAMP, Vector2i(22, 14))
	else:
		_spawn_starting_fixture(VaultBuilding.Kind.LAMP, Vector2i(22, 14), false)
	if sublevel == 5:
		food_system.salvage = LEAN_STORES_SALVAGE
	wing_perk = equipped_perk if equipped_perk in unlocked_perks_for(seed_value) else ""
	_apply_perk_start()
	_spawn_starting_fixture(VaultBuilding.Kind.STOCKPILE, Vector2i(19, 17), false)
	var names := ["Ari", "Bo", "Cyra", "Dax"]
	var cells := [Vector2i(20, 15), Vector2i(21, 16), Vector2i(22, 17), Vector2i(23, 18)]
	var starting_food := [65.0, 72.0, 79.0, 86.0]
	var starting_rest := [55.0, 70.0, 82.0, 94.0]
	var extra_crew := {"Fen": [Vector2i(24, 19), 72.0, 76.0], "Gil": [Vector2i(21, 19), 70.0, 72.0]}
	for extra: String in extra_crew_names(sublevel, wing_perk):
		names.append(extra)
		cells.append(extra_crew[extra][0])
		starting_food.append(extra_crew[extra][1])
		starting_rest.append(extra_crew[extra][2])
	for index in names.size():
		var resident := VaultResident.new()
		resident_root.add_child(resident)
		resident.configure(index + 1, names[index], cells[index], map_grid)
		resident.needs.food = starting_food[index]
		resident.needs.rest = starting_rest[index]
		resident.died.connect(_on_resident_died)
		residents.append(resident)
	crew_traits_version = CREW_TRAITS_V1 if wing_seed != LEGACY_WING_SEED else 0
	apply_crew_traits()
	power_grid.recalculate(buildings)
	refresh_lighting(true)
	oxygen_system.refresh_rates(residents, buildings, false)
	idle_start_stage = 0
	_idle_start_next_id = next_building_id
	_idle_start_floor_count = map_grid.get_floor_cells().size()
	world_camera.position = map_grid.cell_to_world(map_grid.get_chamber_center())
	world_camera.zoom = Vector2.ONE
	_sync_3d_play_view(true)
	tutorial_open = show_tutorial
	user_paused = true
	status_message = "Wing initialized. Stabilize supplies, oxygen, and the pressure hatch."
	status_message_left = 5.0
	player_orders.show_briefing(show_tutorial, show_tutorial)
	player_orders.show_breach_warning(
		breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged
	)
	player_orders.hide_outcome()
	game_started.emit()


func begin_shift() -> void:
	if ended or outcome == "death":
		return
	tutorial_open = false
	user_paused = false
	player_orders.show_briefing(false)
	status_message = "YOU designate dig/build. THEY auto-claim Dig/Haul/Craft/Cook from defaults (P optional)."
	status_message_left = 10.0
	if day_cycle.elapsed_seconds == 0.0:
		_save_day_checkpoint()




func _simulation_step(delta_seconds: float) -> void:
	if ended or outcome == "death":
		return
	# Clock restoration can skip day_started, even with a completed Day 7 clock.
	# Reconcile before work; the announcement latch preserves canceled expeditions.
	_reveal_supply_cache()
	power_grid.recalculate(buildings)
	job_system.reconcile_recreation_state()
	# Sample the actual live Next selector before damage can kill its named resident.
	# This runs for manual/headless steps too, independently of UI refreshes.
	player_orders.record_survival_tip(delta_seconds)
	for resident in residents:
		if not resident.alive:
			continue
		var resident_cell := resident.get_cell(map_grid)
		var lit := lighting_system.is_cell_lit(resident_cell)
		var assigned_bed := get_building_by_id(resident.bed_id)
		var in_bed := assigned_bed != null and assigned_bed.complete and resident_cell == assigned_bed.cell
		# A stress break vents, so passive mood loss pauses as in sleep and active Rec.
		resident.advance_needs(
			delta_seconds / DayCycle.SECONDS_PER_DAY,
			lit,
			in_bed,
			job_system.is_actively_recreating(resident) or (resident.stress_break_left > 0.0 and not resident.drafted),
			oxygen_system.is_low(),
		)
		if outcome in ["death", "loss"]:
			return
	_update_dark_alert(delta_seconds)
	var next_elapsed := minf(
		day_cycle.elapsed_seconds + delta_seconds,
		DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE,
	)
	var phase_before_step := breach_system.phase
	var open_boundary := breach_system.get_open_at()
	var opening_at_step_end := (
		phase_before_step == BreachSystem.Phase.WARNING
		and next_elapsed >= open_boundary
	)
	# Give patch work performed during 79.9-80.0 its complete interval before
	# deciding whether the hatch is still unsealed at the opening boundary.
	var breach_elapsed := open_boundary - 0.000001 if opening_at_step_end else next_elapsed
	breach_system.advance(delta_seconds, breach_elapsed)
	# A hatch that reaches the OPEN boundary at the end of this fixed tick only
	# starts venting on the following tick. This preserves the exact 80-second
	# grace boundary while keeping oxygen loss deterministic.
	oxygen_system.advance(
		delta_seconds,
		residents,
		buildings,
		phase_before_step == BreachSystem.Phase.OPEN,
	)
	if outcome in ["death", "loss"]:
		return
	if get_alive_count() <= 0:
		_finish_loss()
		return
	var warning_paused_this_step := (
		phase_before_step == BreachSystem.Phase.DORMANT
		and breach_system.phase == BreachSystem.Phase.WARNING
		and user_paused
	)
	if warning_paused_this_step:
		day_cycle.advance(delta_seconds)
		return
	job_system.advance(delta_seconds)
	if opening_at_step_end:
		breach_system.advance(0.0, next_elapsed)
	food_system.advance(delta_seconds, buildings)
	power_grid.recalculate(buildings)
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	_advance_reclamation(delta_seconds)
	_check_wing_orders()
	day_cycle.advance(delta_seconds)
	if keep_running:
		_advance_keep_running(delta_seconds)
	elif day_cycle.completed and breach_system.is_sealed() and oxygen_system.is_breathable():
		_finish_win()


func step_simulation(seconds: float) -> void:
	var steps := floori(maxf(0.0, seconds) / SIMULATION_TICK)
	for _index in steps:
		_simulation_step(SIMULATION_TICK)


func is_simulation_paused() -> bool:
	return (
		user_paused
		or tutorial_open
		or ended
		or outcome == "death"
		or (player_orders != null and player_orders.is_briefing_open())
	)


func toggle_pause() -> void:
	if tutorial_open or ended or outcome == "death" or player_orders.is_help_open():
		return
	if user_paused and breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
		acknowledge_breach_warning(true)
		return
	user_paused = not user_paused


func set_speed(speed: int) -> void:
	if player_orders.is_briefing_open() or outcome == "death":
		return
	simulation_speed = clampi(speed, 1, 3)
	if not tutorial_open and not ended:
		if breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
			breach_system.warning_acknowledged = true
			player_orders.show_breach_warning(false)
		user_paused = false


func set_tool(tool: String) -> void:
	active_tool = tool if tool in ["select", "dig", "cancel", "bed", "lamp", "generator", "grow", "kitchen", "stockpile", "air", "rec", "medical", "zone"] else "select"
	status_message = _tool_help(active_tool)
	status_message_left = 4.0
	map_grid.preview_tool = active_tool
	map_grid.queue_redraw()


func issue_order(cell: Vector2i) -> bool:
	if ended or outcome == "death" or tutorial_open or player_orders.is_help_open() or not map_grid.is_inside(cell):
		return false
	if active_tool == "select":
		return _select_at(cell)
	if active_tool == "dig":
		if map_grid.queue_dig(cell):
			job_system.queue_dig(cell)
			status_message = "Excavation queued. A resident with DIG enabled will claim it."
			status_message_left = 3.0
			return true
		if map_grid.is_diggable(cell) and not map_grid.dig_marks.has(cell):
			status_message = "Connect excavation orders to carved floor or an anchored dig chain."
		else:
			status_message = "Dig orders require undesignated rock inside the steel boundary."
		status_message_left = 3.0
		return false
	if active_tool == "zone":
		var painted := map_grid.paint_stockpile(cell)
		status_message = "Stockpile cell painted. Salvage, raw food, and meal haulers prefer reachable zones." if painted else "Zones need empty carved floor; keep fixtures and the hatch clear."
		status_message_left = 3.0
		return painted
	if active_tool == "cancel":
		if map_grid.clear_stockpile(cell):
			status_message = "Stockpile cell cleared. Haulers will choose another destination."
			status_message_left = 3.0
			return true
		if map_grid.cancel_dig(cell):
			status_message = "Excavation order canceled. Any disconnected designations were cleared."
			status_message_left = 2.0
			return true
		var blueprint := get_building_at(cell)
		if blueprint != null and not blueprint.complete:
			return _remove_building(blueprint, blueprint.delivered, "Blueprint canceled; delivered salvage refunded.")
		return false
	if BUILD_KIND_BY_TOOL.has(active_tool):
		return place_blueprint(int(BUILD_KIND_BY_TOOL[active_tool]), cell)
	return false


func place_blueprint(kind: int, cell: Vector2i) -> bool:
	if cell == BreachSystem.HATCH_CELL:
		status_message = "Keep the marked pressure hatch clear for emergency access."
		status_message_left = 3.0
		return false
	if not map_grid.is_walkable(cell):
		status_message = "Carve this tile before placing a fixture."
		status_message_left = 3.0
		return false
	if get_building_at(cell) != null:
		status_message = "That floor tile is already occupied."
		status_message_left = 3.0
		return false
	map_grid.clear_stockpile(cell)
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell)
	next_building_id += 1
	buildings.append(building)
	job_system.queue_building(building)
	status_message = "%s blueprint placed (%d salvage)." % [building.get_display_name(), building.get_cost()]
	status_message_left = 3.0
	return true


func get_building_at(cell: Vector2i) -> VaultBuilding:
	for building in buildings:
		if building.cell == cell:
			return building
	return null


func get_powered_building_count(kind: int) -> int:
	var count := 0
	for building in buildings:
		if building.complete and building.powered and building.kind == kind:
			count += 1
	return count


func is_air_ready() -> bool:
	return get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) > 0


func refresh_lighting(force := false) -> bool:
	return lighting_system.refresh(buildings, force)


func is_resident_lit(resident: VaultResident) -> bool:
	return (
		resident != null
		and resident.alive
		and lighting_system.is_cell_lit(resident.get_cell(map_grid))
	)


# The DARKNESS alert counts a resident only after DARK_ALERT_ONSET s unlit and drops them only
# after DARK_ALERT_RELEASE s lit, so crew crossing a Lumen edge don't flicker it. The HUD D-count
# and the darkness mood penalty still use the live cell every tick.
const DARK_ALERT_ONSET := 2.0
const DARK_ALERT_RELEASE := 6.0


func _update_dark_alert(delta_seconds: float) -> void:
	for resident: VaultResident in residents:
		var dark := resident.alive and not is_resident_lit(resident)
		if dark == resident.dark_alert_flagged:
			resident._dark_alert_dwell = 0.0
			continue
		resident._dark_alert_dwell += delta_seconds
		if resident._dark_alert_dwell >= (DARK_ALERT_ONSET if dark else DARK_ALERT_RELEASE) - 0.0001:
			resident.dark_alert_flagged = dark
			resident._dark_alert_dwell = 0.0


func get_dark_alert_count() -> int:
	var count := 0
	for resident: VaultResident in residents:
		if resident.alive and resident.dark_alert_flagged:
			count += 1
	return count


func get_dark_resident_count() -> int:
	var count := 0
	for resident: VaultResident in residents:
		if resident.alive and not is_resident_lit(resident):
			count += 1
	return count


func toggle_lighting_overlay() -> bool:
	var visible := lighting_system.toggle_coverage_overlay()
	status_message = (
		"LIGHT MAP ON: amber cells are lit; shaded floor is dark."
		if visible
		else "LIGHT MAP OFF: darkness remains visible; coverage guides hidden."
	)
	status_message_left = 4.0
	return visible


func toggle_building_enabled(building_id: int) -> bool:
	var building := get_building_by_id(building_id)
	if building == null or not building.complete or (not building.is_power_consumer() and building.kind != VaultBuilding.Kind.MEDICAL_BED):
		return false
	building.manually_disabled = not building.manually_disabled
	if building.kind == VaultBuilding.Kind.MEDICAL_BED and building.manually_disabled:
		for resident: VaultResident in residents:
			if resident.medical_bed_id == building_id:
				job_system.release_resident(resident)
	power_grid.recalculate(buildings)
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	var state := "disabled" if building.manually_disabled else "enabled"
	status_message = "%s %s. Power grid recalculated." % [building.get_display_name(), state]
	status_message_left = 4.0
	return true


# Mid-game salvage sink (QA 2026-10-18c #3, slice 1). Unlocked by a sealed hatch; one explicit
# purchase, paid in full from stored salvage, installs instantly and keeps the growth fraction.
func can_upgrade_building(building_id: int) -> bool:
	var building := get_building_by_id(building_id)
	return (
		building != null
		and building.can_take_upgrade()
		and is_upgrade_unlocked(building.kind)
		and not ended
		and breach_system.is_sealed()
		and is_air_ready()
		and food_system.salvage >= building.get_upgrade_cost()
	)


func upgrade_building(building_id: int) -> bool:
	if not can_upgrade_building(building_id):
		return false
	var building := get_building_by_id(building_id)
	var cost := building.get_upgrade_cost()
	if food_system.take_salvage(cost) != cost:
		return false
	if building.kind == VaultBuilding.Kind.GROW_TRAY:
		var fraction := building.production_progress / building.get_grow_seconds()
		building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
		building.production_progress = fraction * building.get_grow_seconds()
		status_message = "%s fitted for %d salvage: 1 raw every %d s." % [building.get_display_name(), cost, roundi(building.get_grow_seconds())]
		# Latch now: a paused fit followed by a removal must still count.
		_claim_wing_order(ORDER_FIT_GROW_MK2)
	else:
		building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
		if building.kind == VaultBuilding.Kind.GENERATOR:
			status_message = "%s fitted for %d salvage: %d power." % [building.get_display_name(), cost, building.get_power_output()]
		else:
			status_message = "%s fitted for %d salvage: same air for %d power." % [building.get_display_name(), cost, building.get_base_power_demand()]
	building.queue_redraw()
	power_grid.recalculate(buildings)
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	status_message_left = 4.0
	return true


# Grow Tray Mk II is open to every sealed wing; Charge Node and Air Recycler Mk II need a wing order.
# Claims from a snapshot whose shape is already validated; a save without the key claims nothing.
func _snapshot_order_claims(snapshot: Dictionary) -> Array:
	var orders: Variant = snapshot.get("wing_orders", {})
	if orders is Dictionary and orders.get("claimed") is Array:
		return orders.claimed
	return []


func is_upgrade_unlocked(kind: int) -> bool:
	match kind:
		VaultBuilding.Kind.GROW_TRAY:
			return true
		VaultBuilding.Kind.GENERATOR:
			return ORDER_FIT_GROW_MK2 in wing_orders_claimed
		VaultBuilding.Kind.AIR_RECYCLER:
			return ORDER_STOCK_MEALS in wing_orders_claimed
	return false


func _reset_reclamation() -> void:
	reclaim_active = false
	reclaim_elapsed = 0.0
	reclaim_paid = 0


func can_start_reclamation() -> bool:
	return not ended and breach_system.is_sealed() and not reclaim_active


# One explicit choice: +18 salvage now, then +18 every 30 s of simulation, 6 times (126 in all).
func start_reclamation() -> bool:
	if not can_start_reclamation():
		return false
	reclaim_active = true
	reclaim_elapsed = 0.0
	reclaim_paid = 0
	food_system.add_salvage(RECLAIM_START_SALVAGE)
	status_message = "Reclamation started: +%d salvage now, +%d every %d s (%d deliveries)." % [RECLAIM_START_SALVAGE, RECLAIM_DELIVERY, roundi(RECLAIM_INTERVAL), RECLAIM_DELIVERIES]
	status_message_left = 4.0
	return true


func reclaim_seconds_to_next() -> float:
	if not reclaim_active or reclaim_paid >= RECLAIM_DELIVERIES:
		return -1.0
	return maxf(0.0, float(reclaim_paid + 1) * RECLAIM_INTERVAL - reclaim_elapsed)


func _advance_reclamation(delta_seconds: float) -> void:
	if not reclaim_active or ended or reclaim_paid >= RECLAIM_DELIVERIES:
		return
	reclaim_elapsed += delta_seconds
	while reclaim_paid < RECLAIM_DELIVERIES and reclaim_elapsed >= float(reclaim_paid + 1) * RECLAIM_INTERVAL - 0.0001:
		reclaim_paid += 1
		food_system.add_salvage(RECLAIM_DELIVERY)


# Untouched means: no blueprint ever placed (ids still at the shift start), no dig mark open and no
# rock carved since the wing began. Only a fresh New Wing qualifies; a loaded save never re-offers.
func can_offer_idle_start() -> bool:
	return (
		idle_start_stage == 0
		and not ended
		and _idle_start_next_id > 0
		and day_cycle.elapsed_seconds >= IDLE_START_DELAY
		and breach_system.phase == BreachSystem.Phase.DORMANT
		and next_building_id == _idle_start_next_id
		and map_grid.dig_marks.is_empty()
		and map_grid.get_floor_cells().size() == _idle_start_floor_count
		and not idle_start_dismissed()
	)


# Step 2 stays pending only while the wing has no Air Recycler at all: one placed with [AIR], on any
# cell, as a blueprint or finished, satisfies it (and a reloaded save re-checks the same way).
func idle_start_air_pending() -> bool:
	return idle_start_stage == 1 and not ended and not idle_start_dismissed() and not _idle_start_air_placed()


func _idle_start_air_placed() -> bool:
	for building in buildings:
		if building.kind == VaultBuilding.Kind.AIR_RECYCLER:
			return true
	return false


# Step 3 (QA-e #3): after the seal, one tap starts reclamation and queues 2 bunks. Reconciled from
# the world: a running (or finished) reclamation, or 4+ bunks in any state, already count as done.
func idle_start_bunks_pending() -> bool:
	return (
		idle_start_stage in [1, 2]
		and not ended
		and breach_system.is_sealed()
		and _idle_start_air_placed()
		and not reclaim_active
		and _idle_start_bunk_count() < IDLE_START_BUNK_TARGET
		and not idle_start_dismissed()
	)


func _idle_start_bunk_count() -> int:
	var count := 0
	for building in buildings:
		if building.kind == VaultBuilding.Kind.BED:
			count += 1
	return count


func apply_idle_start_bunks() -> bool:
	if not idle_start_bunks_pending():
		return false
	var cells: Array[Vector2i] = []
	for cell: Vector2i in IDLE_START_BUNK_CELLS:
		if cells.size() < 2 and _idle_start_cell_free(cell):
			cells.append(cell)
	if cells.size() < 2:
		status_message = "No room for 2 bunks by the start; place them with [BUNK]."
		status_message_left = 4.0
		return false
	start_reclamation()
	for cell: Vector2i in cells:
		place_blueprint(VaultBuilding.Kind.BED, cell)
	idle_start_stage = 3
	status_message = "Reclamation started and 2 bunks queued: +%d salvage now, +%d every %d s." % [RECLAIM_START_SALVAGE, RECLAIM_DELIVERY, roundi(RECLAIM_INTERVAL)]
	status_message_left = 5.0
	return true


func idle_start_dismissed() -> bool:
	if not _idle_start_dismissed_cache.has(idle_start_prefs_path):
		var prefs := ConfigFile.new()
		_idle_start_dismissed_cache[idle_start_prefs_path] = prefs.load(idle_start_prefs_path) == OK and bool(prefs.get_value(IDLE_START_PREFS_SECTION, "dismissed", false))
	return bool(_idle_start_dismissed_cache[idle_start_prefs_path])


# Dismissal is per profile: the card never comes back, on this wing or any later one.
func dismiss_idle_start() -> void:
	var prefs := ConfigFile.new()
	prefs.load(idle_start_prefs_path)
	prefs.set_value(IDLE_START_PREFS_SECTION, "dismissed", true)
	prefs.save(idle_start_prefs_path)
	_idle_start_dismissed_cache[idle_start_prefs_path] = true
	idle_start_stage = 0
	status_message = "Idle start dismissed. It will not be offered again."
	status_message_left = 3.0


func _idle_start_cell_free(cell: Vector2i) -> bool:
	return cell != BreachSystem.HATCH_CELL and map_grid.is_walkable(cell) and get_building_at(cell) == null


func apply_idle_start() -> bool:
	if not can_offer_idle_start():
		return false
	for piece: Array in IDLE_START_PIECES:
		if not _idle_start_cell_free(piece[1]):
			status_message = "Recommended start blocked at %s; place the opening by hand." % piece[1]
			status_message_left = 4.0
			return false
	for x: int in IDLE_START_DIG_COLUMNS:
		for y: int in IDLE_START_DIG_ROWS:
			if map_grid.queue_dig(Vector2i(x, y)):
				job_system.queue_dig(Vector2i(x, y))
	for piece: Array in IDLE_START_PIECES:
		place_blueprint(int(piece[0]), piece[1])
	idle_start_stage = 1
	status_message = "Recommended start queued: digs, bunks, power and food. Next: an Air Recycler."
	status_message_left = 5.0
	return true


func place_idle_start_air() -> bool:
	if not idle_start_air_pending():
		return false
	if not _idle_start_cell_free(IDLE_START_AIR_CELL) or not place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, IDLE_START_AIR_CELL):
		status_message = "Air Recycler spot is taken; place one with [AIR]."
		status_message_left = 4.0
		return false
	idle_start_stage = 2
	return true


func _claim_wing_order(order_id: String) -> void:
	if order_id in WING_ORDER_IDS and not order_id in wing_orders_claimed:
		wing_orders_claimed.append(order_id)


# Orders count only while the hatch is sealed and the wing is live. Stored meals only.
func _check_wing_orders() -> void:
	if ended or not breach_system.is_sealed():
		return
	for building in buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY and building.upgrade_tier >= VaultBuilding.UPGRADE_TIER_MAX:
			_claim_wing_order(ORDER_FIT_GROW_MK2)
			break
	if food_system.meals >= ORDER_STOCK_MEALS_TARGET:
		_claim_wing_order(ORDER_STOCK_MEALS)


func deconstruct_building(building_id: int) -> bool:
	var building := get_building_by_id(building_id)
	if building == null or not building.complete or building.is_emergency_core:
		return false
	var refund := building.get_deconstruct_refund()
	return _remove_building(
		building,
		refund,
		"%s deconstructed; %d salvage recovered." % [building.get_display_name(), refund],
	)


func get_building_by_id(building_id: int) -> VaultBuilding:
	for building in buildings:
		if building.building_id == building_id:
			return building
	return null


func get_resident_by_id(resident_id: int) -> VaultResident:
	for resident in residents:
		if resident.resident_id == resident_id:
			return resident
	return null


func toggle_resident_draft(resident_id: int) -> bool:
	if tutorial_open or ended or outcome == "death" or player_orders.is_help_open() or player_orders.is_work_priorities_open():
		return false
	if breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
		return false
	var resident := get_resident_by_id(resident_id)
	if resident == null or not resident.alive:
		return false
	if resident.drafted:
		resident.drafted = false
		resident.clear_manual_move_order()
		resident.clear_forced_order()
		resident.state = "Idle"
		status_message = "%s undrafted; automatic work and self-care resumed." % resident.resident_name
	else:
		job_system.release_resident(resident)
		resident.drafted = true
		resident.sleeping = false
		resident.bed_id = -1
		resident.recreating = false
		resident.recreation_id = -1
		resident.stress_break_left = 0.0
		resident.state = "Drafted"
		status_message = "%s drafted. Right-click reachable carved floor to move; undraft to resume autonomy." % resident.resident_name
	status_message_left = 4.0
	resident.queue_redraw()
	return resident.drafted


func issue_selected_resident_context_order(cell: Vector2i) -> bool:
	if ended or outcome == "death" or tutorial_open or player_orders.is_help_open() or player_orders.is_work_priorities_open() or not map_grid.is_inside(cell):
		return false
	var resident := get_resident_by_id(selected_resident_id)
	if resident == null or not resident.alive:
		return false
	if resident.drafted:
		return _issue_drafted_move(resident, cell)
	var result := job_system.force_job_at(resident, cell)
	status_message = str(result.message)
	status_message_left = 4.0
	return bool(result.ok)


func issue_context_order(cell: Vector2i) -> bool:
	return issue_selected_resident_context_order(cell)


func cancel_selected_resident_command() -> bool:
	var resident := get_resident_by_id(selected_resident_id)
	if resident == null or not resident.alive:
		return false
	if not resident.drafted and not resident.is_forced_job and resident.current_job_id < 0:
		status_message = "%s has no manual command to cancel." % resident.resident_name
		status_message_left = 3.0
		return false
	var canceled := false
	if resident.drafted:
		if resident.has_manual_move_order():
			resident.clear_manual_move_order()
			canceled = true
	else:
		canceled = job_system.cancel_manual_command(resident)
	status_message = "%s manual command canceled." % resident.resident_name if canceled else "%s has no manual command to cancel." % resident.resident_name
	status_message_left = 3.0
	return canceled


func select_resident(resident_id: int) -> void:
	selected_resident_id = resident_id
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = resident.resident_id == resident_id
		resident.queue_redraw()


func select_building(building_id: int) -> void:
	selected_building_id = building_id
	selected_resident_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()


func set_work_priority(resident_id: int, work_type: String, priority: int) -> bool:
	var resident := get_resident_by_id(resident_id)
	if resident == null or not resident.set_work_priority(work_type, priority):
		return false
	if priority == VaultResident.PRIORITY_DISABLED and resident.current_job_id >= 0 and not resident.is_forced_job and not job_system._resident_allows(resident, resident.current_job_type):
		job_system.release_resident(resident)
	status_message = "%s %s priority: %s." % [resident.resident_name, work_type.capitalize(), resident.get_work_priority_label(work_type)]
	status_message_left = 3.0
	return true


func cycle_work_priority(resident_id: int, work_type: String) -> int:
	var resident := get_resident_by_id(resident_id)
	if resident == null or work_type not in VaultResident.WORK_TYPES:
		return -1
	var priority := resident.cycle_work_priority(work_type)
	if priority == VaultResident.PRIORITY_DISABLED and resident.current_job_id >= 0 and not resident.is_forced_job and not job_system._resident_allows(resident, resident.current_job_type):
		job_system.release_resident(resident)
	status_message = "%s %s priority: %s." % [resident.resident_name, work_type.capitalize(), resident.get_work_priority_label(work_type)]
	status_message_left = 3.0
	return priority


func toggle_work(resident_id: int, work_type: String) -> void:
	var resident := get_resident_by_id(resident_id)
	if resident == null or work_type not in VaultResident.WORK_TYPES:
		return
	var priority := (
		VaultResident.PRIORITY_DISABLED
		if resident.get_work_priority(work_type) != VaultResident.PRIORITY_DISABLED
		else VaultResident.DEFAULT_WORK_PRIORITY
	)
	set_work_priority(resident_id, work_type, priority)


func get_alive_count() -> int:
	var alive_count := 0
	for resident in residents:
		if resident.alive:
			alive_count += 1
	return alive_count


func get_completed_building_count(kind: int, exclude_core := false) -> int:
	var count := 0
	for building in buildings:
		if building.complete and building.kind == kind and (not exclude_core or not building.is_emergency_core):
			count += 1
	return count


func save_game(show_message := true, path := "") -> bool:
	var result := save_load.save_snapshot(create_snapshot(), save_path if path == "" else path)
	if show_message:
		status_message = str(result.message)
		status_message_left = 4.0
	return bool(result.ok)


func load_game(path := "") -> bool:
	var result := save_load.load_snapshot(save_path if path == "" else path)
	status_message = str(result.message)
	status_message_left = 5.0
	if not bool(result.ok):
		return false
	if not apply_snapshot(result.snapshot):
		status_message = "The save did not contain a valid vault wing."
		return false
	player_orders.show_work_priorities(false)
	tutorial_open = false
	user_paused = true
	player_orders.show_briefing(false)
	if ended or outcome == "death":
		player_orders.show_outcome(outcome == "win", get_alive_count())
	else:
		player_orders.hide_outcome()
	return true


# Post-seal reclamation: an additive, versioned key, written only once the player started it.
func create_snapshot() -> Dictionary:
	var snapshot := _create_base_snapshot()
	if supply_cache_enabled:
		snapshot[SUPPLY_CACHE_KEY] = {
			"version": 1,
			"position": [map_grid.supply_cache_cell.x, map_grid.supply_cache_cell.y],
			"announced": supply_cache_announced,
			"claimed": supply_cache_claimed,
		}
	if not death_recap.is_empty():
		snapshot[DEATH_RECAP_KEY] = death_recap.duplicate(true)
	if reclaim_active:
		snapshot[RECLAIM_KEY] = {"version": RECLAIM_VERSION, "elapsed": reclaim_elapsed, "paid": reclaim_paid}
	if idle_start_stage == 1:
		snapshot[IDLE_START_KEY] = {"version": IDLE_START_VERSION, "stage": idle_start_stage}
	elif idle_start_stage == 2:
		snapshot[IDLE_START_KEY] = {"version": IDLE_START_VERSION_STEP3, "stage": idle_start_stage}
	if keep_running:
		snapshot[KEEP_RUNNING_KEY] = {"version": KEEP_RUNNING_VERSION, "seconds": keep_running_seconds}
		snapshot[ANNEX_KEY] = {
			"version": ANNEX_VERSION,
			"meals": annex_meals,
			"salvage": annex_salvage,
			"reserve": annex_reserve,
			"done": annex_done,
		}
	return snapshot


func _create_base_snapshot() -> Dictionary:
	var building_data: Array = []
	for building in buildings:
		building_data.append(building.serialize())
	var resident_data: Array = []
	for resident in residents:
		resident_data.append(resident.serialize())
	var snapshot := {
		"map": map_grid.serialize(),
		"buildings": building_data,
		"residents": resident_data,
		"food": food_system.serialize(),
		"oxygen": oxygen_system.serialize(),
		"day": day_cycle.serialize(),
		"breach": breach_system.serialize(),
		"wing_orders": {"claimed": wing_orders_claimed.duplicate()},
		"jobs": job_system.serialize(),
		"next_building_id": next_building_id,
		"camera": [world_camera.position.x, world_camera.position.y, world_camera.zoom.x],
		"ended": ended,
		"outcome": outcome,
		"wing_seed": wing_seed,
	}
	# Wing-seed slice 2: additive, written only for a seeded layout, so legacy saves keep their bytes.
	if map_grid.layout_seed != LEGACY_WING_SEED:
		snapshot["map_layout"] = MAP_LAYOUT_SEEDED
	# Wing-seed slice 3: additive marker; traits themselves are derived from seed + resident id.
	if crew_traits_version == CREW_TRAITS_V1:
		snapshot["crew_traits"] = CREW_TRAITS_V1
	# Records + ladder C4: additive, written only below 07.
	if sublevel != WingRecords.BASE_SUBLEVEL:
		snapshot["sublevel"] = {"version": SUBLEVEL_SAVE_VERSION, "level": sublevel}
	# Meta perks P1: additive, written only when the wing started with a perk.
	if wing_perk != "":
		snapshot["perk"] = {"version": PERK_SAVE_VERSION, "id": wing_perk}
	return snapshot


func apply_snapshot(snapshot: Dictionary) -> bool:
	if not _is_snapshot_shape_valid(snapshot):
		return false
	_reset_supply_cache(snapshot.has(SUPPLY_CACHE_KEY), _snapshot_wing_seed(snapshot))
	if supply_cache_enabled:
		var cache_position: Array = snapshot[SUPPLY_CACHE_KEY].position
		map_grid.supply_cache_cell = Vector2i(int(cache_position[0]), int(cache_position[1]))
		supply_cache_announced = snapshot[SUPPLY_CACHE_KEY].announced
		supply_cache_claimed = snapshot[SUPPLY_CACHE_KEY].claimed
		map_grid.supply_cache_open = supply_cache_announced
		map_grid.supply_cache_visible = supply_cache_announced and not supply_cache_claimed
	if not map_grid.deserialize(snapshot.map):
		return false
	lighting_system.reset()
	for building in buildings:
		building.free()
	for resident in residents:
		resident.free()
	buildings.clear()
	residents.clear()
	for data: Variant in snapshot.buildings:
		if not data is Dictionary:
			continue
		var building := VaultBuilding.new()
		building_root.add_child(building)
		building.deserialize(data)
		buildings.append(building)
	for data: Variant in snapshot.residents:
		if not data is Dictionary:
			continue
		var resident := VaultResident.new()
		resident_root.add_child(resident)
		resident.deserialize(data)
		resident.died.connect(_on_resident_died)
		residents.append(resident)
	if residents.is_empty():
		return false
	food_system.deserialize(snapshot.get("food", {}))
	oxygen_system.deserialize(snapshot.get("oxygen", {}))
	day_cycle.deserialize(snapshot.get("day", {}))
	wing_seed = _snapshot_wing_seed(snapshot)
	sublevel = _snapshot_sublevel(snapshot)
	# LOAD restores which perk the wing started with; its start is in the saved stores, never re-granted.
	wing_perk = str(snapshot.perk.id) if snapshot.get("perk") is Dictionary else ""
	map_grid.apply_layout_seed(wing_seed if int(snapshot.get("map_layout", 0)) == MAP_LAYOUT_SEEDED else LEGACY_WING_SEED)
	_apply_sublevel_rules()
	player_orders.show_wing_id(wing_seed)
	crew_traits_version = CREW_TRAITS_V1 if wing_seed != LEGACY_WING_SEED and int(snapshot.get("crew_traits", 0)) == CREW_TRAITS_V1 else 0
	apply_crew_traits()
	breach_system.deserialize(snapshot.get("breach", {}), day_cycle.elapsed_seconds)
	next_building_id = int(snapshot.get("next_building_id", 1))
	wing_orders_claimed.clear()
	for order_id: Variant in _snapshot_order_claims(snapshot):
		wing_orders_claimed.append(str(order_id))
	_reset_reclamation()
	if snapshot.has(RECLAIM_KEY):
		reclaim_active = true
		reclaim_elapsed = float(snapshot[RECLAIM_KEY].elapsed)
		reclaim_paid = int(snapshot[RECLAIM_KEY].paid)
	idle_start_stage = int(snapshot[IDLE_START_KEY].stage) if snapshot.has(IDLE_START_KEY) else 0
	_reset_keep_running()
	if snapshot.has(KEEP_RUNNING_KEY):
		keep_running = true
		keep_running_seconds = float(snapshot[KEEP_RUNNING_KEY].seconds)
		if snapshot.has(ANNEX_KEY):
			var annex: Dictionary = snapshot[ANNEX_KEY]
			annex_meals = int(annex.meals)
			annex_salvage = int(annex.salvage)
			annex_reserve = int(annex.reserve)
			annex_done = bool(annex.done)
		_reconcile_annex()
	_idle_start_next_id = -1
	_idle_start_floor_count = -1
	ended = bool(snapshot.get("ended", false))
	outcome = str(snapshot.get("outcome", ""))
	death_recap = snapshot.get(DEATH_RECAP_KEY, {}).duplicate(true)
	if not death_recap.is_empty():
		# JSON parses numbers as floats; restore the recap's integer schema just
		# as the resident/building deserializers restore their integer fields.
		death_recap["version"] = int(death_recap.version)
		death_recap["resident_id"] = int(death_recap.resident_id)
		if death_recap.has("elapsed_seconds"):
			death_recap["elapsed_seconds"] = float(death_recap.elapsed_seconds)
	player_orders.clear_survival_tips()
	finish_record = {}
	finish_best = {}
	var camera_data: Array = snapshot.get("camera", [])
	if camera_data.size() >= 3:
		world_camera.position = Vector2(float(camera_data[0]), float(camera_data[1]))
		world_camera.zoom = Vector2.ONE * clampf(float(camera_data[2]), 0.75, 1.8)
	power_grid.reset()
	_mark_floodlight()
	power_grid.recalculate(buildings)
	refresh_lighting(true)
	job_system.rebuild_from_state(snapshot.get("jobs", {}))
	job_system.restore_manual_orders()
	job_system.reconcile_recreation_state()
	for resident in residents:
		resident.restore_hatch_continuation()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	# short_of_air is derived, not saved: rebuild it so a paused load shows the right work speed.
	var thin_air := oxygen_system.is_low()
	for resident in residents:
		resident.short_of_air = thin_air and resident.alive
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	active_tool = "select"
	map_grid.preview_tool = active_tool
	_simulation_accumulator = 0.0
	player_orders.show_breach_warning(
		breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged
	)
	if ended or outcome == "death":
		user_paused = true
		if outcome == "win":
			player_orders.show_outcome(true, get_alive_count())
		else:
			player_orders.show_outcome(false, get_alive_count())
	else:
		player_orders.hide_outcome()
	return true


# Wing seed (QA 2026-10-18c #2, slice 1). Additive snapshot key: a save without it is the legacy wing.
const MAP_LAYOUT_SEEDED := 1
const CREW_TRAITS_V1 := 1
var crew_traits_version := 0


# Gives every resident its seeded trait (or none): new games, and loads after the seed is known.
func apply_crew_traits() -> void:
	var crew := VaultResident.crew_traits_for_seed(wing_seed if crew_traits_version == CREW_TRAITS_V1 else LEGACY_WING_SEED)
	for resident: VaultResident in residents:
		var slot := resident.resident_id - 1
		resident.set_trait(crew[slot] if slot >= 0 and slot < crew.size() else "")


func _snapshot_wing_seed(snapshot: Dictionary) -> int:
	return int(snapshot.get("wing_seed", LEGACY_WING_SEED))


static func sublevel_modifier(level: int) -> Dictionary:
	return SUBLEVEL_MODIFIERS.get(level, {})


# The hatch warning time for a wing: 06 EARLY HATCH moves it 10 s earlier (the 20 s grace is kept).
static func warning_at_for(seed_value: int, level: int) -> float:
	var warn := BreachSystem.warning_at_for_seed(seed_value)
	if seed_value != LEGACY_WING_SEED and level == 6:
		warn -= EARLY_HATCH_ADVANCE_SECONDS
	return warn


func _apply_sublevel_rules() -> void:
	breach_system.warning_at = warning_at_for(wing_seed, sublevel)


# Meta perks P1: the perks the player has unlocked, in display order. Empty when records are off
# (seed 0, tests), so those wings always start on NONE.
func unlocked_perks() -> Array:
	return unlocked_perks_for(wing_seed)


func unlocked_perks_for(seed_value: int) -> Array:
	var unlocked := []
	if not _records_enabled_for(seed_value):
		return unlocked
	var store := wing_records()
	for id: String in PERK_ORDER:
		var perk: Dictionary = PERKS[id]
		if perk.has("unlock_annex_stars"):
			if store.has_annex_badge_with_stars(int(perk.unlock_annex_stars)):
				unlocked.append(id)
		elif store.annex_badge_sublevels() >= int(perk.unlock_annex) if perk.has("unlock_annex") else store.has_win_on(int(perk.unlock_level)):
			unlocked.append(id)
	return unlocked


static func perk_name(id: String) -> String:
	return str(PERKS[id].name) if PERKS.has(id) else "NONE"


func _apply_perk_start() -> void:
	match wing_perk:
		PERK_PROVISIONING:
			food_system.meals += PROVISIONING_MEALS
			food_system.salvage = maxi(0, food_system.salvage - PROVISIONING_SALVAGE_COST)
		PERK_FLOODLIGHT:
			_spawn_starting_fixture(VaultBuilding.Kind.LAMP, FLOODLIGHT_CELL, false)
			food_system.salvage = maxi(0, food_system.salvage - FLOODLIGHT_SALVAGE_COST)
		PERK_VOLUNTEER:
			food_system.salvage = maxi(0, food_system.salvage - VOLUNTEER_SALVAGE_COST)
		PERK_BUNKROOM:
			_spawn_starting_fixture(VaultBuilding.Kind.BED, BUNKROOM_CELL, false)
			food_system.salvage = maxi(0, food_system.salvage - BUNKROOM_SALVAGE_COST)
		PERK_GROW_NOOK:
			_spawn_starting_blueprint(VaultBuilding.Kind.GROW_TRAY, GROW_NOOK_CELL, true)
			food_system.meals = maxi(0, food_system.meals - GROW_NOOK_MEALS_COST)
		PERK_RELAY_LUMEN:
			_spawn_starting_fixture(VaultBuilding.Kind.LAMP, RELAY_LUMEN_CELL, false)
	_mark_floodlight()


# Perk Lumen flags are re-derived on NEW WING and LOAD. Only RELAY LUMEN is self-powered;
# FLOODLIGHT still sheds first. Match id and cell so a replacement Lumen keeps normal demand/priority.
func _mark_floodlight() -> void:
	var cell := FLOODLIGHT_CELL if wing_perk == PERK_FLOODLIGHT else RELAY_LUMEN_CELL
	for building: VaultBuilding in buildings:
		building.shed_first = wing_perk in [PERK_FLOODLIGHT, PERK_RELAY_LUMEN] and building.building_id == FLOODLIGHT_BUILDING_ID and building.kind == VaultBuilding.Kind.LAMP and building.cell == cell
		building.self_powered = wing_perk == PERK_RELAY_LUMEN and building.shed_first
		if building.self_powered:
			# Older saves could disable this Lumen while it was still a grid consumer.
			building.manually_disabled = false


# Only {"version": 1, "id": <known perk>} on a seeded wing; NONE is never written.
func _is_perk_data_valid(data: Variant, seed_value: int) -> bool:
	if not data is Dictionary or (data as Dictionary).size() != 2 or seed_value == LEGACY_WING_SEED:
		return false
	return _is_integer_in_range(data.get("version"), PERK_SAVE_VERSION, PERK_SAVE_VERSION) and typeof(data.get("id")) == TYPE_STRING and PERKS.has(data.id)


# The residents a wing adds to the base four: Fen on 03, Gil with VOLUNTEER.
static func extra_crew_names(level: int, perk: String) -> Array:
	var extra := []
	if level == 3:
		extra.append("Fen")
	if perk == PERK_VOLUNTEER:
		extra.append("Gil")
	return extra


static func starting_crew_size(level: int, perk: String) -> int:
	return BASE_CREW_SIZE + extra_crew_names(level, perk).size()


# LOAD's cap: the wing's starting crew plus room for the Annex resident.
static func max_crew_size(level: int, perk: String) -> int:
	return starting_crew_size(level, perk) + ANNEX_RESIDENT_ROOM


func _snapshot_perk(snapshot: Dictionary) -> String:
	var data: Variant = snapshot.get("perk")
	return str(data.get("id", "")) if data is Dictionary else ""


func _snapshot_sublevel(snapshot: Dictionary) -> int:
	var data: Variant = snapshot.get("sublevel")
	return int(data.level) if data is Dictionary else WingRecords.BASE_SUBLEVEL


# Only {"version": 1, "level": 03..06} on a seeded wing; 07 is never written.
func _is_sublevel_data_valid(data: Variant, seed_value: int) -> bool:
	if not data is Dictionary or (data as Dictionary).size() != 2 or seed_value == LEGACY_WING_SEED:
		return false
	return _is_integer_in_range(data.get("version"), SUBLEVEL_SAVE_VERSION, SUBLEVEL_SAVE_VERSION) and _is_integer_in_range(data.get("level"), WingRecords.DEEPEST_SUBLEVEL, WingRecords.BASE_SUBLEVEL - 1)


# The only entropy in the game: the NEW WING button reads the clock once and hands it to the pure
# pick_wing_seed(). Load, snapshot, simulation and UI refresh never roll.
func roll_wing_seed() -> int:
	return pick_wing_seed(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0), wing_seed)


# Pure and bounded: a seed in 1..MAX_WING_SEED whose breach window differs from the current wing's,
# so back-to-back wings always feel different. Eight windows, so the scan ends within 8 steps.
static func pick_wing_seed(entropy: int, current_seed: int) -> int:
	var current_window := BreachSystem.warning_at_for_seed(current_seed)
	var candidate := 1 + BreachSystem.seed_hash(entropy & 0x7FFFFFFF, 2) % MAX_WING_SEED
	for step in MAX_WING_SEED:
		if BreachSystem.warning_at_for_seed(candidate) != current_window:
			return candidate
		candidate = 1 + candidate % MAX_WING_SEED
	return candidate


func _is_snapshot_shape_valid(snapshot: Dictionary) -> bool:
	if not _is_snapshot_schema_valid(snapshot):
		return false
	var map_data: Variant = snapshot.get("map")
	var resident_data: Variant = snapshot.get("residents")
	var building_data: Variant = snapshot.get("buildings")
	var day_data: Variant = snapshot.get("day", {})
	var breach_data: Variant = snapshot.get("breach", {})
	var oxygen_data: Variant = snapshot.get("oxygen", {})
	var jobs_data: Variant = snapshot.get("jobs", {})
	if not map_data is Dictionary or not resident_data is Array or not building_data is Array:
		return false
	if not MapGrid.is_stockpile_data_valid(map_data):
		return false
	if not _is_supply_cache_snapshot_valid(snapshot):
		return false
	if not job_system.is_serialized_food_haul_data_valid(jobs_data, map_data):
		return false
	for entry: Array in map_data.get("stockpile_cells", []):
		var zone_cell := Vector2i(int(entry[0]), int(entry[1]))
		if zone_cell == BreachSystem.HATCH_CELL:
			return false
		for fixture: Variant in building_data:
			if fixture is Dictionary and fixture.get("cell") == entry:
				return false
	if snapshot.has("ended") and typeof(snapshot.ended) != TYPE_BOOL:
		return false
	if snapshot.has("outcome") and typeof(snapshot.outcome) != TYPE_STRING:
		return false
	if snapshot.has("wing_seed") and not _is_integer_in_range(snapshot.wing_seed, LEGACY_WING_SEED, MAX_WING_SEED):
		return false
	# Wing-seed slice 2: a seeded layout is only valid on a seeded wing, and only version 1 exists.
	if snapshot.has("map_layout") and (not _is_integer_in_range(snapshot.map_layout, MAP_LAYOUT_SEEDED, MAP_LAYOUT_SEEDED)):
		return false
	if snapshot.has("crew_traits") and not _is_integer_in_range(snapshot.crew_traits, CREW_TRAITS_V1, CREW_TRAITS_V1):
		return false
	if snapshot.has("sublevel") and not _is_sublevel_data_valid(snapshot.sublevel, _snapshot_wing_seed(snapshot)):
		return false
	if snapshot.has("perk") and not _is_perk_data_valid(snapshot.perk, _snapshot_wing_seed(snapshot)):
		return false
	# A seeded save is always new, so it must carry a real breach state and clock; only the legacy
	# wing may fall back to the historical synthesis.
	if _snapshot_wing_seed(snapshot) != LEGACY_WING_SEED:
		var seeded_breach: Variant = snapshot.get("breach")
		var seeded_day: Variant = snapshot.get("day")
		if not seeded_breach is Dictionary or seeded_breach.is_empty() or not seeded_day is Dictionary:
			return false
		var seeded_elapsed: Variant = seeded_day.get("elapsed_seconds")
		if typeof(seeded_elapsed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(seeded_elapsed)) or float(seeded_elapsed) < 0.0:
			return false
	if snapshot.has("breach"):
		if not day_data is Dictionary:
			return false
		if not breach_system.is_serialized_data_valid(breach_data, day_data.get("elapsed_seconds"), warning_at_for(_snapshot_wing_seed(snapshot), _snapshot_sublevel(snapshot))):
			return false
	if snapshot.has("oxygen") and not oxygen_system.is_serialized_data_valid(oxygen_data):
		return false
	if resident_data.is_empty() or resident_data.size() > max_crew_size(_snapshot_sublevel(snapshot), _snapshot_perk(snapshot)):
		return false
	var saved_cells: Variant = map_data.get("cells")
	if not saved_cells is Array or saved_cells.size() != MapGrid.WIDTH * MapGrid.HEIGHT:
		return false
	var living_residents := 0
	for entry: Variant in resident_data:
		if not entry is Dictionary or not entry.get("position") is Array or not ResidentNeeds.is_serialized_data_valid(entry.get("needs")):
			return false
		if not VaultResident.is_serialized_work_data_valid(entry):
			return false
		if not _is_serialized_manual_control_semantically_valid(entry, map_data, building_data, jobs_data, breach_data):
			return false
		if entry.position.size() < 2:
			return false
		if entry.has("recreating") and typeof(entry.recreating) != TYPE_BOOL:
			return false
		if entry.has("recreation_id") and not _is_integer_in_range(entry.recreation_id, -1, 2_147_483_647):
			return false
		if entry.has("recreation_sessions") and not _is_integer_in_range(entry.recreation_sessions, 0, 2_147_483_647):
			return false
		if bool(entry.get("recreating", false)):
			if not bool(entry.get("alive", true)) or int(entry.get("recreation_id", -1)) <= 0 or bool(entry.get("sleeping", false)):
				return false
		if bool(entry.get("alive", true)):
			living_residents += 1
	if snapshot.has(RECLAIM_KEY):
		var reclaim: Variant = snapshot[RECLAIM_KEY]
		if not reclaim is Dictionary or not _is_integer_in_range(reclaim.get("version"), RECLAIM_VERSION, RECLAIM_VERSION):
			return false
		if not _is_integer_in_range(reclaim.get("paid"), 0, RECLAIM_DELIVERIES):
			return false
		var elapsed: Variant = reclaim.get("elapsed")
		if typeof(elapsed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(elapsed)) or float(elapsed) < 0.0:
			return false
	if snapshot.has(IDLE_START_KEY):
		var idle_start: Variant = snapshot[IDLE_START_KEY]
		if not idle_start is Dictionary or not _is_integer_in_range(idle_start.get("version"), IDLE_START_VERSION, IDLE_START_VERSION_STEP3):
			return false
		# Version 1 carries stage 1 only; version 2 adds stage 2 (step 3 pending).
		var max_stage := 1 if int(idle_start.version) == IDLE_START_VERSION else 2
		if not _is_integer_in_range(idle_start.get("stage"), 1, max_stage):
			return false
	if snapshot.has(KEEP_RUNNING_KEY):
		var kr: Variant = snapshot[KEEP_RUNNING_KEY]
		if not kr is Dictionary or not _is_integer_in_range(kr.get("version"), KEEP_RUNNING_VERSION, KEEP_RUNNING_VERSION):
			return false
		var kr_seconds: Variant = kr.get("seconds")
		if typeof(kr_seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(kr_seconds)) or float(kr_seconds) < 0.0:
			return false
		# Only a won wing keeps running: Day 7 complete, and never a saved "win" panel at the same time.
		if not day_data is Dictionary or typeof(day_data.get("elapsed_seconds")) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if float(day_data.elapsed_seconds) < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE:
			return false
		if str(snapshot.get("outcome", "")) == "win":
			return false
	if snapshot.has(ANNEX_KEY):
		var annex: Variant = snapshot[ANNEX_KEY]
		if not snapshot.has(KEEP_RUNNING_KEY) or not annex is Dictionary:
			return false
		if not _is_integer_in_range(annex.get("version"), ANNEX_VERSION, ANNEX_VERSION):
			return false
		if not _is_integer_in_range(annex.get("meals"), 0, ANNEX_MEALS) or not _is_integer_in_range(annex.get("salvage"), 0, ANNEX_SALVAGE):
			return false
		if not _is_integer_in_range(annex.get("reserve"), ANNEX_RESERVE_MIN, ANNEX_RESERVE_MAX) or int(annex.reserve) % ANNEX_RESERVE_STEP != 0:
			return false
		if typeof(annex.get("done")) != TYPE_BOOL:
			return false
		if bool(annex.done) and (int(annex.meals) < ANNEX_MEALS or int(annex.salvage) < ANNEX_SALVAGE):
			return false
	if snapshot.has("wing_orders"):
		var orders: Variant = snapshot.wing_orders
		if not orders is Dictionary or not orders.get("claimed") is Array:
			return false
		var seen := {}
		for order_id: Variant in orders.claimed:
			if typeof(order_id) != TYPE_STRING or not order_id in WING_ORDER_IDS or seen.has(order_id):
				return false
			seen[order_id] = true
	var incoming_claims := _snapshot_order_claims(snapshot)
	for entry: Variant in building_data:
		if not entry is Dictionary or not entry.get("cell") is Array or entry.cell.size() < 2:
			return false
		if not _is_integer_in_range(entry.get("kind"), VaultBuilding.Kind.BED, VaultBuilding.Kind.MEDICAL_BED):
			return false
		if entry.has("manually_disabled") and typeof(entry.manually_disabled) != TYPE_BOOL:
			return false
		if entry.has("upgrade_tier"):
			if not _is_integer_in_range(entry.upgrade_tier, VaultBuilding.UPGRADE_TIER_BASE, VaultBuilding.UPGRADE_TIER_MAX):
				return false
			if int(entry.upgrade_tier) > VaultBuilding.UPGRADE_TIER_BASE and (
				not int(entry.kind) in VaultBuilding.UPGRADABLE_KINDS or entry.get("complete") != true or entry.get("is_emergency_core", false) == true
			):
				return false
			# A saved Charge Node / Air Recycler Mk II needs its order claimed in the same save.
			if int(entry.upgrade_tier) > VaultBuilding.UPGRADE_TIER_BASE:
				if int(entry.kind) == VaultBuilding.Kind.GENERATOR and not ORDER_FIT_GROW_MK2 in incoming_claims:
					return false
				if int(entry.kind) == VaultBuilding.Kind.AIR_RECYCLER and not ORDER_STOCK_MEALS in incoming_claims:
					return false
	if not job_system.is_serialized_breach_data_valid(jobs_data, breach_data, resident_data):
		return false

	var saved_ended := bool(snapshot.get("ended", false))
	var saved_outcome := str(snapshot.get("outcome", ""))
	if saved_ended != (saved_outcome in ["win", "loss"]):
		return false
	if saved_outcome == "death" and (living_residents <= 0 or not snapshot.has(DEATH_RECAP_KEY)):
		return false
	if snapshot.has(DEATH_RECAP_KEY):
		if saved_outcome not in ["death", "loss"]:
			return false
		var recap: Dictionary = snapshot[DEATH_RECAP_KEY]
		var named_dead_resident := false
		for entry: Dictionary in resident_data:
			if int(entry.get("id", -1)) == int(recap.resident_id) and not bool(entry.get("alive", true)) and str(entry.get("name", "")) == str(recap.name):
				named_dead_resident = true
				break
		if not named_dead_resident:
			return false
	if saved_outcome == "loss" and living_residents > 0:
		return false
	if saved_outcome == "win":
		if living_residents <= 0 or not day_data is Dictionary:
			return false
		var elapsed_value: Variant = day_data.get("elapsed_seconds")
		if typeof(elapsed_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(elapsed_value)):
			return false
		if float(elapsed_value) < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE:
			return false
		if snapshot.has("breach") and int(breach_data.phase) != BreachSystem.Phase.SEALED:
			return false
		var saved_oxygen := OxygenSystem.STARTING_OXYGEN
		if snapshot.has("oxygen"):
			saved_oxygen = float(oxygen_data.oxygen)
		if saved_oxygen < OxygenSystem.CRITICAL_OXYGEN_THRESHOLD:
			return false
	return true


# Loading is all-or-nothing: apply_snapshot frees and rebuilds the live wing, so
# every value it or a deserializer reads must have its JSON type checked here.
# Missing optional keys keep loader defaults; entries the loaders skip stay skipped,
# but tuple-list prefixes still need checking for the existing semantic lookups.
func _is_snapshot_schema_valid(snapshot: Dictionary) -> bool:
	var map_data: Variant = snapshot.get("map")
	var building_data: Variant = snapshot.get("buildings")
	var resident_data: Variant = snapshot.get("residents")
	if not map_data is Dictionary or not building_data is Array or not resident_data is Array:
		return false
	for key: String in ["food", "oxygen", "day", "breach", "jobs"]:
		if snapshot.has(key) and not snapshot[key] is Dictionary:
			return false
	if not _snapshot_fields_valid(snapshot, {"next_building_id": _SNAPSHOT_INT, "ended": _SNAPSHOT_BOOL, "outcome": _SNAPSHOT_STRING}):
		return false
	if snapshot.has(DEATH_RECAP_KEY):
		var recap: Variant = snapshot[DEATH_RECAP_KEY]
		if not recap is Dictionary or not _is_integer_in_range(recap.get("version"), DEATH_RECAP_VERSION, DEATH_RECAP_VERSION):
			return false
		if not _is_integer_in_range(recap.get("resident_id"), 1, 2_147_483_647):
			return false
		for key: String in ["name", "cause", "time", "tip"]:
			if not recap.has(key) or typeof(recap[key]) != TYPE_STRING:
				return false
		# Additive in v1: older death recaps have no simulated timestamp.
		if not _snapshot_fields_valid(recap, {"elapsed_seconds": _SNAPSHOT_NUMBER}):
			return false
	if snapshot.has("camera"):
		if not snapshot.camera is Array:
			return false
		if snapshot.camera.size() >= 3 and not _snapshot_entries_valid([snapshot.camera], [_SNAPSHOT_NUMBER, _SNAPSHOT_NUMBER, _SNAPSHOT_NUMBER]):
			return false
	if not _snapshot_fields_valid(snapshot.get("food", {}), {"meals": _SNAPSHOT_INT, "raw_food": _SNAPSHOT_INT, "salvage": _SNAPSHOT_INT}):
		return false
	if not _snapshot_fields_valid(snapshot.get("day", {}), {"elapsed_seconds": _SNAPSHOT_NUMBER, "current_day": _SNAPSHOT_INT, "completed": _SNAPSHOT_BOOL}):
		return false
	var saved_cells: Variant = map_data.get("cells")
	if not saved_cells is Array:
		return false
	for value: Variant in saved_cells:
		if not _is_integer_in_range(value, 0, MapGrid.Tile.size() - 1):
			return false
	if not _snapshot_entries_valid(map_data.get("dig_marks", []), [_SNAPSHOT_INT, _SNAPSHOT_INT, _SNAPSHOT_NUMBER]):
		return false
	var jobs_data: Dictionary = snapshot.get("jobs", {})
	for key: String in ["rubble", "raw_food", "meals", "supplies", "breach_supply", "breach_patch"]:
		if jobs_data.has(key) and not jobs_data[key] is Array:
			return false
	if not _snapshot_entries_valid(jobs_data.get("rubble", []), [_SNAPSHOT_INT, _SNAPSHOT_INT, _SNAPSHOT_INT]):
		return false
	if not _snapshot_entries_valid(jobs_data.get("supplies", []), [_SNAPSHOT_INT, _SNAPSHOT_INT, _SNAPSHOT_INT, _SNAPSHOT_INT, _SNAPSHOT_INT]):
		return false
	for entry: Variant in building_data:
		if not entry is Dictionary or not _snapshot_entries_valid([entry.get("cell")], [_SNAPSHOT_INT, _SNAPSHOT_INT], true):
			return false
		if not _snapshot_fields_valid(entry, _SNAPSHOT_BUILDING_FIELDS):
			return false
	for entry: Variant in resident_data:
		if not entry is Dictionary or not _snapshot_entries_valid([entry.get("position")], [_SNAPSHOT_NUMBER, _SNAPSHOT_NUMBER], true):
			return false
		if not _snapshot_fields_valid(entry, _SNAPSHOT_RESIDENT_FIELDS):
			return false
	return true


func _snapshot_fields_valid(data: Dictionary, fields: Dictionary) -> bool:
	for key: String in fields:
		if data.has(key) and not _snapshot_value_valid(data[key], int(fields[key])):
			return false
	return true


# Each Array entry's leading values must match kinds as far as the entry reaches:
# loaders skip short entries, but semantic lookups still read their prefixes.
# Non-Array entries stay skipped. With required, every entry must be a full Array.
func _snapshot_entries_valid(entries: Variant, kinds: Array, required := false) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if not entry is Array or (required and entry.size() < kinds.size()):
			if required:
				return false
			continue
		for index in mini(entry.size(), kinds.size()):
			if not _snapshot_value_valid(entry[index], int(kinds[index])):
				return false
	return true


func _snapshot_value_valid(value: Variant, kind: int) -> bool:
	match kind:
		_SNAPSHOT_INT:
			return _is_integer_in_range(value, -2_147_483_648, 2_147_483_647)
		_SNAPSHOT_NUMBER:
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
		_SNAPSHOT_BOOL:
			return typeof(value) == TYPE_BOOL
		_SNAPSHOT_STRING:
			return typeof(value) == TYPE_STRING
	return false


func _is_serialized_manual_control_semantically_valid(
	resident_data: Dictionary,
	map_data: Dictionary,
	building_data: Array,
	jobs_data: Dictionary,
	breach_data: Variant,
) -> bool:
	var saved_cells: Array = map_data.get("cells", [])
	var destination: Array = resident_data.get("manual_destination", [])
	if destination.size() == 2:
		var destination_cell := Vector2i(int(destination[0]), int(destination[1]))
		if int(saved_cells[destination_cell.y * MapGrid.WIDTH + destination_cell.x]) != MapGrid.Tile.FLOOR:
			return false
	var order: Dictionary = resident_data.get("forced_order", {})
	if order.is_empty():
		return true
	var type := int(order.type)
	var target_data: Array = order.target
	var target := Vector2i(int(target_data[0]), int(target_data[1]))
	var building_id := int(order.building_id)
	match type:
		JobSystem.JobType.DIG:
			return building_id == -1 and _serialized_cell_entry_exists(map_data.get("dig_marks", []), target, 0, 1)
		JobSystem.JobType.HAUL_RUBBLE:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("rubble", []), target, 0, 1)
		JobSystem.JobType.HAUL_RAW_FOOD:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("raw_food", []), target, 0, 1)
		JobSystem.JobType.HAUL_MEAL:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("meals", []), target, 0, 1)
		JobSystem.JobType.SUPPLY_BUILD:
			return building_id > 0 and _serialized_supply_entry_exists(jobs_data.get("supplies", []), building_id, target)
		JobSystem.JobType.BUILD:
			var blueprint := _serialized_building_by_id(building_data, building_id)
			if blueprint.is_empty() or bool(blueprint.get("complete", false)) or blueprint.get("cell", []) != target_data:
				return false
			var kind := int(blueprint.get("kind", -1))
			return int(blueprint.get("delivered", 0)) >= int(VaultBuilding.COSTS.get(kind, 2_147_483_647))
		JobSystem.JobType.COOK:
			var kitchen := _serialized_building_by_id(building_data, building_id)
			return (
				not kitchen.is_empty()
				and bool(kitchen.get("complete", false))
				and int(kitchen.get("kind", -1)) == VaultBuilding.Kind.KITCHEN
				and kitchen.get("cell", []) == target_data
			)
		JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH:
			if building_id != -1 or target != BreachSystem.HATCH_CELL or not breach_data is Dictionary:
				return false
			var phase := int(breach_data.get("phase", BreachSystem.Phase.DORMANT))
			var delivered := int(breach_data.get("patch_delivered", 0))
			if phase not in [BreachSystem.Phase.WARNING, BreachSystem.Phase.OPEN]:
				return false
			if type == JobSystem.JobType.SUPPLY_BREACH:
				return delivered < BreachSystem.PATCH_COST and not (jobs_data.get("breach_supply", []) as Array).is_empty()
			return delivered >= BreachSystem.PATCH_COST and not (jobs_data.get("breach_patch", []) as Array).is_empty()
	return false


func _serialized_cell_entry_exists(entries: Variant, target: Vector2i, x_index: int, y_index: int) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if entry is Array and entry.size() > maxi(x_index, y_index):
			if int(entry[x_index]) == target.x and int(entry[y_index]) == target.y:
				return true
	return false


func _serialized_supply_entry_exists(entries: Variant, building_id: int, target: Vector2i) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if (
			entry is Array
			and entry.size() >= 3
			and int(entry[0]) == building_id
			and int(entry[1]) == target.x
			and int(entry[2]) == target.y
		):
			return true
	return false


func _serialized_building_by_id(building_data: Array, building_id: int) -> Dictionary:
	for entry: Variant in building_data:
		if entry is Dictionary and int(entry.get("id", -1)) == building_id:
			return entry
	return {}


# Ladder 04 DARK START: the starter Lumen begins as a blueprint the crew supply and build.
func _spawn_starting_blueprint(kind: int, cell: Vector2i, supplied := false) -> void:
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell)
	if supplied:
		building.delivered = building.get_cost()
	next_building_id += 1
	buildings.append(building)
	job_system.queue_building(building)


func _spawn_starting_fixture(kind: int, cell: Vector2i, core: bool) -> void:
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell, true)
	building.is_emergency_core = core
	building.queue_redraw()
	next_building_id += 1
	buildings.append(building)


func _select_at(cell: Vector2i) -> bool:
	if cell == BreachSystem.HATCH_CELL:
		# Version-one saves could legally contain a fixture here. Preserve and
		# keep that fixture selectable; the dedicated focus control still opens
		# the breach inspector.
		var legacy_hatch_building := get_building_at(cell)
		if legacy_hatch_building != null:
			select_building(legacy_hatch_building.building_id)
			return true
	if cell == BreachSystem.HATCH_CELL and breach_system.phase != BreachSystem.Phase.DORMANT:
		selected_resident_id = -1
		selected_building_id = -1
		selected_breach = true
		for resident in residents:
			resident.selected = false
			resident.queue_redraw()
		breach_system.queue_redraw()
		return true
	var building := get_building_at(cell)
	var residents_at_cell: Array[VaultResident] = []
	for resident: VaultResident in residents:
		# The drawn hex, not sim occupancy (which stays put until a step arrives).
		if resident.alive and map_grid.world_to_cell(resident.position) == cell:
			residents_at_cell.append(resident)
	if not residents_at_cell.is_empty():
		for index in residents_at_cell.size():
			if residents_at_cell[index].resident_id != selected_resident_id:
				continue
			if index + 1 < residents_at_cell.size():
				select_resident(residents_at_cell[index + 1].resident_id)
			elif building != null:
				select_building(building.building_id)
			else:
				select_resident(residents_at_cell[0].resident_id)
			return true
		select_resident(residents_at_cell[0].resident_id)
		return true
	if building != null:
		select_building(building.building_id)
		return true
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()
	return false


func _issue_drafted_move(resident: VaultResident, cell: Vector2i) -> bool:
	if not map_grid.is_walkable(cell):
		status_message = "%s cannot move there; choose carved floor." % resident.resident_name
		status_message_left = 3.0
		return false
	if map_grid.find_path(resident.get_cell(map_grid), cell).is_empty():
		status_message = "%s cannot reach that floor cell." % resident.resident_name
		status_message_left = 3.0
		return false
	job_system.release_resident(resident)
	resident.drafted = true
	resident.set_manual_move_order(cell)
	status_message = "%s manual move set to %d,%d." % [resident.resident_name, cell.x, cell.y]
	status_message_left = 4.0
	return true


func _input(event: InputEvent) -> void:
	if outcome == "death" and (
		event.is_action_pressed("pause_game")
		or event.is_action_pressed("cancel_order")
		or event.is_action_pressed("work_priorities")
	):
		get_viewport().set_input_as_handled()
		return
	if player_orders != null and player_orders.is_briefing_open():
		if player_orders.is_help_open() and event.is_action_pressed("cancel_order"):
			player_orders.show_briefing(false)
		if event.is_action_pressed("cancel_order") or event.is_action_pressed("pause_game"):
			get_viewport().set_input_as_handled()
			return
	# Space is both the global pause shortcut and Godot's default button accept
	# key. Handle it before GUI focus while this modal is open so it cannot
	# silently change the focused work-priority cell.
	if (
		player_orders != null
		and player_orders.is_work_priorities_open()
		and event.is_action_pressed("pause_game")
	):
		toggle_pause()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if outcome == "death":
		get_viewport().set_input_as_handled()
		return
	if player_orders.is_briefing_open():
		if player_orders.is_help_open() and event.is_action_pressed("cancel_order"):
			player_orders.show_briefing(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("work_priorities"):
		player_orders.toggle_work_priorities()
		get_viewport().set_input_as_handled()
		return
	if player_orders.is_work_priorities_open():
		if event.is_action_pressed("cancel_order"):
			player_orders.show_work_priorities(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("lighting_overlay"):
		var repeated_key: bool = event is InputEventKey and (event as InputEventKey).echo
		var warning_blocked: bool = (
			breach_system.phase == BreachSystem.Phase.WARNING
			and not breach_system.warning_acknowledged
		)
		if not repeated_key and not tutorial_open and not ended and not warning_blocked:
			toggle_lighting_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel_order"):
		set_tool("select")
		return
	if event.is_action_pressed("tool_dig"):
		set_tool("dig")
		return
	if event.is_action_pressed("draft_selected"):
		var repeated_draft_key: bool = event is InputEventKey and (event as InputEventKey).echo
		if not repeated_draft_key:
			toggle_resident_draft(selected_resident_id)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_speed(1)
			KEY_2: set_speed(2)
			KEY_3: set_speed(3)
			KEY_X: set_tool("cancel")
			KEY_HOME, KEY_F: recenter_camera()
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_camera = mouse_event.pressed
			return
		if mouse_event.position.x >= get_viewport_rect().size.x - RIGHT_PANEL_WIDTH:
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			world_camera.zoom = Vector2.ONE * minf(1.8, world_camera.zoom.x + 0.12)
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			world_camera.zoom = Vector2.ONE * maxf(0.75, world_camera.zoom.x - 0.12)
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var selected_resident := get_resident_by_id(selected_resident_id)
			if selected_resident != null and selected_resident.alive:
				issue_selected_resident_context_order(_pick_cell_from_screen())
				return
			set_tool("select")
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			issue_order_at_screen(get_viewport().get_mouse_position())
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_camera:
			world_camera.position -= motion.relative / world_camera.zoom.x
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and active_tool in ["dig", "cancel", "zone"]:
			if motion.position.x < get_viewport_rect().size.x - RIGHT_PANEL_WIDTH:
				issue_order(_pick_cell_from_screen())
		map_grid.hover_cell = _pick_cell_from_screen()
		map_grid.queue_redraw()


func recenter_camera() -> void:
	var selected := get_resident_by_id(selected_resident_id)
	if selected != null:
		world_camera.position = selected.position
	elif selected_breach:
		world_camera.position = map_grid.cell_to_world(BreachSystem.HATCH_CELL)
	else:
		world_camera.position = map_grid.cell_to_world(map_grid.get_chamber_center())


func focus_breach() -> void:
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = true
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()
	breach_system.queue_redraw()
	world_camera.position = map_grid.cell_to_world(BreachSystem.HATCH_CELL)


func acknowledge_breach_warning(resume_response: bool) -> void:
	breach_system.warning_acknowledged = true
	player_orders.show_breach_warning(false)
	focus_breach()
	if resume_response and not tutorial_open and not ended:
		user_paused = false


func _update_camera(delta: float) -> void:
	if outcome == "death" or (player_orders != null and (
		player_orders.is_work_priorities_open() or player_orders.is_briefing_open()
	)):
		_dragging_camera = false
		return
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	world_camera.position += direction * 360.0 * delta / world_camera.zoom.x
	world_camera.position.x = clampf(world_camera.position.x, 300.0, MapGrid.WIDTH * MapGrid.TILE_SIZE - 260.0)
	world_camera.position.y = clampf(world_camera.position.y, 220.0, MapGrid.HEIGHT * MapGrid.TILE_SIZE - 180.0)



func _enable_3d_play_view() -> void:
	# Keep Camera2D as focus/zoom state for saves + tests; 3D camera is the live view.
	world_camera.enabled = false
	map_grid.visible = false
	building_root.visible = false
	resident_root.visible = false
	breach_system.visible = false
	lighting_system.visible = false
	map_view_3d.setup(map_grid, lighting_system)


func _sync_3d_play_view(force_rebuild := false) -> void:
	if map_view_3d == null:
		return
	map_view_3d.rebuild_map(force_rebuild)
	map_view_3d.apply_camera_focus(world_camera.position, world_camera.zoom.x)
	map_view_3d.sync_actors(residents, buildings, true, job_system.jobs, breach_system.phase, breach_system.patch_work_left)
	map_view_3d.sync_air_haze(oxygen_system.oxygen)


## Left click: the select tool first takes a drawn resident capsule in front of
## the terrain; every other tool, and a select click that misses, uses the
## terrain-aware hex. Simulation occupancy is never read or changed here.
func issue_order_at_screen(screen_pos: Vector2) -> bool:
	if active_tool == "select" and not (ended or tutorial_open or player_orders.is_help_open()):
		var hit := get_resident_by_id(map_view_3d.pick_resident_id(screen_pos, residents))
		if hit != null:
			var current := get_resident_by_id(selected_resident_id)
			var current_under_cursor := false
			if current != null and current.alive and map_grid.world_to_cell(current.position) == map_grid.world_to_cell(hit.position):
				var only_current: Array[VaultResident] = [current]
				current_under_cursor = current == hit or map_view_3d.pick_resident_id(screen_pos, only_current) == current.resident_id
			if hit.alive and not current_under_cursor:
				select_resident(hit.resident_id)
				return true
			# Re-clicking the selected resident (or clicking a body) resolves on
			# the drawn hex, keeping the cycle through co-located residents and
			# the fixture there.
			return _select_at(map_grid.world_to_cell(hit.position))
	return issue_order(map_view_3d.pick_cell(screen_pos))


func _pick_cell_from_screen() -> Vector2i:
	return map_view_3d.pick_cell(get_viewport().get_mouse_position())

func _on_rubble_created(cell: Vector2i, amount: int) -> void:
	job_system.queue_rubble(cell, amount)


func _on_map_topology_changed(_cell: Vector2i) -> void:
	refresh_lighting()
	_sync_3d_play_view(true)


func _on_raw_food_produced(cell: Vector2i, amount: int) -> void:
	job_system.queue_raw_food(cell, amount)


func _on_dig_orders_removed(cells: Array[Vector2i]) -> void:
	for cell in cells:
		job_system.cancel_dig(cell)


func _has_cancelable_blueprint_at(cell: Vector2i) -> bool:
	var building := get_building_at(cell)
	return building != null and not building.complete


func _remove_building(building: VaultBuilding, salvage_refund: int, message: String) -> bool:
	if building == null:
		return false
	food_system.add_salvage(maxi(0, salvage_refund))
	job_system.cancel_building(building.building_id)
	for resident: VaultResident in residents:
		if resident.medical_bed_id == building.building_id:
			job_system.release_resident(resident)
		if resident.bed_id == building.building_id:
			resident.bed_id = -1
			resident.sleeping = false
		if resident.recreation_id == building.building_id:
			job_system.release_resident(resident)
		if resident.current_job_id >= 0:
			var target_job := job_system._find_job(resident.current_job_id)
			if not target_job.is_empty() and int(target_job.get("building_id", -1)) == building.building_id:
				job_system.release_resident(resident)
	if selected_building_id == building.building_id:
		selected_building_id = -1
	buildings.erase(building)
	building.free()
	power_grid.recalculate(buildings)
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	status_message = message
	status_message_left = 3.0
	return true


func _is_stockpile_floor(cell: Vector2i) -> bool:
	return get_building_at(cell) == null


func _is_reserved_cell(cell: Vector2i) -> bool:
	return cell == BreachSystem.HATCH_CELL


func _on_resident_died(resident: VaultResident) -> void:
	if ended:
		return
	job_system.release_resident(resident)
	death_recap = player_orders.death_recap_for(resident)
	death_recap["version"] = DEATH_RECAP_VERSION
	status_message = "%s has died. Review the death recap." % resident.resident_name
	status_message_left = 8.0
	if get_alive_count() <= 0:
		_finish_loss()
	else:
		_finish_death()


func _finish_death() -> void:
	if ended:
		return
	# This recap is a recoverable interruption, not a finished or won wing.
	ended = false
	outcome = "death"
	user_paused = true
	status_message = "%s has died. Review the death recap." % str(death_recap.get("name", "A resident"))
	status_message_left = 8.0
	player_orders.show_outcome(false, get_alive_count())


# Possibility, not a forecast: victory needs day 7 complete, a sealed breach and
# breathable oxygen. Optional wing orders never gate it. With no living crew it
# is impossible; endless keep-running crew can always continue. Otherwise only
# a proven food wipe before day 7 rules victory out. Air, work, power and hatch
# forecasts can change with player fixes / fewer mouths, so uncertainty is true.
func can_still_win_shift() -> bool:
	if get_alive_count() <= 0:
		return false
	if keep_running:
		return true
	var seconds_left := maxf(0.0, DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - day_cycle.elapsed_seconds)
	return not player_orders._food_wipe_before(seconds_left)


func resume_after_death() -> bool:
	# Enforce the same decision for callers that bypass the recap button.
	if outcome != "death" or not can_still_win_shift():
		return false
	outcome = ""
	ended = false
	death_recap = {}
	user_paused = false
	player_orders.hide_outcome()
	status_message = "Shift resumed. Protect the surviving residents."
	status_message_left = 5.0
	return true


func _save_day_checkpoint() -> bool:
	return bool(save_load.save_snapshot(create_snapshot(), checkpoint_path).ok)


# Read-only: inspect the same snapshot Retry will apply, including backup recovery.
func day_checkpoint_retry_status() -> Dictionary:
	var result := save_load.load_snapshot(checkpoint_path)
	result["reason"] = "No day checkpoint available"
	if not bool(result.ok):
		return result
	var snapshot: Dictionary = result.snapshot
	result.ok = false
	if not _is_snapshot_shape_valid(snapshot):
		return result
	if _snapshot_wing_seed(snapshot) != wing_seed:
		result.reason = "No checkpoint for this wing"
		return result
	if _snapshot_sublevel(snapshot) != sublevel:
		result.reason = "No checkpoint for this wing"
		return result
	if snapshot.has(KEEP_RUNNING_KEY) != keep_running:
		result.reason = "Checkpoint is from another time"
		return result
	var checkpoint_elapsed := float(snapshot[KEEP_RUNNING_KEY].seconds) if keep_running else float(snapshot.get("day", {}).get("elapsed_seconds", 0.0))
	var current_elapsed := keep_running_seconds if keep_running else day_cycle.elapsed_seconds
	if checkpoint_elapsed > current_elapsed:
		result.reason = "Checkpoint is from a later time"
		return result
	result.ok = true
	result.reason = ""
	return result


func can_retry_day_checkpoint() -> bool:
	return bool(day_checkpoint_retry_status().ok)


func retry_day_checkpoint() -> bool:
	var result := day_checkpoint_retry_status()
	# Callers can bypass the disabled recap button. Refuse before changing any state.
	if not bool(result.ok):
		return false
	if not apply_snapshot(result.snapshot):
		status_message = "Could not restore the day checkpoint."
		status_message_left = 5.0
		return false
	# Pause is not serialized: all serialized fields remain exactly as checkpointed.
	tutorial_open = false
	user_paused = true
	outcome = ""
	ended = false
	death_recap = {}
	player_orders.show_briefing(false)
	player_orders.show_work_priorities(false)
	player_orders.hide_outcome()
	status_message = "Day checkpoint restored. Resume when ready."
	status_message_left = 5.0
	return true


# Pick only initial rock, independent of the current excavation state and RNG stream.
static func supply_cache_position_for(seed_value: int) -> Vector2i:
	var pockets: Array = MapGrid.generate_layout(seed_value)["pockets"]
	var candidates: Array[Vector2i] = []
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.end.y)
		if cell not in pockets:
			candidates.append(cell)
	# Seeded pockets are small; retain a deterministic perimeter fallback.
	if candidates.is_empty():
		for y in range(MapGrid.CHAMBER.position.y + 2, MapGrid.CHAMBER.end.y):
			var cell := Vector2i(MapGrid.CHAMBER.position.x - 1, y)
			if cell not in pockets:
				candidates.append(cell)
	return candidates[BreachSystem.seed_hash(seed_value, 404) % candidates.size()]


func _reset_supply_cache(enabled: bool, seed_value: int) -> void:
	supply_cache_enabled = enabled
	supply_cache_announced = false
	supply_cache_claimed = false
	map_grid.supply_cache_cell = supply_cache_position_for(seed_value) if enabled else Vector2i(-1, -1)
	map_grid.supply_cache_open = false
	map_grid.supply_cache_visible = false


func _reveal_supply_cache() -> void:
	if not supply_cache_enabled or supply_cache_announced or day_cycle.elapsed_seconds < SUPPLY_CACHE_AT:
		return
	# Latch before checkpoints. Canceled designations are never silently re-created.
	supply_cache_announced = true
	map_grid.supply_cache_open = true
	map_grid.supply_cache_visible = not supply_cache_claimed
	if map_grid.queue_dig(map_grid.supply_cache_cell):
		job_system.queue_dig(map_grid.supply_cache_cell)
	map_grid.queue_redraw()


func supply_cache_alert() -> String:
	if not supply_cache_enabled or not supply_cache_announced or supply_cache_claimed or keep_running:
		return ""
	# Excavation removes the dig mark; keep the same notice until Haul claims it.
	if not map_grid.dig_marks.has(map_grid.supply_cache_cell) and not map_grid.is_walkable(map_grid.supply_cache_cell):
		return ""
	return "DAY-4 CACHE (%d,%d): %d salvage + %d %s · Dig/Haul queued; CANCEL to skip" % [
		map_grid.supply_cache_cell.x, map_grid.supply_cache_cell.y,
		SUPPLY_CACHE_SALVAGE, SUPPLY_CACHE_MEALS, "meal" if SUPPLY_CACHE_MEALS == 1 else "meals"]


func claim_supply_cache(resident: VaultResident) -> bool:
	if not supply_cache_enabled or supply_cache_claimed or not supply_cache_announced or day_cycle.elapsed_seconds < SUPPLY_CACHE_AT:
		return false
	if resident == null or not resident.alive or resident.get_cell(map_grid) != map_grid.supply_cache_cell:
		return false
	if not map_grid.is_walkable(map_grid.supply_cache_cell) or resident.current_job_type != JobSystem.JobType.HAUL_RUBBLE:
		return false
	var job := job_system._find_job(resident.current_job_id)
	if job.is_empty() or job.target != map_grid.supply_cache_cell:
		return false
	# Latch before emitting inventory signals; reaching the cache pays exactly once.
	supply_cache_claimed = true
	map_grid.supply_cache_visible = false
	food_system.add_salvage(SUPPLY_CACHE_SALVAGE)
	food_system.add_meals(SUPPLY_CACHE_MEALS)
	map_grid.queue_redraw()
	return true


func _is_supply_cache_snapshot_valid(snapshot: Dictionary) -> bool:
	if not snapshot.has(SUPPLY_CACHE_KEY):
		return true
	var data: Variant = snapshot[SUPPLY_CACHE_KEY]
	if not data is Dictionary or not _is_integer_in_range(data.get("version"), 1, 1):
		return false
	if typeof(data.get("announced")) != TYPE_BOOL or typeof(data.get("claimed")) != TYPE_BOOL:
		return false
	var position: Variant = data.get("position")
	if not position is Array or position.size() != 2:
		return false
	if not _is_integer_in_range(position[0], 1, MapGrid.WIDTH - 2) or not _is_integer_in_range(position[1], 1, MapGrid.HEIGHT - 2):
		return false
	# Position is saved authority, including when an older wing's seed/layout is
	# migrated. Require the same chamber perimeter used by placement.
	var cell := Vector2i(int(position[0]), int(position[1]))
	var south_edge := cell.y == MapGrid.CHAMBER.end.y and cell.x >= MapGrid.CHAMBER.position.x and cell.x < MapGrid.CHAMBER.end.x
	var west_edge := cell.x == MapGrid.CHAMBER.position.x - 1 and cell.y >= MapGrid.CHAMBER.position.y + 2 and cell.y < MapGrid.CHAMBER.end.y
	if not south_edge and not west_edge:
		return false
	var elapsed := float(snapshot.get("day", {}).get("elapsed_seconds", 0.0))
	if data.announced != (elapsed >= SUPPLY_CACHE_AT) or (data.claimed and not data.announced):
		return false
	var tile := int(snapshot.map.cells[cell.y * MapGrid.WIDTH + cell.x])
	if data.claimed and tile != MapGrid.Tile.FLOOR:
		return false
	if not data.announced:
		if tile != MapGrid.Tile.ROCK:
			return false
		for mark: Variant in snapshot.map.get("dig_marks", []):
			if mark is Array and mark.size() >= 2 and mark[0] == cell.x and mark[1] == cell.y:
				return false
	return true


func _on_day_started(_day: int) -> void:
	if not ended and outcome != "death":
		_reveal_supply_cache()
		_save_day_checkpoint()
		save_game(false)
		if breach_system.is_response_active() or (breach_system.is_sealed() and status_message_left > 0.0):
			return
		status_message = "Cycle checkpoint saved locally."
		status_message_left = 3.0


func _on_power_brownout_started(new_shed_count: int, new_shed_demand: int) -> void:
	var fixture_word := "fixture" if new_shed_count == 1 else "fixtures"
	status_message = "POWER BROWNOUT: shedding %d power across %d %s. Disable or deconstruct optional load, or add capacity." % [
		new_shed_demand,
		new_shed_count,
		fixture_word,
	]
	status_message_left = 8.0


func _on_power_brownout_cleared() -> void:
	status_message = "POWER STABLE: all completed fixtures are served."
	status_message_left = 5.0


func _on_power_allocation_changed() -> void:
	refresh_lighting()


func _on_breach_warning_started() -> void:
	job_system.start_breach_response()
	simulation_speed = 1
	user_paused = true
	active_tool = "select"
	map_grid.preview_tool = active_tool
	focus_breach()
	player_orders.show_breach_warning(true)
	status_message = "PRESSURE WARNING: patch the hatch before it starts venting vault oxygen."
	status_message_left = BreachSystem.GRACE_SECONDS


func _on_breach_opened() -> void:
	player_orders.show_breach_warning(false)
	status_message = "BREACH OPEN: vault oxygen is venting until the hatch is patched."
	status_message_left = 12.0


func _on_breach_sealed() -> void:
	player_orders.show_breach_warning(false)
	status_message = "FIRST BREACH CONTAINED: oxygen loss stopped; verify life support recovery."
	status_message_left = 8.0


func _finish_win() -> void:
	if ended or keep_running or outcome == "death":
		return
	ended = true
	outcome = "win"
	user_paused = true
	_record_finish(true)
	save_game(false)
	player_orders.show_outcome(true, get_alive_count())
	game_won.emit(get_alive_count())


func _finish_loss() -> void:
	if ended:
		return
	ended = true
	outcome = "loss"
	user_paused = true
	_record_finish(false)
	player_orders.show_outcome(false, 0)
	if keep_running:
		player_orders.note_keep_running_loss()
	game_lost.emit()


# Records + ladder C3: a finished seeded run merges into its wing record once, here at the
# transition (show_outcome also runs on LOAD, so it never writes). A win carries the crew grade,
# a loss the day reached. A failed or refused write never blocks the outcome.
func _record_finish(won: bool) -> void:
	finish_record = {}
	finish_best = {}
	if not records_enabled():
		return
	var store := wing_records()
	var level := sublevel
	var previous := store.get_record(wing_seed, level)
	var stars: Variant = int(player_orders.crew_grade()["stars"]) if won else null
	var day := clampi(keep_running_day() if keep_running else day_cycle.current_day, 1, WingRecords.MAX_DAY)
	if best_enabled():
		var survivors: Array[String] = []
		for resident: VaultResident in residents:
			if resident.alive:
				survivors.append(resident.resident_name)
		# The normal clock freezes at the seal win; endless days continue from day 8.
		var elapsed := DayCycle.DAYS_TO_SURVIVE * DayCycle.SECONDS_PER_DAY + keep_running_seconds if keep_running else day_cycle.elapsed_seconds
		finish_best = wing_best().submit(wing_seed, level, WingBest.run_from(outcome, day, elapsed, survivors))
	var unlocked_before := store.unlocked_sublevel()
	if store.record(wing_seed, won, stars, day, level):
		finish_record = {"previous": previous, "current": store.get_record(wing_seed, level)}
		var unlocked_now := store.unlocked_sublevel()
		# Only the next sublevel down counts as this win's unlock (03 is the floor).
		if unlocked_now < unlocked_before and unlocked_now == level - 1:
			finish_record["unlocked"] = unlocked_now


func _tool_help(tool: String) -> String:
	match tool:
		"select": return "SELECT: inspect a resident or fixture; use HELP to reopen the checklist."
		"zone": return "STOCKPILE: paint drop-offs for salvage, raw food, and meals. CANCEL [X] clears cells; Esc exits. No cost."
		"dig": return "DIG: click or drag connected rock; hauled rubble yields 3 salvage per tile."
		"cancel": return "CANCEL: clear stockpile cells, dig orders, or unfinished blueprints."
		"medical": return "MEDICAL BED: 8 salvage, 8s assembly, no power. Residents at 95 HP or below claim care automatically (+2 HP/s); hatch repair first. Disable to deny care."
		"bed": return "BUNK: residents sleep here automatically (8 salvage)."
		"lamp": return "LUMEN: lights floor within %d tiles while powered; prevents the 30 mood/day darkness penalty (5 salvage, 1 power)." % LightingSystem.LUMEN_RADIUS
		"generator": return "CHARGE NODE: adds 7 power for food and life support (18 salvage)."
		"grow": return "GROW TRAY: produces raw food for Haul delivery when powered (12 salvage, 3 power)."
		"kitchen": return "NUTRIENT STATION: Cook turns %d stored raw into %d meal for Haul delivery (10 salvage, 2 power)." % [FoodSystem.COOK_INPUT, FoodSystem.COOK_OUTPUT]
		"stockpile": return "SALVAGE BAY: fallback destination for salvage and food hauling (4 salvage)."
		"air": return "AIR RECYCLER: restores vault oxygen; build a Charge Node to supply its 3 power (14 salvage)."
		"rec": return "REC CONSOLE: optional one-seat mood recovery; it sheds first in a brownout (8 salvage, 1 power)."
	return ""


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum


# Keep running: offered only on the win panel. The win stays recorded (KEEP_RUNNING_KEY); the wing
# goes live again on the same vault with the Day 7 clock frozen and a separate keep-running clock.
func can_keep_running() -> bool:
	return ended and outcome == "win" and not keep_running


func start_keep_running() -> bool:
	if not can_keep_running():
		return false
	keep_running = true
	keep_running_seconds = 0.0
	ended = false
	outcome = ""
	user_paused = false
	player_orders.hide_outcome()
	status_message = "Keep running: the seal win is recorded. The vault carries on."
	status_message_left = 5.0
	_save_day_checkpoint()
	save_game(false)
	return true


func keep_running_day() -> int:
	return DayCycle.DAYS_TO_SURVIVE + 1 + floori(keep_running_seconds / DayCycle.SECONDS_PER_DAY)


func _advance_keep_running(delta_seconds: float) -> void:
	_apply_recreation_seek()
	var day_before := keep_running_day()
	keep_running_seconds += delta_seconds
	_advance_annex(delta_seconds)
	annex_welcome_left = maxf(0.0, annex_welcome_left - delta_seconds)
	if keep_running_day() != day_before:
		_maybe_feast()
		_record_progress()
		_save_day_checkpoint()
		save_game(false)


# Keep running owns the seek threshold: 45 while the won vault runs on, the pre-win 35 otherwise.
func _apply_recreation_seek() -> void:
	var seek := ResidentNeeds.KEEP_RUNNING_RECREATION_SEEK if keep_running else ResidentNeeds.RECREATION_SEEK_THRESHOLD
	for resident in residents:
		if is_instance_valid(resident):
			resident.needs.recreation_seek = seek


func _reset_keep_running() -> void:
	keep_running = false
	keep_running_seconds = 0.0
	annex_meals = 0
	annex_salvage = 0
	annex_reserve = ANNEX_RESERVE_DEFAULT
	annex_done = false
	annex_welcome_left = 0.0
	_annex_tick_left = ANNEX_TICK
	_annex_trickle_left = ANNEX_TRICKLE_INTERVAL
	_annex_room_noted = 0
	_apply_recreation_seek()


# Annex: every ANNEX_TICK one meal (only above the reserve, and never while someone is hungry) and
# one salvage go in until each quota is met. Salvage competes with the Mk II fits; a slow upkeep
# trickle (+1 per ANNEX_TRICKLE_INTERVAL) keeps an idle vault from dead-ending on salvage.
# Comfort (north star slice 4): after KEEP RUNNING one tap queues what a won vault needs to stay
# well: a Rec Console and a Med Bed, a Charge Node when planned power cannot carry them, and a Lumen
# by any dark bunk. Derived from the world, no save key: it is offered while the vault keeps
# running without a Rec Console or Med Bed (built or queued).
const COMFORT_KINDS := [VaultBuilding.Kind.RECREATION_CONSOLE, VaultBuilding.Kind.MEDICAL_BED]


func comfort_pending() -> bool:
	if not keep_running or ended:
		return false
	for kind: int in COMFORT_KINDS:
		if _count_buildings(kind) == 0:
			return true
	return false


func _count_buildings(kind: int) -> int:
	var count := 0
	for building in buildings:
		if building.kind == kind:
			count += 1
	return count


func _planned_power_spare() -> int:
	var spare := 0
	for building in buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR:
			spare += building.get_power_output() if building.complete else 7
		elif not building.manually_disabled:
			spare -= building.get_base_power_demand()
	return spare


func _comfort_dark_bunk() -> VaultBuilding:
	for building in buildings:
		if building.kind == VaultBuilding.Kind.BED and lighting_system.is_floor_dark(building.cell):
			return building
	return null


# The comfort pieces still missing, in build order: [kind, cell] pairs ([] if there is no room).
func comfort_plan() -> Array:
	var kinds: Array[int] = []
	for kind: int in COMFORT_KINDS:
		if _count_buildings(kind) == 0:
			kinds.append(kind)
	var dark_bunk := _comfort_dark_bunk()
	var demand := 0
	for kind in kinds:
		demand += int(VaultBuilding.POWER_DEMAND.get(kind, 0))
	if dark_bunk != null:
		demand += int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.LAMP])
	if _planned_power_spare() < demand:
		kinds.push_front(VaultBuilding.Kind.GENERATOR)
	var plan: Array = []
	var cells := _annex_free_cells(kinds.size())
	if cells.size() < kinds.size():
		return []
	for index in kinds.size():
		plan.append([kinds[index], cells[index]])
	if dark_bunk != null:
		var lamp_cell := Vector2i(-1, -1)
		var used: Array[Vector2i] = cells
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var cell := dark_bunk.cell + d
			if cell != BreachSystem.HATCH_CELL and map_grid.is_walkable(cell) and get_building_at(cell) == null and not map_grid.stockpile_cells.has(cell) and not used.has(cell):
				lamp_cell = cell
				break
		if lamp_cell.x >= 0:
			plan.append([VaultBuilding.Kind.LAMP, lamp_cell])
	return plan


func comfort_cost() -> int:
	var cost := 0
	for piece: Array in comfort_plan():
		cost += int(VaultBuilding.COSTS[piece[0]])
	return cost


func apply_comfort() -> bool:
	if not comfort_pending():
		return false
	var plan := comfort_plan()
	if plan.is_empty():
		status_message = "No free floor for comfort fixtures; place a Rec Console and Med Bed by hand."
		status_message_left = 4.0
		return false
	for piece: Array in plan:
		place_blueprint(int(piece[0]), piece[1])
	status_message = COMFORT_STATUS
	status_message_left = 5.0
	return true


const COMFORT_STATUS := "Comfort queued: Rec Console, Med Bed and their power and light."


# Feast (north star slice 5): surplus meals become morale. At each keep-running day rollover, with
# meals at the Annex reserve + max(30, 2 per crew) or more and nobody hungry, every living resident
# eats 2 meals' worth of feast for +12 mood. Self-limiting: 5 crew spend 10 meals a day, more than two
# Grow Trays' surplus, so stock settles near the threshold instead of piling up. No save key.
const FEAST_MEALS_PER_CREW := 2
const FEAST_MOOD := 12.0
const FEAST_STOCK_FLOOR := 30
const FEAST_STATUS := "FEAST: %d meals shared · crew mood +%d"


func feast_threshold() -> int:
	return annex_reserve + maxi(FEAST_STOCK_FLOOR, FEAST_MEALS_PER_CREW * get_alive_count())


func _maybe_feast() -> bool:
	var alive := get_alive_count()
	if not keep_running or ended or alive <= 0 or food_system.meals < feast_threshold():
		return false
	for resident in residents:
		if resident.alive and resident.needs.food < ANNEX_HUNGRY_FOOD:
			return false
	var cost := FEAST_MEALS_PER_CREW * alive
	food_system.meals -= cost
	for resident in residents:
		if resident.alive:
			resident.needs.mood = minf(100.0, resident.needs.mood + FEAST_MOOD)
	status_message = FEAST_STATUS % [cost, roundi(FEAST_MOOD)]
	status_message_left = 4.0
	return true


# Construction goes first: the Annex waits for salvage while any blueprint is unbuilt.
func _blueprints_unbuilt() -> bool:
	for building in buildings:
		if not building.complete:
			return true
	return false


func annex_active() -> bool:
	return keep_running and not ended and not annex_done


func annex_progress() -> float:
	return float(annex_meals + annex_salvage) / float(ANNEX_MEALS + ANNEX_SALVAGE)


func set_annex_reserve(value: int) -> void:
	annex_reserve = clampi(value - value % ANNEX_RESERVE_STEP, ANNEX_RESERVE_MIN, ANNEX_RESERVE_MAX)


func _annex_crew_hungry() -> bool:
	for resident in residents:
		if resident.alive and resident.needs.food < ANNEX_HUNGRY_FOOD:
			return true
	return false


func _advance_annex(delta_seconds: float) -> void:
	# A paid Annex waiting on floor room re-checks every tick (done or not), so freeing room opens it.
	if annex_waiting_for_room():
		_reconcile_annex()
	if not annex_active():
		return
	_annex_trickle_left -= delta_seconds
	while _annex_trickle_left <= 0.0001:
		_annex_trickle_left += ANNEX_TRICKLE_INTERVAL
		food_system.add_salvage(1)
	_annex_tick_left -= delta_seconds
	while _annex_tick_left <= 0.0001 and not annex_done:
		_annex_tick_left += ANNEX_TICK
		if annex_meals < ANNEX_MEALS and food_system.meals > annex_reserve and not _annex_crew_hungry():
			food_system.meals -= 1
			annex_meals += 1
		if annex_salvage < ANNEX_SALVAGE and food_system.salvage > 0 and not _blueprints_unbuilt():
			food_system.salvage -= 1
			annex_salvage += 1
		_reconcile_annex()


func _reconcile_annex() -> void:
	if not annex_quotas_met() or (annex_done and annex_resident() != null):
		return
	if annex_resident() == null:
		var short := annex_room_short()
		if short > 0:
			_note_annex_room(short)
			return
	if annex_done:
		_grant_annex_payoff()
	else:
		annex_done = true
		_on_annex_completed()


func annex_quotas_met() -> bool:
	return annex_meals >= ANNEX_MEALS and annex_salvage >= ANNEX_SALVAGE


# The payoff is all or nothing: one free floor cell (not the hatch, a fixture or a stockpile zone)
# per fixture. Until then the paid Annex waits; nothing is saved, it is derived from the world.
func annex_room_short() -> int:
	return maxi(0, ANNEX_FIXTURES.size() - _annex_free_cell_count(ANNEX_FIXTURES.size()))


func annex_waiting_for_room() -> bool:
	return keep_running and not ended and annex_quotas_met() and annex_resident() == null


static func annex_room_cells_text(short: int) -> String:
	return "%d floor cell%s" % [short, "" if short == 1 else "s"]


func _note_annex_room(short: int) -> void:
	if short == _annex_room_noted:
		return
	_annex_room_noted = short
	status_message = ANNEX_ROOM_STATUS % annex_room_cells_text(short)
	status_message_left = 6.0


# Payoff (north star slice 3): the Annex opens with a bunk, a Grow Tray, a Nutrient Station and a
# Charge Node (food and power for one more mouth), and a fifth resident moves in. A seeded wing gives them the fifth trait slot when traits exist.
const ANNEX_RESIDENT_NAME := "Eko"
const ANNEX_RESIDENT_ID := 5
const ANNEX_FIXTURES := [VaultBuilding.Kind.BED, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GENERATOR]
const ANNEX_WELCOME_SECONDS := 30.0
const ANNEX_OPEN_STATUS := "ANNEX OPEN: %s moves in. +Bunk, Grow Tray, Nutrient Station, Charge Node."
const ANNEX_ROOM_STATUS := "ANNEX READY: free %s for its bunk, Grow Tray, Nutrient Station and Charge Node."
var annex_welcome_left := 0.0
var _annex_room_noted := 0


func _on_annex_completed() -> void:
	_annex_room_noted = 0
	_grant_annex_payoff()
	_record_progress(true)
	annex_welcome_left = ANNEX_WELCOME_SECONDS
	status_message = ANNEX_OPEN_STATUS % ANNEX_RESIDENT_NAME
	status_message_left = 10.0


# Records x Keep Running seam: the Annex resident takes the next id after the wing's starting crew
# (5 on a plain wing; 6 on 03 where Fen is 5, or with VOLUNTEER where Gil is; 7 with both).
func annex_resident_id() -> int:
	return starting_crew_size(sublevel, wing_perk) + 1


# Records x Keep Running seam: a kept-running vault already recorded its win at the finish. Each
# new keep-running day raises best_day and a finished Annex sets the wing's annex badge (never
# stars: they grade the 7-day run). Merges are max / OR, so repeats are harmless.
func _record_progress(annex := false) -> void:
	if not keep_running or not records_enabled():
		return
	wing_records().record(wing_seed, true, null, clampi(keep_running_day(), 1, WingRecords.MAX_DAY), sublevel, annex)


func annex_resident() -> VaultResident:
	for resident in residents:
		if resident.resident_id == annex_resident_id():
			return resident
	return null


# Idempotent: a vault that already has its Annex resident gets nothing twice. All or nothing: without a
# free cell for every fixture it grants nothing (the caller waits, see annex_room_short).
func _grant_annex_payoff() -> void:
	if annex_resident() != null or annex_room_short() > 0:
		return
	var cells := _annex_free_cells(ANNEX_FIXTURES.size() + 1)
	for index in mini(ANNEX_FIXTURES.size(), cells.size()):
		_spawn_starting_fixture(ANNEX_FIXTURES[index], cells[index], false)
	var spawn_cell: Vector2i = cells[-1] if cells.size() > ANNEX_FIXTURES.size() else map_grid.get_chamber_center()
	var resident := VaultResident.new()
	resident_root.add_child(resident)
	resident.configure(annex_resident_id(), ANNEX_RESIDENT_NAME, spawn_cell, map_grid)
	resident.needs.food = 80.0
	resident.needs.rest = 80.0
	resident.died.connect(_on_resident_died)
	residents.append(resident)
	if has_method("apply_crew_traits"):
		call("apply_crew_traits")
	power_grid.recalculate(buildings)
	refresh_lighting(true)
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())


func _annex_free_cells(count: int) -> Array[Vector2i]:
	var center := map_grid.get_chamber_center()
	var free: Array[Vector2i] = []
	for cell: Vector2i in map_grid.get_floor_cells():
		if cell == BreachSystem.HATCH_CELL or get_building_at(cell) != null or map_grid.stockpile_cells.has(cell):
			continue
		free.append(cell)
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x)))
	)
	return free.slice(0, count)


# Same cells as _annex_free_cells without the sort, stopping at `limit` (cheap enough every tick).
func _annex_free_cell_count(limit: int) -> int:
	var taken := {}
	for building in buildings:
		taken[building.cell] = true
	var count := 0
	for cell: Vector2i in map_grid.get_floor_cells():
		if cell == BreachSystem.HATCH_CELL or taken.has(cell) or map_grid.stockpile_cells.has(cell):
			continue
		count += 1
		if count >= limit:
			break
	return count
