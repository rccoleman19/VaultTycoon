class_name PlayerOrders
extends CanvasLayer

const DIG_SALVAGE_YIELD := 3
const MAX_VISIBLE_ALERTS := 2
const IDLE_CREW_WINDOW_S := 3.0
const NEXT_HOLD_S := 2.0

# Keep a plain-text view for alert clause/fold readers while rendering each row separately.
class AlertDetails extends VBoxContainer:
	var text: String:
		get:
			var lines: Array[String] = []
			for row: Label in get_children():
				lines.append(row.text)
			return "\n".join(lines)


# Presentation state is sampled by refresh/the existing simulation-tip hook,
# never by the Next selector. Instance IDs also distinguish loaded residents.
var _idle_crew_since: Dictionary = {}
var _idle_crew_sample_time := -1.0
var _next_hold_signature: Array = []
var _next_hold_since := -1.0
var _next_hold_step: Dictionary = {}
var _next_reclamation_kind := -1
var _displayed_next_step: Dictionary = {}
# Display-only steadiness for Next (QA playtest 2 #2, #3): the shown step, when it
# was first shown (sim s), and the step held while the PRESSURE SURGE modal is up.
const NEXT_STARVING_HOLD_S := 4.0
var _next_shown_step: Dictionary = {}
var _next_shown_since := -1.0
var _next_surge_step: Dictionary = {}

# Guidance reads retain the starvation name until fed or a nearer deadline.
var _starving_resident_id := -1
var _food_forecast_latched := false
var _next_bunk_text := ""
var _next_bunk_help := ""
var _food_forecast_since := 0.0

var game: VaultGame
var root: Control
var clock_label: Label
var resource_label: Label
var power_label: Label
var pause_button: Button
var objective_label: Label
var also_label: Label
var alert_label: Label
var _fitting_alert_line := false
var all_alerts: Array[String] = []
var alert_list: Array[String] = []
var alert_hidden_count: int = 0
var alert_more_label: AlertDetails
var alert_more_header: Label
var crew_mood_label: Label
var crew_mood_bar: ProgressBar
var lighting_label: Label
var lighting_overlay_button: Button
var power_detail_label: Label
var oxygen_label: Label
var oxygen_bar: ProgressBar
var breach_label: Label
var breach_bar: ProgressBar
var breach_focus_button: Button
var right_scroll: ScrollContainer
var details_box: VBoxContainer
var details_toggle: Button
# Divides the pinned summary from the roster; hidden while DETAILS opens at the top of the scroll.
var summary_separator: HSeparator
var _details_expanded := false
var _details_urgencies: Dictionary = {}
var _details_resident_instance_id := 0
var roster_box: VBoxContainer
var inspector_title: Label
var inspector_state: Label
var resident_command_header: Label
var resident_command_row: HBoxContainer
var resident_draft_button: Button
var resident_cancel_button: Button
var draft_button: Button
var work_header: Label
var fixture_header: Label
var fixture_controls: HBoxContainer
var fixture_power_button: Button
var fixture_deconstruct_button: Button
# Mid-game salvage sink (QA 2026-10-18c #3, slice 1): an optional offer outside Next, plus the
# inspector purchase row. Both stay hidden until the hatch is sealed.
var upgrade_offer_button: Button
var reclaim_button: Button
var idle_start_box: VBoxContainer
var idle_start_header: Label
var idle_start_button: Button
var idle_start_dismiss_button: Button
var fixture_upgrade_row: HBoxContainer
var fixture_upgrade_button: Button
# Wing orders (QA 2026-10-18c #3, slice 2): a compact post-seal panel under the offer, outside
# Next and DETAILS. A done row selects a fixture that its reward unlocked.
var wing_orders_box: VBoxContainer
var wing_orders_header: Label
var wing_order_rows := {}
var need_labels: Dictionary = {}
var need_bars: Dictionary = {}
var work_buttons: Dictionary = {}
var command_buttons: Dictionary = {}
var bottom_panel: PanelContainer
var architect_panel: Control
var architect_tab_buttons: Dictionary = {}
var architect_category_rows: Dictionary = {}
var _architect_open_tab := ""
var _last_processed_suggested_tool := ""
var _has_processed_suggested_tool := false
var tool_status: Label
var checklist: RichTextLabel
var briefing_overlay: Control
var briefing_panel: PanelContainer
var briefing_load_button: Button
var briefing_begin_button: Button
var briefing_close_button: Button
var briefing_tips_label: Label
# Records + ladder C6: the opening briefing's sublevel stepper (only once a deeper sublevel is
# unlocked) and the rolled wing's record line.
var briefing_sublevel_row: HBoxContainer
var briefing_sublevel_label: Label
var briefing_deeper_button: Button
var briefing_shallower_button: Button
var briefing_record_label: Label
# Meta perks P2: the perk row under the sublevel stepper (hidden until a perk is unlocked).
var briefing_perk_row: HBoxContainer
var briefing_perk_label: Label
var briefing_perk_prev_button: Button
var briefing_perk_next_button: Button
var _briefing_is_opening := false
var help_button: Button
var breach_warning_panel: PanelContainer
var breach_resume_button: Button
var outcome_panel: PanelContainer
var outcome_title: Label
var outcome_text: Label
var outcome_grade: Label
var outcome_record: Label
var outcome_best: Label
var outcome_resume_button: Button
var outcome_retry_button: Button
var outcome_retry_reason: Label
var _outcome_backdrop: ColorRect
var _outcome_legacy_row: HBoxContainer
var _outcome_recap_row: HBoxContainer
var _survival_tips := {}
var _survival_tip_details := {}
var _survival_tip_sample_left := 0.0
var _survival_tip_tick := 0
var _sampling_survival_tip := false
var work_priorities_overlay: Control
var work_priorities_panel: PanelContainer
var work_priorities_button: Button
var work_priorities_close_button: Button
var work_priorities_grid: GridContainer
var work_priorities_summary: Label
var work_priority_buttons: Dictionary = {}

var _last_roster_signature := ""
var _last_inspected_resident_id := -1
var _last_inspected_building_id := -1
var _last_work_priority_roster_signature := ""
var _next_mood_tip_latched := false
var _next_mood_tip_owner_id := 0


func setup(game_node: VaultGame) -> void:
	game = game_node
	_build_interface()


func _build_interface() -> void:
	root = Control.new()
	root.name = "Interface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_panel := Panel.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_bottom = 52.0
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color("121b21"), Color("45616a")))
	root.add_child(top_panel)
	var top_row := HBoxContainer.new()
	top_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	top_row.add_theme_constant_override("separation", TOP_ROW_SEPARATION)
	top_panel.add_child(top_row)
	var brand := Label.new()
	brand.text = "VAULT WING // SUBLEVEL 07"
	brand.add_theme_color_override("font_color", Color("77d3bc"))
	brand.add_theme_font_size_override("font_size", 15)
	top_row.add_child(brand)
	wing_brand_label = brand
	clock_label = Label.new()
	top_row.add_child(clock_label)
	# Top-bar fit: the resource stats take the free width and clip past it, so PAUSE and 1x-3x always
	# stay on screen; the power status (BROWNOUT, shed load) always reads in full at its own width.
	resource_label = Label.new()
	resource_label.custom_minimum_size.x = TOP_RESOURCE_MIN_WIDTH
	resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_label.clip_text = true
	top_row.add_child(resource_label)
	power_label = Label.new()
	top_row.add_child(power_label)
	pause_button = Button.new()
	pause_button.text = "PAUSE"
	pause_button.pressed.connect(func() -> void: game.toggle_pause())
	top_row.add_child(pause_button)
	for speed in [1, 2, 3]:
		var speed_button := Button.new()
		speed_button.text = "%dx" % speed
		speed_button.pressed.connect(_on_speed_pressed.bind(speed))
		top_row.add_child(speed_button)

	var right_panel := PanelContainer.new()
	right_panel.set_anchor(SIDE_LEFT, 1.0)
	right_panel.set_anchor(SIDE_RIGHT, 1.0)
	right_panel.set_anchor(SIDE_BOTTOM, 1.0)
	right_panel.offset_left = -VaultGame.RIGHT_PANEL_WIDTH
	right_panel.offset_top = 52.0
	right_panel.offset_bottom = -8.0
	right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	right_panel.add_theme_stylebox_override("panel", _panel_style(Color("152129"), Color("3d5962")))
	root.add_child(right_panel)
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 12)
	right_margin.add_theme_constant_override("margin_right", 12)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(right_margin)
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(rail)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 4)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(summary)
	objective_label = Label.new()
	objective_label.text = "Next: YOU designate · THEY auto-work"
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_color_override("font_color", Color("efc56b"))
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.custom_minimum_size.y = 42
	summary.add_child(objective_label)
	also_label = Label.new()
	also_label.visible = false
	also_label.add_theme_color_override("font_color", Color("a8946a"))
	also_label.add_theme_font_size_override("font_size", 13)
	summary.add_child(also_label)
	alert_label = Label.new()
	alert_label.tooltip_text = "Open DETAILS to see the remaining alerts listed by urgency."
	alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	alert_label.custom_minimum_size.y = 34
	alert_label.resized.connect(_fit_alert_line)
	summary.add_child(alert_label)
	_build_idle_start_card(summary)
	_build_comfort_card(summary)
	_build_food_plan_card(summary)
	_build_annex_card(summary)
	upgrade_offer_button = Button.new()
	upgrade_offer_button.visible = false
	upgrade_offer_button.custom_minimum_size.y = 26
	upgrade_offer_button.clip_text = true
	upgrade_offer_button.tooltip_text = "Optional post-seal Mk II fit: selects the fixture; buy it in the inspector. Charge Mk II gives +3 power for a second Grow Tray."
	upgrade_offer_button.pressed.connect(_on_upgrade_offer_pressed)
	summary.add_child(upgrade_offer_button)
	wing_orders_box = VBoxContainer.new()
	wing_orders_box.visible = false
	wing_orders_box.add_theme_constant_override("separation", 2)
	summary.add_child(wing_orders_box)
	wing_orders_header = Label.new()
	wing_orders_header.add_theme_color_override("font_color", Color("8faeb7"))
	wing_orders_header.add_theme_font_size_override("font_size", 13)
	wing_orders_box.add_child(wing_orders_header)
	reclaim_button = Button.new()
	reclaim_button.clip_text = true
	reclaim_button.custom_minimum_size.y = 24
	reclaim_button.add_theme_font_size_override("font_size", 13)
	reclaim_button.tooltip_text = "Optional: start reclaiming the sealed wing for salvage (+%d now, +%d every %d s, %d times)." % [VaultGame.RECLAIM_START_SALVAGE, VaultGame.RECLAIM_DELIVERY, roundi(VaultGame.RECLAIM_INTERVAL), VaultGame.RECLAIM_DELIVERIES]
	reclaim_button.pressed.connect(func() -> void:
		if not game.toggle_cook_reclamation():
			game.start_reclamation())
	wing_orders_box.add_child(reclaim_button)
	for order_id: String in VaultGame.WING_ORDER_IDS:
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.custom_minimum_size.y = 22
		row.add_theme_font_size_override("font_size", 13)
		row.pressed.connect(_on_wing_order_pressed.bind(order_id))
		wing_order_rows[order_id] = row
		wing_orders_box.add_child(row)
	details_toggle = Button.new()
	details_toggle.text = "DETAILS ▸"
	details_toggle.tooltip_text = "Show or hide remaining alerts, mood, power, air, hatch, and light readouts."
	details_toggle.custom_minimum_size.y = 26
	details_toggle.pressed.connect(_toggle_details_rail)
	summary.add_child(details_toggle)
	# DETAILS readouts sit at the top of the roster/inspector scroll (added below), so opening them
	# never pushes the inspector off a 1280x720 screen once the post-seal offer and orders show.
	details_box = VBoxContainer.new()
	details_box.add_theme_constant_override("separation", 4)
	details_box.visible = false
	alert_more_header = Label.new()
	alert_more_header.text = "ALERTS"
	alert_more_header.add_theme_color_override("font_color", Color("8faeb7"))
	details_box.add_child(alert_more_header)
	alert_more_label = AlertDetails.new()
	alert_more_label.add_theme_constant_override("separation", 0)
	details_box.add_child(alert_more_label)
	_refresh_alert_details()
	var mood_header := Label.new()
	mood_header.text = "CREW MOOD"
	mood_header.add_theme_color_override("font_color", Color("8faeb7"))
	details_box.add_child(mood_header)
	crew_mood_label = Label.new()
	crew_mood_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew_mood_label.custom_minimum_size.y = 38
	details_box.add_child(crew_mood_label)
	crew_mood_bar = ProgressBar.new()
	crew_mood_bar.min_value = 0.0
	crew_mood_bar.max_value = 100.0
	crew_mood_bar.show_percentage = false
	crew_mood_bar.custom_minimum_size.y = 10
	details_box.add_child(crew_mood_bar)
	var lighting_row := HBoxContainer.new()
	lighting_row.add_theme_constant_override("separation", 6)
	details_box.add_child(lighting_row)
	lighting_label = Label.new()
	lighting_label.custom_minimum_size = Vector2(LIGHTING_LABEL_MIN_WIDTH, 26)
	lighting_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lighting_label.clip_text = true
	lighting_label.add_theme_font_size_override("font_size", 14)
	lighting_row.add_child(lighting_label)
	lighting_overlay_button = Button.new()
	lighting_overlay_button.text = "[L] MAP OFF"
	lighting_overlay_button.tooltip_text = "Show exact powered-Lumen floor coverage without changing simulation lighting."
	lighting_overlay_button.custom_minimum_size = Vector2(82, 26)
	lighting_overlay_button.pressed.connect(func() -> void: game.toggle_lighting_overlay())
	lighting_row.add_child(lighting_overlay_button)
	var power_header := Label.new()
	power_header.text = "POWER GRID"
	power_header.add_theme_color_override("font_color", Color("8faeb7"))
	details_box.add_child(power_header)
	power_detail_label = Label.new()
	power_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_detail_label.custom_minimum_size.y = 62
	details_box.add_child(power_detail_label)
	var oxygen_header := Label.new()
	oxygen_header.text = "VAULT ATMOSPHERE"
	oxygen_header.add_theme_color_override("font_color", Color("8faeb7"))
	details_box.add_child(oxygen_header)
	oxygen_label = Label.new()
	oxygen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	oxygen_label.custom_minimum_size.y = 38
	details_box.add_child(oxygen_label)
	oxygen_bar = ProgressBar.new()
	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = OxygenSystem.MAX_OXYGEN
	oxygen_bar.show_percentage = false
	oxygen_bar.custom_minimum_size.y = 10
	details_box.add_child(oxygen_bar)
	var breach_header := Label.new()
	breach_header.text = "PRESSURE HATCH"
	breach_header.add_theme_color_override("font_color", Color("8faeb7"))
	details_box.add_child(breach_header)
	breach_label = Label.new()
	breach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	breach_label.custom_minimum_size.y = 64
	details_box.add_child(breach_label)
	breach_bar = ProgressBar.new()
	breach_bar.min_value = 0.0
	breach_bar.max_value = 100.0
	breach_bar.show_percentage = false
	breach_bar.custom_minimum_size.y = 10
	details_box.add_child(breach_bar)
	breach_focus_button = Button.new()
	breach_focus_button.text = "FOCUS HATCH"
	breach_focus_button.custom_minimum_size.y = 26
	breach_focus_button.pressed.connect(func() -> void: game.focus_breach())
	details_box.add_child(breach_focus_button)
	details_box.add_child(HSeparator.new())
	summary_separator = HSeparator.new()
	summary.add_child(summary_separator)
	right_scroll = ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(right_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(side)
	side.add_child(details_box)
	var roster_header_row := HBoxContainer.new()
	roster_header_row.add_theme_constant_override("separation", 6)
	side.add_child(roster_header_row)
	var roster_header := Label.new()
	roster_header.text = "RESIDENT ROSTER"
	roster_header.add_theme_color_override("font_color", Color("8faeb7"))
	roster_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roster_header_row.add_child(roster_header)
	work_priorities_button = Button.new()
	work_priorities_button.name = "WorkPrioritiesButton"
	work_priorities_button.text = "PRIORITIES [P]"
	work_priorities_button.tooltip_text = "RimWorld-style work tab: ranks 1 (highest) to 4, OFF never claims. Same rank goes by job: build, food, rubble, then digs. Defaults already on at 3 — open only to specialize."
	work_priorities_button.custom_minimum_size = Vector2(122, 28)
	work_priorities_button.pressed.connect(toggle_work_priorities)
	roster_header_row.add_child(work_priorities_button)
	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 2)
	side.add_child(roster_box)
	side.add_child(HSeparator.new())
	inspector_title = Label.new()
	inspector_title.text = "INSPECTOR"
	inspector_title.add_theme_font_size_override("font_size", 16)
	side.add_child(inspector_title)
	inspector_state = Label.new()
	inspector_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_state.custom_minimum_size.y = 36
	side.add_child(inspector_state)
	for need_name in ["food", "rest", "mood", "health"]:
		var need_row := HBoxContainer.new()
		var need_label := Label.new()
		need_label.custom_minimum_size.x = 62
		need_row.add_child(need_label)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 13
		need_row.add_child(bar)
		need_labels[need_name] = need_label
		need_bars[need_name] = bar
		side.add_child(need_row)
	resident_command_header = Label.new()
	resident_command_header.text = "RESIDENT COMMAND"
	resident_command_header.add_theme_color_override("font_color", Color("8faeb7"))
	side.add_child(resident_command_header)
	resident_command_row = HBoxContainer.new()
	resident_command_row.name = "ResidentCommandRow"
	resident_command_row.add_theme_constant_override("separation", 5)
	resident_draft_button = Button.new()
	resident_draft_button.name = "ResidentDraftButton"
	resident_draft_button.custom_minimum_size = Vector2(130, 28)
	resident_draft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resident_draft_button.pressed.connect(_on_resident_draft_pressed)
	resident_command_row.add_child(resident_draft_button)
	draft_button = resident_draft_button
	resident_cancel_button = Button.new()
	resident_cancel_button.name = "ResidentCancelCommandButton"
	resident_cancel_button.text = "CANCEL"
	resident_cancel_button.tooltip_text = "Cancel this resident's current manual move or forced job."
	resident_cancel_button.custom_minimum_size = Vector2(86, 28)
	resident_cancel_button.pressed.connect(_on_resident_cancel_command_pressed)
	resident_command_row.add_child(resident_cancel_button)
	side.add_child(resident_command_row)
	_hide_resident_commands()
	work_header = Label.new()
	work_header.text = "WORK PRIORITIES · 1 HIGHEST"
	work_header.add_theme_color_override("font_color", Color("8faeb7"))
	side.add_child(work_header)
	var work_row := GridContainer.new()
	work_row.columns = 2
	work_row.add_theme_constant_override("h_separation", 5)
	work_row.add_theme_constant_override("v_separation", 4)
	for work_type in ["dig", "haul", "craft", "cook"]:
		var work_button := Button.new()
		work_button.custom_minimum_size = Vector2(130, 28)
		work_button.pressed.connect(_on_work_pressed.bind(work_type))
		work_buttons[work_type] = work_button
		work_row.add_child(work_button)
	side.add_child(work_row)
	fixture_header = Label.new()
	fixture_header.text = "FIXTURE CONTROLS"
	fixture_header.add_theme_color_override("font_color", Color("8faeb7"))
	side.add_child(fixture_header)
	fixture_controls = HBoxContainer.new()
	fixture_controls.add_theme_constant_override("separation", 5)
	fixture_power_button = Button.new()
	fixture_power_button.tooltip_text = "Remove or restore this fixture's power demand."
	fixture_power_button.custom_minimum_size = Vector2(92, 28)
	fixture_power_button.pressed.connect(_on_fixture_power_pressed)
	fixture_controls.add_child(fixture_power_button)
	fixture_deconstruct_button = Button.new()
	fixture_deconstruct_button.text = "REMOVE"
	fixture_deconstruct_button.custom_minimum_size = Vector2(92, 28)
	fixture_deconstruct_button.pressed.connect(_on_fixture_deconstruct_pressed)
	fixture_controls.add_child(fixture_deconstruct_button)
	side.add_child(fixture_controls)
	fixture_upgrade_row = HBoxContainer.new()
	fixture_upgrade_row.visible = false
	fixture_upgrade_button = Button.new()
	fixture_upgrade_button.custom_minimum_size = Vector2(189, 28)
	fixture_upgrade_button.pressed.connect(_on_fixture_upgrade_pressed)
	fixture_upgrade_row.add_child(fixture_upgrade_button)
	side.add_child(fixture_upgrade_row)
	_hide_fixture_controls()

	bottom_panel = PanelContainer.new()
	bottom_panel.name = "ArchitectRail"
	bottom_panel.set_anchor(SIDE_RIGHT, 1.0)
	bottom_panel.set_anchor(SIDE_TOP, 1.0)
	bottom_panel.set_anchor(SIDE_BOTTOM, 1.0)
	bottom_panel.offset_left = 8.0
	bottom_panel.offset_right = -VaultGame.RIGHT_PANEL_WIDTH - 8.0
	bottom_panel.offset_top = -72.0
	bottom_panel.offset_bottom = -8.0
	# Two help lines grow the rail up, not off the bottom of the screen.
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color("121b21"), Color("45616a")))
	root.add_child(bottom_panel)
	var bottom_content := VBoxContainer.new()
	bottom_content.add_theme_constant_override("separation", 4)
	bottom_panel.add_child(bottom_content)
	architect_panel = Control.new()
	architect_panel.name = "ArchitectPanel"
	architect_panel.visible = false
	architect_panel.custom_minimum_size = Vector2(0, 40)
	bottom_content.add_child(architect_panel)
	var tools := {
		"select": ["SELECT", "Inspect residents and fixtures; Esc returns here", 76],
		"dig": ["DIG [E]", "Mark rock for excavation", 68],
		"cancel": ["CANCEL [X]", "Clear zone cells, orders, and blueprints", 96],
		"bed": ["BUNK $8", "Rest fixture", 80],
		"lamp": ["LUMEN $5", "1 power; lights floor within %d tiles" % LightingSystem.LUMEN_RADIUS, 90],
		"generator": ["CHARGE $18", "+7 power", 104],
		"grow": ["GROW $12", "3 power; yields raw food for hauling", 90],
		"kitchen": ["NUTRI $10", "2 power; cooks meals for hauling", 96],
		"zone": ["ZONE", "Paint drop-offs for salvage, raw food, and meals; CANCEL [X] clears", 76],
		"stockpile": ["BAY $4", "Fallback destination for salvage and food hauling", 64],
		"air": ["AIR $14", "Air Recycler: 3 power; restores vault oxygen", 86],
		"medical": ["MED $8", "Medical Bed: automatic injury recovery, +2 HP/s; no power", 82],
		"rec": ["REC $8", "Rec Console: 1 power; restores one resident's mood", 82],
	}
	var categories := [
		["orders", "ORDERS", ["select"]],
		["dig", "DIG", ["dig", "zone", "stockpile"]],
		["build", "BUILD", ["bed", "lamp", "generator", "grow", "kitchen", "air", "medical", "rec"]],
		["restrict", "RESTRICT", ["cancel"]],
		["work", "WORK", []],
		["menu", "MENU", []],
	]
	for category in categories:
		var row := HBoxContainer.new()
		row.name = "ArchitectRow_%s" % category[0]
		row.visible = false
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 5)
		architect_panel.add_child(row)
		architect_category_rows[category[0]] = row
		for tool_id in category[2]:
			var definition: Array = tools[tool_id]
			var button := Button.new()
			button.text = definition[0]
			button.tooltip_text = definition[1]
			button.custom_minimum_size = Vector2(float(definition[2]), 36)
			button.clip_text = true
			button.pressed.connect(_on_tool_pressed.bind(tool_id))
			command_buttons[tool_id] = button
			row.add_child(button)
		if category[0] == "work":
			var priorities_rail_button := Button.new()
			priorities_rail_button.text = "PRIORITIES [P]"
			priorities_rail_button.tooltip_text = "RimWorld-style work tab: ranks 1 (highest) to 4, OFF never claims."
			priorities_rail_button.custom_minimum_size = Vector2(122, 36)
			priorities_rail_button.pressed.connect(toggle_work_priorities)
			row.add_child(priorities_rail_button)
		elif category[0] == "menu":
			var save_button := Button.new()
			save_button.text = "SAVE"
			save_button.tooltip_text = "Save one local wing slot"
			save_button.custom_minimum_size = Vector2(72, 36)
			save_button.pressed.connect(func() -> void: game.save_game())
			row.add_child(save_button)
			var load_button := Button.new()
			load_button.text = "LOAD"
			load_button.tooltip_text = "Load the local wing slot"
			load_button.custom_minimum_size = Vector2(72, 36)
			load_button.pressed.connect(func() -> void: game.load_game())
			row.add_child(load_button)
			help_button = Button.new()
			help_button.text = "HELP"
			help_button.tooltip_text = "Pause behind the live first-shift checklist"
			help_button.custom_minimum_size = Vector2(72, 36)
			help_button.pressed.connect(open_help)
			row.add_child(help_button)
	var tab_rail := HBoxContainer.new()
	tab_rail.name = "ArchitectTabs"
	tab_rail.add_theme_constant_override("separation", 4)
	bottom_content.add_child(tab_rail)
	for category in categories:
		var tab := Button.new()
		tab.text = category[1]
		tab.custom_minimum_size = Vector2(88, 32)
		tab.pressed.connect(_on_architect_tab_pressed.bind(category[0]))
		tab_rail.add_child(tab)
		architect_tab_buttons[category[0]] = tab
	tool_status = Label.new()
	tool_status.text = "SELECT"
	# A long help line must not widen the rail under the right panel (playtest finding 5).
	tool_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tool_status.mouse_filter = Control.MOUSE_FILTER_PASS
	tool_status.add_theme_color_override("font_color", Color("efc56b"))
	bottom_content.add_child(tool_status)

	_build_work_priorities_board()
	_build_briefing()
	_build_breach_warning()
	_build_outcome()


func _on_architect_tab_pressed(tab_id: String) -> void:
	if _architect_open_tab == tab_id:
		_set_architect_tab("")
	else:
		_set_architect_tab(tab_id)


func _set_architect_tab(tab_id: String) -> void:
	_architect_open_tab = tab_id
	var open := not tab_id.is_empty()
	architect_panel.visible = open
	for key: String in architect_category_rows:
		var row: Control = architect_category_rows[key]
		row.visible = open and key == tab_id
	for key: String in architect_tab_buttons:
		var tab: Button = architect_tab_buttons[key]
		tab.modulate = Color("efc56b") if key == tab_id else Color.WHITE
	bottom_panel.offset_top = -118.0 if open else -72.0


func _build_work_priorities_board() -> void:
	work_priorities_overlay = Control.new()
	work_priorities_overlay.name = "WorkPrioritiesOverlay"
	work_priorities_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	work_priorities_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(work_priorities_overlay)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.025, 0.045, 0.055, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	work_priorities_overlay.add_child(scrim)

	work_priorities_panel = PanelContainer.new()
	work_priorities_panel.name = "WorkPriorities"
	work_priorities_panel.set_anchors_preset(Control.PRESET_CENTER)
	work_priorities_panel.position = Vector2(-340, -235)
	work_priorities_panel.size = Vector2(680, 470)
	work_priorities_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	work_priorities_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("72cdb8"), 3))
	work_priorities_overlay.add_child(work_priorities_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	work_priorities_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_stack)
	var eyebrow := Label.new()
	eyebrow.name = "WorkPrioritiesEyebrow"
	eyebrow.text = "WORK TAB // RANK 1 FIRST · TIES GO BY JOB"
	eyebrow.add_theme_color_override("font_color", Color("8faeb7"))
	title_stack.add_child(eyebrow)
	var title := Label.new()
	title.text = "WORK PRIORITIES"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("75d4b4"))
	title_stack.add_child(title)
	work_priorities_close_button = Button.new()
	work_priorities_close_button.name = "CloseWorkPriorities"
	work_priorities_close_button.text = "CLOSE [P / ESC]"
	work_priorities_close_button.custom_minimum_size = Vector2(142, 38)
	work_priorities_close_button.pressed.connect(show_work_priorities.bind(false))
	title_row.add_child(work_priorities_close_button)

	var explanation := Label.new()
	explanation.name = "WorkPrioritiesHelp"
	# Mirrors JobSystem._job_claims_before: rank, then _job_priority kind order, then distance.
	explanation.text = "Like RimWorld: click to cycle 1 (do first) → 2 → 3 → 4 → OFF. Same rank goes by job, not column: build, food, rubble, then digs; nearest first. Everyone starts at 3 for all four — auto work runs without opening this board. Draft/force is optional override. Hatch urgency beats ranks; OFF still blocks. HAUL = salvage + food."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size.y = 42
	content.add_child(explanation)

	var matrix_panel := PanelContainer.new()
	matrix_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	matrix_panel.add_theme_stylebox_override("panel", _panel_style(Color("152129"), Color("3d5962")))
	content.add_child(matrix_panel)
	var matrix_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		matrix_margin.add_theme_constant_override(side, 10)
	matrix_panel.add_child(matrix_margin)
	work_priorities_grid = GridContainer.new()
	work_priorities_grid.name = "PriorityMatrix"
	work_priorities_grid.columns = 5
	work_priorities_grid.add_theme_constant_override("h_separation", 7)
	work_priorities_grid.add_theme_constant_override("v_separation", 6)
	matrix_margin.add_child(work_priorities_grid)

	work_priorities_summary = Label.new()
	work_priorities_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	work_priorities_summary.custom_minimum_size.y = 40
	content.add_child(work_priorities_summary)
	work_priorities_overlay.visible = false


func _rebuild_work_priority_rows() -> void:
	for child: Node in work_priorities_grid.get_children():
		child.free()
	work_priority_buttons.clear()
	var headers := ["RESIDENT", "DIG", "HAUL", "CRAFT", "COOK"]
	var header_widths := [120.0, 110.0, 110.0, 110.0, 110.0]
	for index in headers.size():
		var header := Label.new()
		header.text = headers[index]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.custom_minimum_size = Vector2(header_widths[index], 24)
		header.add_theme_color_override("font_color", Color("8faeb7"))
		work_priorities_grid.add_child(header)
	for resident: VaultResident in game.residents:
		var resident_label := Label.new()
		resident_label.text = "%s%s" % [resident.resident_name.to_upper(), "\nDRAFTED" if resident.drafted and resident.alive else ""]
		resident_label.tooltip_text = (
			"Resident %d · DRAFTED; priorities remain editable and apply after undraft." % resident.resident_id
			if resident.drafted and resident.alive
			else "Resident %d" % resident.resident_id
		)
		resident_label.custom_minimum_size = Vector2(120, 46)
		resident_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		resident_label.add_theme_color_override("font_color", Color("6f7d80") if not resident.alive else Color("e8f0ef"))
		work_priorities_grid.add_child(resident_label)
		for work_type: String in VaultResident.WORK_TYPES:
			var button := Button.new()
			button.name = "Priority_%d_%s" % [resident.resident_id, work_type.capitalize()]
			button.custom_minimum_size = Vector2(110, 46)
			button.disabled = not resident.alive
			button.pressed.connect(_on_work_priority_pressed.bind(resident.resident_id, work_type))
			var key := _work_priority_key(resident.resident_id, work_type)
			work_priority_buttons[key] = button
			work_priorities_grid.add_child(button)
	_configure_work_priority_focus()


func _work_priority_focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		for work_type: String in VaultResident.WORK_TYPES:
			var button := get_work_priority_button(resident.resident_id, work_type)
			if button != null and not button.disabled:
				controls.append(button)
	if work_priorities_close_button != null:
		controls.append(work_priorities_close_button)
	return controls


func _configure_work_priority_focus() -> void:
	var controls := _work_priority_focus_controls()
	if controls.is_empty():
		return
	for index in controls.size():
		var control := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		# Directional keyboard/gamepad navigation also stays inside the modal.
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_bottom = control.get_path_to(next)


func _focus_first_work_priority_control() -> void:
	var controls := _work_priority_focus_controls()
	if not controls.is_empty():
		controls[0].grab_focus()


func _work_priority_key(resident_id: int, work_type: String) -> String:
	return "%d:%s" % [resident_id, work_type]


func get_work_priority_button(resident_id: int, work_type: String) -> Button:
	return work_priority_buttons.get(_work_priority_key(resident_id, work_type)) as Button


