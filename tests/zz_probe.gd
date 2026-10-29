extends SceneTree
# Adapted from clip-2026-10-23/clip_driver.gd. Env: PT_SUB, PT_SEED, PT_MODE(engaged|idle), PT_FRAMES, PT_RELAY(1), PT_LOG
const MAIN_SCENE := preload("res://scenes/main.tscn")
var game: VaultGame
var frame := 0
var breach_seen_frame := -1
var mode := OS.get_environment("PT_MODE")
var total := int(OS.get_environment("PT_FRAMES"))
var logf: FileAccess
var last := {}
var ended_frame := -1
var ended_sim := -1.0

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
	_log("START perk=%s unlocked=%s" % [game.wing_perk, str(game.unlocked_perks())])

var _last_offer := ""
var _last_card := ""

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
	_watch()
	var ub = game.player_orders.upgrade_offer_button
	var ut: String = (ub.text if ub != null and ub.is_visible_in_tree() else "none")
	var fb2 = game.player_orders.find_child("FoodPlanButton", true, false)
	var ct: String = (fb2.text if fb2 != null and fb2.is_visible_in_tree() else "none")
	if ut != _last_offer or ct != _last_card:
		_last_offer = ut; _last_card = ct
		_log("OFFER=%s | CARD=%s dis=%s" % [ut, ct, (str(fb2.disabled) if fb2 != null else "-")])
	if ended_frame > 0 and frame == ended_frame + 3:
		_log("RECAP=%s" % game.player_orders.outcome_text.text.replace("\n", " / "))
	if str(frame) in OS.get_environment("PT_SHOTS").split(","):
		var im := root.get_texture().get_image()
		im.save_png("%s/f%05d.png" % [OS.get_environment("PT_SHOT_DIR"), frame])
		var fb = game.player_orders.find_child("FoodPlanButton", true, false)
		_log("SHOT f%05d CARD=%s DISABLED=%s DETAILS=%s salvage=%d" % [frame, (fb.text if fb != null and fb.is_visible_in_tree() else "none"), (str(fb.disabled) if fb != null else "-"), str(game.player_orders.details_box.visible), game.food_system.salvage])
	if frame >= total or (ended_frame > 0 and frame >= ended_frame + 150):
		_log("END reason=%s outcome=%s sim=%.1f outcome_frame=%d outcome_sim=%.1f day=%d" % [
			_end_reason(), game.outcome, game.day_cycle.elapsed_seconds, ended_frame, ended_sim,
			game.day_cycle.current_day])
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
