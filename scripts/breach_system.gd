class_name BreachSystem
extends Node2D

enum Phase { DORMANT, WARNING, OPEN, SEALED }

signal warning_started
signal breach_opened
signal breach_sealed

const HATCH_CELL := Vector2i(28, 15)
const PATCH_COST := 4
const PATCH_WORK_SECONDS := 8.0
const WARNING_AT_SECONDS := 60.0
const GRACE_SECONDS := 20.0

const _OPEN_AT_SECONDS := WARNING_AT_SECONDS + GRACE_SECONDS
# Wing seed (QA 2026-10-18c #2, slice 1). The legacy wing (seed 0) warns at 60 s exactly as before;
# a seeded wing warns at one of 45, 50, ... 80 s. The time is derived from the saved seed, never
# saved itself. The game sets warning_at before reset/deserialize.
const SEEDED_WARNING_MIN := 45.0
const SEEDED_WARNING_STEP := 5.0
const SEEDED_WARNING_SLOTS := 8
var warning_at := WARNING_AT_SECONDS

var game: Node
var phase: Phase = Phase.DORMANT
var patch_delivered := 0
var patch_work_left := PATCH_WORK_SECONDS
var warning_acknowledged := false

var _elapsed_seconds := 0.0
var _warning_emitted := false
var _open_emitted := false
var _sealed_emitted := false
var _last_selected := false


func setup(game_node: Node) -> void:
	game = game_node
	_last_selected = _is_selected()
	queue_redraw()


func reset() -> void:
	phase = Phase.DORMANT
	patch_delivered = 0
	patch_work_left = PATCH_WORK_SECONDS
	warning_acknowledged = false
	_elapsed_seconds = 0.0
	_warning_emitted = false
	_open_emitted = false
	_sealed_emitted = false
	_last_selected = _is_selected()
	queue_redraw()


func advance(_delta_seconds: float, elapsed_seconds: float) -> void:
	# Slice 3 moves the open-hatch consequence into OxygenSystem, which owns
	# both air loss and suffocation damage.
	var step_end := _finite_nonnegative(elapsed_seconds)
	_elapsed_seconds = step_end

	if phase == Phase.DORMANT and step_end >= warning_at:
		_enter_warning(true)
	if phase == Phase.WARNING and step_end >= get_open_at():
		_enter_open(true)

	if phase != Phase.DORMANT:
		queue_redraw()


func is_response_active() -> bool:
	return phase == Phase.WARNING or phase == Phase.OPEN


func is_sealed() -> bool:
	return phase == Phase.SEALED


func is_open() -> bool:
	return phase == Phase.OPEN


func needs_supply() -> bool:
	return is_response_active() and patch_delivered < PATCH_COST


func is_supplied() -> bool:
	return patch_delivered >= PATCH_COST


func add_delivery(amount: int) -> int:
	if not is_response_active() or amount <= 0 or not needs_supply():
		return 0
	var accepted := mini(amount, PATCH_COST - patch_delivered)
	patch_delivered += accepted
	queue_redraw()
	return accepted


func apply_patch_work(amount: float) -> bool:
	if not is_response_active() or not is_supplied() or not is_finite(amount) or amount <= 0.0:
		return false
	patch_work_left = maxf(0.0, patch_work_left - amount)
	if patch_work_left <= 0.0 or is_zero_approx(patch_work_left):
		patch_work_left = 0.0
		_enter_sealed(true)
		return true
	queue_redraw()
	return false


func get_pressure_percent() -> float:
	match phase:
		Phase.WARNING:
			return clampf(
				(_elapsed_seconds - warning_at) / GRACE_SECONDS * 100.0,
				0.0,
				100.0,
			)
		Phase.OPEN:
			return 100.0
	return 0.0


func get_time_to_warning(elapsed_seconds: float = -1.0) -> float:
	var current_time := _elapsed_seconds if elapsed_seconds < 0.0 else elapsed_seconds
	return maxf(0.0, warning_at - _finite_nonnegative(current_time))


func get_time_to_open() -> float:
	if phase == Phase.OPEN or phase == Phase.SEALED:
		return 0.0
	return maxf(0.0, get_open_at() - _elapsed_seconds)


static func warning_at_for_seed(wing_seed: int) -> float:
	if wing_seed == 0:
		return WARNING_AT_SECONDS
	return SEEDED_WARNING_MIN + SEEDED_WARNING_STEP * float(seed_hash(wing_seed, 1) % SEEDED_WARNING_SLOTS)


# Fixed 31-bit integer mix (no RNG): the same seed and salt always give the same value.
static func seed_hash(wing_seed: int, salt: int) -> int:
	var h := (wing_seed * 0x2545F491 + salt * 0x9E3779B1) & 0x7FFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0x7FFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0x7FFFFFFF
	return h ^ (h >> 15)