func _build_briefing() -> void:
	briefing_overlay = Control.new()
	briefing_overlay.name = "BriefingOverlay"
	briefing_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	briefing_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(briefing_overlay)
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.025, 0.045, 0.055, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	briefing_overlay.add_child(scrim)
	briefing_panel = PanelContainer.new()
	briefing_panel.set_anchors_preset(Control.PRESET_CENTER)
	briefing_panel.offset_left = -280.0
	briefing_panel.offset_right = 280.0
	briefing_panel.offset_top = -220.0
	briefing_panel.offset_bottom = 220.0
	briefing_panel.custom_minimum_size = Vector2(560, 440)
	briefing_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	briefing_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("72cdb8"), 3))
	briefing_overlay.add_child(briefing_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	briefing_panel.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(shell)
	var title := Label.new()
	title.text = "VAULT WING 07 // SEAL STABILIZATION"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("75d4b4"))
	shell.add_child(title)
	wing_briefing_title = title
	briefing_sublevel_row = HBoxContainer.new()
	briefing_sublevel_row.add_theme_constant_override("separation", 8)
	briefing_sublevel_row.visible = false
	shell.add_child(briefing_sublevel_row)
	briefing_deeper_button = Button.new()
	briefing_deeper_button.text = "◀"
	briefing_deeper_button.tooltip_text = "Deeper sublevel"
	briefing_deeper_button.pressed.connect(step_sublevel.bind(-1))
	briefing_sublevel_row.add_child(briefing_deeper_button)
	briefing_sublevel_label = Label.new()
	briefing_sublevel_label.add_theme_color_override("font_color", Color("efc56b"))
	briefing_sublevel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_sublevel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing_sublevel_row.add_child(briefing_sublevel_label)
	briefing_shallower_button = Button.new()
	briefing_shallower_button.text = "▶"
	briefing_shallower_button.tooltip_text = "Shallower sublevel"
	briefing_shallower_button.pressed.connect(step_sublevel.bind(1))
	briefing_sublevel_row.add_child(briefing_shallower_button)
	briefing_perk_row = HBoxContainer.new()
	briefing_perk_row.add_theme_constant_override("separation", 8)
	briefing_perk_row.visible = false
	shell.add_child(briefing_perk_row)
	briefing_perk_prev_button = Button.new()
	briefing_perk_prev_button.text = "◀"
	briefing_perk_prev_button.tooltip_text = "Previous perk"
	briefing_perk_prev_button.pressed.connect(step_perk.bind(-1))
	briefing_perk_row.add_child(briefing_perk_prev_button)
	briefing_perk_label = Label.new()
	briefing_perk_label.add_theme_color_override("font_color", Color("9fd8c4"))
	briefing_perk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_perk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing_perk_row.add_child(briefing_perk_label)
	briefing_perk_next_button = Button.new()
	briefing_perk_next_button.text = "▶"
	briefing_perk_next_button.tooltip_text = "Next perk"
	briefing_perk_next_button.pressed.connect(step_perk.bind(1))
	briefing_perk_row.add_child(briefing_perk_next_button)
	briefing_record_label = Label.new()
	briefing_record_label.add_theme_color_override("font_color", Color("efc56b"))
	briefing_record_label.add_theme_font_size_override("font_size", 14)
	briefing_record_label.visible = false
	shell.add_child(briefing_record_label)
	var intro := Label.new()
	intro.text = "YOU designate dig/build/stockpile. THEY auto-claim from Dig/Haul/Craft/Cook defaults. Draft is optional. Survive seven days."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.y = 36
	shell.add_child(intro)
	var checklist_scroll := ScrollContainer.new()
	checklist_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	checklist_scroll.custom_minimum_size.y = 180
	checklist_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(checklist_scroll)
	checklist = RichTextLabel.new()
	checklist.bbcode_enabled = true
	checklist.fit_content = true
	checklist.scroll_active = false
	checklist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checklist_scroll.add_child(checklist)
	briefing_tips_label = Label.new()
	briefing_tips_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_tips_label.add_theme_color_override("font_color", Color("8faeb7"))
	briefing_tips_label.add_theme_font_size_override("font_size", 13)
	shell.add_child(briefing_tips_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	shell.add_child(buttons)
	briefing_load_button = Button.new()
	briefing_load_button.text = "LOAD"
	briefing_load_button.pressed.connect(func() -> void: game.load_game())
	buttons.add_child(briefing_load_button)
	briefing_close_button = Button.new()
	briefing_close_button.text = "CLOSE [ESC]"
	briefing_close_button.pressed.connect(show_briefing.bind(false))
	buttons.add_child(briefing_close_button)
	briefing_begin_button = Button.new()
	briefing_begin_button.text = "BEGIN SHIFT"
	briefing_begin_button.custom_minimum_size.x = 140
	briefing_begin_button.pressed.connect(func() -> void: game.begin_shift())
	buttons.add_child(briefing_begin_button)


func _build_outcome() -> void:
	_outcome_backdrop = ColorRect.new()
	_outcome_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outcome_backdrop.color = Color(0.02, 0.04, 0.05, 0.76)
	_outcome_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_outcome_backdrop.visible = false
	root.add_child(_outcome_backdrop)
	outcome_panel = PanelContainer.new()
	outcome_panel.set_anchors_preset(Control.PRESET_CENTER)
	outcome_panel.position = Vector2(-260, -145)
	outcome_panel.size = Vector2(520, 290)
	outcome_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	outcome_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	outcome_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("efc56b"), 3))
	root.add_child(outcome_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	outcome_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	outcome_title = Label.new()
	outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_title.add_theme_font_size_override("font_size", 26)
	content.add_child(outcome_title)
	outcome_grade = Label.new()
	outcome_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_grade.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_grade.add_theme_font_size_override("font_size", 17)
	outcome_grade.visible = false
	content.add_child(outcome_grade)
	outcome_record = Label.new()
	outcome_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_record.add_theme_font_size_override("font_size", 15)
	outcome_record.add_theme_color_override("font_color", Color("efc56b"))
	outcome_record.visible = false
	content.add_child(outcome_record)
	outcome_best = Label.new()
	outcome_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_best.add_theme_font_size_override("font_size", 14)
	outcome_best.add_theme_color_override("font_color", Color("efc56b"))
	outcome_best.visible = false
	content.add_child(outcome_best)
	outcome_text = Label.new()
	outcome_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_text.custom_minimum_size.y = 92
	content.add_child(outcome_text)
	outcome_invested = Label.new()
	outcome_invested.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_invested.add_theme_color_override("font_color", Color("efc56b"))
	outcome_invested.visible = false
	content.add_child(outcome_invested)
	var row := HBoxContainer.new()
	_outcome_legacy_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var load_button := Button.new()
	load_button.text = "LOAD LAST CHECKPOINT"
	load_button.pressed.connect(func() -> void: game.load_game())
	row.add_child(load_button)
	var restart_button := Button.new()
	restart_button.text = "NEW WING"
	restart_button.pressed.connect(func() -> void: game.new_wing())
	row.add_child(restart_button)
	outcome_replay_button = Button.new()
	outcome_replay_button.name = "ReplayWingButton"
	outcome_replay_button.text = "REPLAY WING"
	outcome_replay_button.visible = false
	outcome_replay_button.pressed.connect(replay_wing)
	row.add_child(outcome_replay_button)
	var recap_row := HBoxContainer.new()
	_outcome_recap_row = recap_row
	recap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	recap_row.add_theme_constant_override("separation", 12)
	content.add_child(recap_row)
	outcome_resume_button = Button.new()
	outcome_resume_button.text = "Continue with survivors"
	_style_outcome_recap_button(outcome_resume_button)
	outcome_resume_button.pressed.connect(func() -> void: game.resume_after_death())
	recap_row.add_child(outcome_resume_button)
	outcome_retry_button = Button.new()
	outcome_retry_button.text = "Retry from day checkpoint"
	_style_outcome_recap_button(outcome_retry_button)
	outcome_retry_button.pressed.connect(func() -> void: game.retry_day_checkpoint())
	recap_row.add_child(outcome_retry_button)
	outcome_retry_reason = Label.new()
	outcome_retry_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_retry_reason.add_theme_color_override("font_color", Color("b8bdc9"))
	outcome_retry_reason.visible = false
	content.add_child(outcome_retry_reason)
	_size_outcome_recap_buttons()
	outcome_panel.visible = false


func _size_outcome_recap_buttons() -> void:
	# Reset the old equal width before measuring a new resident's longer label.
	for button: Button in [outcome_resume_button, outcome_retry_button]:
		button.custom_minimum_size.x = 0
	var button_width := maxf(outcome_resume_button.get_combined_minimum_size().x, outcome_retry_button.get_combined_minimum_size().x)
	for button: Button in [outcome_resume_button, outcome_retry_button]:
		button.custom_minimum_size.x = button_width


func _style_outcome_recap_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var styles := {
		"normal": _panel_style(Color("263e46"), Color("8faeb7")),
		"hover": _panel_style(Color("35545b"), Color("efc56b")),
		"pressed": _panel_style(Color("1b3038"), Color("efc56b")),
		"disabled": _panel_style(Color("1c2b32"), Color("45616a")),
		# Focus overlays the current state; a light tint keeps hover/press visible.
		"focus": _panel_style(Color(Color("efc56b"), 0.10), Color("efc56b"), 2),
	}
	for state: String in styles:
		var style: StyleBoxFlat = styles[state]
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("e0efe9"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffffff"))
	button.add_theme_color_override("font_focus_color", Color("ffffff"))
	button.add_theme_color_override("font_disabled_color", Color("8faeb7"))


# End-of-run line (midgame slice 4): salvage spent on the Mk II fits still standing. Derived
# from each fixture's saved upgrade_tier, so a won or lost save reloads to the same number.
var outcome_invested: Label


func mk2_salvage_invested() -> int:
	var total := 0
	for building: VaultBuilding in game.buildings:
		if building.complete and building.upgrade_tier >= VaultBuilding.UPGRADE_TIER_MAX:
			total += building.get_upgrade_cost()
	return total


func _build_breach_warning() -> void:
	breach_warning_panel = PanelContainer.new()
	breach_warning_panel.name = "BreachWarning"
	breach_warning_panel.set_anchors_preset(Control.PRESET_CENTER)
	breach_warning_panel.position = Vector2(-285, -150)
	breach_warning_panel.size = Vector2(570, 300)
	breach_warning_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	breach_warning_panel.add_theme_stylebox_override("panel", _panel_style(Color("211a14"), Color("efc56b"), 3))
	root.add_child(breach_warning_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	breach_warning_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "PRIORITY INCIDENT // MAINTENANCE HATCH"
	eyebrow.add_theme_color_override("font_color", Color("efc56b"))
	content.add_child(eyebrow)
	var title := Label.new()
	title.text = "PRESSURE SURGE DETECTED"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("fff1ba"))
	content.add_child(title)
	var body := Label.new()
	body.text = "The east maintenance hatch is beginning to fail. The shift is paused at 1× and the hatch is focused. Keep 4 salvage available and at least one HAUL and CRAFT priority above OFF: residents will deliver an emergency patch, then reinforce it before the 20-second grace period expires and vault oxygen begins venting."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.y = 100
	content.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)
	var inspect_button := Button.new()
	inspect_button.text = "FOCUS HATCH"
	inspect_button.pressed.connect(func() -> void:
		game.acknowledge_breach_warning(false)
	)
	buttons.add_child(inspect_button)
	breach_resume_button = Button.new()
	breach_resume_button.text = "RESUME RESPONSE"
	breach_resume_button.pressed.connect(func() -> void:
		game.acknowledge_breach_warning(true)
	)
	buttons.add_child(breach_resume_button)
	breach_warning_panel.visible = false


func refresh() -> void:
	_update_idle_crew_tracking()
	if game == null or clock_label == null:
		return
	clock_label.text = game.day_cycle.get_clock_text() if not game.keep_running else keep_running_clock_text()
	resource_label.text = "MEALS %d (+%d)%s  RAW %d (+%d)  SALVAGE %d" % [
		game.food_system.meals,
		game.job_system.get_pending_meals(),
		_meal_runway_text(),
		game.food_system.raw_food,
		game.job_system.get_pending_raw_food(),
		game.food_system.salvage,
	]
	resource_label.tooltip_text = "Stored inventory; values in parentheses are produced food still awaiting Haul delivery. DAYS = stored + pending meals at the living crew's food drain (normally one meal a day each; FRUGAL eats 15% less)."
	command_buttons.zone.text = "ZONE %d" % game.map_grid.stockpile_cells.size()
	command_buttons.zone.tooltip_text = "Stockpile: %d cells. Salvage, raw food, and meals prefer reachable zones; otherwise Salvage Bay / chamber center. Click/drag to paint; CANCEL [X] clears." % game.map_grid.stockpile_cells.size()
	var objective_step: Dictionary = _refresh_objective()
	_displayed_next_step = objective_step
	var step: Dictionary = objective_step
	power_label.text = game.power_grid.get_status_text()
	power_label.add_theme_color_override("font_color", Color("ef6860") if game.power_grid.brownout_active else Color("75d4b4"))
	_refresh_power_detail()
	pause_button.text = "RESUME" if game.user_paused else "PAUSE"
	var active_help := game.status_message if game.status_message_left > 0.0 else game._tool_help(game.active_tool)
	if step.is_empty() and not game.ended:
		# The objective showed an outcome line; the help still follows Next.
		step = _primary_next_step() if not game.keep_running else keep_running_next_step()
	var tool_label := game.active_tool.to_upper()
	if game.ended and ((game.wing_seed != 0 and not game.has_post_outcome_status()) or (game.status_message_left <= 0.0 and game.active_tool == "select")):
		# Seeded actions replace stale live messages, then yield to fresh outcome feedback.
		tool_label = "SHIFT ENDED"
		active_help = "LOAD LAST CHECKPOINT, NEW WING or REPLAY WING" if game.wing_seed != 0 else "LOAD LAST CHECKPOINT or NEW WING"
	elif game.status_message_left <= 0.0 and game.active_tool == "select":
		var select_help := "Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
		if not game.tutorial_open:
			var next_help := str(step.get("help", "")).strip_edges()
			if not next_help.is_empty():
				active_help = "%s %s" % [next_help, select_help]
			else:
				active_help = select_help
		else:
			active_help = select_help
	tool_status.text = "%s // %s" % [tool_label, active_help]
	tool_status.tooltip_text = tool_status.text
	var suggested := str(step.get("tool", ""))
	_open_suggested_tab(suggested)
	for key: String in command_buttons:
		var button: Button = command_buttons[key]
		if key == game.active_tool:
			button.modulate = Color("efc56b")
		elif key == suggested and not game.tutorial_open and not game.ended:
			button.modulate = Color("75d4b4")
		else:
			button.modulate = Color.WHITE
	for key: String in command_buttons:
		var button: Button = command_buttons[key]
		button.disabled = game.tutorial_open or is_help_open() or game.ended
	if help_button != null:
		help_button.disabled = (
			game.tutorial_open
			or game.ended
			or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
		)
	if work_priorities_button != null:
		work_priorities_button.disabled = (
			game.tutorial_open
			or game.ended
			or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
		)
	if lighting_overlay_button != null:
		lighting_overlay_button.disabled = (
			game.tutorial_open
			or is_help_open()
			or game.ended
			or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
		)
	_refresh_upgrade_offer()
	_refresh_idle_start()
	_refresh_comfort()
	_refresh_food_plan()
	_refresh_annex()
	_refresh_roster()
	_refresh_work_priorities_board()
	_refresh_crew_mood()
	_refresh_lighting()
	_refresh_oxygen()
	_refresh_breach()
	_refresh_inspector()
	_refresh_alerts(objective_step)
	_refresh_checklist()


func _open_suggested_tab(suggested: String) -> void:
	if (
		game.tutorial_open
		or is_help_open()
		or game.ended
		or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
		or is_work_priorities_open()
	):
		return
	if _has_processed_suggested_tool and suggested == _last_processed_suggested_tool:
		return
	_last_processed_suggested_tool = suggested
	_has_processed_suggested_tool = true
	if suggested in ["bed", "lamp", "generator", "grow", "kitchen", "air", "medical", "rec"]:
		_set_architect_tab("build")


func _toggle_details_rail() -> void:
	_details_expanded = not _details_expanded
	if details_box != null:
		details_box.visible = _details_expanded
	if details_toggle != null:
		details_toggle.text = "DETAILS ▾" if _details_expanded else "DETAILS ▸"
	if summary_separator != null:
		summary_separator.visible = not _details_expanded
	if _details_expanded and right_scroll != null:
		right_scroll.scroll_vertical = 0
	_refresh_alert_details()


func _unfinished_charge_count() -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR and not building.complete and not building.is_emergency_core:
			count += 1
	return count


func _salvage_shortfall(kind: int) -> int:
	var needed := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and not building.complete and not building.is_emergency_core:
			needed += building.get_cost() - building.delivered - game.job_system.get_build_supply_in_transit(building.building_id)
	if needed <= 0:
		return 0
	var spendable: int = game.food_system.salvage - game.job_system.get_breach_salvage_reserve()
	return maxi(0, needed - spendable)


func _salvage_dig_tiles(shortfall: int) -> int:
	return _dig_tiles_after_rubble(shortfall, game.job_system.get_uncredited_rubble())


# A funding tip may wait only for actual designated digging or enough rubble,
# including salvage already being carried. Keep this rule shared by every fund tip.
func _fund_salvage_step(name: String, shortfall: int, help: String, rubble := -1) -> Dictionary:
	if rubble < 0:
		rubble = game.job_system.get_uncredited_rubble()
	var tiles := _dig_tiles_after_rubble(shortfall, rubble)
	if game.map_grid.dig_marks.is_empty() and rubble < shortfall:
		tiles = maxi(1, tiles)
	return {
		"text": "Next: YOU mark %d rock [E] · THEY fund the %s" % [tiles, name] if tiles > 0 else "Next: YOU leave Dig + Haul on · THEY fund the %s" % name,
		"help": help,
		"tool": "dig" if tiles > 0 else "select",
	}


func _dig_tiles_after_rubble(shortfall: int, rubble: int) -> int:
	var after_rubble := shortfall - rubble
	if after_rubble <= 0:
		return 0
	return ceili(float(after_rubble) / DIG_SALVAGE_YIELD) - game.map_grid.dig_marks.size()


# Building a Nutrient Station and cooking takes most of a day; 2.5 days of food is the lead
# time an idle wing needs to hear about food before the Rec tip (QA 2026-10-18c #5).
const FOOD_LEAD_DAYS := 2.5
const FOOD_PER_DAY := 60.0
const FOOD_PER_MEAL := 60.0
# Food also compares production runway, but naming requires this own deadline.
const NEXT_DEATH_WARNING_SECONDS := 60.0
const STARVING_RUNWAY_S := NEXT_DEATH_WARNING_SECONDS
const STARVING_SWITCH_S := 10.0
const FOOD_SHORT_LABEL := "food runway short"
# The forecast turns on at the runway trigger exactly as before. Once on it
# holds until the runway clears the trigger by this much AND this long has
# passed (whichever is later). A named resident (own death under
# STARVING_RUNWAY_S) always overrides the hold.
const FOOD_FORECAST_RELEASE_S := 15.0
const FOOD_FORECAST_MIN_HOLD_S := 5.0

# 03/4242 RELAY LUMEN: waiting for NO MEALS at 217.3 s left only 51 s
# before Ari died at 268.3 s (CRITICAL at 230 s). Even an immediately placed
# Charge Node took 26.1 s (ready at 243.4 s), leaving only 24.9 s for
# Grow + raw haul + Cook + meal haul. Add 20 s for queued work and staggered
# meals ON TOP OF the supply/build, real 9 s Grow cycle, Cook and delivery
# lead, rather than waiting for that failed 51 s death window. A larger 75 s
# buffer interrupts the healthy opening with 40–80 s of stock; 20 s preserves
# that recovery window while warning before the larder runs out.
const FOOD_RUNWAY_MARGIN_SECONDS := 20.0
# Interrupted workers can need floor rest (48 rest/day: 0 -> 25 takes 20.8 s),
# a seven-second break and turns at the shared Rec Console. Budget one 40 s
# sim day before funding/building resumes, separately from pantry contingency.
const FOOD_WORK_RECOVERY_SECONDS := DayCycle.SECONDS_PER_DAY
# Air recovery includes a long salvage/supply chain (05: 171 s warning,
# recycler powered at 248 s). Its existing forecast needs its own buffer.
const AIR_RECOVERY_MARGIN_SECONDS := 75.0


# Shared consumption rate for the HUD, pantry forecast and crew's food reserve.
func _crew_meals_per_day() -> float:
	var consumption := 0.0
	for resident: VaultResident in game.residents:
		if resident.alive:
			consumption += FOOD_PER_DAY * resident.needs.food_drain_scale / FOOD_PER_MEAL
	return consumption


# Shared stock and already-produced food, in meals / living crew's meals per
# second. Cooking consumes raw only at completion, so its input is ALREADY in
# raw_food: adding another meal for a COOK job would double count it. Pending
# haul totals include cargo in transit. Future Grow cycles are not stock.
func _food_runway_seconds() -> float:
	var consumption := _crew_meals_per_day() / DayCycle.SECONDS_PER_DAY
	if consumption <= 0.0:
		return INF
	var meals := float(game.food_system.meals + game.job_system.get_pending_meals())
	if game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) > 0:
		meals += floorf(float(game.food_system.raw_food + game.job_system.get_pending_raw_food()) / FoodSystem.COOK_INPUT) * FoodSystem.COOK_OUTPUT
	return meals / consumption


func _food_work_seconds(work: String, amount: float) -> float:
	var fastest := 0.0
	for resident: VaultResident in game.residents:
		if resident.alive:
			# Enabling work or undrafting is itself an available player fix. Estimate
			# the work after that action, rather than using the .35 floor for an
			# otherwise healthy all-drafted crew.
			fastest = maxf(fastest, resident.get_work_multiplier() * resident.get_trait_factor(work))
	return amount / maxf(0.35, fastest)


func _food_delivery_seconds(cell: Vector2i) -> float:
	var stock := game.map_grid.nearest_stockpile(cell)
	if stock.x < 0:
		stock = game.job_system._stockpile_cell()
	var path := game.map_grid.find_path(cell, stock)
	if path.is_empty():
		return INF
	# A worker walks out to collect and returns with the output. Each handoff
	# also crosses a simulation tick; use the same movement speed as residents.
	return 2.0 * float(path.size()) * MapGrid.TILE_SIZE / VaultResident.MOVE_SPEED + 2.0 * VaultGame.SIMULATION_TICK


func _food_funding_seconds(cost: int) -> float:
	var reserve := 0 if game.breach_system.is_sealed() else BreachSystem.PATCH_COST - game.breach_system.patch_delivered
	var shortfall := maxi(0, cost + reserve - game.food_system.salvage - game.job_system.get_uncredited_rubble())
	if shortfall == 0:
		return 0.0
	var tiles := ceili(float(shortfall) / DIG_SALVAGE_YIELD)
	var workers := 0
	for resident: VaultResident in game.residents:
		if not resident.alive or resident.drafted or resident.sleeping or resident.recreating or resident.stress_break_left > 0.0:
			continue
		if resident.current_job_type not in [JobSystem.JobType.COOK, JobSystem.JobType.HAUL_RAW_FOOD, JobSystem.JobType.HAUL_MEAL] and resident.medical_bed_id < 0:
			workers += 1
	workers = maxi(1, workers)
	# Food delivery and sleep already occupy crew: living mouths are not all
	# available parallel miners. Dig work is eight seconds per rock. Crew can excavate different cells
	# concurrently, then Haul must credit the rubble before supply can start.
	var rounds := ceilf(float(tiles) / workers)
	return rounds * _food_work_seconds("dig", 8.0) + _food_delivery_seconds(MapGrid.CHAMBER.get_center())


func _food_fixture_seconds(kind: int) -> float:
	var fastest := INF
	for building: VaultBuilding in game.buildings:
		if building.kind != kind:
			continue
		if building.complete:
			if kind == VaultBuilding.Kind.GENERATOR:
				# Called for a capacity deficit: existing output is already spent.
				continue
			return 0.0
		var supply := _food_delivery_seconds(building.cell) if not building.is_supplied() else 0.0
		fastest = minf(fastest, _food_funding_seconds(maxi(0, building.get_cost() - building.delivered - game.job_system.get_build_supply_in_transit(building.building_id))) + supply + _food_work_seconds("craft", building.construction_left))
	# New food fixtures take 8 work seconds (VaultBuilding.get_build_time).
	return fastest if is_finite(fastest) else _food_funding_seconds(int(VaultBuilding.COSTS[kind])) + _food_work_seconds("craft", 8.0) + _food_delivery_seconds(MapGrid.CHAMBER.get_center())


# Budget a dependency once: existing generators cannot pay for added capacity,
# and delivered/in-transit blueprint supplies are no longer loose salvage.
func _food_remaining_cost(kind: int, added_capacity := false) -> int:
	var remaining := int(VaultBuilding.COSTS[kind])
	for building: VaultBuilding in game.buildings:
		if building.kind != kind:
			continue
		if building.complete:
			if not added_capacity:
				return 0
			continue
		remaining = mini(remaining, maxi(0, building.get_cost() - building.delivered - game.job_system.get_build_supply_in_transit(building.building_id)))
	return remaining


# A short pantry cannot fund the kitchen, power and next harvest independently
# with the same salvage. If that shared funding also crosses a predicted stress
# break, food needs the real Rec recovery first. Forecast it before the kitchen
# is powered: waiting until its workers actually break made 05 miss its harvest.
# Funded openings incur no speculative Rec delay.
func _food_chain_work_lead(food_seconds: float) -> float:
	var cost := _food_remaining_cost(VaultBuilding.Kind.KITCHEN) + _food_remaining_cost(VaultBuilding.Kind.GROW_TRAY)
	var demand := 0
	for kind: int in [VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY]:
		if game.get_powered_building_count(kind) == 0:
			demand += int(VaultBuilding.POWER_DEMAND[kind])
	if demand > game.power_grid.supply - game.power_grid.served:
		cost += _food_remaining_cost(VaultBuilding.Kind.GENERATOR, true)
	var funding := _food_funding_seconds(cost)
	if funding <= 0.0:
		return 0.0
	var rec := _food_fixture_seconds(VaultBuilding.Kind.RECREATION_CONSOLE)
	var horizon := food_seconds + funding + rec + FOOD_WORK_RECOVERY_SECONDS + FOOD_RUNWAY_MARGIN_SECONDS
	for resident: VaultResident in game.residents:
		if not resident.alive or resident.drafted or resident.sleeping or resident.medical_bed_id >= 0:
			continue
		var loss := -resident.needs._get_mood_delta_per_day(game.is_resident_lit(resident), false, game.oxygen_system.is_low()) / DayCycle.SECONDS_PER_DAY
		var projected := resident.needs.mood - loss * horizon
		# Match ResidentNeeds' future tired penalty; current loss already includes
		# it below 30 rest. Rest drains 34/day while this worker stays awake.
		if resident.needs.rest >= 30.0:
			var tired_at := (resident.needs.rest - 30.0) / (34.0 / DayCycle.SECONDS_PER_DAY)
			projected -= ResidentNeeds.LOW_NEED_MOOD_LOSS_PER_DAY / DayCycle.SECONDS_PER_DAY * maxf(0.0, horizon - tired_at)
		if projected <= ResidentNeeds.BREAK_MOOD_THRESHOLD:
			return funding + rec + FOOD_WORK_RECOVERY_SECONDS
	return funding


# One existing switch is quicker than supplying/building another generator.
# Only shed a decorative load if it frees enough power for the food fixture;
# life support is never a candidate.
func _food_power_release_step(kind: int) -> Dictionary:
	# Keep the last light: dark crew repeatedly break before food work.
	if game.get_powered_building_count(VaultBuilding.Kind.LAMP) < 2:
		return {}
	var needed: int = VaultBuilding.POWER_DEMAND[kind]
	var available := game.power_grid.supply - game.power_grid.served
	for lamp: VaultBuilding in game.buildings:
		if lamp.kind == VaultBuilding.Kind.LAMP and lamp.complete and lamp.powered and lamp.get_power_demand() > 0 and available + lamp.get_power_demand() >= needed:
			return _food_step({
				"text": "Next: YOU disable a Lumen · THEY power the kitchen" if kind == VaultBuilding.Kind.KITCHEN else "Next: YOU disable a Lumen · THEY power the Grow Tray",
				"help": "Select a powered Lumen and click DISABLE to free power for food now. Restore lighting once a Charge Node is available.",
				"tool": "select",
			})
	return {}


# Before placing another food/power blueprint, fund it without spending the
# hatch's four salvage. Waiting for stock here is a player action sequence;
# changing the job system's reserve would silently alter plain idle play.
func _food_prebuild_step(kind: int, placement: Dictionary) -> Dictionary:
	if game.breach_system.is_sealed():
		return placement
	var reserve := maxi(0, BreachSystem.PATCH_COST - game.breach_system.patch_delivered - game.job_system.get_breach_supply_in_transit())
	var shortfall := maxi(0, int(VaultBuilding.COSTS[kind]) + reserve - game.food_system.salvage)
	if shortfall == 0:
		return placement
	var name: String = VaultBuilding.KIND_NAMES[kind]
	return _food_step(_fund_salvage_step(name, shortfall,
		"Fund the %s before placing it, keeping %d salvage for the hatch. Each dug rock yields %d salvage once hauled." % [name, reserve, DIG_SALVAGE_YIELD]))


func _food_blueprint_in_progress(kind: int) -> bool:
	for building: VaultBuilding in game.buildings:
		if building.kind != kind or building.complete or not building.is_supplied():
			continue
		for job: Dictionary in game.job_system.jobs:
			if not bool(job.done) and int(job.type) == JobSystem.JobType.BUILD and int(job.building_id) == building.building_id and int(job.reserved_by) > 0:
				return true
	return false


func _food_fix_plan(rescue_seconds := INF) -> Dictionary:
	var kitchen := _kitchen_recovery_step()
	var kitchen_seconds := _food_fixture_seconds(VaultBuilding.Kind.KITCHEN)
	if game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 0:
		var available := game.power_grid.supply - game.power_grid.served
		if available < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.KITCHEN]) and _food_power_release_step(VaultBuilding.Kind.KITCHEN).is_empty():
			kitchen_seconds += _food_fixture_seconds(VaultBuilding.Kind.GENERATOR)
	var kitchen_building := _food_blueprint_in_progress(VaultBuilding.Kind.KITCHEN) and _has_eligible_worker("cook") and _has_eligible_worker("haul")
	if kitchen_building:
		# Construction already has a worker: parallelize its next blocker rather
		# than repeat "leave Craft on" until the kitchen is complete and shed.
		if game.power_grid.supply - game.power_grid.served < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.KITCHEN]):
			if not _food_blueprint_in_progress(VaultBuilding.Kind.GENERATOR):
				var power_step := _charge_finish_step() if _unfinished_charge_count() > 0 else {
					"text": "Next: YOU place a Charge Node · THEY power the kitchen",
					"help": "The grid lacks available power for the Nutrient Station. Place a Charge Node to add 7 power.",
					"tool": "generator",
				}
				if _unfinished_charge_count() == 0:
					power_step = _food_prebuild_step(VaultBuilding.Kind.GENERATOR, power_step)
				return {"step": _food_step(power_step), "seconds": kitchen_seconds + _food_work_seconds("cook", 4.0) + _food_delivery_seconds(MapGrid.CHAMBER.get_center())}
		kitchen = {}
	var delivery := _food_delivery_seconds(MapGrid.CHAMBER.get_center())
	var cook := _food_work_seconds("cook", 4.0)
	for resident: VaultResident in game.residents:
		if resident.alive and resident.current_job_type == JobSystem.JobType.COOK:
			cook = minf(cook, maxf(0.0, 4.0 - resident.work_accumulator) / (resident.get_work_multiplier() * resident.get_trait_factor("cook")))
	var cooking := false
	for resident: VaultResident in game.residents:
		if resident.alive and resident.current_job_type == JobSystem.JobType.COOK:
			cooking = true
	var raw := game.food_system.raw_food + game.job_system.get_pending_raw_food()
	var automatic_food := kitchen.is_empty() and _has_eligible_worker("cook") and _has_eligible_worker("haul") and (cooking or game.job_system.get_pending_meals() > 0 or kitchen_building)
	if game.job_system.get_pending_meals() > 0 and not automatic_food:
		return {"step": _meal_recovery_step(true), "seconds": delivery}
	if raw >= FoodSystem.COOK_INPUT and not automatic_food:
		return {"step": kitchen if not kitchen.is_empty() else _meal_recovery_step(true),
			"seconds": kitchen_seconds + cook + delivery + (delivery if game.food_system.raw_food == 0 else 0.0)}
	if not kitchen.is_empty():
		return {"step": kitchen, "seconds": kitchen_seconds + cook + delivery}
	# There is no forage/mark-food tool in this game (DIG yields salvage).
	# Grow is the next actual source. Include unfinished construction, restoring
	# power, the tray's remaining real cycle (Mk I 9 s / Mk II 6 s), raw haul,
	# cooking and meal haul, rather than treating power restoration as a meal.
	var grow_seconds := INF
	for tray: VaultBuilding in game.buildings:
		if tray.kind != VaultBuilding.Kind.GROW_TRAY:
			continue
		# Include disabled trays: ENABLE immediately recalculates power, resuming
		# paused progress once powered. Completed trays need no supply/build time.
		var ready := 0.0 if tray.complete else _food_fixture_seconds(VaultBuilding.Kind.GROW_TRAY)
		if not tray.powered and game.power_grid.supply - game.power_grid.served < tray.get_base_power_demand() and _food_power_release_step(VaultBuilding.Kind.GROW_TRAY).is_empty():
			ready += _food_fixture_seconds(VaultBuilding.Kind.GENERATOR)
		grow_seconds = minf(grow_seconds, ready + maxf(0.0, tray.get_grow_seconds() - tray.production_progress) + _food_delivery_seconds(tray.cell))
	if not is_finite(grow_seconds):
		grow_seconds = _food_fixture_seconds(VaultBuilding.Kind.GROW_TRAY) + FoodSystem.GROW_SECONDS + delivery
		if game.power_grid.supply - game.power_grid.served < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.GROW_TRAY]) and _food_power_release_step(VaultBuilding.Kind.GROW_TRAY).is_empty():
			grow_seconds += _food_fixture_seconds(VaultBuilding.Kind.GENERATOR)
	grow_seconds = maxf(grow_seconds, kitchen_seconds) + cook + delivery
	var rescue_budget := minf(rescue_seconds, _food_runway_seconds())
	if grow_seconds > rescue_budget:
		# A switch restores production, not an edible meal. Even a completed
		# tray must cover its remaining cycle, raw haul, Cook and meal haul.
		# Work already underway still offers a faster rescue than the next crop.
		var ready: Dictionary = {}
		if game.job_system.get_pending_meals() > 0:
			ready = {"step": _food_step({
				"text": "Next: YOU enable Haul · THEY deliver food" if not _has_eligible_worker("haul") else "Next: YOU leave Haul on · THEY deliver food",
				"help": "Keep Haul enabled on a living, undrafted resident. Cooked meals are waiting for delivery.",
				"tool": "select",
			}), "seconds": delivery}
		var raw_seconds := kitchen_seconds + cook + delivery + (delivery if game.food_system.raw_food < FoodSystem.COOK_INPUT else 0.0)
		if raw >= FoodSystem.COOK_INPUT and (ready.is_empty() or raw_seconds < float(ready.seconds)):
			ready = {"step": kitchen if not kitchen.is_empty() else _meal_recovery_step(true), "seconds": raw_seconds}
		if not ready.is_empty() and float(ready.seconds) <= rescue_budget:
			ready["rescue"] = true
			return ready
		return {"step": _food_step({
			"text": "Next: nothing lands in time · keep crew fed where possible",
			"help": "No available food fix can deliver a meal within the food runway. Keep Cook and Haul enabled to feed crew where possible.",
			"tool": "select",
			"too_late": true,
		}), "seconds": grow_seconds}
	# When cooking/delivery is already running, those meals are in runway.
	# Lead with the next source while they still cover construction, rather
	# than repeating an already-satisfied Cook instruction until raw hits zero.
	var step := _meal_recovery_step(true)
	if automatic_food:
		step = _grow_recovery_step()
	if str(step.get("tool", "")) == "grow":
		step = _food_prebuild_step(VaultBuilding.Kind.GROW_TRAY, step)
	var restores_tray := bool(step.get("restores_existing_tray", false))
	if not restores_tray and _salvage_shortfall(VaultBuilding.Kind.GROW_TRAY) > 0:
		step = _food_step(_fund_blueprint_step(VaultBuilding.Kind.GROW_TRAY))
	return {"step": step, "seconds": grow_seconds}


# Days the living crew can eat from stored meals plus what is already in their bellies.
func _crew_food_days() -> float:
	var consumption := _crew_meals_per_day()
	var belly := 0.0
	for resident: VaultResident in game.residents:
		if resident.alive:
			belly += resident.needs.food
	if consumption <= 0.0:
		return INF
	return (belly + game.food_system.meals * FOOD_PER_MEAL) / (FOOD_PER_MEAL * consumption)


# Allocate only stored rations, in the order crew reach the automatic eating
# threshold. One remaining meal must not hide another resident's starvation.
# Stop once the remaining rations cannot affect the warning horizon.
func _food_depletion_times() -> Dictionary:
	var depletion: Dictionary = {}
	var next_meal: Dictionary = {}
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		var rate := FOOD_PER_DAY * resident.needs.food_drain_scale / DayCycle.SECONDS_PER_DAY
		depletion[resident.resident_id] = resident.needs.food / rate if rate > 0.0 else INF
		if not resident.drafted and rate > 0.0:
			next_meal[resident.resident_id] = maxf(0.0, (resident.needs.food - MED_BED_MIN_FOOD) / rate)
	for _meal in game.food_system.meals:
		var first_id := -1
		var first_at := NEXT_DEATH_WARNING_SECONDS
		for id: int in next_meal:
			if float(next_meal[id]) < first_at:
				first_id = id
				first_at = next_meal[id]
		if first_id < 0:
			break
		var resident := game.get_resident_by_id(first_id)
		var ration_seconds := FOOD_PER_MEAL / (FOOD_PER_DAY * resident.needs.food_drain_scale / DayCycle.SECONDS_PER_DAY)
		depletion[first_id] = float(depletion[first_id]) + ration_seconds
		next_meal[first_id] = maxf(0.0, float(depletion[first_id]) - MED_BED_MIN_FOOD * ration_seconds / FOOD_PER_MEAL)
	return depletion


# Project only the existing drains, not future jobs or buildings.
# Air below 15% can already be recovering, so its damage has an end as well as
# an onset. Combining the intervals accounts for low HP and overlapping drains.
func _projected_death_seconds(resident: VaultResident, food_seconds: float, relieved := "", only_food := false) -> float:
	var needs := resident.needs
	var medical := resident.medical_bed_id >= 0 and resident.state == "Rest-Medical"
	var loss := -JobSystem.MEDICAL_HP_PER_SECOND if medical and not only_food else 0.0
	if not only_food and relieved != "mood" and needs.mood <= ResidentNeeds.SEVERE_MOOD_THRESHOLD:
		loss += 5.0 / DayCycle.SECONDS_PER_DAY
	var changes: Array[Vector2] = []
	if not only_food and relieved != "rest" and not resident.sleeping and not medical:
		if needs.rest <= 0.0 or resident.drafted:
			changes.append(Vector2(needs.rest / (34.0 / DayCycle.SECONDS_PER_DAY), 30.0 / DayCycle.SECONDS_PER_DAY))
	if relieved != "food" and is_finite(food_seconds):
		changes.append(Vector2(food_seconds, 160.0 / DayCycle.SECONDS_PER_DAY))
	if not only_food and relieved != "air":
		var oxygen := game.oxygen_system
		var crossing := oxygen.get_seconds_to_critical_crossing()
		if oxygen.is_critical():
			if oxygen.net_rate <= 0.0 or oxygen.oxygen < OxygenSystem.CRITICAL_OXYGEN_THRESHOLD:
				changes.append(Vector2(0.0, OxygenSystem.SUFFOCATION_DAMAGE_PER_SECOND))
				if oxygen.net_rate > 0.0 and crossing >= 0.0:
					changes.append(Vector2(crossing, -OxygenSystem.SUFFOCATION_DAMAGE_PER_SECOND))
		elif oxygen.net_rate < 0.0 and crossing >= 0.0:
			changes.append(Vector2(crossing, OxygenSystem.SUFFOCATION_DAMAGE_PER_SECOND))
	changes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var health := needs.health
	var elapsed := 0.0
	for change: Vector2 in changes:
		var interval := float(change.x) - elapsed
		if loss > 0.0 and health / loss <= interval:
			return elapsed + health / loss
		health = clampf(health - loss * interval, 0.0, 100.0)
		elapsed = change.x
		loss += change.y
	return elapsed + health / loss if loss > 0.0 else INF


# A deliberately optimistic impossibility proof for can_still_win_shift.
# Next's `too_late` means pantry runway misses a production estimate, not that
# every resident must die. Require no food anywhere, then grant instant power,
# construction, Mk II upgrades, cooking and delivery. Even an imaginary new tray
# still needs its six-second cycle; existing trays keep their growth fraction.
# If all crew starve before even that raw harvest AND before day 7, no meal fix
# can save the shift. Ignore remediable rest/mood/air damage in this projection.
func _food_wipe_before(seconds_left: float) -> bool:
	if seconds_left <= VaultGame.SIMULATION_TICK or _food_runway_seconds() > 0.0:
		return false
	if game.food_system.meals > 0 or game.food_system.raw_food > 0 or game.job_system.get_pending_meals() > 0 or game.job_system.get_pending_raw_food() > 0:
		return false
	var first_raw := VaultBuilding.GROW_MK2_SECONDS
	for tray: VaultBuilding in game.buildings:
		if tray.kind == VaultBuilding.Kind.GROW_TRAY:
			var remaining_fraction := maxf(0.0, 1.0 - tray.production_progress / tray.get_grow_seconds())
			first_raw = minf(first_raw, remaining_fraction * VaultBuilding.GROW_MK2_SECONDS)
	var deadline := minf(seconds_left, first_raw) - VaultGame.SIMULATION_TICK
	var depletion := _food_depletion_times()
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		# Hungry crew cannot newly claim medical care. Existing reservations can
		# keep healing even while starving, so do not try to prove those doomed.
		if resident.needs.food > MED_BED_MIN_FOOD or resident.medical_bed_id >= 0:
			return false
		if _projected_death_seconds(resident, float(depletion[resident.resident_id]), "", true) >= deadline:
			return false
	return true


# An enabled recipe is not a fix when stress breaks repeatedly interrupt its
# four work seconds. Recover the crew's existing work loop before repeating
# "leave Cook on". Keep the established Rec action, with the food warning name.
func _food_work_blocker_step() -> Dictionary:
	if not _has_eligible_worker("cook") or not _has_eligible_worker("haul") or game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 0:
		return {}
	var has_source := false
	for building: VaultBuilding in game.buildings:
		has_source = has_source or (building.kind == VaultBuilding.Kind.GROW_TRAY and (building.powered or not building.complete))
	if game.food_system.raw_food + game.job_system.get_pending_raw_food() + game.job_system.get_pending_meals() == 0 and not has_source:
		return {}
	var breaking := false
	var rec_lead := _food_fixture_seconds(VaultBuilding.Kind.RECREATION_CONSOLE) + FOOD_WORK_RECOVERY_SECONDS
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		var loss := -resident.needs._get_mood_delta_per_day(game.is_resident_lit(resident), resident.sleeping, game.oxygen_system.is_low()) / DayCycle.SECONDS_PER_DAY
		var until_break := maxf(0.0, resident.needs.mood - ResidentNeeds.BREAK_MOOD_THRESHOLD) / loss if loss > 0.0 else INF
		breaking = breaking or resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD or until_break < rec_lead
	for rec: VaultBuilding in game.buildings:
		# A +16 stress break is transient relief, not a repaired work loop.
		breaking = breaking or (rec.kind == VaultBuilding.Kind.RECREATION_CONSOLE and not rec.complete)
	if not breaking:
		return {}
	if game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) == 0:
		for rec: VaultBuilding in game.buildings:
			if rec.kind == VaultBuilding.Kind.RECREATION_CONSOLE and not rec.complete:
				if _salvage_shortfall(rec.kind) > 0:
					return _food_step(_fund_blueprint_step(rec.kind, true))
				return _food_step({
					"text": "Next: YOU leave Haul + Craft on · THEY finish the Rec Console",
					"help": "Keep Haul + Craft above OFF so crew supply and finish the Rec Console blueprint.",
					"tool": "select",
				})
		return _food_prebuild_step(VaultBuilding.Kind.RECREATION_CONSOLE, _food_step({
			"text": "Next: YOU place a Rec Console · THEY recover mood",
			"help": "Place a Rec Console so crew can recover mood.",
			"tool": "rec",
		}))
	return _offline_rec_step()


func _food_worker_recovery_seconds() -> float:
	var recovery := _food_fixture_seconds(VaultBuilding.Kind.RECREATION_CONSOLE)
	if game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) > 0 and game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) == 0 and game.power_grid.supply - game.power_grid.served < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.RECREATION_CONSOLE]):
		recovery += _food_fixture_seconds(VaultBuilding.Kind.GENERATOR)
	return recovery + FOOD_WORK_RECOVERY_SECONDS


func _resident_urgency_step(suppressed_builds: Dictionary = {}) -> Dictionary:
	var threatened: VaultResident = null
	var air_lead := _food_fixture_seconds(VaultBuilding.Kind.AIR_RECYCLER)
	var food_blocker := _food_work_blocker_step()
	# Supplying a new Air blueprint suspends optional supply jobs. Let a Rec
	# already restoring the food workers finish while air still covers that
	# work plus the normal warning window; otherwise both chains stall.
	var care_window := not food_blocker.is_empty() and game.oxygen_system.get_seconds_to_critical_crossing() > _food_fixture_seconds(VaultBuilding.Kind.RECREATION_CONSOLE) + air_lead
	var air_forecast := game.oxygen_system.net_rate < 0.0 and game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) == 0 and not care_window
	var soonest := maxf(NEXT_DEATH_WARNING_SECONDS, air_lead + AIR_RECOVERY_MARGIN_SECONDS) if air_forecast else NEXT_DEATH_WARNING_SECONDS
	var food_times := _food_depletion_times()
	# A food forecast names someone only inside their own starvation window.
	# Keep that name until fed unless another resident is at least 10 s closer.
	var plan := _food_fix_plan()
	var food_lead := float(plan.seconds) + _food_chain_work_lead(float(plan.seconds))
	if not food_blocker.is_empty() and game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) == 0:
		# The selected fix is restoring food workers, so its construction/power
		# and recovery precede funding/building the missing harvest. A running
		# food chain already counts its output in runway; optional future care
		# must not add a construction delay to that existing production.
		food_lead = maxf(food_lead, float(plan.seconds) + _food_worker_recovery_seconds())
	var food_runway := _food_runway_seconds()
	var food_trigger := food_lead + FOOD_RUNWAY_MARGIN_SECONDS
	# Repeating an already-enabled Cook order cannot clear another life-support
	# deadline. Once food work is running/waiting on its source, let an actionable
	# air fix lead while its supply/build/haul window is still open.
	var food_resident: VaultResident = null
	var food_death := INF
	# The food steps and their urgency follow the forecast and the nearest
	# deadline. The NAME is separate: only a resident inside their own
	# STARVING_RUNWAY_S, kept until fed unless another is STARVING_SWITCH_S closer.
	var named_resident: VaultResident = null
	var named_death := INF
	var sticky_resident: VaultResident = null
	var sticky_food_death := INF
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		var food_seconds := float(food_times[resident.resident_id]) + resident.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)
		if food_seconds < food_death:
			food_resident = resident
			food_death = food_seconds
		if food_seconds < STARVING_RUNWAY_S and food_seconds < named_death:
			named_resident = resident
			named_death = food_seconds
		if resident.resident_id == _starving_resident_id and food_seconds < STARVING_RUNWAY_S:
			sticky_resident = resident
			sticky_food_death = food_seconds
		var seconds := _projected_death_seconds(resident, INF)
		if seconds < soonest:
			threatened = resident
			soonest = seconds
	if sticky_resident != null and named_death > sticky_food_death - STARVING_SWITCH_S:
		named_resident = sticky_resident
		named_death = sticky_food_death
	_starving_resident_id = named_resident.resident_id if named_resident != null else -1
	var food_danger := _food_forecast_with_hold(food_runway, food_trigger, named_resident != null)
	# Pantry runway governs the crop cutoff. A produced-food rescue must also
	# reach the named resident before their own starvation health runs out,
	# including recovery if breaks currently block delivery or cooking.
	if bool(plan.get("rescue", false)):
		var rescue_budget := minf(food_death, _food_runway_seconds())
		if not food_blocker.is_empty():
			rescue_budget -= _food_worker_recovery_seconds()
		if float(plan.seconds) > rescue_budget:
			plan = _food_fix_plan(rescue_budget)
	var food_waiting := ("YOU leave Cook on" in str(plan.step.text) and food_blocker.is_empty()) or bool(plan.step.get("too_late", false))
	var cause := ""
	if food_danger and food_resident != null and (threatened == null or (food_death <= soonest and not food_waiting)):
		threatened = named_resident if named_resident != null else food_resident
		soonest = food_death
		cause = "food"
	elif threatened != null:
		var best_runway := soonest
		for need: String in ["air", "rest", "mood"]:
			var runway := _projected_death_seconds(threatened, INF, need)
			if runway > best_runway:
				cause = need
				best_runway = runway
	if threatened == null:
		return {}
	var step: Dictionary = {}
	var condition := "critical"
	match cause:
		"food":
			condition = "starving" if named_resident != null else ""
			if threatened.drafted:
				step = _food_step({
					"text": "Next: YOU undraft %s [R] · THEY eat/work" % threatened.resident_name,
					"help": "Drafted crew cannot eat. Select %s and press R to undraft; keep food work enabled." % threatened.resident_name,
					"tool": "select",
				})
			else:
				step = {} if bool(plan.step.get("too_late", false)) else food_blocker
				if not step.is_empty():
					var shed := _shed_tray_step(suppressed_builds)
					if not shed.is_empty():
						step = shed
				if step.is_empty():
					step = plan.step

		"air":
			# "suffocating" only once O2 is below 15% and air is actually hurting crew.
			condition = "suffocating" if not game.oxygen_system.is_breathable() else "low on air"
			# A covered hatch response already fixes the air leak. Preserve its
			# warning/watch priority and wording; blockers were checked first.
			if game.breach_system.is_response_active():
				return _watch_hatch_step()
			step = _air_recovery_step()
			if step.is_empty() and game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) == 0:
				step = _charge_finish_step() if _unfinished_charge_count() > 0 else {
					"text": "Next: YOU place a Charge Node · THEY power the Air Recycler",
					"help": "The grid lacks available power for the Air Recycler. Place a Charge Node to add 7 power.",
					"tool": "generator",
				}
			if step.is_empty():
				step = {
					"text": "Next: YOU place Air Recycler · THEY recycle more air",
					"help": "The current recycling cannot cover crew consumption. Place and power another Air Recycler.",
					"tool": "air",
				}
		"rest":
			condition = "exhausted"
			step = {
				"text": "Next: YOU undraft %s [R] · THEY rest" % threatened.resident_name if threatened.drafted else "Next: YOU place bunks · THEY craft",
				"help": "Undraft tired crew so they can rest. Place bunks so tired undrafted crew have a bed.",
				"tool": "select" if threatened.drafted else "bed",
			}
		"mood":
			condition = "in despair"
			if not threatened.drafted:
				var console := game.get_building_by_id(threatened.recreation_id) as VaultBuilding
				if threatened.recreating and console != null and console.reserved_by == threatened.resident_id and game.job_system.can_use_recreation_console(threatened, console):
					# The reserved console already fixes mood, including the walk to it.
					condition = "recovering at the Rec Console"
					step = {
						"text": "Next: THEY recover mood",
						"help": "%s already has a powered, reachable Rec Console reserved. Let them recover mood." % threatened.resident_name,
						"tool": "select",
						"recovering": true,
					}
				else:
					step = _offline_rec_step()
			if step.is_empty():
				step = {
					"text": "Next: YOU undraft %s [R] · THEY recover mood" % threatened.resident_name if threatened.drafted else "Next: YOU place a Rec Console · THEY recover mood",
					"help": "Undraft crew so they can recover mood. Place and power a Rec Console for recreation.",
					"tool": "select" if threatened.drafted else "rec",
				}
	if step.is_empty() or _next_build_is_suppressed(step, suppressed_builds):
		return {}
	if cause == "food" and named_resident == null:
		if _is_food_chain_step(step):
			step.text = _unnamed_food_text(step)
		step["food_unnamed"] = true
	elif cause != "food" or _is_food_chain_step(step):
		# A mood, power or hatch step for a food crisis leaves "starving" to the alert line.
		step.text = "Next: %s %s · %s" % [threatened.resident_name, condition, str(step.text).trim_prefix("Next: ")]
	step["urgent"] = true
	step["resident_id"] = threatened.resident_id
	step["cause"] = cause
	# A named step reports that resident's own deadline.
	step["death_seconds"] = named_death if cause == "food" and named_resident != null else soonest
	return step


func _food_forecast_with_hold(runway: float, trigger: float, named: bool) -> bool:
	var now := game.day_cycle.elapsed_seconds
	if named:
		_food_forecast_latched = false
		return runway < trigger
	if _food_forecast_latched and now < _food_forecast_since:
		_food_forecast_latched = false
	if _food_forecast_latched:
		if runway >= trigger + FOOD_FORECAST_RELEASE_S and now - _food_forecast_since >= FOOD_FORECAST_MIN_HOLD_S:
			_food_forecast_latched = false
		return _food_forecast_latched or runway < trigger
	if runway < trigger:
		_food_forecast_latched = true
		_food_forecast_since = now
		return true
	return false


# The unnamed forecast prefix belongs only on steps that act on the food chain:
# not on the Rec Console steps that keep food workers from breaking, and not on
# unrelated blockers such as the hatch warning.
# The unnamed tip always reads "food runway short · YOU <action> · THEY <effect>".
# The too-late step names no action of its own, so it gets the standing one.
func _unnamed_food_text(step: Dictionary) -> String:
	var body := str(step.text).trim_prefix("Next: ")
	if bool(step.get("too_late", false)) or not (body.begins_with("YOU ") and " · THEY " in body):
		body = "YOU keep Cook + Haul on · THEY feed crew where possible"
	return "Next: %s · %s" % [FOOD_SHORT_LABEL, body]


func _is_food_chain_step(step: Dictionary) -> bool:
	var text := str(step.get("text", "")).to_lower()
	if str(step.get("tool", "")) == "rec" or "rec console" in text:
		return false
	if str(step.get("kind", "")) == STEP_KIND_FOOD:
		return true
	for word: String in ["nutrient station", "grow tray", "kitchen", "cook", "meal", "eat/work"]:
		if word in text:
			return true
	return false


func _urgency_interrupts_care(step: Dictionary) -> bool:
	if step.is_empty():
		return false
	var resident := game.get_resident_by_id(int(step.get("resident_id", -1)))
	if resident == null:
		return false
	match str(step.get("cause", "")):
		"food":
			return true

		"air":
			return true
		"rest":
			return resident.needs.rest <= 0.0
		"mood":
			return resident.needs.mood <= ResidentNeeds.SEVERE_MOOD_THRESHOLD and not bool(step.get("recovering", false))
	return false


func _name_food_recovery(step: Dictionary, urgent_step: Dictionary) -> Dictionary:
	var resident: VaultResident = null
	if str(urgent_step.get("cause", "")) == "food":
		if bool(urgent_step.get("food_unnamed", false)):
			# Forecast only: no resident is inside their own runway yet.
			if _is_food_chain_step(step):
				step.text = _unnamed_food_text(step)
			step["urgent"] = true
			step["resident_id"] = int(urgent_step.resident_id)
			step["cause"] = "food"
			step["food_unnamed"] = true
			return step
		resident = game.get_resident_by_id(int(urgent_step.resident_id))
	elif game.food_system.meals < game.get_alive_count():
		# Existing crisis advice also names a crew member already below the
		# food crisis threshold. Cookable raw/pending meals can cover the runway
		# while Cook or Haul is OFF; that must not leave this crisis unnamed.
		# This labels an existing action; new food warnings still use runway.
		for candidate: VaultResident in game.residents:
			if candidate.alive and candidate.needs.food < 20.0 and (resident == null or candidate.needs.food < resident.needs.food):
				resident = candidate
	if resident == null:
		return step
	# Only a food action carries the name; a mood, power or hatch step leaves
	# starving to the alert line (QA playtest 2 #2) but keeps its urgency.
	if _is_food_chain_step(step):
		step.text = "Next: %s starving · %s" % [resident.resident_name, str(step.text).trim_prefix("Next: ")]
	step["urgent"] = true
	step["resident_id"] = resident.resident_id
	step["cause"] = "food"
	return step


func _charge_finish_step() -> Dictionary:
	var shortfall := _salvage_shortfall(VaultBuilding.Kind.GENERATOR)
	if shortfall == 0:
		return {
			"text": "Next: YOU leave Haul + Craft on · THEY finish the Charge Node",
			"help": "Keep Haul + Craft above OFF so crew supply and finish the Charge Node blueprint.",
			"tool": "select",
		}
	return _fund_blueprint_step(VaultBuilding.Kind.GENERATOR)


# Next-tip hysteresis (QA 2026-10-18b #3). The Rec tip enters at the break line (mood 9) but
# holds until no living resident still wants recreation (mood <= 35), so a +16 stress break
# (9 -> 25) cannot flip it. Presentation only, never saved; a new game or load replaces the
# resident nodes, which resets the latch.
func _hold_mood_break_tip(break_risk: bool, rec_wanted: bool) -> bool:
	var owner_id := 0 if game.residents.is_empty() else game.residents[0].get_instance_id()
	if owner_id != _next_mood_tip_owner_id:
		_next_mood_tip_owner_id = owner_id
		_next_mood_tip_latched = false
	_next_mood_tip_latched = break_risk or (_next_mood_tip_latched and rec_wanted)
	return _next_mood_tip_latched


func _offline_rec_step() -> Dictionary:
	if game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) < 1 or game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) > 0:
		return {}
	var all_rec_disabled := true
	for rec: VaultBuilding in game.buildings:
		if rec.kind == VaultBuilding.Kind.RECREATION_CONSOLE and rec.complete and not rec.manually_disabled:
			all_rec_disabled = false
			break
	if all_rec_disabled:
		return {
			"text": "Next: YOU enable a Rec Console · THEY recover mood",
			"tool": "select",
			"help": "Select a completed Rec Console and click ENABLE so crew can recover mood.",
		}
	if _unfinished_charge_count() > 0:
		return _charge_finish_step()
	return {
		"text": "Next: YOU place a Charge Node · THEY power the Rec Console",
		"tool": "generator",
		"help": "The grid lacks available power for the Rec Console. Place a Charge Node to add 7 power.",
	}


func _fund_blueprint_step(kind: int, food_work_blocker := false) -> Dictionary:
	var shortfall := _salvage_shortfall(kind)
	if food_work_blocker:
		# Existing food blueprints spend from the same inventory before this
		# optional supply job. Account for them once when designating funding.
		for building: VaultBuilding in game.buildings:
			if not building.complete and building.kind != kind:
				shortfall += maxi(0, building.get_cost() - building.delivered - game.job_system.get_build_supply_in_transit(building.building_id))
	var kind_name: String = VaultBuilding.KIND_NAMES[kind]
	return _fund_salvage_step(kind_name, shortfall,
		"The %s blueprint is %d salvage short. Each dug rock tile yields %d salvage once hauled." % [kind_name, shortfall, DIG_SALVAGE_YIELD])


static var _STARVING_PREFIX := RegEx.create_from_string("^Next: \\S+ starving · ")


# "Next: Bo starving · YOU cook" -> "Next: YOU cook"; the action without its name.
static func next_action_text(text: String) -> String:
	return _STARVING_PREFIX.sub(text, "Next: ")


static func next_starving_name(text: String) -> String:
	var m := _STARVING_PREFIX.search(text)
	return "" if m == null else m.get_string().trim_prefix("Next: ").trim_suffix(" starving · ")


func _surge_modal_up() -> bool:
	var breach := game.breach_system
	return breach.phase == BreachSystem.Phase.WARNING and not breach.warning_acknowledged


# What Next shows, made steady for the player (display only; the chain is unchanged):
# - While the PRESSURE SURGE modal is up, Next names what blocks the hatch response
#   (or keeps the step it showed when the response is covered) and does not swap
#   until the modal is answered (QA playtest 2 #3).
# - When only the "<name> starving" prefix would drop or change name on the same
#   action, the shown text holds for NEXT_STARVING_HOLD_S; a new prefix shows at once.
func _steady_next_step(step: Dictionary) -> Dictionary:
	var now := _survival_tip_sim_time()
	if _surge_modal_up():
		if _next_surge_step.is_empty():
			var hatch := _breach_blocker_step()
			if hatch.is_empty():
				# A covered response has no hatch step: keep what Next already shows.
				hatch = step if _next_shown_step.is_empty() else _next_shown_step
			_next_surge_step = hatch.duplicate(true)
		step = _next_surge_step.duplicate(true)
	else:
		_next_surge_step = {}
	var text := str(step.get("text", ""))
	var shown := str(_next_shown_step.get("text", ""))
	if not shown.is_empty() and text != shown and next_action_text(text) == next_action_text(shown):
		var shown_name := next_starving_name(shown)
		var new_name := next_starving_name(text)
		var age := now - _next_shown_since
		if not shown_name.is_empty() and new_name != shown_name and age >= 0.0 and age < NEXT_STARVING_HOLD_S:
			var held := step.duplicate(true)
			held.text = shown
			return held
	if text != shown:
		_next_shown_since = now
	_next_shown_step = step.duplicate(true)
	return step


func _breach_blocker_step() -> Dictionary:
	# During WARNING/OPEN, name what stops the automatic patch before any other tip.
	# A covered response returns {} here; _primary_next_step then shows survival
	# tips first and watch hatch instead of build-order tips. Sealing ends this branch.
	var response := game.job_system.get_hatch_response()
	if response.state in [JobSystem.HatchResponseState.WATCHING, JobSystem.HatchResponseState.SEALED]:
		return {}
	if not response.has_undrafted_crew:
		if not response.has_living_crew:
			# Nobody is alive (the loss screen): there is no hatch advice to give.
			return {}
		return _hatch_key_step(
			"undraft crew [R]",
			"respond to hatch",
			"Drafted crew never answer the hatch. Select a drafted resident and press R to undraft.",
		)
	# A forced hatch supply order covers its trip, but cannot enable the
	# automatic rubble hauling needed to fund a salvage shortfall.
	var missing_work: Array = response.missing_work.duplicate()
	if response.salvage_shortfall > 0 and not response.automatic_haul and not missing_work.has("haul"):
		missing_work.push_front("haul")
	var missing: Array[String] = []
	for work_type: String in missing_work:
		missing.append(work_type.capitalize())
	if not missing.is_empty():
		var names := " + ".join(missing)
		return _hatch_key_step(
			"enable %s [P]" % names,
			"patch hatch",
			"Open PRIORITIES [P] and set %s above OFF for an undrafted resident so crew auto-respond to the hatch." % names,
		)
	if response.state == JobSystem.HatchResponseState.NO_PATH:
		# Same check as DETAILS "NO PATH TO HATCH". DIG [E] is never locked by the modal.
		var path_blocker := "No undrafted %s crew can walk to the hatch." % ("Haul" if response.job_type == JobSystem.JobType.SUPPLY_BREACH else "Craft")
		if response.responder != null:
			path_blocker = "%s can't walk to the hatch." % response.responder.resident_name
		return {
			"text": "Next: YOU mark a tunnel to the hatch [E] · THEY dig it out",
			"help": "%s Mark rock with DIG [E] to connect them to the hatch; crew with Dig above OFF dig it out." % path_blocker,
			"tool": "dig",
		}
	var shortfall: int = response.salvage_shortfall
	if shortfall > 0:
		# Salvage already delivered to an unfinished blueprint is the only instant source:
		# cancelling refunds it at once, while digging rarely beats the 20 s grace. Name the
		# smallest partly supplied blueprint that covers the shortfall (ties: lowest id). Guidance only.
		var refund_blueprint: VaultBuilding = null
		for building: VaultBuilding in game.buildings:
			# A fully supplied blueprint only awaits assembly; it is not offered for a refund.
			if building.complete or building.is_emergency_core or building.delivered < shortfall or building.delivered >= building.get_cost():
				continue
			if refund_blueprint == null or building.delivered < refund_blueprint.delivered or (building.delivered == refund_blueprint.delivered and building.building_id < refund_blueprint.building_id):
				refund_blueprint = building
		if refund_blueprint != null:
			var kind_name: String = VaultBuilding.KIND_NAMES[refund_blueprint.kind]
			var refund_step := _hatch_key_step(
				"cancel the %s [X]" % kind_name,
				"fund the hatch patch",
				"The hatch patch is %d salvage short. Cancelling the unfinished %s at (%d, %d) refunds its %d delivered salvage at once; digging rarely beats the timer. Place it again after the seal." % [shortfall, kind_name, refund_blueprint.cell.x, refund_blueprint.cell.y, refund_blueprint.delivered],
			)
			if str(refund_step.text).begins_with("Next: YOU cancel"):
				refund_step.tool = "cancel"
			return refund_step
		# Only rubble a Haul resident can reach (the scheduler's test) funds the patch.
		var rubble := game.job_system.get_uncredited_rubble(true, shortfall)
		var has_digger := _has_eligible_worker("dig")
		if shortfall > rubble and not has_digger:
			return _hatch_key_step(
				"enable Dig [P]",
				"fund the hatch patch",
				"The hatch patch is %d salvage short. Open PRIORITIES [P] and set Dig above OFF for an undrafted resident so crew dig salvage." % shortfall,
			)
		var step := _fund_salvage_step("hatch patch", shortfall,
			"The hatch patch is %d salvage short. Each dug rock tile yields %d salvage once hauled." % [shortfall, DIG_SALVAGE_YIELD], rubble)
		if not has_digger and str(step.tool) == "select":
			step.text = "Next: YOU leave Haul on · THEY fund the hatch patch"
		return step
	return {}


func _hatch_key_step(action: String, they: String, help: String) -> Dictionary:
	# R (draft) and P (priorities) are refused while the WARNING modal is
	# unacknowledged (game.toggle_resident_draft, show_work_priorities), so name
	# the acknowledgement first. OPEN never locks them.
	var breach := game.breach_system
	if breach.phase == BreachSystem.Phase.WARNING and not breach.warning_acknowledged:
		return {
			"text": "Next: YOU acknowledge warning · then %s" % action,
			"help": "Acknowledge the hatch warning first (RESUME RESPONSE, FOCUS HATCH or Space); R and P stay locked until then. %s" % help,
			"tool": "select",
		}
	return {
		"text": "Next: YOU %s · THEY %s" % [action, they],
		"help": help,
		"tool": "select",
	}


func _kitchen_recovery_step() -> Dictionary:
	var completed_kitchens := game.get_completed_building_count(VaultBuilding.Kind.KITCHEN)
	if completed_kitchens < 1:
		var unfinished_kitchens := 0
		for kitchen: VaultBuilding in game.buildings:
			if kitchen.kind == VaultBuilding.Kind.KITCHEN and not kitchen.complete:
				unfinished_kitchens += 1
		if unfinished_kitchens >= 1:
			return _food_step({
				"text": "Next: YOU leave Haul + Craft on · THEY finish the Nutrient Station",
				"help": "Keep Haul + Craft above OFF so crew supply and finish the Nutrient Station blueprint.",
				"tool": "select",
			})
		return _food_step({
			"text": "Next: YOU place a Nutrient Station · THEY cook",
			"help": "Place and power a Nutrient Station so Cook can turn raw food into meals.",
			"tool": "kitchen",
		})
	if completed_kitchens > 0 and game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 0:
		var all_kitchens_disabled := true
		for kitchen: VaultBuilding in game.buildings:
			if kitchen.kind == VaultBuilding.Kind.KITCHEN and kitchen.complete and not kitchen.manually_disabled:
				all_kitchens_disabled = false
				break
		if all_kitchens_disabled:
			return _food_step({
				"text": "Next: YOU power the Nutrient Station · THEY cook",
				"help": "Power the Nutrient Station so Cook can run.",
				"tool": "select",
			})
		var release := _food_power_release_step(VaultBuilding.Kind.KITCHEN)
		if not release.is_empty():
			return release
		if _unfinished_charge_count() > 0:
			return _food_step(_charge_finish_step())
		return _food_step({
			"text": "Next: YOU place a Charge Node · THEY power the kitchen",
			"help": "The grid lacks available power for the Nutrient Station. Place a Charge Node to add 7 power.",
			"tool": "generator",
		})
	return {}


func _meal_recovery_step(urgent := false) -> Dictionary:
	if not _has_eligible_worker("haul") and (game.job_system.get_pending_meals() > 0 or (not game.food_system.can_cook() and game.job_system.get_pending_raw_food() > 0)):
		return _food_step({
			"text": "Next: YOU enable Haul · THEY deliver food",
			"tool": "select",
			"help": "Open PRIORITIES [P] and enable Haul on a living, undrafted resident. Food is waiting for delivery.",
		})
	if not _has_eligible_worker("cook") and (
		not urgent or game.food_system.can_cook() or game.job_system.get_pending_raw_food() > 0
		or game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) > 0
	):
		return _food_step({
			"text": "Next: YOU enable Cook · THEY cook",
			"tool": "select",
			"help": "Enable Cook on a living, undrafted resident so the powered Nutrient Station can run.",
		})
	elif game.food_system.can_cook():
		return _food_step({
			"text": "Next: YOU leave Cook on · THEY cook",
			"tool": "select",
			"help": "Meals are short. The powered Nutrient Station can cook.",
		})
	else:
		if game.job_system.get_pending_meals() == 0 and game.job_system.get_pending_raw_food() == 0:
			return _grow_recovery_step()
	return _food_step({
		"text": "Next: YOU leave Cook on · THEY cook",
		"tool": "select",
		"help": "Meals are short. Leave Cook on. The powered Nutrient Station is waiting on raw food.",
	})



func _shed_tray_step(suppressed_builds: Dictionary = {}) -> Dictionary:
	if game.ended or game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY) == 0 or game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) > 0:
		return {}
	if game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) == 0 or game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 0:
		return {}
	var blocked_tray := false
	for tray: VaultBuilding in game.buildings:
		if tray.kind == VaultBuilding.Kind.GROW_TRAY and tray.complete and (tray.manually_disabled or game.power_grid.is_building_shed(tray.building_id)):
			blocked_tray = true
			break
	if not blocked_tray:
		return {}
	var step := _grow_recovery_step()
	if _next_build_is_suppressed(step, suppressed_builds):
		return {}
	step["restores_existing_tray"] = true
	return step