func get_open_at() -> float:
	return warning_at + GRACE_SECONDS


func serialize() -> Dictionary:
	return {
		"phase": int(phase),
		"patch_delivered": patch_delivered,
		"patch_work_left": patch_work_left,
		"warning_acknowledged": warning_acknowledged,
		"warning_emitted": _warning_emitted,
		"open_emitted": _open_emitted,
		"sealed_emitted": _sealed_emitted,
	}


func deserialize(data: Dictionary, elapsed_seconds: float = 0.0) -> void:
	_elapsed_seconds = maxf(0.0, elapsed_seconds)

	# Breach state was optional in schema version 1. A legacy save beyond the
	# grace period is treated as already contained rather than inventing damage.
	if data.is_empty():
		_deserialize_legacy_state()
		queue_redraw()
		return

	phase = clampi(
		int(data.get("phase", Phase.DORMANT)),
		int(Phase.DORMANT),
		int(Phase.SEALED),
	) as Phase
	patch_delivered = clampi(int(data.get("patch_delivered", 0)), 0, PATCH_COST)
	patch_work_left = clampf(
		float(data.get("patch_work_left", PATCH_WORK_SECONDS)),
		0.0,
		PATCH_WORK_SECONDS,
	)
	warning_acknowledged = bool(data.get("warning_acknowledged", phase != Phase.DORMANT))

	_warning_emitted = bool(data.get("warning_emitted", phase != Phase.DORMANT))
	_open_emitted = bool(data.get("open_emitted", phase == Phase.OPEN))
	_sealed_emitted = bool(data.get("sealed_emitted", phase == Phase.SEALED))

	# Loading never replays interruption signals. If an explicit snapshot is
	# slightly behind its clock, the next simulation step performs the pending
	# transition once and emits only the genuinely new event.
	queue_redraw()


func is_serialized_data_valid(data: Variant, elapsed_seconds: Variant = null, warning_time := -1.0) -> bool:
	var warn := warning_at if warning_time < 0.0 else warning_time
	var open_at := warn + GRACE_SECONDS
	if not data is Dictionary:
		return false
	var saved: Dictionary = data
	if saved.is_empty():
		return true
	var required_fields := [
		"phase",
		"patch_delivered",
		"patch_work_left",
		"warning_acknowledged",
		"warning_emitted",
		"open_emitted",
		"sealed_emitted",
	]
	for field: String in required_fields:
		if not saved.has(field):
			return false

	if not _is_number(saved.phase) or not _is_number(saved.patch_delivered) or not _is_number(saved.patch_work_left):
		return false
	var phase_number := float(saved.phase)
	var delivered_number := float(saved.patch_delivered)
	var work_left := float(saved.patch_work_left)
	if not is_finite(phase_number) or phase_number != floorf(phase_number) or phase_number < Phase.DORMANT or phase_number > Phase.SEALED:
		return false
	if not is_finite(delivered_number) or delivered_number != floorf(delivered_number) or delivered_number < 0.0 or delivered_number > PATCH_COST:
		return false
	if not is_finite(work_left) or work_left < 0.0 or work_left > PATCH_WORK_SECONDS:
		return false
	for flag_name in ["warning_acknowledged", "warning_emitted", "open_emitted", "sealed_emitted"]:
		if typeof(saved[flag_name]) != TYPE_BOOL:
			return false

	var saved_phase := int(phase_number)
	var delivered := int(delivered_number)
	var warning_emitted := bool(saved.warning_emitted)
	var open_emitted := bool(saved.open_emitted)
	var sealed_emitted := bool(saved.sealed_emitted)
	if delivered < PATCH_COST and not is_equal_approx(work_left, PATCH_WORK_SECONDS):
		return false
	var state_is_valid := false
	match saved_phase:
		Phase.DORMANT:
			state_is_valid = (
				delivered == 0
				and is_equal_approx(work_left, PATCH_WORK_SECONDS)
				and not bool(saved.warning_acknowledged)
				and not warning_emitted
				and not open_emitted
				and not sealed_emitted
			)
		Phase.WARNING:
			state_is_valid = warning_emitted and not open_emitted and not sealed_emitted and work_left > 0.0
		Phase.OPEN:
			state_is_valid = warning_emitted and open_emitted and not sealed_emitted and work_left > 0.0
		Phase.SEALED:
			state_is_valid = warning_emitted and sealed_emitted and delivered == PATCH_COST and is_zero_approx(work_left)
	if not state_is_valid:
		return false
	if elapsed_seconds == null:
		return true
	if not _is_number(elapsed_seconds):
		return false
	var saved_elapsed := float(elapsed_seconds)
	match saved_phase:
		Phase.DORMANT:
			return saved_elapsed < warn
		Phase.WARNING:
			return saved_elapsed >= warn and saved_elapsed < open_at
		Phase.OPEN:
			return saved_elapsed >= open_at
		Phase.SEALED:
			return saved_elapsed >= warn
	return false