func _grow_recovery_step() -> Dictionary:
	var total_trays := 0
	var completed_trays := 0
	var enabled_trays := 0
	for tray: VaultBuilding in game.buildings:
		if tray.kind != VaultBuilding.Kind.GROW_TRAY:
			continue
		total_trays += 1
		if tray.complete:
			completed_trays += 1
			if not tray.manually_disabled:
				enabled_trays += 1
	if total_trays == 0:
		return _food_step({
			"text": "Next: YOU place a Grow Tray · THEY grow",
			"tool": "grow",
			"help": "Place a Grow Tray and keep it powered. Its raw food output needs Haul delivery before Cook can use it.",
		})
	if completed_trays == 0:
		return _food_step({
			"text": "Next: YOU leave Haul + Craft on · THEY finish the Grow Tray",
			"tool": "select",
			"help": "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint.",
		})
	if game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) == 0:
		if enabled_trays == 0:
			return _food_step({
				"text": "Next: YOU enable a Grow Tray · THEY grow",
				"tool": "select",
				"help": "Enable a completed Grow Tray so it can grow raw food. Haul delivers its output for Cook.",
				"restores_existing_tray": true,
			})
		var release := _food_power_release_step(VaultBuilding.Kind.GROW_TRAY)
		if not release.is_empty():
			release["restores_existing_tray"] = true
			return release
		if _unfinished_charge_count() > 0:
			return _food_step(_charge_finish_step())
		return _food_step({
			"text": "Next: YOU place a Charge Node · THEY power the Grow Tray",
			"tool": "generator",
			"help": "The grid lacks available power for the Grow Tray. Place a Charge Node to add 7 power.",
		})
	return _food_step({
		"text": "Next: YOU leave Cook on · THEY cook",
		"tool": "select",
		"help": "Meals are short. Leave Cook on. The powered Nutrient Station is waiting on raw food.",
	})


func _air_recovery_step() -> Dictionary:
	if game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) < 1:
		var completed_air := 0
		var unfinished_air := 0
		var disabled_air := 0
		for recycler: VaultBuilding in game.buildings:
			if recycler.kind != VaultBuilding.Kind.AIR_RECYCLER:
				continue
			if recycler.complete:
				completed_air += 1
				if recycler.manually_disabled:
					disabled_air += 1
			else:
				unfinished_air += 1
		if completed_air == 0:
			if unfinished_air > 0:
				if _salvage_shortfall(VaultBuilding.Kind.AIR_RECYCLER) > 0:
					return _fund_blueprint_step(VaultBuilding.Kind.AIR_RECYCLER)
				return {
					"text": "Next: YOU leave Haul + Craft on · THEY finish the Air Recycler",
					"help": "Keep Haul + Craft above OFF so crew supply and finish the Air Recycler blueprint.",
					"tool": "select",
				}
			return {
				"text": "Next: YOU place Air Recycler · THEY craft it",
				"help": "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint.",
				"tool": "air",
			}
		if disabled_air == completed_air:
			return {
				"text": "Next: YOU enable an Air Recycler · THEY recycle air",
				"help": "Select a completed Air Recycler and click ENABLE so it can recycle air.",
				"tool": "select",
			}
	return {}


func _watch_hatch_step() -> Dictionary:
	return {
		"text": "Next: YOU watch hatch · THEY auto-patch",
		"help": "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft.",
		"tool": "select",
	}


const NEXT_BUILD_PROGRESS_NAMES := {
	VaultBuilding.Kind.BED: "bunks",
	VaultBuilding.Kind.LAMP: "Lumens",
	VaultBuilding.Kind.GENERATOR: "Charge Nodes",
	VaultBuilding.Kind.GROW_TRAY: "Grow Trays",
	VaultBuilding.Kind.KITCHEN: "Nutrient Stations",
	VaultBuilding.Kind.STOCKPILE: "Salvage Bays",
	VaultBuilding.Kind.AIR_RECYCLER: "Air Recyclers",
	VaultBuilding.Kind.RECREATION_CONSOLE: "Rec Consoles",
	VaultBuilding.Kind.MEDICAL_BED: "Med Beds",
}


func _next_build_is_suppressed(step: Dictionary, suppressed_builds: Dictionary) -> bool:
	var kind := int(VaultGame.BUILD_KIND_BY_TOOL.get(str(step.get("tool", "")), -1))
	return suppressed_builds.has(kind)


func _next_in_progress_suffix(names: Array) -> String:
	var suffix := ""
	for display_name: String in names:
		suffix += " · %s in progress" % display_name
	return suffix


# Only skip a build link when the selected placement actually repeats a queued
# blueprint. Existing finish/funding tips still return unchanged on the first pass.
# Post-seal early air warning: O2 reaches LOW within AIR_WARNING_LEAD_S at the current drain.
const AIR_WARNING_LEAD_S := 60.0
var _air_warning_latched := false
var _air_next_latched := false
var _air_chain_named := false


# Latched: once live it stays until the drain stops, so a brief dip in the drain
# rate cannot flip Next back and forth.
# Last safe tap: the latest moment a newly placed Air Recycler still comes online
# before O2 drops below 15%. A recycler takes 20-24 s to place, build and power
# (05 s8 idle: tapped at 143/240/250 s, online ~24 s later); AIR_SPINUP_S uses the
# slow end. 05 s8 gives ~242 s; measured taps at 240 and 250 s won, 258 s lost.
const AIR_SPINUP_S := 24.0
const AIR_ESCALATE_S := 60.0
const AIR_LAST_CHANCE_S := 30.0


# Seconds until the last safe tap, or INF when no countdown applies (not sealed,
# a recycler is already placed, or O2 is not falling). Display only.
func air_safe_tap_seconds() -> float:
	if game.ended or not game.breach_system.is_sealed() or _count_kind(VaultBuilding.Kind.AIR_RECYCLER) > 0:
		return INF
	var oxygen := game.oxygen_system
	if not (oxygen.net_rate < -0.0001) or not oxygen.is_breathable():
		return INF
	return (oxygen.oxygen - OxygenSystem.CRITICAL_OXYGEN_THRESHOLD) / -oxygen.net_rate - AIR_SPINUP_S


func _air_countdown_clock(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%d:%02d" % [total / 60, total % 60]


func _air_countdown_text(seconds: float) -> String:
	var clock := _air_countdown_clock(seconds)
	if seconds <= AIR_LAST_CHANCE_S:
		return "LAST CHANCE · BUILD AIR IN %s" % clock
	if seconds <= AIR_ESCALATE_S:
		return "BUILD AIR NOW · %s LEFT" % clock
	return "BUILD AIR IN %s" % clock


# Next names the Air Recycler: append the same countdown the alert shows.
func _with_air_countdown(text: String) -> String:
	# Only the step that builds or places the recycler carries the clock; a power step for it
	# ("THEY power the Air Recycler") keeps its text, and the alert line still counts down.
	if not text.begins_with("Next: ") or not "Air Recycler" in text or "power the Air Recycler" in text:
		return text
	var seconds := air_safe_tap_seconds()
	if is_inf(seconds) or seconds <= 0.0 or not (game.oxygen_system.is_low() or air_early_warning()):
		return text
	return "%s · %s" % [text, _air_countdown_text(seconds)]


func air_early_warning() -> bool:
	if game.ended or not game.breach_system.is_sealed() or game.oxygen_system.is_low():
		_air_warning_latched = false
		return false
	var to_low: float = game.oxygen_system.get_seconds_to_low()
	if is_inf(to_low):
		_air_warning_latched = false
	elif to_low <= AIR_WARNING_LEAD_S:
		_air_warning_latched = true
	return _air_warning_latched


# Air warning (early or LOW) is live after the seal and no Air Recycler exists yet.
func _air_warning_needs_recycler() -> bool:
	if game.ended or not game.breach_system.is_sealed() or _count_kind(VaultBuilding.Kind.AIR_RECYCLER) > 0:
		_air_next_latched = false
		return false
	return _air_next_latched or air_early_warning() or game.oxygen_system.is_low()


# A queued Charge Node counts as the power it will add, so Next moves on to the Air Recycler.
func _air_warning_power_short() -> bool:
	var supply: int = game.power_grid.supply
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR and not building.complete and not building.is_emergency_core:
			supply += 7
	return supply - game.power_grid.demand < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.AIR_RECYCLER])


# The one build that answers the air warning: Charge Node first when power is short.
func _air_warning_kind() -> int:
	if not _air_warning_needs_recycler():
		return -1
	return VaultBuilding.Kind.GENERATOR if _air_warning_power_short() else VaultBuilding.Kind.AIR_RECYCLER


# A resident's own urgent step still wins, unless it would send the player to Rec Console.
func _air_warning_step(chain_step: Dictionary) -> Dictionary:
	_air_chain_named = false
	# Once Next has named the Air Recycler after the seal, it keeps naming it.
	if _next_named_build_kind(chain_step) == VaultBuilding.Kind.AIR_RECYCLER and game.breach_system.is_sealed() and not game.ended:
		_air_next_latched = true
		_air_chain_named = true
		# The chain already names it: keep its wording rather than restating it.
		return {}
	# A food rescue that cannot land in time is no step at all: show Air, starving stays an alert.
	var hopeless_food := bool(chain_step.get("too_late", false)) and str(chain_step.get("cause", "")) == "food"
	if hopeless_food and _unfinished_air_recycler():
		# The Air tap is placed (03 s8 at 145.1 s): finishing it is still the step that lands.
		return {
			"text": "Next: YOU leave Haul + Craft on · THEY finish the Air Recycler",
			"help": "Keep Haul + Craft above OFF so crew supply and finish the Air Recycler blueprint.",
			"tool": "select",
			"cause": "air",
			"food_resident_id": int(chain_step.get("resident_id", -1)),
			# Finishing Air is the step that lands; no salvage nudge may replace it.
			"hold_air_finish": true,
		}
	var kind := _air_warning_kind()
	if kind < 0:
		return {}
	if bool(chain_step.get("urgent", false)) and not hopeless_food and _next_named_build_kind(chain_step) != VaultBuilding.Kind.RECREATION_CONSOLE:
		return {}
	var cost := int(VaultBuilding.COSTS[kind])
	var spendable: int = game.food_system.salvage - game.job_system.get_breach_salvage_reserve()
	var them := "THEY power the Air Recycler" if kind == VaultBuilding.Kind.GENERATOR else "THEY craft it"
	var step := {
		"text": "Next: YOU place %s · %s" % ["a Charge Node" if kind == VaultBuilding.Kind.GENERATOR else "Air Recycler", them],
		"help": "Oxygen reaches LOW within a minute. Place an Air Recycler (3 power)%s; Craft auto-builds the blueprint." % (", after a Charge Node for power" if kind == VaultBuilding.Kind.GENERATOR else ""),
		"tool": "generator" if kind == VaultBuilding.Kind.GENERATOR else "air",
		"cause": "air",
	}
	if hopeless_food:
		step["food_resident_id"] = int(chain_step.get("resident_id", -1))
	if spendable >= cost:
		step.text = "Next: YOU spend %d: build %s · %s" % [cost, VaultBuilding.KIND_NAMES[kind], them]
		step["tool"] = "select"
		step["action"] = "spend"
	return step


func _unfinished_air_recycler() -> bool:
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.AIR_RECYCLER and not building.complete and not building.is_emergency_core:
			return true
	return false


func _primary_next_step() -> Dictionary:
	var suppressed_builds: Dictionary = {}
	var in_progress: Array[String] = []
	var step := _primary_next_step_chain(suppressed_builds)
	while not step.is_empty():
		var kind := int(VaultGame.BUILD_KIND_BY_TOOL.get(str(step.get("tool", "")), -1))
		var queued := false
		for building: VaultBuilding in game.buildings:
			if building.kind == kind and not building.complete and not building.is_emergency_core:
				queued = true
				break
		if not queued:
			break
		suppressed_builds[kind] = true
		in_progress.append(str(NEXT_BUILD_PROGRESS_NAMES[kind]))
		step = _primary_next_step_chain(suppressed_builds)
	var air_first := _air_warning_step(step)
	if not air_first.is_empty():
		if not in_progress.is_empty():
			air_first.text = str(air_first.text) + _next_in_progress_suffix(in_progress)
			air_first["in_progress"] = in_progress
		return _hatch_reserve_step(_salvage_next_step(air_first))
	if in_progress.is_empty():
		var first_air := _post_seal_air_step(step, game.food_system.salvage - game.job_system.get_breach_salvage_reserve())
		return _hatch_reserve_step(_salvage_next_step(first_air if not first_air.is_empty() else step))
	if step.is_empty():
		step = {
			"text": "Next: %s · THEY finish it" % _next_in_progress_suffix(in_progress).trim_prefix(" · "),
			"help": "Keep Haul + Craft above OFF so crew supply and finish the blueprints.",
			"tool": "select",
		}
	else:
		step.text = str(step.text) + _next_in_progress_suffix(in_progress)
	step["in_progress"] = in_progress
	return _hatch_reserve_step(_salvage_next_step(step))


# Before the seal a tip never spends the hatch patch: a new build must fit in the
# same spendable salvage as the food plan (salvage - patch owed - queued builds).
func _hatch_reserve_blocks(kind: int) -> bool:
	if kind < 0 or game.ended or game.breach_system.is_sealed():
		return false
	return int(VaultBuilding.COSTS.get(kind, 0)) > game.food_plan_spendable()


func _hatch_reserve_step(step: Dictionary) -> Dictionary:
	if step.is_empty():
		return step
	var text := str(step.get("text", ""))
	var prefix := _next_step_prefix(step)
	var body := text.trim_prefix(prefix)
	if not (body.begins_with("YOU place ") or body.begins_with("YOU spend ")):
		return step
	var kind := _next_named_build_kind(step)
	if not _hatch_reserve_blocks(kind):
		return step
	var owed := game.food_plan_patch_owed()
	var held := step.duplicate(true)
	var queued := game.queued_build_commitment()
	var cost := int(VaultBuilding.COSTS[kind])
	var free := maxi(0, game.food_plan_spendable())
	var kind_name: String = VaultBuilding.KIND_NAMES[kind]
	var kept: PackedStringArray = []
	if owed > 0:
		held.text = prefix + "YOU save %d for the hatch patch · THEY dig salvage" % owed
		kept.append("%d salvage for the hatch patch" % owed)
	elif queued > 0:
		held.text = prefix + "YOU save %d for the queued builds · THEY finish them" % queued
	else:
		# Patch paid and nothing queued: the only shortfall is this build's own cost.
		held.text = prefix + "YOU need %d more salvage for the %s · THEY dig salvage" % [cost - free, kind_name]
	if queued > 0:
		kept.append("%d for queued builds" % queued)
	var keep := ("Before the seal, keep %s. " % " and ".join(kept)) if not kept.is_empty() else "The hatch patch is paid. "
	held.help = "%s%s costs %d; only %d is free. Place it after the seal." % [keep, kind_name, cost, free]
	held.tool = "select"
	held.erase("action")
	_next_reclamation_kind = -1
	return held


func _update_idle_crew_tracking() -> void:
	if game == null:
		return
	var now := _survival_tip_sim_time()
	if now < _idle_crew_sample_time:
		_idle_crew_since.clear()
	_idle_crew_sample_time = now
	var idle_ids: Dictionary = {}
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and resident.state == "Idle":
			var id := resident.get_instance_id()
			idle_ids[id] = true
			if not _idle_crew_since.has(id):
				_idle_crew_since[id] = now
	for id: int in _idle_crew_since.keys():
		if not idle_ids.has(id):
			_idle_crew_since.erase(id)


func _has_idle_crew() -> bool:
	var now := _survival_tip_sim_time()
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and resident.state == "Idle":
			var id := resident.get_instance_id()
			if _idle_crew_since.has(id) and now - float(_idle_crew_since[id]) >= IDLE_CREW_WINDOW_S - 0.000001:
				return true
	return false


func _salvage_crisis_live() -> bool:
	if not _air_ready() or not game.oxygen_system.is_breathable():
		return true
	for resident: VaultResident in game.residents:
		if resident.alive and (resident.needs.food < 20.0 or resident.needs.rest < 15.0):
			return true
	return false


# Read the displayed selection, including its urgency metadata. Re-selecting
# here would recurse through Next's salvage helpers and could change its text.
func next_urgent_build_kind() -> int:
	return _next_named_build_kind(_displayed_next_step) if bool(_displayed_next_step.get("urgent", false)) else -1


func _next_named_build_kind(step: Dictionary) -> int:
	var kind := int(VaultGame.BUILD_KIND_BY_TOOL.get(str(step.get("tool", "")), -1))
	if kind >= 0:
		return kind
	var text := str(step.get("text", "")).trim_suffix(_next_in_progress_suffix(step.get("in_progress", []))).to_lower()
	# Match the funded/finished fixture, not another need in the resident prefix.
	if " · they fund the " in text:
		text = text.get_slice(" · they fund the ", 1)
	for candidate: int in VaultBuilding.KIND_NAMES:
		if str(VaultBuilding.KIND_NAMES[candidate]).to_lower() in text:
			return candidate
	if "bunks" in text:
		return VaultBuilding.Kind.BED
	if "med bed" in text:
		return VaultBuilding.Kind.MEDICAL_BED
	return -1


# Presentation only, after urgency and queued-build suppression have chosen a step.
# Keep the underlying signature separate from decoration, including urgency identity.
func _salvage_next_step(step: Dictionary) -> Dictionary:
	if step.is_empty() or game.ended:
		_next_reclamation_kind = -1
		_next_bunk_text = ""
		_next_hold_signature.clear()
		_next_hold_step.clear()
		_next_hold_since = -1.0
		return step
	step = step.duplicate(true)
	var held_bunk := _is_bunk_place_step(_next_hold_step)
	var bunk_age := _survival_tip_sim_time() - _next_hold_since
	if held_bunk and _is_unnamed_rec_blocker(step) and bunk_age >= 0.0 and bunk_age < NEXT_HOLD_S - 0.000001:
		# The food-worker Rec blocker waits out the existing Next hold of the
		# bunk step it would replace. No new urgency rule.
		var held := _next_hold_step.duplicate(true)
		_next_reclamation_kind = _next_named_build_kind(held)
		return held
	step = _stabilize_bunk_step(step)
	var signature: Array = [step.get("text", ""), step.get("kind", ""), step.get("tool", ""),
		step.get("action", ""), step.get("urgent", false), step.get("too_late", false),
		step.get("resident_id", -1), step.get("cause", "")]
	_next_reclamation_kind = _next_named_build_kind(step)
	var now := _survival_tip_sim_time()
	var held_valid := not (" · THEY fund the " in str(_next_hold_step.get("text", "")) and _next_kind_affordable(_next_named_build_kind(_next_hold_step)))
	if str(_next_hold_step.get("action", "")) == "reclaim":
		var held_kind := _next_named_build_kind(_next_hold_step)
		held_valid = held_valid and game.can_start_reclamation() and not _next_kind_affordable(held_kind)
	if signature == _next_hold_signature and held_valid and now >= _next_hold_since and now - _next_hold_since < NEXT_HOLD_S - 0.000001:
		# Keep current diagnosis/deadline metadata while holding presentation only.
		for field: String in ["text", "tool", "help", "action"]:
			if _next_hold_step.has(field):
				step[field] = _next_hold_step[field]
			else:
				step.erase(field)
		_next_reclamation_kind = _next_named_build_kind(step)
		return step
	var result := _choose_salvage_next_step(step)
	if now < _next_hold_since or signature != _next_hold_signature or not held_valid or str(result.get("text", "")) != str(_next_hold_step.get("text", "")) or str(result.get("action", "")) != str(_next_hold_step.get("action", "")):
		_next_hold_since = now
	_next_hold_signature = signature
	_next_hold_step = result.duplicate(true)
	_next_reclamation_kind = _next_named_build_kind(result)
	return result


# "place 1 bunk", "place 2 bunks" and "place bunks" are one step. Latch the
# wording, not the information: a bunk step that states no count ("place bunks")
# keeps the count text first shown, so 1 bunk <-> bunks never flips on its own.
# A stated count ("place 2 bunks") is shown as built and becomes the latch, so a
# real mid-episode count change (2 -> 1 after a placement) still reaches Next.
func _is_bunk_place_step(step: Dictionary) -> bool:
	return str(step.get("tool", "")) == "bed" and not bool(step.get("urgent", false)) and str(step.get("text", "")).begins_with("Next: YOU place ") and "bunk" in str(step.get("text", ""))


# One source of truth for Next and Spend: a needed bunk step outranks a salvage nudge.
func _bunks_hold_salvage_nudge(step: Dictionary) -> bool:
	return _is_bunk_place_step(step)


func _bunk_step_states_count(step: Dictionary) -> bool:
	var count_word := str(step.get("text", "")).trim_prefix("Next: YOU place ").get_slice(" ", 0)
	return count_word.is_valid_int()


func _stabilize_bunk_step(step: Dictionary) -> Dictionary:
	if not _is_bunk_place_step(step):
		_next_bunk_text = ""
		_next_bunk_help = ""
		return step
	if _next_bunk_text.is_empty() or _bunk_step_states_count(step):
		_next_bunk_text = str(step.text)
		_next_bunk_help = str(step.get("help", ""))
		return step
	step.text = _next_bunk_text
	if not _next_bunk_help.is_empty():
		step["help"] = _next_bunk_help
	return step


func _is_unnamed_rec_blocker(step: Dictionary) -> bool:
	return bool(step.get("food_unnamed", false)) and str(step.get("tool", "")) == "rec"


func _next_kind_affordable(kind: int) -> bool:
	return kind >= 0 and game.food_system.salvage - game.job_system.get_breach_salvage_reserve() >= int(VaultBuilding.COSTS[kind])


# The presentation prefix comes from the step's fields, not segment position:
# only a named urgent step carries "Next: <Name> <condition> · ", and an unnamed
# food step carries the runway label only on food-chain steps.
func _next_step_prefix(step: Dictionary) -> String:
	var text := str(step.get("text", ""))
	if not bool(step.get("urgent", false)):
		return "Next: "
	if bool(step.get("food_unnamed", false)):
		var label := "Next: %s · " % FOOD_SHORT_LABEL
		return label if text.begins_with(label) else "Next: "
	return text.get_slice(" · ", 0) + " · "


func _choose_salvage_next_step(step: Dictionary) -> Dictionary:
	var text := str(step.get("text", ""))
	var danger := bool(step.get("urgent", false))
	var prefix := _next_step_prefix(step)
	var body := text.trim_prefix(prefix).get_slice(" · ", 0)
	var funding := " · THEY fund the " in text
	var placing := body.begins_with("YOU place ")
	var kind := _next_named_build_kind(step)
	var spendable: int = game.food_system.salvage - game.job_system.get_breach_salvage_reserve()
	var affordable := _next_kind_affordable(kind)
	if funding and affordable:
		step.text = text.replace(" · THEY fund the ", " · THEY build the ")
		if str(step.get("action", "")) == "reclaim":
			step.erase("action")
		# A previously decorated input must not keep the reclamation appendix.
		step["help"] = str(step.get("help", "")).get_slice("\nReclamation:", 0)
		return step
	# No amount of salvage replaces an immediate switch, undraft, priority or cutoff.
	var salvage_action := placing or (funding and (body.begins_with("YOU mark ") or body.begins_with("YOU leave ")))
	if bool(step.get("too_late", false)) or bool(step.get("hold_air_finish", false)) or (danger and not salvage_action):
		return step
	var idle := _has_idle_crew()
	var sink := salvage_survival_sink(spendable) if idle else -1
	# The recorded 05 food-worker recovery already places Rec. Express its
	# affordable recovery as spending too, even though its kind is unchanged.
	var food_rec_recovery := danger and str(step.get("cause", "")) == "food" and kind == VaultBuilding.Kind.RECREATION_CONSOLE and sink == kind
	# The latched air step keeps naming the Air Recycler: an idle-crew blip must not
	# swap it for another sink every few seconds (05 s8 idle flicker from 230 s).
	var air_held := kind == VaultBuilding.Kind.AIR_RECYCLER and _air_next_latched
	if idle and danger and placing and sink >= 0 and (sink != kind or food_rec_recovery) and not air_held:
		return _next_spend_build(step, sink, prefix)
	var short := kind >= 0 and not affordable and (funding or placing)
	var reclaim_kind := kind
	if idle and sink < 0 and (placing or (not danger and (_is_default_step(step) or body.begins_with("YOU leave ")))):
		var candidates := _salvage_survival_candidates()
		if not candidates.is_empty():
			reclaim_kind = candidates[0]
			short = not _next_kind_affordable(reclaim_kind)
	if reclaim_kind < 0 and idle and _salvage_crisis_live():
		# A passive crisis step has no fixture of its own. Name the live need.
		reclaim_kind = VaultBuilding.Kind.AIR_RECYCLER if not _air_ready() or not game.oxygen_system.is_breathable() else VaultBuilding.Kind.BED
		for resident: VaultResident in game.residents:
			if resident.alive and resident.needs.food < 20.0 and reclaim_kind != VaultBuilding.Kind.AIR_RECYCLER:
				reclaim_kind = VaultBuilding.Kind.KITCHEN if game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) == 0 else VaultBuilding.Kind.GROW_TRAY
	var passive_crisis := idle and _salvage_crisis_live() and not _next_kind_affordable(reclaim_kind)
	if game.can_start_reclamation() and reclaim_kind >= 0 and not _next_kind_affordable(reclaim_kind) and (short or passive_crisis):
		_next_reclamation_kind = reclaim_kind
		step.text = prefix + "YOU begin reclamation · +%d · THEY fund the %s" % [VaultGame.RECLAIM_START_SALVAGE, VaultBuilding.KIND_NAMES[reclaim_kind]] + _next_in_progress_suffix(step.get("in_progress", []))
		step["tool"] = "select"
		step["action"] = "reclaim"
		step["help"] = str(step.get("help", "")) + "\nReclamation: +%d salvage now, +%d every %d s, %d times" % [VaultGame.RECLAIM_START_SALVAGE, VaultGame.RECLAIM_DELIVERY, roundi(VaultGame.RECLAIM_INTERVAL), VaultGame.RECLAIM_DELIVERIES]
		return step
	if danger or not idle or not (_is_default_step(step) or body.begins_with("YOU leave ")):
		return step
	# Bunks the crew still need are the player's real next action: neither a Mk II
	# fit nor a salvage nudge overwrites them, or Next flashes the fit or nudged build
	# until the bunks are placed (03 s4242: Rec at 81.6 s, Air at 84.2 s; 05 s4242
	# busy: a Mk II fit and back to the bunks 8 times from 76.5 s). Survival needs
	# arrive as urgent steps, which this non-urgent bunk step excludes.
	if _bunks_hold_salvage_nudge(step):
		return step
	# Preserve Mk II precedence on the non-danger path.
	var target := _upgrade_offer_target()
	if target != null and target.get_upgrade_cost() <= spendable:
		step.text = "Next: YOU spend %d: fit %s Mk II" % [target.get_upgrade_cost(), ALSO_NAMES[target.kind]] + _next_in_progress_suffix(step.get("in_progress", []))
		step["help"] = "Select the %s and fit Mk II in its inspector." % VaultBuilding.KIND_NAMES[target.kind]
		step["tool"] = "select"
		step["action"] = "spend"
		return step
	return _next_spend_build(step, sink, prefix) if sink >= 0 else step


# A single Mk I tray can feed a small crew before Air unlocks the next fits.
# Offer that prerequisite during the ordinary bunk plateau, without an Idle wait.
func _post_seal_air_step(step: Dictionary, spendable: int) -> Dictionary:
	if not _is_bunk_place_step(step) or str(step.get("text", "")) != "Next: YOU place bunks · THEY craft" or game.ended or not game.breach_system.is_sealed() or not game.reclaim_active:
		return {}
	if _count_kind(VaultBuilding.Kind.AIR_RECYCLER) > 0 or spendable < int(VaultBuilding.COSTS[VaultBuilding.Kind.AIR_RECYCLER]):
		return {}
	if _blueprints_awaiting_salvage() > 0 or _count_kind(VaultBuilding.Kind.GROW_TRAY) != 1 or game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 0:
		return {}
	var tray: VaultBuilding
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			tray = building
	if tray == null or not tray.complete or not tray.powered or tray.upgrade_tier != VaultBuilding.UPGRADE_TIER_BASE:
		return {}
	if DayCycle.SECONDS_PER_DAY / tray.get_grow_seconds() <= _crew_meals_per_day():
		return {}
	# Keep every current service, including optional Rec, powered after Air.
	if game.power_grid.supply - game.power_grid.demand < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.AIR_RECYCLER]):
		if _unfinished_charge_count() > 0:
			return _charge_finish_step()
		if spendable >= int(VaultBuilding.COSTS[VaultBuilding.Kind.GENERATOR]):
			return _next_spend_build(step, VaultBuilding.Kind.GENERATOR, "Next: ")
		return {
			"text": "Next: YOU place a Charge Node · THEY power the Air Recycler",
			"help": "The grid lacks available power for the Air Recycler. Place a Charge Node to add 7 power.",
			"tool": "generator",
		}
	return {
		"text": "Next: YOU spend 14: build Air Recycler",
		"help": "Place an Air Recycler blueprint on free floor. Keep Haul + Craft above OFF so crew supply and build it.",
		"tool": "select",
		"action": "spend",
	}


func _next_spend_build(step: Dictionary, sink: int, prefix: String) -> Dictionary:
	step.text = prefix + "YOU spend %d: build %s · THEY craft" % [VaultBuilding.COSTS[sink], VaultBuilding.KIND_NAMES[sink]] + _next_in_progress_suffix(step.get("in_progress", []))
	step["help"] = "Place a %s blueprint on free floor. Keep Haul + Craft above OFF so crew supply and build it." % VaultBuilding.KIND_NAMES[sink]
	step["tool"] = "select"
	step["action"] = "spend"
	return step


func _primary_next_step_chain(suppressed_builds: Dictionary) -> Dictionary:
	var critical_resident := false
	var mood_break_risk := false
	var rec_wanted := false
	var injured_without_reservation := false
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		if resident.needs.food < 20.0 or resident.needs.rest < 15.0:
			critical_resident = true
		if resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD:
			mood_break_risk = true
		if resident.needs.wants_recreation():
			rec_wanted = true
		if resident.needs.wants_medical_care() and resident.medical_bed_id < 0:
			injured_without_reservation = true
	var urgent_step := _resident_urgency_step(suppressed_builds)
	var breach_blocker := _breach_blocker_step()
	if not breach_blocker.is_empty():
		_hold_mood_break_tip(mood_break_risk, rec_wanted)
		# Funding/patching the hatch still leads, but it must not erase an
		# existing food warning while it blocks the workers/food budget.
		return _name_food_recovery(breach_blocker, urgent_step)
	var interrupts_care := _urgency_interrupts_care(urgent_step)
	# An empty larder outranks the mood tips: a stress break passes, starvation does not.
	var empty_larder_break := mood_break_risk and game.food_system.meals == 0
	# With no Nutrient Station the larder only falls. Once the crew's stored meals and
	# bellies cover less than FOOD_LEAD_DAYS, food outranks the Rec tip (QA 2026-10-18c #5).
	var unfed_larder_break := (
		mood_break_risk
		and game.food_system.meals <= game.get_alive_count()
		and game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) < 1
		and _crew_food_days() < FOOD_LEAD_DAYS
	)
	if unfed_larder_break or ((critical_resident or empty_larder_break) and game.food_system.meals < game.get_alive_count()):
		_hold_mood_break_tip(mood_break_risk, rec_wanted)
		var kitchen_step := _kitchen_recovery_step()
		if not kitchen_step.is_empty() and not _next_build_is_suppressed(kitchen_step, suppressed_builds):
			# Existing kitchen crisis advice already leads optional builds. Keep its
			# wording unless a different threat, undrafting or ready meals take priority.
			if not interrupts_care or (
				str(urgent_step.get("kind", "")) == STEP_KIND_FOOD
				and not bool(urgent_step.get("too_late", false))
				and not game.get_resident_by_id(int(urgent_step.resident_id)).drafted
				and game.job_system.get_pending_meals() == 0
			):
				return _name_food_recovery(kitchen_step, urgent_step)
	if interrupts_care:
		_hold_mood_break_tip(mood_break_risk, rec_wanted)
		return urgent_step
	var shed := _shed_tray_step(suppressed_builds)
	if not shed.is_empty():
		_hold_mood_break_tip(mood_break_risk, rec_wanted)
		return shed
	mood_break_risk = _hold_mood_break_tip(mood_break_risk, rec_wanted)
	if mood_break_risk and game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) < 1 and not suppressed_builds.has(VaultBuilding.Kind.RECREATION_CONSOLE):
		var unfinished_rec := 0
		for rec: VaultBuilding in game.buildings:
			if rec.kind == VaultBuilding.Kind.RECREATION_CONSOLE and not rec.complete:
				unfinished_rec += 1
		if unfinished_rec >= 1:
			return {
				"text": "Next: YOU leave Haul + Craft on · THEY finish the Rec Console",
				"help": "Keep Haul + Craft above OFF so crew supply and finish the Rec Console blueprint.",
				"tool": "select",
			}
		return {
			"text": "Next: YOU place a Rec Console · THEY recover mood",
			"help": "Place a Rec Console so crew can recover mood.",
			"tool": "rec",
		}
	if mood_break_risk:
		var offline_rec_step := _offline_rec_step()
		if not offline_rec_step.is_empty() and not _next_build_is_suppressed(offline_rec_step, suppressed_builds):
			return offline_rec_step
	var free_medical := 0
	for bed: VaultBuilding in game.buildings:
		if bed.kind == VaultBuilding.Kind.MEDICAL_BED and bed.complete and not bed.manually_disabled and bed.reserved_by < 0:
			free_medical += 1
	if injured_without_reservation and free_medical == 0 and not suppressed_builds.has(VaultBuilding.Kind.MEDICAL_BED):
		var free_disabled_medical := false
		var unfinished_medical := false
		for bed: VaultBuilding in game.buildings:
			if bed.kind != VaultBuilding.Kind.MEDICAL_BED:
				continue
			if bed.complete and bed.manually_disabled and bed.reserved_by < 0:
				free_disabled_medical = true
			if not bed.complete:
				unfinished_medical = true
		if free_disabled_medical:
			return {
				"text": "Next: YOU enable a Med Bed · THEY treat",
				"tool": "select",
				"help": "Select a completed Med Bed and click ENABLE so the injured can be treated.",
			}
		if unfinished_medical:
			return {
				"text": "Next: YOU leave Haul + Craft on · THEY finish the Med Bed",
				"tool": "select",
				"help": "Keep Haul + Craft above OFF so crew supply and finish the Med Bed blueprint.",
			}
		return {
			"text": "Next: YOU place a Med Bed · THEY treat",
			"help": "Place a Med Bed so the injured can be treated.",
			"tool": "medical",
		}
	var residents_needing_bunks := 0
	var occupied_bunks: Dictionary = {}
	for resident: VaultResident in game.residents:
		if resident.sleeping and resident.bed_id >= 0:
			occupied_bunks[resident.bed_id] = true
		elif resident.medical_bed_id >= 0 and resident.state == "Rest-Medical":
			continue
		elif resident.alive and not resident.drafted and (resident.needs.rest <= 28.0 or (resident.sleeping and resident.bed_id < 0)):
			residents_needing_bunks += 1
	var free_bunks := 0
	var unfinished_bunks := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.BED and building.complete and not occupied_bunks.has(building.building_id):
			free_bunks += 1
		if building.kind == VaultBuilding.Kind.BED and not building.complete:
			unfinished_bunks += 1
	if residents_needing_bunks > free_bunks and not suppressed_builds.has(VaultBuilding.Kind.BED):
		if unfinished_bunks >= (residents_needing_bunks - free_bunks):
			return {
				"text": "Next: YOU leave Haul + Craft on · THEY finish the bunks",
				"tool": "select",
				"help": "Keep Haul + Craft above OFF so crew supply and finish the bunk blueprints.",
			}
		return {
			"text": "Next: YOU place bunks · THEY craft",
			"help": "Place bunks so tired undrafted crew have a bed.",
			"tool": "bed",
		}
	if critical_resident and game.food_system.meals < game.get_alive_count() and game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) >= 1:
		var meal_step := _meal_recovery_step()
		if not _next_build_is_suppressed(meal_step, suppressed_builds):
			return _name_food_recovery(meal_step, urgent_step)
	if game.breach_system.is_response_active():
		# Covered WARNING/OPEN (the blocker step found nothing missing): survival
		# tips above still win, but no build-order tip until the hatch seals.
		return _watch_hatch_step()
	if bool(urgent_step.get("recovering", false)):
		return urgent_step
	var initial_floor := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
	var floor_count := game.map_grid.get_floor_cells().size() - game.map_grid.layout_pocket_count
	var dig_marks := game.map_grid.dig_marks.size()
	if floor_count < initial_floor + 12:
		if dig_marks <= 0:
			return {
				"text": "Next: YOU mark rock [E] · THEY dig on Dig defaults",
				"help": "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional.",
				"tool": "dig",
			}
		return {
			"text": "Next: YOU keep marking digs [E] · THEY dig/haul alone",
			"help": "Keep designating connected rock. They dig then haul rubble without draft. PRIORITIES [P] only to specialize.",
			"tool": "dig",
		}
	var completed_bunks := game.get_completed_building_count(VaultBuilding.Kind.BED)
	if completed_bunks < 2 and not suppressed_builds.has(VaultBuilding.Kind.BED):
		var deficit := 2 - completed_bunks - unfinished_bunks
		if unfinished_bunks >= (2 - completed_bunks):
			return {
				"text": "Next: YOU leave Haul + Craft on · THEY finish the bunks",
				"tool": "select",
				"help": "Keep Haul + Craft above OFF so crew supply and finish the bunk blueprints.",
			}
		return {
			"text": "Next: YOU place 1 bunk · THEY craft from Craft" if deficit == 1 else "Next: YOU place 2 bunks · THEY craft from Craft",
			"help": "Place BUNK blueprints on carved floor. Undrafted Craft priority finishes them.",
			"tool": "bed",
		}
	if game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true) < 1 and not suppressed_builds.has(VaultBuilding.Kind.GENERATOR):
		if _unfinished_charge_count() > 0:
			return _charge_finish_step()
		return {
			"text": "Next: YOU place a Charge Node · THEY supply/build",
			"help": "Designate CHARGE. Haul + Craft auto-claim the blueprint. Adds +7 power.",
			"tool": "generator",
		}
	var cook_ok := _has_eligible_worker("cook")
	var haul_ok := _has_eligible_worker("haul")
	var food_ready := (
		game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) >= 1
		and game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) >= 1
		and cook_ok
		and haul_ok
	)
	if not food_ready:
		if game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY) < 1 and not suppressed_builds.has(VaultBuilding.Kind.GROW_TRAY):
			for tray: VaultBuilding in game.buildings:
				if tray.kind == VaultBuilding.Kind.GROW_TRAY and not tray.complete:
					return _food_step({
						"text": "Next: YOU leave Haul + Craft on · THEY finish the Grow Tray",
						"help": "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint.",
						"tool": "select",
					})
			return _food_step({
				"text": "Next: YOU place Grow Tray · THEY haul output",
				"help": "Designate GROW and keep it powered. Haul defaults move raw food to stock.",
				"tool": "grow",
			})
		if game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) < 1 and not suppressed_builds.has(VaultBuilding.Kind.KITCHEN):
			var unfinished_kitchens := 0
			for kitchen: VaultBuilding in game.buildings:
				if kitchen.kind == VaultBuilding.Kind.KITCHEN and not kitchen.complete:
					unfinished_kitchens += 1
			if unfinished_kitchens >= 1:
				return _food_step({
					"text": "Next: YOU leave Haul + Craft on · THEY finish the Nutrient Station",
					"help": "Keep Haul + Craft above OFF so crew supply and finish the Nutrient Station blueprint.",
					"tool": "select",
				})
			return _food_step({
				"text": "Next: YOU place Nutrient Station · THEY cook/haul",
				"help": "Designate NUTRI, power it, leave Cook + Haul above OFF.",
				"tool": "kitchen",
			})
		var food_capacity_short := false
		if cook_ok and haul_ok:
			food_capacity_short = true
			for kind in [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN]:
				if game.get_powered_building_count(kind) >= 1:
					continue
				var enabled_shed := false
				for building: VaultBuilding in game.buildings:
					if building.kind == kind and building.complete and not building.manually_disabled and game.power_grid.is_building_shed(building.building_id):
						enabled_shed = true
						break
				if not enabled_shed:
					food_capacity_short = false
					break
		if food_capacity_short and not suppressed_builds.has(VaultBuilding.Kind.GENERATOR):
			if _unfinished_charge_count() > 0:
				return _food_step(_charge_finish_step())
			return _food_step({
				"text": "Next: YOU place a Charge Node · THEY add power",
				"help": "The grid lacks power for the food chain. Place a Charge Node to add 7 power.",
				"tool": "generator",
			})
		return _food_step({
			"text": "Next: YOU power food chain · THEY cook/haul alone",
			"help": "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.",
			"tool": "select",
		})
	var air_step := _air_recovery_step()
	if not air_step.is_empty() and not _next_build_is_suppressed(air_step, suppressed_builds):
		return air_step
	var hatch_ready := (
		game.breach_system.is_sealed()
		or (
			game.food_system.salvage
				+ game.breach_system.patch_delivered
				+ game.job_system.get_breach_supply_in_transit()
				>= BreachSystem.PATCH_COST
			and _has_eligible_worker("haul")
			and _has_eligible_worker("craft")
		)
	)
	if not hatch_ready:
		return {
			"text": "Next: YOU keep 4 salvage · THEY haul/craft hatch",
			"help": "Reserve 4 salvage. Leave Haul + Craft above OFF so they auto-respond to the hatch.",
			"tool": "select",
		}
	if not game.breach_system.is_sealed():
		return _watch_hatch_step()
	if not game.day_cycle.completed:
		var oldest_short_blueprint: VaultBuilding = null
		for building: VaultBuilding in game.buildings:
			if building.complete or building.is_emergency_core or building.is_supplied():
				continue
			if _salvage_shortfall(building.kind) <= 0:
				continue
			if oldest_short_blueprint == null or building.building_id < oldest_short_blueprint.building_id:
				oldest_short_blueprint = building
		if oldest_short_blueprint != null:
			return _fund_blueprint_step(oldest_short_blueprint.kind)
		if rec_wanted:
			var offline_rec_step := _offline_rec_step()
			if not offline_rec_step.is_empty() and not _next_build_is_suppressed(offline_rec_step, suppressed_builds):
				return offline_rec_step
		if not suppressed_builds.is_empty():
			return {}
		return {
			"text": "Next: YOU designate needs · THEY hold Day 7",
			"help": "Keep designating dig/build/stockpile. Defaults keep food, power, and air running.",
			"tool": "select",
		}
	if not suppressed_builds.is_empty():
		return {}
	return {
		"text": "Next: YOU check blockers · THEY idle on defaults",
		"help": "Seal and breathable O2 remain required at Day 7.",
		"tool": "select",
	}


# Returns the Next step it showed ({} for an outcome line) so refresh() reuses it.
func _refresh_objective() -> Dictionary:
	if game.outcome == "death":
		objective_label.text = "RESIDENT LOST // review recap to resume"
		objective_label.add_theme_color_override("font_color", Color("ef6860"))
		return {}
	if game.ended and game.outcome == "win":
		# The SEAL STABILIZED panel is up: report the result, not a Next tip.
		# Short like #90's "WING LOST // no residents remain" so it fits one line.
		var survivors := game.get_alive_count()
		objective_label.text = "SEALED // %d resident%s survived" % [survivors, "" if survivors == 1 else "s"]
		objective_label.add_theme_color_override("font_color", Color("75d4b4"))
		_expand_details_on_urgency()
		return {}
	if game.keep_running and not game.ended:
		var kr_step := keep_running_next_step()
		_remember_survival_tip(kr_step)
		# Same clock as the alert line (Codex 6531176283): the air step counts down here too.
		objective_label.text = _with_air_countdown(str(kr_step.text))
		objective_label.add_theme_color_override("font_color", Color("efc56b"))
		_expand_details_on_urgency()
		return kr_step
	if game.day_cycle.completed and not game.ended:
		var blockers: Array[String] = []
		if not game.breach_system.is_sealed():
			blockers.append("SEAL HATCH")
		if not game.oxygen_system.is_breathable():
			blockers.append("RESTORE O2 TO 15%")
		objective_label.text = "VICTORY PENDING // %s" % " + ".join(blockers)
		objective_label.add_theme_color_override("font_color", Color("ef6860"))
		_expand_details_on_urgency()
		return {}
	if game.ended and game.outcome == "loss":
		# The WING LOST panel is up and no crew remain: show the outcome, not a Next tip.
		objective_label.text = "WING LOST // no residents remain"
		objective_label.add_theme_color_override("font_color", Color("ef6860"))
		_expand_details_on_urgency()
		return {}
	var step: Dictionary = _steady_next_step(_primary_next_step())
	_remember_survival_tip(step)
	objective_label.text = _with_air_countdown(str(step.get("text", "NEXT // Survive")))
	objective_label.add_theme_color_override("font_color", Color("efc56b"))
	_expand_details_on_urgency()
	return step


func _expand_details_on_urgency() -> void:
	# New games and loaded snapshots replace resident nodes, even at the same sim time.
	# Residents remain in the roster after death, so this identity is stable during play.
	var resident_instance_id := 0 if game.residents.is_empty() else game.residents[0].get_instance_id()
	if resident_instance_id != _details_resident_instance_id:
		_details_urgencies.clear()
		_details_resident_instance_id = resident_instance_id
	var active: Dictionary = {}
	if game.breach_system.phase == BreachSystem.Phase.WARNING:
		active["breach_warning"] = true
	if game.breach_system.phase == BreachSystem.Phase.OPEN:
		active["breach_open"] = true
	if game.power_grid.brownout_active:
		active["brownout"] = true
	if game.oxygen_system.is_low() or air_early_warning():
		active["low_o2"] = true
	if game.day_cycle.completed and not game.ended and not game.keep_running and (
		not game.breach_system.is_sealed() or not game.oxygen_system.is_breathable()
	):
		active["victory_pending"] = true
	var gained_urgency := false
	for urgency: String in active:
		if not _details_urgencies.has(urgency):
			gained_urgency = true
			break
	_details_urgencies = active
	if gained_urgency and details_box != null and not _details_expanded:
		_details_expanded = true
		details_box.visible = true
		if details_toggle != null:
			details_toggle.text = "DETAILS ▾"
		if summary_separator != null:
			summary_separator.visible = false
		if right_scroll != null:
			right_scroll.scroll_vertical = 0
		_refresh_alert_details()


func _refresh_roster() -> void:
	var parts: Array[String] = []
	for resident in game.residents:
		parts.append("%d:%d:%d:%d:%d:%s:%s:%s:%s:%s" % [
			resident.resident_id,
			floori(resident.needs.food),
			floori(resident.needs.rest),
			floori(resident.needs.mood),
			floori(resident.needs.health),
			resident.state,
			str(resident.drafted),
			str(resident.has_manual_move_order()),
			str(resident.is_forced_job),
			resident.trait_id,
		])
	var signature := "|".join(parts)
	if signature == _last_roster_signature:
		return
	_last_roster_signature = signature
	for child in roster_box.get_children():
		child.queue_free()
	for resident in game.residents:
		var button := Button.new()
		var urgent := minf(resident.needs.food, minf(resident.needs.rest, minf(resident.needs.mood, resident.needs.health)))
		var resident_status := _get_resident_order_status(resident)
		button.text = _roster_row_text(resident, resident_status, urgent)
		button.tooltip_text = button.text
		# Two short lines: vitals, then what the resident is doing. Rare stacked
		# command flags wrap instead of clipping at the panel edge.
		button.add_theme_font_size_override("font_size", ROSTER_FONT_SIZE)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not resident.alive
		button.pressed.connect(_on_resident_pressed.bind(resident.resident_id))
		if resident.alive and resident.trait_id != "":
			button.text = _roster_text_with_trait(button.text, resident.trait_id)
			button.tooltip_text = "%s\n%s: %s" % [button.text, resident.trait_id, VaultResident.TRAIT_EFFECTS[resident.trait_id]]
		roster_box.add_child(button)


const ROSTER_FONT_SIZE := 13


func _roster_row_text(resident: VaultResident, resident_status: String, urgent: float) -> String:
	if not resident.alive:
		return "%s · DECEASED" % resident.resident_name
	return "%s · HP %d · MOOD %d · LOW %d\n%s" % [resident.resident_name, floori(resident.needs.health), floori(resident.needs.mood), floori(urgent), resident_status]


func _refresh_inspector() -> void:
	var resident := game.get_resident_by_id(game.selected_resident_id)
	if resident != null:
		_last_inspected_building_id = -1
		if _last_inspected_resident_id != resident.resident_id:
			_last_inspected_resident_id = resident.resident_id
			call_deferred("_reveal_work_permissions")
		work_header.visible = true
		inspector_title.text = "%s // RESIDENT" % resident.resident_name.to_upper()
		var is_lit := game.is_resident_lit(resident)
		var mood_factors := resident.needs.get_mood_factors(is_lit, resident.sleeping, game.oxygen_system.is_low())
		# A corpse has no live mood drivers: no light, hunger, low-O2 or break line.
		if not resident.alive:
			mood_factors = "Deceased · no live factors"
		elif resident.recreating:
			if game.job_system.is_recreation_running(resident):
				mood_factors = "Rec Console · +%.0f mood/s" % ResidentNeeds.RECREATION_RECOVERY_PER_SECOND
			elif game.job_system.is_actively_recreating(resident):
				mood_factors = "Rec Console · paused"
			else:
				mood_factors = "Seeking Rec Console · %s" % resident.needs.get_mood_factors(is_lit, false, game.oxygen_system.is_low())
		elif resident.stress_break_left > 0.0 and not resident.sleeping and not resident.drafted:
			mood_factors = "Stress break · mood holds · +%d in %ds" % [int(ResidentNeeds.STRESS_BREAK_RECOVERY), ceili(resident.stress_break_left)]
		inspector_state.text = "Current task: %s\nWork speed: %d%%%s\nMood: %s\n%s" % [
			_get_resident_order_status(resident),
			roundi((resident.get_work_multiplier() if resident.alive else 1.0) * 100.0),
			(" · Rec boost %ds%s" % [ceili(resident.rec_boost_left), " paused" if resident.sleeping else ""]) if resident.rec_boost_left > 0.0 else "",
			resident.needs.get_mood_state(),
			mood_factors,
		]
		if not resident.alive:
			# A corpse has no mood tier either (QA 2026-10-18c #6).
			var inspector_lines := inspector_state.text.split("\n")
			inspector_lines[2] = "Mood: none"
			inspector_state.text = "\n".join(inspector_lines)
		_set_need("food", "FOOD", resident.needs.food)
		_set_need("rest", "REST", resident.needs.rest)
		_set_need("mood", "MOOD", resident.needs.mood)
		_set_need("health", "HEALTH", resident.needs.health)
		_show_resident_commands(resident)
		if resident.trait_id != "":
			inspector_state.text += "\nTrait: %s · %s" % [resident.trait_id, VaultResident.TRAIT_EFFECTS[resident.trait_id]]
		work_header.text = "WORK PRIORITIES · APPLY AFTER UNDRAFT" if resident.drafted else "WORK PRIORITIES · 1 HIGHEST"
		for key: String in work_buttons:
			var button: Button = work_buttons[key]
			button.visible = true
			button.disabled = not resident.alive
			button.text = "%s: %s" % [key.to_upper(), resident.get_work_priority_label(key)]
			button.tooltip_text = (
				"Cycle %s priority: 1 highest, 4 lowest, or OFF. This schedule applies after undraft."
				% key.capitalize()
				if resident.drafted
				else "Cycle %s priority: 1 highest, 4 lowest, or OFF." % key.capitalize()
			)
			_set_priority_button_color(button, resident.get_work_priority(key))
		_hide_fixture_controls()
		return
	_last_inspected_resident_id = -1
	if game.selected_breach:
		_last_inspected_building_id = -1
		inspector_title.text = "MAINTENANCE HATCH"
		match game.breach_system.phase:
			BreachSystem.Phase.WARNING:
				inspector_state.text = "Seal load · %d%%\nO2 venting in %s\n%s" % [
					roundi(game.breach_system.get_pressure_percent()),
					_format_seconds(game.breach_system.get_time_to_open()),
					_breach_response_line(),
				]
			BreachSystem.Phase.OPEN:
				inspector_state.text = "BREACH OPEN · O2 -%.1f%%/s\nPatch work remaining: %.1fs\n%s" % [
					OxygenSystem.OPEN_BREACH_LOSS_PER_SECOND,
					game.breach_system.patch_work_left,
					_breach_response_line(),
				]
			BreachSystem.Phase.SEALED:
				inspector_state.text = "CONTAINED · Patch complete\nNo further breach oxygen loss."
			_:
				inspector_state.text = "Seal monitor nominal."
		_hide_needs_and_work()
		_hide_fixture_controls()
		return
	var building := game.get_building_by_id(game.selected_building_id)
	if building != null:
		if _last_inspected_building_id != building.building_id:
			_last_inspected_building_id = building.building_id
			call_deferred("_reveal_fixture_controls")
		inspector_title.text = building.get_display_name().to_upper()
		if building.complete:
			var power_text := "NO DEMAND"
			if building.is_power_consumer():
				if building.manually_disabled:
					power_text = "DISABLED"
				elif building.powered:
					power_text = "POWERED"
				elif game.power_grid.is_building_shed(building.building_id):
					power_text = "SHED · BROWNOUT"
				else:
					power_text = "UNPOWERED"
			inspector_state.text = "Online · %s\nPower: %d demand / %d output" % [power_text, building.get_base_power_demand(), building.get_power_output()]
			if building.is_power_consumer():
				inspector_state.text += "\nPriority: %s (fixed)" % building.get_power_priority_name()
			if building.kind == VaultBuilding.Kind.LAMP:
				inspector_state.text += "\nLight: %s · %d-tile radius\nFootprint: %d carved floor cells\nDarkness outside coverage: -%d mood/day" % [
					"ACTIVE" if building.powered else "OFFLINE",
					LightingSystem.LUMEN_RADIUS,
					game.lighting_system.get_lumen_lit_floor_count(building),
					roundi(ResidentNeeds.DARKNESS_MOOD_LOSS_PER_DAY),
				]
			elif building.kind == VaultBuilding.Kind.GROW_TRAY:
				inspector_state.text += "\nGrowth: %d%% · yields 1 raw\nAwaiting Haul: %d raw" % [
					floori(building.production_progress / building.get_grow_seconds() * 100.0),
					game.job_system.get_pending_raw_food_at(building.cell),
				]
			elif building.kind == VaultBuilding.Kind.KITCHEN:
				inspector_state.text += "\nRecipe: %d raw -> %d meal\nAwaiting Haul: %d meals" % [
					FoodSystem.COOK_INPUT,
					FoodSystem.COOK_OUTPUT,
					game.job_system.get_pending_meals_at(building.cell),
				]
			elif building.kind == VaultBuilding.Kind.AIR_RECYCLER:
				inspector_state.text += "\nO2 recovery: +%.1f%%/s" % OxygenSystem.RECYCLER_OUTPUT_PER_SECOND
			elif building.kind == VaultBuilding.Kind.MEDICAL_BED:
				var patient := game.get_resident_by_id(building.reserved_by)
				inspector_state.text += "\nCare: %s\nRecovery: +2 HP/s · seek at HP <= 95" % ("DISABLED" if building.manually_disabled else ("AVAILABLE" if patient == null else patient.resident_name + " · " + patient.state))
			elif building.kind == VaultBuilding.Kind.RECREATION_CONSOLE:
				inspector_state.text += "\nMood recovery: +%.0f/s · one resident" % ResidentNeeds.RECREATION_RECOVERY_PER_SECOND
				var console_user := _get_recreation_user(building.building_id)
				if not building.powered:
					inspector_state.text += "\nRecreation: OFFLINE"
				elif console_user != null:
					var use_state := "RESERVED"
					if game.job_system.is_recreation_running(console_user):
						use_state = "IN USE"
					elif game.job_system.is_actively_recreating(console_user):
						use_state = "PAUSED"
					inspector_state.text += "\nRecreation: %s · %s" % [use_state, console_user.resident_name]
				else:
					inspector_state.text += "\nRecreation: AVAILABLE · seek at %d%%" % roundi(ResidentNeeds.RECREATION_SEEK_THRESHOLD)
			_show_fixture_controls(building)
		else:
			inspector_state.text = "Blueprint · Salvage %d/%d\nAssembly remaining: %.1fs" % [building.delivered, building.get_cost(), building.construction_left]
			var shortfall := _salvage_shortfall(building.kind)
			if shortfall > 0 and not building.is_supplied():
				var tiles := _salvage_dig_tiles(shortfall)
				inspector_state.text += "\nShort %d salvage (shared stock) · " % shortfall
				inspector_state.text += "dig %d more rock" % tiles if tiles > 0 else "queued dig/haul covers it"
			_hide_fixture_controls()
		_hide_needs_and_work()
		return
	_last_inspected_building_id = -1
	inspector_title.text = "INSPECTOR"
	inspector_state.text = "AUTO WORK is the main loop (Dig/Haul/Craft/Cook defaults). Optional: [R] draft/undraft; right-click drafted = move, undrafted = force once. PRIORITIES [P] only to specialize."
	_hide_needs_and_work()
	_hide_fixture_controls()


func _refresh_alerts(step: Dictionary) -> void:
	all_alerts.clear()
	alert_list.clear()
	alert_hidden_count = 0
	_refresh_alert_details()
	if game.ended:
		# The outcome panel is up and the shift is over: one outcome line, no live advice.
		var won := game.outcome == "win"
		alert_label.text = "SHIFT ENDED · %s" % ("SEAL STABILIZED" if won else "WING LOST")
		_fit_alert_line()
		alert_label.add_theme_color_override("font_color", Color("75d4b4") if won else Color("ef6860"))
		return
	var alerts: Array[String] = []
	var drafted_count := 0
	for resident: VaultResident in game.residents:
		if resident.alive and resident.drafted:
			drafted_count += 1
	if drafted_count > 0:
		alerts.append("DRAFTED CREW %d · AUTO WORK PAUSED" % drafted_count)
		if game.breach_system.phase == BreachSystem.Phase.WARNING or game.breach_system.phase == BreachSystem.Phase.OPEN:
			alerts.append("HATCH RESPONSE EXCLUDES DRAFTED CREW")
	if game.day_cycle.completed and not game.ended and not game.keep_running:
		var victory_blockers: Array[String] = []
		if not game.breach_system.is_sealed():
			victory_blockers.append("SEAL HATCH")
		if not game.oxygen_system.is_breathable():
			victory_blockers.append("O2 >= 15%")
		alerts.append("VICTORY PENDING · %s" % " + ".join(victory_blockers))
	if game.keep_running and game.annex_welcome_left > 0.0 and game.annex_resident() != null:
		alerts.append(ANNEX_TEXT.welcome % game.annex_resident().resident_name.to_upper())
	var air_tap := air_safe_tap_seconds()
	if is_finite(air_tap) and air_tap > 0.0 and (game.oxygen_system.is_low() or air_early_warning()):
		alerts.append("OXYGEN · " + _air_countdown_text(air_tap))
	elif game.oxygen_system.is_critical():
		alerts.append("OXYGEN CRITICAL")
	elif game.oxygen_system.is_low():
		alerts.append("OXYGEN LOW")
	elif air_early_warning():
		alerts.append("OXYGEN LOW IN %s" % _format_seconds(game.oxygen_system.get_seconds_to_low()))
	if game.breach_system.phase == BreachSystem.Phase.OPEN:
		alerts.append("BREACH OPEN · O2 VENTING" + _breach_patch_alert_suffix())
	elif game.breach_system.phase == BreachSystem.Phase.WARNING:
		alerts.append("SEAL WARNING · %s" % _format_seconds(game.breach_system.get_time_to_open()))
	if game.food_system.meals <= 0 and game.get_alive_count() > 0:
		alerts.append("NO MEALS")
	elif game.food_system.meals < game.get_alive_count():
		alerts.append("LOW MEALS")
	var pending_food := game.job_system.get_pending_raw_food() + game.job_system.get_pending_meals()
	if pending_food > 0 and not _has_eligible_worker("haul"):
		alerts.append("FOOD WAITING · ENABLE HAUL")
	if game.power_grid.brownout_active:
		alerts.append("POWER BROWNOUT · SHED %s" % game.power_grid.get_shed_summary())
	var dark_residents := game.get_dark_alert_count()
	if dark_residents > 0:
		alerts.append("DARKNESS · %d CREW UNLIT" % dark_residents)
	var residents_needing_bunks := 0
	var occupied_bunks: Dictionary = {}
	for resident: VaultResident in game.residents:
		if resident.sleeping and resident.bed_id >= 0:
			occupied_bunks[resident.bed_id] = true
		elif resident.medical_bed_id >= 0 and resident.state == "Rest-Medical":
			continue
		elif resident.alive and not resident.drafted and (resident.needs.rest <= 28.0 or (resident.sleeping and resident.bed_id < 0)):
			residents_needing_bunks += 1
	var free_bunks := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.BED and building.complete and not occupied_bunks.has(building.building_id):
			free_bunks += 1
	if residents_needing_bunks > free_bunks:
		var rest_critical := false
		for resident: VaultResident in game.residents:
			if resident.alive and resident.needs.rest < 15.0:
				rest_critical = true
				break
		alerts.append("BED SHORTAGE" if rest_critical else "BED SHORTAGE · crew rotate")
	var injured := 0
	var free_medical := 0
	for resident: VaultResident in game.residents:
		if _counts_as_injured(resident):
			injured += 1
	for bed: VaultBuilding in game.buildings:
		if bed.kind == VaultBuilding.Kind.MEDICAL_BED and bed.complete and not bed.manually_disabled and bed.reserved_by < 0:
			free_medical += 1
	var medical_beds_built := game.get_completed_building_count(VaultBuilding.Kind.MEDICAL_BED)
	if medical_beds_built > 0:
		alerts.append("INJURED %d · MED BEDS FREE %d" % [injured, free_medical])
	else:
		# F5a: NO MED BED names a Med Bed need, so a scratch above the seek threshold
		# (no Med Bed wanted yet) stays out of it; the HUD injured count is unchanged.
		var needing_med_bed := 0
		for resident: VaultResident in game.residents:
			if _counts_as_injured(resident) and resident.needs.wants_medical_care():
				needing_med_bed += 1
		if needing_med_bed > 0:
			alerts.append("INJURED %d · NO MED BED" % needing_med_bed)
	var lowest_mood_resident: VaultResident = null
	var recreation_needed := false
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		if resident.needs.wants_recreation():
			recreation_needed = true
		if lowest_mood_resident == null or resident.needs.mood < lowest_mood_resident.needs.mood:
			lowest_mood_resident = resident
	if recreation_needed:
		if game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) <= 0:
			alerts.append("NO REC CONSOLE")
		elif game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) <= 0:
			alerts.append("REC CONSOLE OFFLINE")
	if lowest_mood_resident != null:
		if lowest_mood_resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD:
			alerts.append("MOOD BREAK RISK · %s" % lowest_mood_resident.resident_name)
		elif lowest_mood_resident.needs.mood < 40.0:
			alerts.append("MOOD STRESSED · %s" % lowest_mood_resident.resident_name)
	if game.keep_running and not game.ended:
		_keep_running_injury_alert(alerts, free_medical)
	var cook_enabled := _has_eligible_worker("cook")
	if not cook_enabled:
		alerts.append("NO COOK ENABLED")
	var critical_residents: Array[VaultResident] = []
	for resident: VaultResident in game.residents:
		if resident.alive and (resident.needs.food < 20.0 or resident.needs.rest < 15.0):
			var seconds := _projected_death_seconds(resident, INF)
			var index := critical_residents.size()
			while index > 0 and seconds < _projected_death_seconds(critical_residents[index - 1], INF):
				index -= 1
			critical_residents.insert(index, resident)
	if not critical_residents.is_empty():
		# Keep the first-ranked fallback when Next already covers everyone.
		var critical_resident: VaultResident = critical_residents[0]
		for resident: VaultResident in critical_residents:
			if not _alert_stated_by_next("CRITICAL: %s" % resident.resident_name, step):
				critical_resident = resident
				break
		alerts.append("CRITICAL: %s" % critical_resident.resident_name)
	# The cache is informational and must not escalate the status colour.
	var only_welcome := alerts.size() == 1 and game.keep_running and game.annex_welcome_left > 0.0 and alerts[0].begins_with("NEW CREW")
	var alert_color := Color("75d4b4") if alerts.is_empty() or only_welcome else Color("ef6860")
	var cache_notice := game.supply_cache_alert()
	if not cache_notice.is_empty():
		alerts.append(cache_notice)
	var cook_notice := game.cook_auto_alert()
	if not cook_notice.is_empty():
		alerts.append(cook_notice)
	var reclaim_notice := game.cook_auto_reclaim_alert()
	if not reclaim_notice.is_empty():
		alerts.append(reclaim_notice)
	all_alerts = _order_alerts_by_urgency(alerts)
	for alert: String in all_alerts:
		# Air alerts stay listed even when Next names the fix: they are the most lethal.
		# The open breach's patch step leads and stays listed too: it is what stops the venting.
		if alert.begins_with("OXYGEN ") or alert.begins_with("BREACH OPEN") or not _alert_stated_by_next(alert, step):
			alert_list.append(alert)
	# A starving resident leads the alert line right after any air alert, even though Next names them too.
	var starving := _starving_alert(step)
	if not starving.is_empty():
		all_alerts.insert(_air_alert_count(all_alerts), starving)
		alert_list.insert(_air_alert_count(alert_list), starving)
	if all_alerts.is_empty():
		alert_label.text = "STATUS NOMINAL"
	elif alert_list.is_empty():
		alert_label.text = "SEE NEXT"
	# Include folded clauses in the severity decision, after the existing Next filtering.
	if game.keep_running and not alert_list.is_empty():
		var only_warnings := true
		for alert: String in alert_list:
			if not _is_calm_stress_alert(alert):
				only_warnings = false
				break
		if only_warnings:
			alert_color = Color("efc56b")
	_fit_alert_line()
	alert_label.add_theme_color_override("font_color", alert_color)
	_refresh_alert_details()


const STARVING_ALERT_PREFIX := "STARVING: "


# " · MARK 1 ROCK [E]": the YOU action of the hatch blocker step, or "" when the patch is covered.
func _breach_patch_alert_suffix() -> String:
	var blocker := _breach_blocker_step()
	var text := str(blocker.get("text", ""))
	if not text.begins_with("Next: YOU "):
		return ""
	return " · " + text.trim_prefix("Next: YOU ").get_slice(" · ", 0).to_upper()


func _air_alert_count(alerts: Array[String]) -> int:
	var count := 0
	while count < alerts.size() and (alerts[count].begins_with("OXYGEN ") or alerts[count].begins_with("BREACH OPEN")):
		count += 1
	return count


func _starving_alert(step: Dictionary) -> String:
	if _starving_resident_id < 0:
		return ""
	# The starvation state drives the alert, not the name in Next: a hatch, power or mood
	# step for the same food crisis drops the name but keeps cause=food and the resident.
	# An Air step that replaced a hopeless food rescue carries that resident as food_resident_id.
	var food_id := int(step.get("resident_id", -1)) if str(step.get("cause", "")) == "food" else int(step.get("food_resident_id", -1))
	if food_id != _starving_resident_id:
		return ""
	for resident: VaultResident in game.residents:
		if resident.alive and resident.resident_id == _starving_resident_id:
			return STARVING_ALERT_PREFIX + resident.resident_name
	return ""


func _alert_line_text(visible_count: int) -> String:
	var clauses: Array[String] = []
	for alert: String in alert_list.slice(0, visible_count):
		# Internal spaces (including those around an internal dot) never wrap.
		clauses.append(alert.replace(" ", "\u00a0"))
	if not clauses.is_empty():
		clauses[0] = _break_overwide_clause(clauses[0])
	var hidden := alert_list.size() - visible_count
	if hidden > 0:
		clauses.append("+%d\u00a0more" % hidden)
	# Only the separators between complete clauses offer line breaks.
	return "  ·  ".join(clauses)