func _deserialize_legacy_state() -> void:
	patch_delivered = 0
	patch_work_left = PATCH_WORK_SECONDS
	warning_acknowledged = false
	_warning_emitted = false
	_open_emitted = false
	_sealed_emitted = false

	if _elapsed_seconds >= get_open_at():
		phase = Phase.SEALED
		patch_delivered = PATCH_COST
		patch_work_left = 0.0
		warning_acknowledged = true
		_warning_emitted = true
		_open_emitted = true
		_sealed_emitted = true
	elif _elapsed_seconds >= warning_at:
		phase = Phase.WARNING
		warning_acknowledged = true
		_warning_emitted = true
	else:
		phase = Phase.DORMANT


func _enter_warning(emit_event: bool) -> void:
	if phase != Phase.DORMANT:
		return
	phase = Phase.WARNING
	warning_acknowledged = false
	if emit_event and not _warning_emitted:
		_warning_emitted = true
		warning_started.emit()
	queue_redraw()


func _enter_open(emit_event: bool) -> void:
	if phase != Phase.WARNING:
		return
	phase = Phase.OPEN
	warning_acknowledged = true
	if emit_event and not _open_emitted:
		_open_emitted = true
		breach_opened.emit()
	queue_redraw()


func _enter_sealed(emit_event: bool) -> void:
	if phase == Phase.SEALED:
		return
	phase = Phase.SEALED
	patch_delivered = PATCH_COST
	patch_work_left = 0.0
	if emit_event and not _sealed_emitted:
		_sealed_emitted = true
		breach_sealed.emit()
	queue_redraw()


func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _finite_nonnegative(value: float) -> float:
	return maxf(0.0, value) if is_finite(value) else 0.0


func _is_selected() -> bool:
	return game is VaultGame and game.selected_breach


func _process(_delta: float) -> void:
	var current_selected := _is_selected()
	if current_selected != _last_selected:
		_last_selected = current_selected
		queue_redraw()


func _draw() -> void:
	var tile_size := float(MapGrid.TILE_SIZE)
	var center := MapGrid.offset_cell_to_world(HATCH_CELL)
	var hatch_rect := Rect2(center - Vector2.ONE * tile_size * 0.38, Vector2.ONE * tile_size * 0.76)
	var marker_color := Color("637b85")
	var phase_text := "HATCH"
	match phase:
		Phase.WARNING:
			marker_color = Color("efc56b")
			phase_text = "! %ds" % ceili(get_time_to_open())
		Phase.OPEN:
			marker_color = Color("ef6860")
			phase_text = "OPEN"
		Phase.SEALED:
			marker_color = Color("75d4b4")
			phase_text = "SEALED"

	draw_rect(hatch_rect, Color("111b21"))
	draw_rect(hatch_rect, marker_color, false, 2.0)
	# Cross-bracing and phase text keep state readable without color alone.
	draw_line(hatch_rect.position + Vector2(3, 3), hatch_rect.end - Vector2(3, 3), marker_color, 1.5)
	draw_line(
		Vector2(hatch_rect.end.x - 3, hatch_rect.position.y + 3),
		Vector2(hatch_rect.position.x + 3, hatch_rect.end.y - 3),
		marker_color,
		1.5,
	)
	if _is_selected():
		draw_rect(hatch_rect.grow(4.0), Color("f5f1da"), false, 2.0)

	var font := ThemeDB.fallback_font
	draw_string(
		font,
		center + Vector2(-tile_size, -tile_size * 0.55),
		phase_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		tile_size * 2.0,
		8,
		Color("f5f1da"),
	)

	if is_response_active():
		var progress := 0.0
		if needs_supply():
			progress = float(patch_delivered) / float(PATCH_COST)
		else:
			progress = 1.0 - patch_work_left / PATCH_WORK_SECONDS
		var progress_rect := Rect2(
			hatch_rect.position + Vector2(0, hatch_rect.size.y + 3),
			Vector2(hatch_rect.size.x, 3),
		)
		draw_rect(progress_rect, Color("111b21"))
		draw_rect(
			Rect2(progress_rect.position, Vector2(progress_rect.size.x * clampf(progress, 0.0, 1.0), 3)),
			marker_color,
		)