# A first clause wider than the rail (e.g. "BREACH OPEN · O2 VENTING · ENABLE CRAFT [P]" at
# 310 px) breaks at its own " · " separators instead of overflowing the right edge.
func _break_overwide_clause(clause: String) -> String:
	var width := alert_label.size.x
	if width <= 0.0:
		return clause
	var font := alert_label.get_theme_font("font")
	var font_size := alert_label.get_theme_font_size("font_size")
	if font.get_string_size(clause, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return clause
	var lines: PackedStringArray = []
	var line := ""
	for part: String in clause.split("\u00a0·\u00a0"):
		var candidate := line + "\u00a0·\u00a0" + part if not line.is_empty() else part
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = part
		else:
			line = candidate
	lines.append(line)
	return "\n".join(lines)


func _wrap_alert_line(text: String) -> String:
	var width := alert_label.size.x
	if width <= 0.0:
		return text
	var font := alert_label.get_theme_font("font")
	var font_size := alert_label.get_theme_font_size("font_size")
	var lines: PackedStringArray = []
	var line := ""
	for clause: String in text.split("  ·  "):
		var candidate := line + "  ·  " + clause if not line.is_empty() else clause
		# Measure only the rendered last line (a broken first clause already holds newlines).
		var last_line := candidate.get_slice("\n", candidate.count("\n"))
		if not line.is_empty() and font.get_string_size(last_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = clause
		else:
			line = candidate
	lines.append(line)
	return "\n".join(lines)


func _fit_alert_line() -> void:
	if _fitting_alert_line or alert_list.is_empty():
		return
	_fitting_alert_line = true
	var visible_count := mini(MAX_VISIBLE_ALERTS, alert_list.size())
	alert_label.text = _alert_line_text(visible_count)
	if visible_count == 2 and alert_label.size.x > 0.0:
		var font := alert_label.get_theme_font("font")
		var font_size := alert_label.get_theme_font_size("font_size")
		var second_width := font.get_string_size(alert_list[1].replace(" ", "\u00a0"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		# Word wrapping cannot split a clause. Reject an overwide second clause
		# too, since it could overflow horizontally while counting as one line.
		if second_width > alert_label.size.x or alert_label.get_line_count() > 2:
			visible_count = 1
			alert_label.text = _alert_line_text(visible_count)
	# Keep the existing clause/fold decision above. A separator belongs only
	# between clauses sharing a rendered line, never at either edge of a wrap.
	alert_label.text = _wrap_alert_line(alert_label.text)
	alert_hidden_count = alert_list.size() - visible_count
	_refresh_alert_details()
	_fitting_alert_line = false


func _refresh_alert_details() -> void:
	if alert_more_label == null:
		return
	var folded := alert_list.slice(alert_list.size() - alert_hidden_count)
	while alert_more_label.get_child_count() > folded.size():
		alert_more_label.get_child(-1).free()
	for index in folded.size():
		var row: Label
		if index < alert_more_label.get_child_count():
			row = alert_more_label.get_child(index)
		else:
			row = Label.new()
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			alert_more_label.add_child(row)
		row.text = folded[index]
		row.add_theme_color_override("font_color", Color("efc56b") if _is_calm_stress_alert(row.text) else Color("ef6860"))
	alert_more_label.visible = _details_expanded and alert_hidden_count > 0
	alert_more_header.visible = alert_more_label.visible


func _is_calm_stress_alert(alert: String) -> bool:
	return game.keep_running and alert.begins_with("MOOD STRESSED · ")


func _alert_urgency_seconds(alert: String) -> float:
	if alert.begins_with("CRITICAL: "):
		for resident: VaultResident in game.residents:
			if resident.alive and alert == "CRITICAL: %s" % resident.resident_name:
				return _projected_death_seconds(resident, INF)
		return INF
	if alert.begins_with("OXYGEN "):
		if game.oxygen_system.is_critical():
			return 0.0
		var crossing := game.oxygen_system.get_seconds_to_critical_crossing()
		return crossing if crossing >= 0.0 else INF
	if alert.begins_with("BREACH OPEN") or alert.begins_with("SEAL WARNING"):
		return game.breach_system.get_time_to_open()
	if alert == "NO MEALS" or alert == "LOW MEALS":
		return _food_runway_seconds()
	return INF


func _order_alerts_by_urgency(alerts: Array[String]) -> Array[String]:
	# Insertion keeps the old severity order for equal deadlines (including INF).
	var ordered: Array[String] = []
	for alert: String in _order_alerts_by_severity(alerts):
		var seconds := _alert_urgency_seconds(alert)
		var index := ordered.size()
		while index > 0 and seconds < _alert_urgency_seconds(ordered[index - 1]):
			index -= 1
		ordered.insert(index, alert)
	# Lethality tiers lead: air, then starvation, then critical HP, then the rest.
	# Each tier keeps the deadline order above.
	var air_deadline := _air_alert_deadline(ordered)
	var tiered: Array[String] = []
	# An open breach vents the air for everyone: its patch step leads every tier.
	for alert: String in ordered:
		if alert.begins_with("BREACH OPEN"):
			tiered.append(alert)
	for tier in 4:
		for alert: String in ordered:
			if alert.begins_with("BREACH OPEN"):
				continue
			if _alert_lethality_tier(alert, air_deadline) == tier:
				tiered.append(alert)
	return tiered


# Earliest oxygen deadline among the alerts, or -INF when no oxygen alert is listed.
func _air_alert_deadline(alerts: Array[String]) -> float:
	var deadline := -INF
	for alert: String in alerts:
		if alert.begins_with("OXYGEN "):
			var seconds := _alert_urgency_seconds(alert)
			deadline = seconds if deadline == -INF else minf(deadline, seconds)
	return deadline


func _alert_lethality_tier(alert: String, air_deadline: float = -INF) -> int:
	if alert.begins_with("OXYGEN "):
		return 0
	# A hatch that opens before the air runs out vents the air first: it joins the air tier.
	if alert.begins_with("SEAL WARNING") and air_deadline != -INF and game.breach_system.get_time_to_open() < air_deadline:
		return 0
	if alert == "NO MEALS" or alert == "LOW MEALS" or alert.begins_with(STARVING_ALERT_PREFIX):
		return 1
	if alert.begins_with("CRITICAL: "):
		return 2
	return 3


func _alert_stated_by_next(alert: String, step: Dictionary) -> bool:
	if step.is_empty():
		return false
	var text := str(step.get("text", "")).to_lower()
	# Queued builds are explicitly stated even when another action now leads Next.
	for building_name: String in step.get("in_progress", []):
		text += " · " + building_name.to_lower() + " in progress"
	if alert.begins_with("CRITICAL: "):
		var resident_name := alert.trim_prefix("CRITICAL: ")
		for resident: VaultResident in game.residents:
			if resident.resident_name == resident_name and bool(step.get("urgent", false)) and int(step.get("resident_id", -1)) == resident.resident_id:
				return true
		for condition: String in ["starving", "exhausted", "critical", "suffocating", "low on air", "in despair"]:
			if (" " + resident_name.to_lower() + " " + condition) in (" " + text):
				return true
		return false
	if alert.begins_with("BED SHORTAGE"):
		return str(step.get("tool", "")) == "bed" or "bunk" in text
	if alert == "NO REC CONSOLE" or alert == "REC CONSOLE OFFLINE" or alert.begins_with("MOOD "):
		if "rec console" in text or "recover mood" in text:
			return true
		if alert.begins_with("MOOD "):
			var resident_name := alert.get_slice(" · ", 1).to_lower()
			return not resident_name.is_empty() and (" " + resident_name + " ") in (" " + text.replace(" · ", " ") + " ")
	if alert == "NO COOK ENABLED":
		return "enable cook" in text
	if alert == "FOOD WAITING · ENABLE HAUL":
		return "enable haul" in text
	if alert == "NO MEALS" or alert == "LOW MEALS":
		return str(step.get("kind", "")) == STEP_KIND_FOOD or "nutrient station" in text or "grow tray" in text or "cook" in text or "meals" in text or "starving" in text
	if alert.begins_with("OXYGEN "):
		return "air recycler" in text or "suffocating" in text
	if alert.begins_with("SEAL WARNING") or alert.begins_with("BREACH OPEN"):
		return "hatch" in text or (alert.begins_with("SEAL WARNING") and "acknowledge warning" in text)
	if alert.begins_with("POWER BROWNOUT"):
		return "charge node" in text
	if alert.begins_with("INJURED ") and "NO MED BED" in alert:
		return "med bed" in text or "medical bed" in text
	if alert.begins_with("DARKNESS"):
		return "lumen" in text
	return false


# Starvation is not an injury a Med Bed can treat (QA 2026-10-18c #4): JobSystem._handle_medical
# never admits a resident at food <= 35 and starving drains 4 HP/s, so a hungry resident's lost
# HP counts toward INJURED only once they are fed, or while they already hold a Med Bed.
const MED_BED_MIN_FOOD := 35.0


func _counts_as_injured(resident: VaultResident) -> bool:
	if not resident.alive or resident.needs.health >= 100.0:
		return false
	return resident.medical_bed_id >= 0 or resident.needs.food > MED_BED_MIN_FOOD


# Alert bar severity (QA 2026-10-18b #5): a resident CRITICAL leads, then the O2, breach and
# food threats, then everything else. Order within a tier and every wording are unchanged.
const ALERT_THREAT_PREFIXES: Array[String] = ["OXYGEN ", "BREACH OPEN", "SEAL WARNING", "NO MEALS", "LOW MEALS", "FOOD WAITING", "NO COOK ENABLED"]


func _order_alerts_by_severity(alerts: Array[String]) -> Array[String]:
	var ordered: Array[String] = []
	var threats: Array[String] = []
	var rest: Array[String] = []
	for alert in alerts:
		if alert.begins_with("CRITICAL: "):
			ordered.append(alert)
			continue
		var is_threat := false
		for prefix in ALERT_THREAT_PREFIXES:
			if alert.begins_with(prefix):
				is_threat = true
				break
		if is_threat:
			threats.append(alert)
		else:
			rest.append(alert)
	ordered.append_array(threats)
	ordered.append_array(rest)
	return ordered


func _refresh_power_detail() -> void:
	var power := game.power_grid
	power_detail_label.text = "SUPPLY %d · DEMAND %d\nSERVED %d · RESERVE %d" % [
		power.supply,
		power.demand,
		power.served,
		maxi(0, power.supply - power.served),
	]
	if power.brownout_active:
		power_detail_label.text += "\nSHED %d POWER · %s" % [power.shed_demand, power.get_shed_summary()]
	elif power.disabled_demand > 0:
		power_detail_label.text += "\nDISABLED %d POWER · %s" % [power.disabled_demand, power.get_disabled_summary()]
	else:
		power_detail_label.text += "\nALL CONSUMERS SERVED"
	power_detail_label.add_theme_color_override("font_color", Color("ef6860") if power.brownout_active else Color("75d4b4"))


func _refresh_crew_mood() -> void:
	var lowest: VaultResident = null
	var mood_total := 0.0
	var living_count := 0
	var recreation_count := 0
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		living_count += 1
		mood_total += resident.needs.mood
		if lowest == null or resident.needs.mood < lowest.needs.mood:
			lowest = resident
		if game.job_system.is_recreation_running(resident):
			recreation_count += 1
	if lowest == null:
		crew_mood_label.text = "NO LIVING RESIDENTS"
		crew_mood_bar.value = 0.0
		crew_mood_bar.modulate = Color("ef6860")
		return
	crew_mood_label.text = "LOW %s %d%% · %s\nAVERAGE %d%% · %d RECREATING" % [
		lowest.resident_name.to_upper(),
		roundi(lowest.needs.mood),
		lowest.needs.get_mood_state(),
		roundi(mood_total / float(living_count)),
		recreation_count,
	]
	crew_mood_bar.value = lowest.needs.mood
	crew_mood_bar.modulate = Color("ef5a54") if lowest.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD else (Color("efc56b") if lowest.needs.mood < 70.0 else Color("75d4b4"))


func _refresh_lighting() -> void:
	var lighting := game.lighting_system
	var lit_floor := lighting.get_lit_floor_count()
	var dark_floor := lighting.get_dark_floor_count()
	var total_floor := lit_floor + dark_floor
	var dark_residents := game.get_dark_resident_count()
	lighting_label.text = "LIT %d/%d · L%d/%d · D%d" % [
		lit_floor,
		total_floor,
		lighting.get_powered_lumen_count(),
		lighting.get_completed_lumen_count(),
		dark_residents,
	]
	lighting_label.tooltip_text = "%d%% of carved floor lit · %d/%d Lumens online · %d living residents dark" % [
		roundi(lighting.get_floor_coverage_percent()),
		lighting.get_powered_lumen_count(),
		lighting.get_completed_lumen_count(),
		dark_residents,
	]
	lighting_label.add_theme_color_override("font_color", Color("efc56b") if dark_residents > 0 else Color("75d4b4"))
	lighting_overlay_button.text = "[L] MAP %s" % ("ON" if lighting.is_coverage_overlay_visible() else "OFF")
	lighting_overlay_button.modulate = Color("efc56b") if lighting.is_coverage_overlay_visible() else Color.WHITE


# Use the same living crew drain as the food forecast, including FRUGAL.
# Floor to a tenth so the HUD never overpromises.
func _meal_runway_text() -> String:
	var consumption := _crew_meals_per_day()
	if game.ended or consumption <= 0.0:
		return ""
	var meals := game.food_system.meals + game.job_system.get_pending_meals()
	return " · %.1f DAYS" % (floorf(float(meals) * 10.0 / consumption) / 10.0)

func _refresh_oxygen() -> void:
	var oxygen := game.oxygen_system
	var rate_prefix := "+" if oxygen.net_rate > 0.0001 else ""
	oxygen_label.text = "O2 %d%% · %s%.2f%%/s\nUSE %.2f · RECYCLE %.2f" % [
		roundi(oxygen.oxygen),
		rate_prefix,
		oxygen.net_rate,
		oxygen.consumption_rate,
		oxygen.recycler_output_rate,
	]
	if oxygen.breach_loss_rate > 0.0:
		oxygen_label.text += " · LEAK %.1f" % oxygen.breach_loss_rate
	# A finished wing no longer simulates, so a countdown would freeze forever.
	var crossing := -1.0 if game.ended else oxygen.get_seconds_to_critical_crossing()
	if crossing >= 0.0:
		oxygen_label.text += "\n%s IN %s" % [
			"CRITICAL" if oxygen.net_rate < 0.0 else "BREATHABLE",
			_format_seconds(crossing),
		]
	elif not game.ended and oxygen.is_critical() and oxygen.net_rate <= 0.0001:
		# Below the line with no recovery in sight, count down the HP drain instead.
		var first_death := _seconds_to_first_suffocation()
		if first_death >= 0.0:
			oxygen_label.text += "\nSUFFOCATING · FIRST DEATH IN %s" % _format_seconds(first_death)
	oxygen_bar.value = oxygen.oxygen
	if oxygen.is_critical():
		oxygen_bar.modulate = Color("ef6860")
	elif oxygen.is_low():
		oxygen_bar.modulate = Color("efc56b")
	else:
		oxygen_bar.modulate = Color("75d4b4")


func _breach_response_line() -> String:
	# After a wipe nobody can answer the hatch, but JobSystem still names the
	# first blocker (e.g. ENABLE HAUL). Win always ends SEALED, so this is loss-only.
	if game.ended:
		return "NO LIVING CREW · RESPONSE ENDED"
	return game.job_system.get_breach_response_status()


func _refresh_breach() -> void:
	var breach := game.breach_system
	breach_focus_button.visible = breach.phase != BreachSystem.Phase.DORMANT
	_order_hatch_block(breach.is_response_active())
	match breach.phase:
		BreachSystem.Phase.DORMANT:
			breach_label.text = "WATCH ACTIVE · TEST IN %s" % _format_seconds(breach.get_time_to_warning(game.day_cycle.elapsed_seconds))
			breach_bar.value = 0.0
			breach_bar.modulate = Color("8faeb7")
		BreachSystem.Phase.WARNING:
			breach_label.text = "WARNING · SEAL LOAD %d%% · %s\nPATCH %d/%d\n%s" % [
				roundi(breach.get_pressure_percent()),
				_format_seconds(breach.get_time_to_open()),
				breach.patch_delivered,
				BreachSystem.PATCH_COST,
				_breach_response_line(),
			]
			breach_bar.value = breach.get_pressure_percent()
			breach_bar.modulate = Color("efc56b")
		BreachSystem.Phase.OPEN:
			breach_label.text = "BREACH OPEN · O2 -%.1f%%/s\nPATCH %d/%d · WORK %.1fs\n%s" % [
				OxygenSystem.OPEN_BREACH_LOSS_PER_SECOND,
				breach.patch_delivered,
				BreachSystem.PATCH_COST,
				breach.patch_work_left,
				_breach_response_line(),
			]
			breach_bar.value = 100.0
			breach_bar.modulate = Color("ef6860")
		BreachSystem.Phase.SEALED:
			breach_label.text = "CONTAINED · PATCH COMPLETE\nHATCH STABLE · NO ACTIVE LEAK"
			breach_bar.value = 0.0
			breach_bar.modulate = Color("75d4b4")


func _refresh_checklist() -> void:
	if checklist == null:
		return
	var initial_floor_count := game.map_grid.get_initial_floor_count()
	var cook_enabled := _has_eligible_worker("cook")
	var hatch_ready := (
		game.breach_system.is_sealed()
		or (
			game.food_system.salvage
				+ game.breach_system.patch_delivered
				+ game.job_system.get_breach_supply_in_transit()
				>= BreachSystem.PATCH_COST
			and _has_eligible_worker("haul")
			and _has_eligible_worker("craft")
		)
	)
	var food_chain_ready := (
		game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) >= 1
		and game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) >= 1
		and cook_enabled
		and _has_eligible_worker("haul")
	)
	var checks := [
		[game.map_grid.get_floor_cells().size() >= initial_floor_count + 12, "Excavate at least 12 connected tiles; haul rubble for salvage"],
		[game.get_completed_building_count(VaultBuilding.Kind.BED) >= 2, "Assemble at least 2 bunks"],
		[game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true) >= 1, "Build a Charge Node (+7 power)"],
		[food_chain_ready, "Power Grow Tray + Nutrient Station; keep Cook + Haul enabled"],
		[game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) >= 1, "Power an Air Recycler (3 power)"],
		[hatch_ready, "Reserve 4 salvage; keep Haul + Craft enabled"],
		[game.breach_system.is_sealed(), "Patch and seal the maintenance hatch"],
		[
			game.day_cycle.completed and game.breach_system.is_sealed() and game.oxygen_system.is_breathable(),
			"Finish Day 7 with a sealed hatch and O2 >= 15%",
		],
	]
	var lines: Array[String] = ["[color=#8faeb7]REQUIRED[/color]"]
	for check in checks:
		var marker := "[color=#75d4b4][DONE][/color]" if check[0] else "[color=#efc56b][    ][/color]"
		lines.append("%s  %s" % [marker, check[1]])
	if not _briefing_is_opening:
		lines.append_array(postseal_checklist_lines())
		var rec_done := game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) >= 1
		var rec_marker := "[color=#75d4b4][DONE][/color]" if rec_done else "[color=#8faeb7][OPTIONAL][/color]"
		lines.append("%s  Power a Rec Console; free 1 power if shed" % rec_marker)
		lines.append("[color=#efc56b]LIGHTING[/color]  Powered Lumens cover %d tiles. Shed Lumens stop lighting cells; darkness costs awake residents 30 extra mood/day. [L] maps coverage" % LightingSystem.LUMEN_RADIUS)
		lines.append("Optional: ZONE paints salvage + food drop-offs; CANCEL clears cells")
		lines.append("Optional: Medical Bed ($8) heals injuries; disable to deny care")
		lines.append("[color=#8faeb7][OPTIONAL][/color]  PRIORITIES [P]: 1 highest · 4 lowest · OFF disabled · same rank: build, food, rubble, then digs (defaults 3)")
		lines.append("[color=#8faeb7][OPTIONAL][/color]  MANUAL ORDERS (optional override): [R] draft/undraft; right-click force — ordinary auto-work does not need this")
	checklist.text = "\n".join(lines)
	if briefing_tips_label != null:
		if _briefing_is_opening:
			briefing_tips_label.text = "Tips: YOU designate · THEY auto-work · HELP · P specialize · R draft optional"
		else:
			briefing_tips_label.text = "Tips: Esc closes Help · P priorities · L light map · R draft / force orders"


# QA-e #2: after the seal, HELP names the post-seal economy the right panel offers.
func postseal_checklist_lines() -> Array[String]:
	var lines: Array[String] = []
	if game.ended or not game.breach_system.is_sealed():
		return lines
	var done_marker := "[color=#75d4b4][DONE][/color]"
	var open_marker := "[color=#efc56b][    ][/color]"
	lines.append("[color=#8faeb7]AFTER THE SEAL[/color]")
	for order_id: String in VaultGame.WING_ORDER_IDS:
		var goal: String = WING_ORDER_TEXT[order_id][0]
		var claimed := order_id in game.wing_orders_claimed
		if order_id == VaultGame.ORDER_STOCK_MEALS:
			goal = goal % VaultGame.ORDER_STOCK_MEALS_TARGET
			if not claimed:
				goal += " (%d/%d)" % [mini(game.food_system.meals, VaultGame.ORDER_STOCK_MEALS_TARGET), VaultGame.ORDER_STOCK_MEALS_TARGET]
		lines.append("%s  Wing order: %s → unlocks %s" % [done_marker if claimed else open_marker, goal, WING_ORDER_TEXT[order_id][1]])
	var reclaim_marker := open_marker
	if game.reclaim_active:
		reclaim_marker = done_marker if game.reclaim_paid >= VaultGame.RECLAIM_DELIVERIES else "[color=#75d4b4][ACTIVE][/color]"
	lines.append("%s  %s" % [reclaim_marker, reclaim_button_text()])
	var target := _upgrade_offer_target()
	if target != null:
		lines.append("[color=#efc56b][OFFER][/color]  Mk II: %s" % upgrade_offer_text(target))
	else:
		lines.append("[color=#8faeb7][OFFER][/color]  Mk II: nothing to fit right now")
	return lines


func _has_eligible_worker(work_type: String) -> bool:
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and resident.get_work_priority(work_type) != VaultResident.PRIORITY_DISABLED:
			return true
	return false


func _refresh_work_priorities_board() -> void:
	if work_priorities_grid == null or game == null:
		return
	var roster_parts: Array[String] = []
	for resident: VaultResident in game.residents:
		roster_parts.append("%d:%s:%s:%s" % [resident.resident_id, resident.resident_name, str(resident.alive), str(resident.drafted)])
	var roster_signature := "|".join(roster_parts)
	var roster_rebuilt := false
	if roster_signature != _last_work_priority_roster_signature:
		_last_work_priority_roster_signature = roster_signature
		_rebuild_work_priority_rows()
		roster_rebuilt = true
	var coverage := {"dig": 0, "haul": 0, "craft": 0, "cook": 0}
	for resident: VaultResident in game.residents:
		for work_type: String in VaultResident.WORK_TYPES:
			var button := get_work_priority_button(resident.resident_id, work_type)
			if button != null:
				var priority := resident.get_work_priority(work_type)
				button.text = resident.get_work_priority_label(work_type)
				button.disabled = not resident.alive
				button.tooltip_text = (
					"%s · %s priority %s. Click: 1 → 2 → 3 → 4 → OFF → 1."
					% [resident.resident_name, work_type.capitalize(), resident.get_work_priority_label(work_type)]
				)
				if resident.drafted:
					button.tooltip_text += " DRAFTED: this schedule remains editable and applies after undraft."
				_set_priority_button_color(button, priority)
				if resident.alive and not resident.drafted and priority != VaultResident.PRIORITY_DISABLED:
					coverage[work_type] = int(coverage[work_type]) + 1
	var coverage_parts: Array[String] = []
	var missing: Array[String] = []
	for work_type: String in VaultResident.WORK_TYPES:
		var count := int(coverage[work_type])
		coverage_parts.append("%s %d" % [work_type.to_upper(), count])
		if count <= 0:
			missing.append(work_type.to_upper())
	work_priorities_summary.text = "DEFAULTS ON // all start at 3 · open only to specialize\nCOVERAGE // %s" % "  ·  ".join(coverage_parts)
	var drafted_count := 0
	for resident: VaultResident in game.residents:
		if resident.alive and resident.drafted:
			drafted_count += 1
	if drafted_count > 0:
		work_priorities_summary.text += "\nDRAFTED %d · excluded from automatic work until undrafted; schedules remain editable." % drafted_count
	if missing.is_empty():
		work_priorities_summary.text += "\nAll ordinary work categories have at least one eligible resident."
		work_priorities_summary.add_theme_color_override("font_color", Color("75d4b4"))
	else:
		work_priorities_summary.text += "\nNO ELIGIBLE CREW // %s" % ", ".join(missing)
		work_priorities_summary.add_theme_color_override("font_color", Color("ef6860"))
	if work_priorities_overlay.visible:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if roster_rebuilt or focus_owner == null or not work_priorities_overlay.is_ancestor_of(focus_owner):
			_focus_first_work_priority_control()


func _set_priority_button_color(button: Button, priority: int) -> void:
	match priority:
		VaultResident.PRIORITY_HIGHEST:
			button.modulate = Color("efc56b")
		2:
			button.modulate = Color("9ed8c7")
		3:
			button.modulate = Color("75b9c5")
		VaultResident.PRIORITY_LOWEST:
			button.modulate = Color("8faeb7")
		_:
			button.modulate = Color("d68b8b")


func show_briefing(visible: bool, opening := false) -> void:
	if briefing_overlay == null or briefing_panel == null:
		return
	var was_visible := briefing_overlay.visible
	_briefing_is_opening = opening and visible
	briefing_overlay.visible = visible
	briefing_panel.visible = visible
	if briefing_begin_button != null:
		briefing_begin_button.visible = opening
	if briefing_close_button != null:
		briefing_close_button.visible = not opening
	# A replay's opening briefing hides LOAD: the checkpoint belongs to the run the player just ended.
	if briefing_load_button != null:
		briefing_load_button.visible = not (opening and _replay_opening)
	_refresh_sublevel_stepper()
	if visible:
		show_work_priorities(false)
		_refresh_checklist()
		_configure_briefing_focus(opening)
		_focus_first_briefing_control(opening)
	elif was_visible:
		get_viewport().gui_release_focus()


func _briefing_focus_controls(opening: bool) -> Array[Control]:
	var controls: Array[Control] = []
	var primary: Button = briefing_begin_button if opening else briefing_close_button
	if primary != null and primary.visible and not primary.disabled:
		controls.append(primary)
	# Tab reaches the sublevel stepper between the primary and LOAD; a disabled endpoint arrow stays out.
	if briefing_sublevel_row != null and briefing_sublevel_row.visible:
		for button: Button in [briefing_deeper_button, briefing_shallower_button]:
			if button.visible and not button.disabled:
				controls.append(button)
	# Meta perks P2: the perk arrows follow the sublevel arrows, before LOAD.
	if briefing_perk_row != null and briefing_perk_row.visible:
		for button: Button in [briefing_perk_prev_button, briefing_perk_next_button]:
			if button.visible and not button.disabled:
				controls.append(button)
	if briefing_load_button != null and briefing_load_button.visible and not briefing_load_button.disabled:
		controls.append(briefing_load_button)
	return controls


func _configure_briefing_focus(opening: bool) -> void:
	var controls := _briefing_focus_controls(opening)
	if controls.is_empty():
		return
	for index in controls.size():
		var control := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_bottom = control.get_path_to(next)


func _focus_first_briefing_control(opening: bool) -> void:
	var controls := _briefing_focus_controls(opening)
	if not controls.is_empty():
		controls[0].grab_focus()


func open_help() -> void:
	if (
		game == null
		or game.tutorial_open
		or game.ended
		or game.outcome == "death"
		or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
	):
		return
	show_briefing(true, false)


func is_help_open() -> bool:
	return (
		is_briefing_open()
		and game != null
		and not game.tutorial_open
	)


func is_briefing_open() -> bool:
	return briefing_overlay != null and briefing_overlay.visible


func show_breach_warning(visible: bool) -> void:
	if breach_warning_panel != null:
		breach_warning_panel.visible = visible
		if visible and breach_resume_button != null:
			show_briefing(false)
			show_work_priorities(false)
			if right_scroll != null:
				right_scroll.scroll_vertical = 0
			breach_resume_button.grab_focus()
		elif breach_resume_button != null and breach_resume_button.has_focus():
			breach_resume_button.release_focus()


func show_work_priorities(visible: bool) -> void:
	if work_priorities_overlay == null:
		return
	if visible and (
		game == null
		or game.tutorial_open
		or is_help_open()
		or game.ended
		or game.outcome == "death"
		or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
	):
		return
	var was_visible := work_priorities_overlay.visible
	work_priorities_overlay.visible = visible
	if visible:
		_refresh_work_priorities_board()
		_focus_first_work_priority_control()
	elif was_visible:
		get_viewport().gui_release_focus()


func toggle_work_priorities() -> void:
	show_work_priorities(not is_work_priorities_open())


func is_work_priorities_open() -> bool:
	return work_priorities_overlay != null and work_priorities_overlay.visible


func _reveal_work_permissions() -> void:
	await get_tree().process_frame
	if right_scroll == null or game == null or game.get_resident_by_id(game.selected_resident_id) == null:
		return
	if inspector_title != null:
		right_scroll.scroll_vertical = roundi(inspector_title.position.y)


func _reveal_fixture_controls() -> void:
	await get_tree().process_frame
	if right_scroll == null or game == null or game.get_building_by_id(game.selected_building_id) == null:
		return
	if inspector_title != null:
		right_scroll.scroll_vertical = roundi(inspector_title.position.y)


func clear_survival_tips() -> void:
	# New Game, LOAD and Retry all pass here: air latches recompute from the restored state.
	_air_warning_latched = false
	_air_next_latched = false
	_air_chain_named = false
	_idle_crew_since.clear()
	_idle_crew_sample_time = -1.0
	_next_hold_signature.clear()
	_next_hold_since = -1.0
	_next_hold_step.clear()
	_next_reclamation_kind = -1
	_displayed_next_step = {}
	_next_shown_step = {}
	_next_shown_since = -1.0
	_next_surge_step = {}
	_starving_resident_id = -1
	_food_forecast_latched = false
	_next_bunk_text = ""
	_next_bunk_help = ""
	_survival_tips.clear()
	_survival_tip_details.clear()
	_survival_tip_sample_left = 0.0
	_survival_tip_tick = 0
	_sampling_survival_tip = false


# Sample the very same selection used by the Next label, even without a HUD
# refresh (headless simulation). UI refreshes also retain the exact shown step.
func record_survival_tip(delta_seconds := 0.5) -> void:
	_update_idle_crew_tracking()
	if game.outcome != "" or game.ended:
		return
	_survival_tip_tick += 1
	_survival_tip_sample_left -= maxf(0.0, delta_seconds)
	if _survival_tip_sample_left > 0.0:
		return
	_survival_tip_sample_left = 0.5
	_sampling_survival_tip = true
	_remember_survival_tip(keep_running_next_step() if game.keep_running else _primary_next_step())
	_sampling_survival_tip = false


func _remember_survival_tip(step: Dictionary) -> void:
	if bool(step.get("too_late", false)) or bool(step.get("recovering", false)):
		return
	var resident := game.get_resident_by_id(int(step.get("resident_id", -1)))
	var tip := str(step.get("text", ""))
	# Queued work is HUD context, not part of the action that could save them.
	tip = tip.trim_suffix(_next_in_progress_suffix(step.get("in_progress", [])))
	if resident != null and resident.alive and tip.begins_with("Next: ") and resident.resident_name in tip:
		var cause := str(step.get("cause", step.get("kind", "")))
		if not _survival_tips.has(resident.resident_id):
			_survival_tips[resident.resident_id] = {}
			_survival_tip_details[resident.resident_id] = {}
		if _survival_tips[resident.resident_id].has(cause):
			return
		# Retain the first saving opportunity for each cause, before later
		# symptoms narrow the advice to an action that may arrive too late.
		_survival_tips[resident.resident_id][cause] = tip
		_survival_tip_details[resident.resident_id][cause] = {
			"cause": cause,
			"elapsed_seconds": _survival_tip_sim_time(),
			# A newly shown UI tip belongs to the upcoming simulation tick.
			"tick": _survival_tip_tick if _sampling_survival_tip else _survival_tip_tick + 1,
		}


func _survival_tip_sim_time() -> float:
	return game.day_cycle.elapsed_seconds + (game.keep_running_seconds if game.keep_running else 0.0)


func _saving_tip_for(resident: VaultResident) -> String:
	var cause: String = ["food", "rest", "mood", "air", ""][_resident_loss_cause(resident)]
	var details: Dictionary = _survival_tip_details.get(resident.resident_id, {})
	var first: Dictionary = details.get(cause, {})
	if first.is_empty():
		return ""
	# Damage and the death signal run before this tick advances the clock.
	# Require an earlier sim time, including for tips first shown by a UI
	# refresh. Only the capped Day 7 clock needs the simulation tick fallback.
	if float(first.elapsed_seconds) >= _survival_tip_sim_time():
		var clock_capped := game.day_cycle.completed and not game.keep_running
		if not clock_capped or int(first.tick) >= _survival_tip_tick:
			return ""
	if cause.is_empty() or str(first.cause) != cause:
		return ""
	var tips: Dictionary = _survival_tips.get(resident.resident_id, {})
	return str(tips.get(cause, ""))


func death_recap_for(resident: VaultResident) -> Dictionary:
	# Use the HUD's clock source at the death signal, before the tick aborts.
	var clock := game.day_cycle.get_clock_text()
	if game.day_cycle.completed and not game.day_cycle.wing_lost:
		# A death on the last tick of day 7 is not a completed day.
		clock = "DAY %d/7  ·  24:00" % DayCycle.DAYS_TO_SURVIVE
	if game.keep_running:
		var fraction := fmod(game.keep_running_seconds, DayCycle.SECONDS_PER_DAY) / DayCycle.SECONDS_PER_DAY
		var hours := floori(fraction * 24.0)
		var minutes := floori(fmod(fraction * 24.0, 1.0) * 60.0)
		clock = "DAY %d  ·  %02d:%02d" % [game.keep_running_day(), hours, minutes]
	var cause: String = ["starvation", "exhaustion", "despair", "suffocation", "unknown causes"][_resident_loss_cause(resident)]
	return {
		"resident_id": resident.resident_id,
		"name": resident.resident_name,
		"cause": cause,
		"time": clock,
		"elapsed_seconds": game.keep_running_seconds if game.keep_running else game.day_cycle.elapsed_seconds,
		"tip": _tip_naming_sidebar_build(_saving_tip_for(resident), cause),
	}


# For a starvation loss the recap names the food build the sidebar offers at the loss, not an older
# one from the first warning. Other causes keep their own advice (a suffocation Charge Node stays).
func _tip_naming_sidebar_build(tip: String, cause: String) -> String:
	if cause != "starvation":
		return tip
	var offered := _food_card_offer_kind()
	if offered < 0:
		offered = _upgrade_offer_nudge_kind() if _upgrade_offer_target() == null else -1
	if offered < 0 or not FOOD_PLAN_STEP_NAMES.has(offered) or not "YOU place a " in tip:
		return tip
	for kind: int in FOOD_PLAN_STEP_NAMES:
		var said := "YOU place a %s" % FOOD_PLAN_STEP_NAMES[kind]
		if said in tip:
			return tip.replace(said, "YOU place a %s" % FOOD_PLAN_STEP_NAMES[offered])
	return tip


func show_outcome(won: bool, survivors: int) -> void:
	outcome_replay_button.visible = game.wing_seed != 0
	show_briefing(false)
	show_work_priorities(false)
	show_breach_warning(false)
	outcome_panel.visible = true
	_outcome_backdrop.visible = not won
	var resumable := not won and game.outcome == "death" and game.can_still_win_shift()
	outcome_resume_button.visible = resumable
	outcome_resume_button.disabled = not resumable
	outcome_retry_button.visible = not won
	var retry_status := game.day_checkpoint_retry_status()
	outcome_retry_button.disabled = not bool(retry_status.ok)
	outcome_retry_button.tooltip_text = str(retry_status.reason)
	outcome_retry_reason.text = str(retry_status.reason)
	outcome_retry_reason.visible = not won and outcome_retry_button.disabled
	_outcome_recap_row.visible = not won
	_outcome_legacy_row.visible = not resumable
	var dead_name := str(game.death_recap.get("name", "")).strip_edges()
	outcome_resume_button.text = "Continue without %s" % dead_name if not dead_name.is_empty() else "Continue with survivors"
	_size_outcome_recap_buttons()
	var invested := mk2_salvage_invested()
	outcome_invested.text = "Salvage invested: %d in Mk II upgrades" % invested
	outcome_invested.visible = invested > 0
	if won:
		outcome_title.text = "SEAL STABILIZED"
		outcome_title.add_theme_color_override("font_color", Color("75d4b4"))
		outcome_text.text = "The pressure breach was contained, breathable air was restored, and the wing remained inhabited through seven full days. %d resident%s survived. Your local victory state has been saved." % [survivors, "" if survivors == 1 else "s"]
		var grade := crew_grade()
		outcome_grade.text = format_crew_grade(grade)
		outcome_grade.add_theme_color_override("font_color", CREW_GRADE_COLORS[int(grade["stars"]) - 1])
		outcome_grade.visible = true
	else:
		# Keep the frozen-corpse cause summary, with the single recorded Next tip
		# below instead of a second generic advice engine on this screen.
		outcome_grade.text = "" if resumable else format_loss_cause(loss_cause()).get_slice("\n", 0)
		outcome_grade.add_theme_color_override("font_color", Color("ef6860"))
		outcome_grade.visible = not outcome_grade.text.is_empty()
		outcome_title.text = "RESIDENT LOST" if resumable else "WING LOST"
		outcome_title.add_theme_color_override("font_color", Color("ef6860"))
		var recap := game.death_recap
		if recap.is_empty():
			# Legacy loss saves have frozen need facts, but no recorded live tip.
			for resident: VaultResident in game.residents:
				if not resident.alive:
					recap = death_recap_for(resident)
		var prefix := "No residents remain alive.\n\n" if survivors <= 0 else ""
		var tip := str(recap.get("tip", ""))
		var saving_tip := "This would have saved %s: %s" % [recap.get("name", "A resident"), tip.trim_prefix("Next: ")] if not tip.is_empty() else ""
		# No recorded tip: say nothing rather than claim no tip could have helped.
		outcome_text.text = "%s%s died of %s.\n%s%s" % [
			prefix, recap.get("name", "A resident"), recap.get("cause", "unknown causes"),
			recap.get("time", game.day_cycle.get_clock_text()),
			"\n\n" + saving_tip if not saving_tip.is_empty() else "",
		]
	outcome_best.text = best_line(true)
	outcome_best.visible = not outcome_best.text.is_empty()
	outcome_record.text = record_line(won)
	outcome_record.visible = not resumable and not outcome_record.text.is_empty()
	if not won and not resumable and outcome_best.visible:
		var record_first_line := outcome_record.text.get_slice("\n", 0)
		var perk_start := record_first_line.find(" · with ")
		if perk_start >= 0:
			outcome_best.text += record_first_line.substr(perk_start)
		var unlock_start := outcome_record.text.find("\n")
		if unlock_start >= 0:
			outcome_best.text += outcome_record.text.substr(unlock_start)
		outcome_record.visible = false
	_show_keep_running_button(won)
	if resumable:
		for button: Button in [outcome_resume_button, outcome_retry_button]:
			var other := outcome_retry_button if button == outcome_resume_button and not outcome_retry_button.disabled else outcome_resume_button
			var target := button.get_path_to(other)
			button.focus_next = target
			button.focus_previous = target
			button.focus_neighbor_left = target
			button.focus_neighbor_right = target
			button.focus_neighbor_top = target
			button.focus_neighbor_bottom = target
	if outcome_retry_button.is_visible_in_tree() and not outcome_retry_button.disabled:
		outcome_retry_button.grab_focus()
	elif outcome_resume_button.is_visible_in_tree() and not outcome_resume_button.disabled:
		outcome_resume_button.grab_focus()
	elif not won:
		for button: Button in _outcome_legacy_row.get_children():
			if button.is_visible_in_tree() and not button.disabled:
				button.grab_focus()
				break


# Records + ladder C3: the wing's record under the crew rating. A win shows the best grade, a loss
# the furthest day; NEW RECORD only right after the finish that raised it (a LOAD shows the plain
# record). Empty for seed 0, in tests without an injected store, and with no record.
func record_line(won: bool) -> String:
	if not game.records_enabled():
		return ""
	var fresh: bool = not game.finish_record.is_empty()
	var current: Dictionary = game.finish_record.current if fresh else game.wing_records().get_record(game.wing_seed, game.sublevel)
	var previous: Dictionary = game.finish_record.previous if fresh else {}
	if current.is_empty():
		return ""
	var text := ""
	var raised := false
	if won:
		if current.best_stars == null:
			return ""
		var best := int(current.best_stars)
		text = "BEST %s%s" % ["★".repeat(best), "☆".repeat(3 - best)]
		raised = previous.is_empty() or previous.best_stars == null or best > int(previous.best_stars)
	else:
		text = "FURTHEST DAY %d" % int(current.best_day)
		raised = previous.is_empty() or int(current.best_day) > int(previous.best_day)
	if fresh and raised:
		text += " · NEW RECORD"
	# Meta perks P2: records are not split by perk; the line says which perk this run used.
	if game.wing_perk != "":
		text += " · with %s" % VaultGame.perk_name(game.wing_perk)
	if fresh and game.finish_record.has("unlocked"):
		var level := int(game.finish_record.unlocked)
		text += "\nSUBLEVEL %02d UNLOCKED · %s" % [level, VaultGame.sublevel_modifier(level).get("name", "")]
	return text


# Read-only on both LOAD and recoverable death recaps. Only _record_finish submits.
func best_line(finish := false) -> String:
	if not game.best_enabled():
		return ""
	var fresh: bool = finish and game.ended and not game.finish_best.is_empty()
	var best: Dictionary = game.finish_best.current if fresh else game.wing_best().get_best(game.wing_seed, game.sublevel)
	if best.is_empty():
		return ""
	var text := "Best: WIN"
	if not best.won:
		# Stored elapsed includes every day, including Keep Running. Match DayCycle's clock math.
		var fraction := fmod(float(best.elapsed), DayCycle.SECONDS_PER_DAY) / DayCycle.SECONDS_PER_DAY
		var hours := floori(fraction * 24.0)
		var minutes := floori(fmod(fraction * 24.0, 1.0) * 60.0)
		text = "Best: DAY %d · %02d:%02d" % [best.day, hours, minutes]
	text += " · %d survived" % best.survivors.size()
	if fresh and bool(game.finish_best.new_best):
		text += " · NEW BEST"
	return text


# Win-screen crew rating (QA 2026-10-18b #8). A win starts at 3 stars and loses one per failed
# check, never below 1: whole crew alive, hatch never opened, no survivor at BREAK RISK (mood <=
# 9) or CRITICAL (food < 20 or rest < 15, the alert-bar rule). Derived from saved state only, so a
# load into a won save shows the same grade; nothing new is saved.
const CREW_GRADE_COLORS: Array[Color] = [Color("ef6860"), Color("efc56b"), Color("75d4b4")]


func crew_grade() -> Dictionary:
	var crew := game.residents.size()
	var lost := 0
	var break_risk := 0
	var critical := 0
	for resident: VaultResident in game.residents:
		if not resident.alive:
			lost += 1
			continue
		if resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD:
			break_risk += 1
		if resident.needs.food < 20.0 or resident.needs.rest < 15.0:
			critical += 1
	var reasons: Array[String] = []
	if lost > 0:
		reasons.append("%d of %d crew lost" % [lost, crew])
	if game.breach_system.has_opened():
		reasons.append("hatch opened")
	if break_risk > 0:
		reasons.append("%d survivor%s at BREAK RISK" % [break_risk, "" if break_risk == 1 else "s"])
	if critical > 0:
		reasons.append("%d survivor%s CRITICAL" % [critical, "" if critical == 1 else "s"])
	var failed := int(lost > 0) + int(game.breach_system.has_opened()) + int(break_risk > 0 or critical > 0)
	return {"stars": maxi(1, 3 - failed), "reasons": reasons}


func format_crew_grade(grade: Dictionary) -> String:
	var stars := int(grade["stars"])
	var reasons: Array = grade["reasons"]
	var reason := "whole crew home, hatch held, crew steady" if reasons.is_empty() else " · ".join(reasons)
	return "CREW RATING %s%s · %s" % ["★".repeat(stars), "☆".repeat(3 - stars), reason]


# Loss cause (QA 2026-10-18c #1). A corpse's needs freeze at death and O2 is saved, so the likely
# cause is derived, never stored. Per dead resident, retained evidence first (the first match
# wins): food 0, rest 0, mood at the severe line, then O2 at or below the suffocation line, else
# unknown. A corpse still above 0 health (a direct kill) is unknown. The hint follows the largest
# count; ties keep this order.
const LOSS_CAUSES: Array[String] = ["starved", "exhausted", "in despair", "suffocated", "unknown"]
const LOSS_CAUSE_HINTS: Array[String] = [
	"Next wing: keep a Grow Tray and Nutrient Station powered, with Cook and Haul on, before the starting meals run out.",
	"Next wing: build Bunks and undraft tired residents so they can sleep.",
	"Next wing: keep the crew lit and build a powered Rec Console.",
	"Next wing: keep an Air Recycler powered and patch the hatch before it opens.",
	"Next wing: pause when health falls and check food, rest, mood and oxygen.",
]


func loss_cause() -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for resident: VaultResident in game.residents:
		if resident.alive:
			continue
		counts[_resident_loss_cause(resident)] += 1
	return counts


func _resident_loss_cause(resident: VaultResident) -> int:
	if resident.needs.health > 0.0:
		return 4
	if resident.needs.food <= 0.0:
		return 0
	if resident.needs.rest <= 0.0:
		return 1
	if resident.needs.mood <= ResidentNeeds.SEVERE_MOOD_THRESHOLD:
		return 2
	if game.oxygen_system.oxygen <= OxygenSystem.CRITICAL_OXYGEN_THRESHOLD:
		return 3
	return 4


func format_loss_cause(counts: Array[int]) -> String:
	var parts: Array[String] = []
	var top := -1
	for i in counts.size():
		if counts[i] <= 0:
			continue
		parts.append("%d %s" % [counts[i], LOSS_CAUSES[i]])
		if top < 0 or counts[i] > counts[top]:
			top = i
	if top < 0:
		return ""
	return "LIKELY CAUSE · %s\n%s" % [" · ".join(parts), LOSS_CAUSE_HINTS[top]]


func hide_outcome() -> void:
	if outcome_panel != null:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and outcome_panel.is_ancestor_of(focus_owner):
			focus_owner.release_focus()
		outcome_panel.visible = false
		_outcome_backdrop.visible = false
		for button: Button in [outcome_resume_button, outcome_retry_button]:
			button.focus_next = NodePath()
			button.focus_previous = NodePath()
			button.focus_neighbor_left = NodePath()
			button.focus_neighbor_right = NodePath()
			button.focus_neighbor_top = NodePath()
			button.focus_neighbor_bottom = NodePath()


func _set_need(key: String, label_text: String, value: float) -> void:
	var label: Label = need_labels[key]
	var bar: ProgressBar = need_bars[key]
	label.visible = true
	bar.visible = true
	label.text = label_text
	bar.value = value
	if key == "mood":
		bar.modulate = Color("ef6860") if value <= ResidentNeeds.BREAK_MOOD_THRESHOLD else (Color("efc56b") if value < 70.0 else Color("75d4b4"))
	else:
		bar.modulate = Color("ef6860") if value < 25.0 else (Color("efc56b") if value < 50.0 else Color("75d4b4"))


# Wing seed (QA 2026-10-18c #2, slice 1): a seeded wing names itself, e.g. `07-3F2A`, on the top
# bar and the briefing. The legacy wing (seed 0) keeps today's labels exactly.
var wing_brand_label: Label
var wing_briefing_title: Label


# Wing-seed slice 4: REPLAY WING starts a fresh run of the seeded wing on screen (same seed,
# current rules). Seed 0 never shows it, so legacy outcome panels keep their two buttons.
var outcome_replay_button: Button
var _replay_opening := false


func replay_wing() -> void:
	if game.wing_seed != 0:
		_replay_opening = true
		game.new_game(true, game.wing_seed, game.sublevel)
		_replay_opening = false


func _refresh_sublevel_stepper() -> void:
	if briefing_sublevel_row == null or game == null:
		return
	var deepest := game.unlocked_sublevel()
	var level: int = game.sublevel
	briefing_sublevel_row.visible = _briefing_is_opening and game.wing_seed != 0 and deepest < WingRecords.BASE_SUBLEVEL
	var modifier := VaultGame.sublevel_modifier(level)
	briefing_sublevel_label.text = "SUBLEVEL %02d · %s" % [level, modifier.get("name", "BASE")]
	briefing_deeper_button.disabled = level <= deepest
	briefing_shallower_button.disabled = level >= WingRecords.BASE_SUBLEVEL
	briefing_record_label.text = briefing_record_text()
	briefing_record_label.visible = _briefing_is_opening and not briefing_record_label.text.is_empty()
	_refresh_perk_row()


# Meta perks P2: NONE plus every unlocked perk, in order; shown only once one is unlocked.
func perk_choices() -> Array:
	return [""] + game.unlocked_perks()


func _refresh_perk_row() -> void:
	if briefing_perk_row == null:
		return
	var choices := perk_choices()
	briefing_perk_row.visible = _briefing_is_opening and game.wing_seed != 0 and choices.size() > 1
	var index := maxi(0, choices.find(game.wing_perk))
	var id: String = choices[index]
	briefing_perk_label.text = "PERK · NONE" if id == "" else "PERK · %s: %s" % [VaultGame.perk_name(id), VaultGame.PERKS[id].detail]
	briefing_perk_prev_button.disabled = index <= 0
	briefing_perk_next_button.disabled = index >= choices.size() - 1


# ◀/▶ pick the perk for this and later wings; the wing is rebuilt on the same seed and sublevel so the
# perk's start applies once. Keyboard focus stays on the perk arrows, as on the sublevel stepper.
func step_perk(direction: int) -> void:
	if not _briefing_is_opening or game.wing_seed == 0:
		return
	var choices := perk_choices()
	var index := clampi(maxi(0, choices.find(game.wing_perk)) + direction, 0, choices.size() - 1)
	if choices[index] == game.wing_perk:
		return
	var replay := briefing_load_button != null and not briefing_load_button.visible
	var arrows := [briefing_perk_prev_button, briefing_perk_next_button]
	if direction > 0:
		arrows.reverse()
	var keep_focus := get_viewport().gui_get_focus_owner() in arrows
	game.equipped_perk = choices[index]
	_replay_opening = replay
	game.new_game(true, game.wing_seed, game.sublevel)
	_replay_opening = false
	if keep_focus:
		for button: Button in arrows:
			if button in _briefing_focus_controls(true):
				button.grab_focus()
				break


# "RECORD 06-1092 · BEST ★★☆ · FURTHEST DAY 7": the rolled wing's record on this sublevel.
func briefing_record_text() -> String:
	if not game.records_enabled():
		return ""
	var record := game.wing_records().get_record(game.wing_seed, game.sublevel)
	var lines: Array[String] = []
	if not record.is_empty():
		var parts: Array[String] = ["RECORD %s" % wing_id(game.wing_seed, game.sublevel)]
		if record.best_stars != null:
			parts.append("BEST %s%s" % ["★".repeat(int(record.best_stars)), "☆".repeat(3 - int(record.best_stars))])
		parts.append("FURTHEST DAY %d" % int(record.best_day))
		if bool(record.annex):
			parts.append("ANNEX")
		lines.append(" · ".join(parts))
	var best := best_line()
	if not best.is_empty():
		lines.append(best)
	return "\n".join(lines)


# ◀ goes one sublevel deeper (down to the deepest unlocked), ▶ one shallower (up to 07). The wing is
# rebuilt on the same seed so the new rules apply; a replay's briefing keeps LOAD hidden.
func step_sublevel(direction: int) -> void:
	if not _briefing_is_opening or game.wing_seed == 0:
		return
	var level := clampi(game.sublevel + direction, game.unlocked_sublevel(), WingRecords.BASE_SUBLEVEL)
	if level == game.sublevel:
		return
	var replay := briefing_load_button != null and not briefing_load_button.visible
	var arrows := [briefing_deeper_button, briefing_shallower_button]
	if direction > 0:
		arrows.reverse()
	var keep_focus := get_viewport().gui_get_focus_owner() in arrows
	_replay_opening = replay
	game.new_game(true, game.wing_seed, level)
	_replay_opening = false
	# Keyboard focus stays on the arrow just used; at an endpoint it is disabled, so the other arrow takes it.
	if keep_focus:
		for button: Button in arrows:
			if button in _briefing_focus_controls(true):
				button.grab_focus()
				break


static func wing_id(wing_seed: int, level := WingRecords.BASE_SUBLEVEL) -> String:
	return "07" if wing_seed == 0 else WingRecords.key_for_seed(wing_seed, level)


# "2 ROCK POCKETS · 3 SALVAGE VEINS": what a seeded wing holds, named on the NEW WING briefing.
static func wing_layout_summary(wing_seed: int) -> String:
	return "%d ROCK POCKETS · %d SALVAGE VEINS" % [MapGrid.pocket_count_for_seed(wing_seed), MapGrid.vein_count_for_seed(wing_seed)]


func _sublevel() -> int:
	return game.sublevel if game != null else WingRecords.BASE_SUBLEVEL


func show_wing_id(wing_seed: int) -> void:
	if wing_brand_label != null:
		wing_brand_label.text = "VAULT WING // SUBLEVEL 07" if wing_seed == 0 else "VAULT WING // %s" % wing_id(wing_seed, _sublevel())
		var modifier := VaultGame.sublevel_modifier(_sublevel()) if wing_seed != 0 else {}
		if not modifier.is_empty():
			wing_brand_label.text += " · %s" % modifier.name
	if wing_briefing_title != null:
		wing_briefing_title.text = "VAULT WING %s // SEAL STABILIZATION" % wing_id(wing_seed, _sublevel())
		if wing_seed != 0:
			var warn := roundi(VaultGame.warning_at_for(wing_seed, _sublevel()))
			wing_briefing_title.text += "\nHATCH TEST AT %02d:%02d" % [warn / 60, warn % 60]
			var modifier := VaultGame.sublevel_modifier(_sublevel())
			if not modifier.is_empty():
				wing_briefing_title.text += "\nSUBLEVEL %02d · %s: %s" % [_sublevel(), modifier.name, modifier.detail]
			# Contents name the applied layout. A pre-layout seeded save keeps wing_seed but
			# loads with layout_seed 0, so the briefing must not advertise pockets/veins.
			if game != null and game.map_grid.layout_seed != 0:
				wing_briefing_title.text += "\n%s" % wing_layout_summary(wing_seed)


func _get_recreation_user(building_id: int) -> VaultResident:
	for resident: VaultResident in game.residents:
		if resident.alive and resident.recreating and resident.recreation_id == building_id:
			return resident
	return null


func _get_resident_order_status(resident: VaultResident) -> String:
	var status_parts: Array[String] = []
	if resident.drafted:
		status_parts.append("DRAFTED")
	if resident.has_manual_move_order():
		status_parts.append("MANUAL MOVE")
	if resident.is_forced_job:
		status_parts.append("FORCED")
	status_parts.append(resident.state)
	return " · ".join(status_parts)


# Wing-seed slice 3: a seeded trait leads the row's second line (what they do) when the row has
# two lines, otherwise it follows the name. Unseeded rows are never touched.
static func _roster_text_with_trait(text: String, trait_name: String) -> String:
	var newline := text.find("\n")
	if newline >= 0:
		return "%s\n%s · %s" % [text.substr(0, newline), trait_name, text.substr(newline + 1)]
	var name_end := text.find(" · ")
	return "%s · %s%s" % [text.substr(0, name_end), trait_name, text.substr(name_end)]


func _show_resident_commands(resident: VaultResident) -> void:
	var should_show := resident.alive
	resident_command_header.visible = should_show
	resident_command_row.visible = should_show
	if not should_show:
		return
	resident_draft_button.text = "UNDRAFT [R]" if resident.drafted else "DRAFT [R]"
	resident_draft_button.tooltip_text = (
		"Right-click reachable carved floor to move this drafted resident; undraft to return them to automatic work."
		if resident.drafted
		else "Draft this resident for manual movement. Right-click moves drafted residents; while undrafted, right-click forces a context job."
	)
	resident_draft_button.disabled = _resident_commands_blocked()
	resident_draft_button.modulate = Color("efc56b") if resident.drafted else Color.WHITE
	if resident_cancel_button != null:
		var has_manual_command := resident.has_manual_move_order() or resident.is_forced_job
		resident_cancel_button.disabled = _resident_commands_blocked() or not has_manual_command
		resident_cancel_button.tooltip_text = (
			"Cancel this resident's current manual command."
			if has_manual_command
			else "This resident has no manual command to cancel."
		)


func _hide_resident_commands() -> void:
	if resident_command_header != null:
		resident_command_header.visible = false
	if resident_command_row != null:
		resident_command_row.visible = false


func _resident_commands_blocked() -> bool:
	return (
		game == null
		or game.tutorial_open
		or is_help_open()
		or is_work_priorities_open()
		or game.ended
		or (outcome_panel != null and outcome_panel.visible)
		or (game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged)
	)


func _hide_needs_and_work() -> void:
	_hide_resident_commands()
	work_header.visible = false
	for label: Label in need_labels.values():
		label.visible = false
	for bar: ProgressBar in need_bars.values():
		bar.visible = false
	for button: Button in work_buttons.values():
		button.visible = false


func _show_fixture_controls(building: VaultBuilding) -> void:
	var visible := building.complete
	fixture_header.visible = visible
	fixture_controls.visible = visible
	if not visible:
		fixture_upgrade_row.visible = false
		return
	var is_consumer := building.is_power_consumer() or building.kind == VaultBuilding.Kind.MEDICAL_BED
	fixture_header.text = "FIXTURE CONTROLS"
	fixture_power_button.visible = is_consumer
	fixture_power_button.text = "ENABLE" if building.manually_disabled else "DISABLE"
	fixture_power_button.disabled = not is_consumer
	fixture_power_button.tooltip_text = "Allow or deny medical care." if building.kind == VaultBuilding.Kind.MEDICAL_BED else "Remove or restore this fixture's power demand."
	fixture_deconstruct_button.disabled = building.is_emergency_core
	fixture_deconstruct_button.tooltip_text = "Emergency core cannot be deconstructed." if building.is_emergency_core else "Recover %d salvage and remove this fixture." % building.get_deconstruct_refund()
	_show_fixture_upgrade(building)


func _show_fixture_upgrade(building: VaultBuilding) -> void:
	var offered := building.can_take_upgrade() and game.is_upgrade_unlocked(building.kind) and game.breach_system.is_sealed() and not game.ended
	fixture_upgrade_row.visible = offered
	if not offered:
		return
	var cost := building.get_upgrade_cost()
	fixture_upgrade_button.text = "FIT MK II · %d SALVAGE" % cost
	fixture_upgrade_button.disabled = not game.can_upgrade_building(building.building_id)
	fixture_upgrade_button.tooltip_text = (
		_upgrade_benefit_text(building)
		if not fixture_upgrade_button.disabled
		else "Needs a powered Air Recycler"
		if not game.is_air_ready()
		else "Needs %d salvage (have %d)." % [cost, game.food_system.salvage]
	)


func _upgrade_benefit_text(building: VaultBuilding) -> String:
	match building.kind:
		VaultBuilding.Kind.GENERATOR:
			return "%d power instead of %d." % [VaultBuilding.CHARGE_MK2_OUTPUT, building.get_power_output()]
		VaultBuilding.Kind.AIR_RECYCLER:
			return "Same air for %d power instead of %d." % [VaultBuilding.AIR_MK2_POWER, building.get_base_power_demand()]
	return "1 raw every %d s instead of %d s · same %d power." % [roundi(VaultBuilding.GROW_MK2_SECONDS), roundi(FoodSystem.GROW_SECONDS), building.get_base_power_demand()]


# The post-seal Mk II offer (QA-d #2/#4), resolved at refresh and again at click time: a Charge Node
# first when a finished Grow Tray sits unpowered and Charge Mk II is unlocked, then the first tier-1
# Grow Tray, Charge Node and Air Recycler whose fit is unlocked.
func _upgrade_offer_target() -> VaultBuilding:
	if game.ended or not game.breach_system.is_sealed():
		return null
	# Air first (NX37): no Mk II fit before an Air Recycler is finished and powered, or the salvage
	# the Air Recycler needs goes on trays and the crew suffocates (05/4242 GROW NOOK, t=229).
	if not _air_ready():
		return null
	if _unpowered_tray() != null:
		var charge := _first_fittable(VaultBuilding.Kind.GENERATOR)
		if charge != null:
			return charge
	for kind: int in [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.AIR_RECYCLER]:
		var target := _first_fittable(kind)
		if target != null:
			return target
	return null


func _air_ready() -> bool:
	return game.is_air_ready()


func _first_fittable(kind: int) -> VaultBuilding:
	if not game.is_upgrade_unlocked(kind):
		return null
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and building.can_take_upgrade() and not building.is_emergency_core:
			return building
	return null


func _unpowered_tray() -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY and building.complete and not building.powered and not building.manually_disabled:
			return building
	return null


# Idle post-seal salvage (QA-d #4): name the next useful build the stored salvage can pay for. A raw
# pile wants a second Nutrient Station, then a Rec Console, then a second Grow Tray; when the grid has
# no room for it, a Charge Node first. -1 when nothing useful is affordable, or while a paid Annex
# waits on floor. Shown only when no Mk II fit is on offer.
const NUDGE_RAW_PILE := 6
const NUDGE_TOOLS := {
	VaultBuilding.Kind.KITCHEN: "kitchen",
	VaultBuilding.Kind.RECREATION_CONSOLE: "rec",
	VaultBuilding.Kind.GROW_TRAY: "grow",
	VaultBuilding.Kind.GENERATOR: "generator",
	VaultBuilding.Kind.AIR_RECYCLER: "air",
}


# Use the same food runway as urgency selection, even when another threat
# currently wins the resident ranking.
func _salvage_food_crisis_live() -> bool:
	if game.get_alive_count() == 0:
		return false
	var plan := _food_fix_plan()
	var lead := float(plan.seconds) + _food_chain_work_lead(float(plan.seconds))
	if not _food_work_blocker_step().is_empty() and game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY) == 0:
		lead = maxf(lead, float(plan.seconds) + _food_worker_recovery_seconds())
	return _food_runway_seconds() < lead + FOOD_RUNWAY_MARGIN_SECONDS


# Ordered survival needs, independent of their price. Keep this list so an
# unaffordable first choice can name reclamation without hiding cheaper relief.
func _salvage_survival_candidates() -> Array[int]:
	var candidates: Array[int] = []
	if game.ended or not game.breach_system.is_sealed():
		return candidates
	if game.annex_waiting_for_room() and game.annex_room_short() > 0:
		return candidates
	var food_crisis := _salvage_food_crisis_live()
	var breaking := false
	for resident: VaultResident in game.residents:
		if resident.alive:
			food_crisis = food_crisis or (resident.needs.food < 20.0 and game.food_system.meals < game.get_alive_count())
			breaking = breaking or resident.needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD
	var tray := _unpowered_tray()
	if food_crisis and tray != null and game.power_grid.supply - game.power_grid.served < tray.get_base_power_demand():
		candidates.append(VaultBuilding.Kind.GENERATOR)
	if food_crisis and _count_kind(VaultBuilding.Kind.KITCHEN) == 0:
		candidates.append(VaultBuilding.Kind.KITCHEN)
	if food_crisis and game.food_system.raw_food >= NUDGE_RAW_PILE and _count_kind(VaultBuilding.Kind.KITCHEN) < 2:
		candidates.append(VaultBuilding.Kind.KITCHEN)
	if food_crisis and _count_kind(VaultBuilding.Kind.GROW_TRAY) < 2 and _air_ready():
		if _planned_power_spare() < int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.GROW_TRAY]):
			candidates.append(VaultBuilding.Kind.GENERATOR)
		else:
			candidates.append(VaultBuilding.Kind.GROW_TRAY)
	if breaking and _count_kind(VaultBuilding.Kind.RECREATION_CONSOLE) == 0:
		candidates.append(VaultBuilding.Kind.RECREATION_CONSOLE)
	# The literal 05 probe has just vented a break (mood 11-13). Its existing
	# food-work forecast still calls for Rec; keep that affordable recovery.
	if food_crisis and _count_kind(VaultBuilding.Kind.RECREATION_CONSOLE) == 0 and _next_named_build_kind(_food_work_blocker_step()) == VaultBuilding.Kind.RECREATION_CONSOLE:
		candidates.append(VaultBuilding.Kind.RECREATION_CONSOLE)
	return candidates


func salvage_survival_sink(spendable: int) -> int:
	for candidate: int in _salvage_survival_candidates():
		if int(VaultBuilding.COSTS[candidate]) <= spendable:
			return candidate
	var fallback := salvage_nudge_kind()
	return fallback if fallback >= 0 and int(VaultBuilding.COSTS[fallback]) <= spendable else -1


func salvage_nudge_kind() -> int:
	if game.ended or not game.breach_system.is_sealed():
		return -1
	# Every nudge places a fixture on free floor; a paid Annex waiting on room needs those cells.
	# Mk II fits upgrade in place and stay on offer.
	if game.annex_waiting_for_room() and game.annex_room_short() > 0:
		return -1
	var want := -1
	if game.food_system.raw_food >= NUDGE_RAW_PILE and _count_kind(VaultBuilding.Kind.KITCHEN) < 2:
		want = VaultBuilding.Kind.KITCHEN
	elif _count_kind(VaultBuilding.Kind.RECREATION_CONSOLE) == 0:
		want = VaultBuilding.Kind.RECREATION_CONSOLE
	elif _count_kind(VaultBuilding.Kind.GROW_TRAY) < 2 and _air_ready():
		want = VaultBuilding.Kind.GROW_TRAY
	if want < 0:
		return -1
	if _planned_power_spare() < int(VaultBuilding.POWER_DEMAND.get(want, 0)):
		want = VaultBuilding.Kind.GENERATOR
	if _blueprints_awaiting_salvage() >= NUDGE_MAX_UNFUNDED:
		return -1
	return want if game.food_system.salvage >= int(VaultBuilding.COSTS[want]) else -1


# Blueprints still waiting for salvage. With two of them the nudge waits: placing more only spread
# each delivery thinner (four blueprints in two seconds) and left nothing for the next choice.
const NUDGE_MAX_UNFUNDED := 2


func _blueprints_awaiting_salvage() -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if not building.complete and not building.is_emergency_core and building.needs_supply():
			count += 1
	return count


func _count_kind(kind: int) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and not building.is_emergency_core:
			count += 1
	return count


# Supply (counting unfinished Charge Nodes at 7) minus the demand of every consumer, built or planned.
func _planned_power_spare() -> int:
	var spare := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR:
			spare += building.get_power_output() if building.complete else 7
		elif not building.manually_disabled:
			spare -= building.get_base_power_demand()
	return spare


func _salvage_nudge() -> bool:
	return salvage_nudge_kind() >= 0


func upgrade_offer_text(target: VaultBuilding) -> String:
	var cost := target.get_upgrade_cost()
	match target.kind:
		VaultBuilding.Kind.GENERATOR:
			if _unpowered_tray() != null:
				return "Tray unpowered · Charge Mk II %d" % cost
			return "Charge Mk II · %d · +%d power" % [cost, VaultBuilding.CHARGE_MK2_OUTPUT - target.get_power_output()]
		VaultBuilding.Kind.AIR_RECYCLER:
			return "Air Mk II · %d salvage · -%d power" % [cost, target.get_base_power_demand() - VaultBuilding.AIR_MK2_POWER]
	return "Grow Tray Mk II · %d salvage" % cost


# The right panel holds RIGHT_PANEL_WIDTH: the lighting row's label clips into what is left beside
# [L] MAP OFF instead of forcing 188 px, and the Mk II offer is short and clips (Codex VT-20 follow-up).
const LIGHTING_LABEL_MIN_WIDTH := 120.0


# While the hatch is in WARNING or OPEN, the PRESSURE HATCH block (header, readout, bar, FOCUS
# HATCH) moves to the top of DETAILS so FOCUS HATCH sits well inside the scroll however tall the
# other readouts grow; afterwards it returns below VAULT ATMOSPHERE (Codex VT-20 follow-up).
func _order_hatch_block(first: bool) -> void:
	var header := details_box.get_child(breach_label.get_index() - 1)
	var at_top := header.get_index() == 0
	if first == at_top:
		return
	var block: Array[Node] = [header, breach_label, breach_bar, breach_focus_button]
	if first:
		for index in block.size():
			details_box.move_child(block[index], index)
		return
	var previous: Node = oxygen_bar
	for node: Node in block:
		details_box.move_child(node, previous.get_index())
		previous = node


# QA-d #8: the idle start card (hidden unless the wing is untouched at 30 s, or step 2 is pending).
const IDLE_START_TEXT := {
	"header_1": "IDLE START · 1/2 · beds, food, power",
	"header_2": "IDLE START · 2/2 · air",
	"start": "Dig + 2 Beds, Gen, Kitchen, Tray",
	"air": "Place Air Recycler · %d salvage",
	"header_3": "IDLE START · after the seal · bunks",
	"bunks": "Begin reclamation · 2 bunks",
	"dismiss": "Dismiss · don't offer again",
}


func _build_idle_start_card(parent: Control) -> void:
	idle_start_box = VBoxContainer.new()
	idle_start_box.visible = false
	idle_start_box.add_theme_constant_override("separation", 2)
	parent.add_child(idle_start_box)
	idle_start_header = Label.new()
	idle_start_header.add_theme_color_override("font_color", Color("8faeb7"))
	idle_start_header.add_theme_font_size_override("font_size", 13)
	idle_start_box.add_child(idle_start_header)
	idle_start_button = Button.new()
	idle_start_button.clip_text = true
	idle_start_button.custom_minimum_size.y = 26
	idle_start_button.tooltip_text = "Queues the standard opening: dig marks, two Bunks, a Charge Node, a Nutrient Station and a Grow Tray. Step 2 offers the Air Recycler."
	idle_start_button.pressed.connect(_on_idle_start_pressed)
	idle_start_box.add_child(idle_start_button)
	idle_start_dismiss_button = Button.new()
	idle_start_dismiss_button.clip_text = true
	idle_start_dismiss_button.custom_minimum_size.y = 22
	idle_start_dismiss_button.add_theme_font_size_override("font_size", 12)
	idle_start_dismiss_button.text = IDLE_START_TEXT.dismiss
	idle_start_dismiss_button.pressed.connect(_on_idle_start_dismissed)
	idle_start_box.add_child(idle_start_dismiss_button)


func _refresh_idle_start() -> void:
	if idle_start_box == null:
		return
	var offer := game.can_offer_idle_start()
	# The hatch warning owns the panel (its readouts and FOCUS HATCH must stay in view).
	var air := game.idle_start_air_pending() and game.breach_system.phase != BreachSystem.Phase.WARNING
	var bunks := game.idle_start_bunks_pending()
	idle_start_box.visible = offer or air or bunks
	if offer:
		idle_start_header.text = IDLE_START_TEXT.header_1
		idle_start_button.text = IDLE_START_TEXT.start
	elif air:
		idle_start_header.text = IDLE_START_TEXT.header_2
		idle_start_button.text = IDLE_START_TEXT.air % int(VaultBuilding.COSTS[VaultBuilding.Kind.AIR_RECYCLER])
	elif bunks:
		idle_start_header.text = IDLE_START_TEXT.header_3
		idle_start_button.text = "Queue 2 bunks" if _next_kind_affordable(VaultBuilding.Kind.BED) else IDLE_START_TEXT.bunks


func _on_idle_start_pressed() -> void:
	if game.can_offer_idle_start():
		game.apply_idle_start()
	elif game.idle_start_air_pending():
		game.place_idle_start_air()
	elif game.idle_start_bunks_pending():
		game.apply_idle_start_bunks()
	refresh()


func _on_idle_start_dismissed() -> void:
	game.dismiss_idle_start()
	refresh()


# While anyone starves or the food runway is short, Spend names only the food card's step.
func _food_nudge_active() -> bool:
	if game.get_alive_count() == 0:
		return false
	for resident: VaultResident in game.residents:
		if resident.alive and (resident.resident_id == _starving_resident_id or resident.needs.food <= 0.0):
			return true
	return _salvage_food_crisis_live()


# Cook auto food step: the same food-short test the Spend nudge uses.
func cook_food_short() -> bool:
	return _food_nudge_active()


func food_plan_lead_kind() -> int:
	return _food_plan_lead_kind()


# The food build the card leads with, when it is shown and tappable; else -1.
func _food_card_offer_kind() -> int:
	if not game.food_plan_pending() or game.keep_running or game.breach_system.phase == BreachSystem.Phase.WARNING:
		return -1
	var offer := game.food_plan_offer(_food_plan_lead_kind())
	return -1 if offer.is_empty() else offer[0]


func _upgrade_offer_nudge_kind() -> int:
	# Spend agrees with a held finish-Air Next: nothing else is queued while Air is being built.
	if bool(_displayed_next_step.get("hold_air_finish", false)):
		return -1
	if _air_warning_kind() >= 0:
		# Spend offers what the displayed Next names; an urgent resident step that wins Next wins here too.
		var air_kind := -1
		if str(_displayed_next_step.get("cause", "")) == "air":
			air_kind = _next_named_build_kind(_displayed_next_step)
		elif _air_chain_named:
			air_kind = VaultBuilding.Kind.AIR_RECYCLER
		if air_kind != VaultBuilding.Kind.AIR_RECYCLER and air_kind != VaultBuilding.Kind.GENERATOR:
			return -1
		var spendable: int = game.food_system.salvage - game.job_system.get_breach_salvage_reserve()
		return air_kind if spendable >= int(VaultBuilding.COSTS[air_kind]) else -1
	if _food_nudge_active():
		if game.ended or not game.breach_system.is_sealed():
			return -1
		var food := _food_card_offer_kind()
		var urgent := next_urgent_build_kind()
		return food if food >= 0 and (urgent < 0 or urgent == food) else -1
	var nudge := salvage_nudge_kind()
	var urgent_kind := next_urgent_build_kind()
	if _hatch_reserve_blocks(nudge):
		return -1
	# Spend follows Next: the same guard that keeps the bunks as Next keeps Spend
	# from offering the nudged build (03 s4242: Spend 8 Rec beside "place bunks").
	if nudge >= 0 and _bunks_hold_salvage_nudge(_displayed_next_step):
		return -1
	return -1 if urgent_kind >= 0 and nudge != urgent_kind else nudge


# What the Spend button costs: its click arms one build tool, so the cost of that build.
func upgrade_offer_cost(nudge: int) -> int:
	return int(VaultBuilding.COSTS[nudge]) if nudge >= 0 else 0


func _refresh_upgrade_offer() -> void:
	if upgrade_offer_button == null:
		return
	# The bunk guard owns Spend too: while Next shows the bunks, Spend places them
	# instead of offering a Mk II fit or another build (05 s4242 busy: 8 bounces).
	if _bunks_hold_salvage_nudge(_displayed_next_step):
		var bunks := spend_bunk_count()
		upgrade_offer_button.visible = bunks > 0
		if bunks > 0:
			upgrade_offer_button.text = "Spend %d: place %s" % [bunks * int(VaultBuilding.COSTS[VaultBuilding.Kind.BED]), "1 bunk" if bunks == 1 else "%d bunks" % bunks]
		_refresh_wing_orders()
		_refresh_also()
		return
	var target := _upgrade_offer_target()
	var nudge := _upgrade_offer_nudge_kind() if target == null else -1
	upgrade_offer_button.visible = target != null or nudge >= 0
	if target != null:
		upgrade_offer_button.text = upgrade_offer_text(target)
	elif nudge >= 0:
		upgrade_offer_button.text = "Spend %d: build %s" % [upgrade_offer_cost(nudge), VaultBuilding.KIND_NAMES[nudge]]
	_refresh_wing_orders()
	_refresh_also()


# QA-e #2: a dim line under Next names a live post-seal action. Next itself is unchanged.
const ALSO_NAMES := {
	VaultBuilding.Kind.GROW_TRAY: "Grow Tray",
	VaultBuilding.Kind.GENERATOR: "Charge",
	VaultBuilding.Kind.AIR_RECYCLER: "Air",
}


func also_text() -> String:
	if game.ended or not game.breach_system.is_sealed():
		return ""
	if game.can_start_reclamation() and not _next_kind_affordable(_next_reclamation_kind):
		# The idle-start step-3 card already offers reclamation; one prompt there is enough.
		if game.idle_start_bunks_pending():
			return ""
		return "Also: begin reclamation · +%d salvage" % VaultGame.RECLAIM_START_SALVAGE
	var target := _upgrade_offer_target()
	if target != null and game.food_system.salvage >= target.get_upgrade_cost():
		return "Also: fit %s Mk II · %d" % [ALSO_NAMES.get(target.kind, "a"), target.get_upgrade_cost()]
	return ""


func _refresh_also() -> void:
	if also_label == null:
		return
	also_label.text = also_text()
	also_label.visible = not also_label.text.is_empty()


const WING_ORDER_TEXT := {
	VaultGame.ORDER_FIT_GROW_MK2: ["Fit Grow Mk II", "Charge Mk II", "Charge Node Mk II"],
	VaultGame.ORDER_STOCK_MEALS: ["Stock %d meals", "Air Mk II", "Air Recycler Mk II"],
}
const WING_ORDER_REWARD_KIND := {
	VaultGame.ORDER_FIT_GROW_MK2: VaultBuilding.Kind.GENERATOR,
	VaultGame.ORDER_STOCK_MEALS: VaultBuilding.Kind.AIR_RECYCLER,
}


func _refresh_wing_orders() -> void:
	if wing_orders_box == null:
		return
	wing_orders_box.visible = game.breach_system.is_sealed() and not game.ended
	if not wing_orders_box.visible:
		return
	var done := 0
	for order_id: String in VaultGame.WING_ORDER_IDS:
		var claimed := order_id in game.wing_orders_claimed
		done += 1 if claimed else 0
		var goal: String = WING_ORDER_TEXT[order_id][0]
		var reward: String = WING_ORDER_TEXT[order_id][1]
		var reward_full: String = WING_ORDER_TEXT[order_id][2]
		var row: Button = wing_order_rows[order_id]
		if order_id == VaultGame.ORDER_STOCK_MEALS:
			goal = goal % VaultGame.ORDER_STOCK_MEALS_TARGET
			if not claimed:
				goal += " (%d/%d)" % [mini(game.food_system.meals, VaultGame.ORDER_STOCK_MEALS_TARGET), VaultGame.ORDER_STOCK_MEALS_TARGET]
		row.text = ("[DONE] %s → %s" if claimed else "[  ] %s → %s") % [goal, reward]
		row.disabled = not claimed or _wing_order_target(order_id) == null
		row.tooltip_text = (
			"Select a %s to fit %s." % [VaultBuilding.KIND_NAMES[WING_ORDER_REWARD_KIND[order_id]], reward_full]
			if claimed
			else "Wing order: %s to unlock %s." % [goal, reward_full]
		)
	wing_orders_header.text = "WING ORDERS · %d/%d" % [done, VaultGame.WING_ORDER_IDS.size()]
	_refresh_reclaim_button()


func reclaim_button_text() -> String:
	if game.can_start_reclamation() and _next_kind_affordable(_next_reclamation_kind):
		return "Reclamation available · +%d salvage" % VaultGame.RECLAIM_START_SALVAGE
	if game.can_start_reclamation():
		return "Begin reclamation · +%d salvage" % VaultGame.RECLAIM_START_SALVAGE
	var left := VaultGame.RECLAIM_DELIVERIES - game.reclaim_paid
	if left <= 0:
		return "Reclamation complete"
	if game.reclaim_paused:
		return "Reclamation paused · tap to resume · %d left" % left
	if game.cook_auto_started_reclaim:
		return "Cook's reclamation · tap to pause · %d left" % left
	return "Reclamation · +%d in %d s · %d left" % [VaultGame.RECLAIM_DELIVERY, ceili(game.reclaim_seconds_to_next()), left]


func _refresh_reclaim_button() -> void:
	if reclaim_button == null:
		return
	reclaim_button.text = reclaim_button_text()
	reclaim_button.disabled = not game.can_start_reclamation() and not game.cook_reclaim_tappable()


func _wing_order_target(order_id: String) -> VaultBuilding:
	if not order_id in game.wing_orders_claimed:
		return null
	for building: VaultBuilding in game.buildings:
		if building.kind == WING_ORDER_REWARD_KIND[order_id] and building.can_take_upgrade():
			return building
	return null


func _on_wing_order_pressed(order_id: String) -> void:
	var target := _wing_order_target(order_id)
	if target != null:
		game.select_building(target.building_id)


func _on_upgrade_offer_pressed() -> void:
	if _bunks_hold_salvage_nudge(_displayed_next_step):
		place_spend_bunks()
		return
	var target := _upgrade_offer_target()
	var nudge := _upgrade_offer_nudge_kind() if target == null else -1
	if target != null:
		game.select_building(target.building_id)
	elif NUDGE_TOOLS.has(nudge):
		place_spend_build(nudge)


# The rooms a Spend build belongs beside; it goes on the nearest free floor to them.
const SPEND_ANCHOR_KINDS := {
	VaultBuilding.Kind.RECREATION_CONSOLE: [VaultBuilding.Kind.BED, VaultBuilding.Kind.MEDICAL_BED],
	VaultBuilding.Kind.BED: [VaultBuilding.Kind.BED, VaultBuilding.Kind.MEDICAL_BED, VaultBuilding.Kind.RECREATION_CONSOLE],
	VaultBuilding.Kind.KITCHEN: [VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY],
	VaultBuilding.Kind.GROW_TRAY: [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN],
	VaultBuilding.Kind.GENERATOR: [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.AIR_RECYCLER],
	VaultBuilding.Kind.AIR_RECYCLER: [VaultBuilding.Kind.AIR_RECYCLER, VaultBuilding.Kind.GENERATOR],
}


# One press of Spend for a named build: a blueprint on the best free floor the crew can reach,
# by the same rules as a manual placement (game.place_blueprint), so it can be canceled or
# moved the usual way. With no such floor it says so and leaves the select tool on.
func place_spend_build(kind: int) -> bool:
	var build_name: String = VaultBuilding.KIND_NAMES[kind]
	game.set_tool("select")
	for cell: Vector2i in spend_build_cells(kind):
		if _crew_can_reach(cell) and game.place_blueprint(kind, cell):
			game.status_message = "%s placed · THEY build it" % build_name
			game.status_message_left = 4.0
			refresh()
			return true
	game.status_message = "No free floor for %s · dig more" % build_name
	game.status_message_left = 4.0
	refresh()
	return false


# How many bunks Spend places for the shown bunk step: the stated count, else the
# tired crew still without a free or unfinished bunk, capped by spendable salvage.
func spend_bunk_count() -> int:
	var text := str(_displayed_next_step.get("text", ""))
	var wanted := 1
	if _bunk_step_states_count(_displayed_next_step):
		wanted = int(text.trim_prefix("Next: YOU place ").get_slice(" ", 0))
	else:
		var needing := 0
		var occupied: Dictionary = {}
		for resident: VaultResident in game.residents:
			if resident.sleeping and resident.bed_id >= 0:
				occupied[resident.bed_id] = true
			elif resident.medical_bed_id >= 0 and resident.state == "Rest-Medical":
				continue
			elif resident.alive and not resident.drafted and (resident.needs.rest <= 28.0 or (resident.sleeping and resident.bed_id < 0)):
				needing += 1
		for building: VaultBuilding in game.buildings:
			if building.kind == VaultBuilding.Kind.BED and (not building.complete or not occupied.has(building.building_id)):
				needing -= 1
		wanted = maxi(needing, 1)
	var spendable: int = game.food_system.salvage - game.job_system.get_breach_salvage_reserve()
	return mini(wanted, spendable / int(VaultBuilding.COSTS[VaultBuilding.Kind.BED]))


# One press of Spend on the bunk step: bunk blueprints on reachable free floor by the
# same rules as place_spend_build, one message for the whole press.
func place_spend_bunks() -> int:
	var wanted := spend_bunk_count()
	var placed := 0
	game.set_tool("select")
	if wanted > 0:
		for cell: Vector2i in spend_build_cells(VaultBuilding.Kind.BED):
			if placed >= wanted:
				break
			if _crew_can_reach(cell) and game.place_blueprint(VaultBuilding.Kind.BED, cell):
				placed += 1
	if wanted > 0:
		game.status_message = "Bunks placed · THEY build it" if placed > 0 else "No free floor for bunks · dig more"
		game.status_message_left = 4.0
	refresh()
	return placed


# Free carved floor, nearest the build's related rooms first.
func spend_build_cells(kind: int) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	for building: VaultBuilding in game.buildings:
		if building.kind in SPEND_ANCHOR_KINDS.get(kind, []):
			anchors.append(building.cell)
	if anchors.is_empty():
		for building: VaultBuilding in game.buildings:
			anchors.append(building.cell)
	if anchors.is_empty():
		anchors.append(MapGrid.CHAMBER.get_center())
	var scored: Array = []
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			if cell == BreachSystem.HATCH_CELL or not game.map_grid.is_walkable(cell) or game.get_building_at(cell) != null or game.map_grid.stockpile_cells.has(cell):
				continue
			var best := INF
			for anchor: Vector2i in anchors:
				best = minf(best, Vector2(cell - anchor).length())
			scored.append([best, y, x, cell])
	scored.sort()
	var cells: Array[Vector2i] = []
	for entry: Array in scored:
		cells.append(entry[3])
	return cells


func _crew_can_reach(cell: Vector2i) -> bool:
	if game.get_alive_count() == 0:
		return true
	for resident: VaultResident in game.residents:
		if resident.alive and not game.map_grid.find_path(resident.get_cell(game.map_grid), cell).is_empty():
			return true
	return false


func _on_fixture_upgrade_pressed() -> void:
	var building := game.get_building_by_id(game.selected_building_id)
	if building != null:
		game.upgrade_building(building.building_id)


func _hide_fixture_controls() -> void:
	if fixture_header != null:
		fixture_header.visible = false
	if fixture_controls != null:
		fixture_controls.visible = false
	if fixture_upgrade_row != null:
		fixture_upgrade_row.visible = false


func _on_tool_pressed(tool: String) -> void:
	game.set_tool(tool)


const TOP_RESOURCE_MIN_WIDTH := 200.0
const TOP_ROW_SEPARATION := 8


func _on_speed_pressed(speed: int) -> void:
	game.set_speed(speed)


func _on_resident_pressed(resident_id: int) -> void:
	game.select_resident(resident_id)


func _on_resident_draft_pressed() -> void:
	var resident := game.get_resident_by_id(game.selected_resident_id)
	if resident != null and resident.alive and not _resident_commands_blocked():
		game.toggle_resident_draft(resident.resident_id)


func _on_resident_cancel_command_pressed() -> void:
	if not _resident_commands_blocked():
		game.cancel_selected_resident_command()


func _on_work_pressed(work_type: String) -> void:
	if game.selected_resident_id >= 0:
		game.cycle_work_priority(game.selected_resident_id, work_type)


func _on_work_priority_pressed(resident_id: int, work_type: String) -> void:
	game.cycle_work_priority(resident_id, work_type)


func _on_fixture_power_pressed() -> void:
	var building := game.get_building_by_id(game.selected_building_id)
	if building != null:
		game.toggle_building_enabled(building.building_id)


func _on_fixture_deconstruct_pressed() -> void:
	var building := game.get_building_by_id(game.selected_building_id)
	if building != null:
		game.deconstruct_building(building.building_id)


# Seconds until the first living resident's health runs out at its current
# rate: suffocation plus starvation, exhaustion and despair drain, minus medical
# healing. -1.0 when nobody is alive.
func _seconds_to_first_suffocation() -> float:
	var soonest := -1.0
	for resident: VaultResident in game.residents:
		if not resident.alive:
			continue
		var seconds := resident.needs.health / _suffocating_health_loss_per_second(resident)
		if soonest < 0.0 or seconds < soonest:
			soonest = seconds
	return soonest


# Mirrors ResidentNeeds.advance() and JobSystem medical care; suffocation (4)
# always outpaces medical healing (2), so the result stays positive.
func _suffocating_health_loss_per_second(resident: VaultResident) -> float:
	var medical := resident.medical_bed_id >= 0 and resident.state == "Rest-Medical"
	var drain_per_day := 0.0
	if resident.needs.food <= 0.0:
		drain_per_day += 160.0
	if resident.needs.rest <= 0.0 and not resident.sleeping and not medical:
		drain_per_day += 30.0
	if resident.needs.mood <= ResidentNeeds.SEVERE_MOOD_THRESHOLD:
		drain_per_day += 5.0
	var loss := OxygenSystem.SUFFOCATION_DAMAGE_PER_SECOND + drain_per_day / DayCycle.SECONDS_PER_DAY
	if medical:
		loss -= JobSystem.MEDICAL_HP_PER_SECOND
	return loss


# Keep both fields padded across digit/minute boundaries so countdowns do not reflow.
func _format_seconds(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _panel_style(background: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# Keep running (north star slice 1). The win panel offers KEEP RUNNING beside LOAD / NEW WING; the
# wing then stays live past Day 7. Next keeps its survival steps, but a Med Bed / Rec Console
# suggestion latches until that fixture exists or the need has been gone for KEEP_RUNNING_UNLATCH_S,
# so an idle vault never flips between them.
const KEEP_RUNNING_TEXT := {
	"button": "KEEP RUNNING",
	"next": "Next: YOU watch the vault · THEY keep it running",
	"loss": "The seal win stands; the vault was lost while it kept running.",
}
const KEEP_RUNNING_UNLATCH_S := 10.0
var keep_running_button: Button
var _kr_latch_text := ""
var _kr_latch_tool := ""
var _kr_latch_clear_at := -1.0


func keep_running_clock_text() -> String:
	return "DAY %d · LIVE" % game.keep_running_day()


func _show_keep_running_button(won: bool) -> void:
	if keep_running_button == null:
		var row: Node = null
		for node: Node in outcome_panel.find_children("*", "HBoxContainer", true, false):
			for child: Node in node.get_children():
				if child is Button and (child as Button).text == "NEW WING":
					row = node
		if row == null:
			return
		# Its own centred row under LOAD / NEW WING (/ REPLAY), so the first row never grows.
		var own_row := HBoxContainer.new()
		own_row.name = "KeepRunningRow"
		own_row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.get_parent().add_child(own_row)
		keep_running_button = Button.new()
		keep_running_button.name = "KeepRunningButton"
		keep_running_button.text = KEEP_RUNNING_TEXT.button
		keep_running_button.pressed.connect(func() -> void: game.start_keep_running())
		own_row.add_child(keep_running_button)
	keep_running_button.visible = won and game.can_keep_running()


func note_keep_running_loss() -> void:
	outcome_text.text += " " + KEEP_RUNNING_TEXT.loss


func _is_latchable_step(step: Dictionary) -> bool:
	if str(step.get("action", "")) in ["reclaim", "spend"]:
		return false
	if bool(step.get("urgent", false)):
		return false
	return str(step.get("tool", "")) in ["medical", "rec"] or (
		str(step.get("text", "")).contains("Med Bed") or str(step.get("text", "")).contains("Rec Console")
	)


func console_seek_threshold() -> float:
	return ResidentNeeds.KEEP_RUNNING_RECREATION_SEEK if game.keep_running and not game.ended else ResidentNeeds.RECREATION_SEEK_THRESHOLD


func keep_running_next_step() -> Dictionary:
	if game.comfort_pending():
		# The comfort card covers Rec and Med: Next points at it over those steps (latched or not)
		# and over the calm default; other life-support steps (air, food, power) still lead.
		var primary := _primary_next_step()
		# A paid Annex waiting on floor comes first: the comfort blueprints would take cells it needs.
		if _is_default_step(primary) and game.annex_waiting_for_room() and game.annex_room_short() > 0:
			return keep_running_default_step()
		if _is_latchable_step(primary) or _is_default_step(primary):
			return {"text": COMFORT_TEXT.next, "tool": "select"}
		return primary
	var step := _primary_next_step()
	var now := game.keep_running_seconds
	var latchable := _is_latchable_step(step)
	if _kr_latch_text != "":
		var kind := VaultBuilding.Kind.MEDICAL_BED if _kr_latch_tool == "medical" or _kr_latch_text.contains("Med Bed") else VaultBuilding.Kind.RECREATION_CONSOLE
		var resolved: bool = game.get_completed_building_count(kind) > 0 and str(step.get("text", "")) != _kr_latch_text
		if latchable or resolved:
			_kr_latch_clear_at = -1.0
		elif _kr_latch_clear_at < 0.0:
			_kr_latch_clear_at = now + KEEP_RUNNING_UNLATCH_S
		if resolved or (_kr_latch_clear_at >= 0.0 and now >= _kr_latch_clear_at):
			_kr_latch_text = ""
			_kr_latch_tool = ""
			_kr_latch_clear_at = -1.0
		elif latchable or _is_default_step(step):
			return {"text": _kr_latch_text, "tool": _kr_latch_tool}
	if latchable:
		_kr_latch_text = str(step.text)
		_kr_latch_tool = str(step.get("tool", ""))
		_kr_latch_clear_at = -1.0
		return step
	if _is_default_step(step):
		return keep_running_default_step()
	return step


# Past Day 7 only life-support steps pass through (food chain, power, air, care); opening steps
# such as marking rock or placing the first bunks give way to the keep-running Next.
const KEEP_RUNNING_PASS := ["Air Recycler", "Nutrient Station", "Charge Node", "power", "Med Bed", "Rec Console"]
# Steps classified by the diagnosis that produced them, so their wording never decides it.
const STEP_KIND_FOOD := "food"
# Every "<name> <condition>" prefix a resident step puts on Next (_resident_step); the follow
# playtest driver reads this list so it acts on each of them.
const NEXT_DANGER_CONDITIONS: Array[String] = ["starving", "suffocating", "low on air", "exhausted", "in despair"]
const KEEP_RUNNING_PASS_KINDS := [STEP_KIND_FOOD]


# Food-chain recovery (Cook, Haul, Grow Tray, Nutrient Station and their power) from _primary_next_step.
func _food_step(step: Dictionary) -> Dictionary:
	step["kind"] = STEP_KIND_FOOD
	return step


func _is_default_step(step: Dictionary) -> bool:
	if str(step.get("action", "")) in ["reclaim", "spend"]:
		return false
	if bool(step.get("urgent", false)):
		return false
	if str(step.get("kind", "")) in KEEP_RUNNING_PASS_KINDS:
		return false
	var text := str(step.get("text", ""))
	for word: String in KEEP_RUNNING_PASS:
		if text.contains(word):
			return false
	return true


func keep_running_default_step() -> Dictionary:
	var room_short := game.annex_room_short() if game.annex_waiting_for_room() else 0
	if room_short > 0:
		return {
			"text": ANNEX_TEXT.room_next % VaultGame.annex_room_cells_text(room_short),
			"help": ANNEX_TEXT.room_help % VaultGame.annex_room_cells_text(room_short),
			"tool": "dig",
		}
	if game.comfort_pending():
		return {"text": COMFORT_TEXT.next, "tool": "select"}
	if game.annex_active():
		return {"text": ANNEX_TEXT.next, "tool": "select"}
	if game.annex_done:
		return {"text": ANNEX_TEXT.stable_next, "tool": "select"}
	return {"text": KEEP_RUNNING_TEXT.next, "tool": "select"}


# Annex card (north star slice 2): progress bar, the two quotas, and a meal-reserve stepper.
const ANNEX_TEXT := {
	"header": "ANNEX · meals %d/%d · salvage %d/%d",
	"reserve": "Keep %d meals",
	"minus": "−",
	"plus": "+",
	"next": "Next: YOU set the meal reserve · THEY build the Annex",
	"done": "ANNEX COMPLETE",
	"open": "ANNEX OPEN · %d crew · vault stable",
	"stable_next": "Next: YOU enjoy a stable vault · THEY run all of it",
	"welcome": "NEW CREW · %s MOVES IN",
	"room": "ANNEX READY · free %s",
	"room_next": "Next: YOU free %s · THEY open the Annex",
	"room_help": "The Annex needs %s more without a fixture or stockpile zone. Dig rock [E] or clear a zone.",
}
var annex_box: VBoxContainer
var annex_header: Label
var annex_bar: ProgressBar
var annex_reserve_label: Label
var annex_minus_button: Button
var annex_plus_button: Button


const COMFORT_TREATABLE_HP := 95.0
const COMFORT_TEXT := {
	"header": "AFTER THE WIN · comfort",
	"button": "Rec, Med Bed, power, light · %d",
	"next": "Next: YOU tap comfort · THEY build Rec + Med",
}
var comfort_box: VBoxContainer
var comfort_header: Label
var comfort_button: Button


# A won vault only flags injuries a Med Bed will treat (95 HP or below); with none, no INJURED line.
func _keep_running_injury_alert(alerts: Array[String], free_medical: int) -> void:
	var index := -1
	for i in alerts.size():
		if alerts[i].begins_with("INJURED "):
			index = i
			break
	if index < 0:
		return
	var injured := 0
	for resident: VaultResident in game.residents:
		# #107: a starving resident is not a Med Bed patient; keep that rule and add the 95 HP line.
		if _counts_as_injured(resident) and resident.needs.health <= COMFORT_TREATABLE_HP:
			injured += 1
	if injured <= 0:
		alerts.remove_at(index)
	elif alerts[index].ends_with("· NO MED BED"):
		alerts[index] = "INJURED %d · NO MED BED" % injured
	else:
		alerts[index] = "INJURED %d · MED BEDS FREE %d" % [injured, free_medical]


func _build_comfort_card(parent: Control) -> void:
	comfort_box = VBoxContainer.new()
	comfort_box.name = "ComfortCard"
	comfort_box.visible = false
	comfort_box.add_theme_constant_override("separation", 2)
	parent.add_child(comfort_box)
	comfort_header = Label.new()
	comfort_header.text = COMFORT_TEXT.header
	comfort_header.add_theme_color_override("font_color", Color("8faeb7"))
	comfort_header.add_theme_font_size_override("font_size", 13)
	comfort_box.add_child(comfort_header)
	comfort_button = Button.new()
	comfort_button.clip_text = true
	comfort_button.custom_minimum_size.y = 26
	comfort_button.tooltip_text = "Queues a Rec Console and a Med Bed, plus a Charge Node and a Lumen if power or a dark bunk needs them. Crew build them from salvage."
	comfort_button.pressed.connect(func() -> void:
		game.apply_comfort()
		refresh())
	comfort_box.add_child(comfort_button)


func _refresh_comfort() -> void:
	if comfort_box == null:
		return
	comfort_box.visible = game.comfort_pending() and not (game.annex_waiting_for_room() and game.annex_room_short() > 0)
	if comfort_box.visible:
		comfort_button.text = COMFORT_TEXT.button % game.comfort_cost()


const FOOD_PLAN_TEXT := {
	"header": "FOOD PLAN",
	"button": "%s · %d",
	"held": "Keep %d salvage for the hatch",
	"short": "Need %d salvage: %s",
}
const FOOD_PLAN_NAMES := {VaultBuilding.Kind.GENERATOR: "Charge", VaultBuilding.Kind.KITCHEN: "Station", VaultBuilding.Kind.GROW_TRAY: "Tray"}
const FOOD_PLAN_STEP_NAMES := {VaultBuilding.Kind.GENERATOR: "Charge Node", VaultBuilding.Kind.KITCHEN: "Nutrient Station", VaultBuilding.Kind.GROW_TRAY: "Grow Tray"}
var food_plan_box: VBoxContainer
var food_plan_button: Button


func _build_food_plan_card(parent: Control) -> void:
	food_plan_box = VBoxContainer.new()
	food_plan_box.name = "FoodPlanCard"
	food_plan_box.visible = false
	food_plan_box.add_theme_constant_override("separation", 2)
	parent.add_child(food_plan_box)
	var header := Label.new()
	header.text = FOOD_PLAN_TEXT.header
	header.add_theme_color_override("font_color", Color("8faeb7"))
	header.add_theme_font_size_override("font_size", 13)
	food_plan_box.add_child(header)
	food_plan_button = Button.new()
	food_plan_button.name = "FoodPlanButton"
	food_plan_button.clip_text = true
	food_plan_button.custom_minimum_size.y = 26
	food_plan_button.tooltip_text = "Queues a Nutrient Station and a Grow Tray, plus a Charge Node first if power is short. Held while the hatch still needs its patch salvage."
	food_plan_button.pressed.connect(func() -> void:
		game.apply_food_plan(_food_plan_lead_kind())
		refresh())
	food_plan_box.add_child(food_plan_button)


func _refresh_food_plan() -> void:
	if food_plan_box == null:
		return
	# The pre-seal hatch warning opens DETAILS with every readout: the card would push them off-screen.
	food_plan_box.visible = game.food_plan_pending() and not game.keep_running and game.breach_system.phase != BreachSystem.Phase.WARNING
	if not food_plan_box.visible:
		return
	var lead := _food_plan_lead_kind()
	var offer := game.food_plan_offer(lead)
	food_plan_button.disabled = offer.is_empty()
	if offer.size() == 1:
		food_plan_button.text = FOOD_PLAN_TEXT.button % [FOOD_PLAN_STEP_NAMES[offer[0]], game.food_plan_offer_cost(lead)]
	elif not offer.is_empty():
		var names: Array[String] = []
		for kind in offer:
			names.append(FOOD_PLAN_NAMES[kind])
		food_plan_button.text = FOOD_PLAN_TEXT.button % [" + ".join(names), game.food_plan_offer_cost(lead)]
	elif game.food_plan_patch_owed() > 0:
		food_plan_button.text = FOOD_PLAN_TEXT.held % game.food_plan_patch_owed()
	else:
		var want := lead
		if want < 0:
			want = game.food_plan_kinds()[-1]
			for kind: int in VaultGame.FOOD_PLAN_KINDS:
				if game._count_buildings(kind) == 0:
					want = kind
					break
		food_plan_button.text = FOOD_PLAN_TEXT.short % [int(VaultBuilding.COSTS[want]), FOOD_PLAN_STEP_NAMES[want]]


# The food build the displayed Next asks the player to place, or -1.
func _food_plan_lead_kind() -> int:
	var step := _displayed_next_step
	if step.is_empty() or str(step.get("kind", "")) != STEP_KIND_FOOD:
		return -1
	var text := str(step.get("text", ""))
	for kind: int in FOOD_PLAN_STEP_NAMES:
		if ("YOU place a %s" % FOOD_PLAN_STEP_NAMES[kind]) in text:
			return kind
	return -1


func _build_annex_card(parent: Control) -> void:
	annex_box = VBoxContainer.new()
	annex_box.name = "AnnexCard"
	annex_box.visible = false
	annex_box.add_theme_constant_override("separation", 2)
	parent.add_child(annex_box)
	annex_header = Label.new()
	annex_header.add_theme_color_override("font_color", Color("8faeb7"))
	annex_header.add_theme_font_size_override("font_size", 13)
	annex_box.add_child(annex_header)
	annex_bar = ProgressBar.new()
	annex_bar.min_value = 0.0
	annex_bar.max_value = 1.0
	annex_bar.step = 0.0
	annex_bar.show_percentage = false
	annex_bar.custom_minimum_size.y = 8
	annex_bar.modulate = Color("75d4b4")
	annex_box.add_child(annex_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	annex_box.add_child(row)
	annex_minus_button = Button.new()
	annex_minus_button.text = ANNEX_TEXT.minus
	annex_minus_button.custom_minimum_size = Vector2(26, 22)
	annex_minus_button.tooltip_text = "Keep fewer meals back: more go to the Annex."
	annex_minus_button.pressed.connect(func() -> void: game.set_annex_reserve(game.annex_reserve - VaultGame.ANNEX_RESERVE_STEP))
	row.add_child(annex_minus_button)
	annex_reserve_label = Label.new()
	annex_reserve_label.add_theme_font_size_override("font_size", 13)
	annex_reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	annex_reserve_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(annex_reserve_label)
	annex_plus_button = Button.new()
	annex_plus_button.text = ANNEX_TEXT.plus
	annex_plus_button.custom_minimum_size = Vector2(26, 22)
	annex_plus_button.tooltip_text = "Keep more meals back for the crew."
	annex_plus_button.pressed.connect(func() -> void: game.set_annex_reserve(game.annex_reserve + VaultGame.ANNEX_RESERVE_STEP))
	row.add_child(annex_plus_button)


func annex_header_text() -> String:
	return ANNEX_TEXT.header % [game.annex_meals, VaultGame.ANNEX_MEALS, game.annex_salvage, VaultGame.ANNEX_SALVAGE]


func _refresh_annex() -> void:
	if annex_box == null:
		return
	annex_box.visible = game.annex_active() or (game.keep_running and game.annex_done and not game.ended)
	if not annex_box.visible:
		return
	var open := game.annex_done
	var room_short := game.annex_room_short() if game.annex_waiting_for_room() else 0
	annex_minus_button.get_parent().visible = not open and room_short == 0
	if room_short > 0:
		annex_header.text = ANNEX_TEXT.room % VaultGame.annex_room_cells_text(room_short)
		annex_bar.value = 1.0
		return
	if open:
		annex_header.text = ANNEX_TEXT.open % game.get_alive_count()
		annex_bar.value = 1.0
		return
	annex_header.text = annex_header_text()
	annex_bar.value = game.annex_progress()
	annex_reserve_label.text = ANNEX_TEXT.reserve % game.annex_reserve
	annex_minus_button.disabled = game.annex_reserve <= VaultGame.ANNEX_RESERVE_MIN
	annex_plus_button.disabled = game.annex_reserve >= VaultGame.ANNEX_RESERVE_MAX
