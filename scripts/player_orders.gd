class_name PlayerOrders
extends CanvasLayer

var game: VaultGame
var root: Control
var clock_label: Label
var resource_label: Label
var power_label: Label
var pause_button: Button
var objective_label: Label
var alert_label: Label
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
var need_labels: Dictionary = {}
var need_bars: Dictionary = {}
var work_buttons: Dictionary = {}
var command_buttons: Dictionary = {}
var command_grid: GridContainer
var tool_status: Label
var checklist: RichTextLabel
var briefing_overlay: Control
var briefing_panel: PanelContainer
var briefing_load_button: Button
var briefing_begin_button: Button
var briefing_close_button: Button
var help_button: Button
var breach_warning_panel: PanelContainer
var breach_resume_button: Button
var outcome_panel: PanelContainer
var outcome_title: Label
var outcome_text: Label
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
	top_row.add_theme_constant_override("separation", 14)
	top_panel.add_child(top_row)
	var brand := Label.new()
	brand.text = "VAULT WING // SUBLEVEL 07"
	brand.add_theme_color_override("font_color", Color("77d3bc"))
	brand.add_theme_font_size_override("font_size", 17)
	brand.custom_minimum_size.x = 262
	top_row.add_child(brand)
	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 170
	top_row.add_child(clock_label)
	resource_label = Label.new()
	resource_label.custom_minimum_size.x = 185
	top_row.add_child(resource_label)
	power_label = Label.new()
	power_label.custom_minimum_size.x = 210
	top_row.add_child(power_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
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
	objective_label.text = "OBJECTIVE // 7 DAYS · SEAL · O2"
	objective_label.add_theme_color_override("font_color", Color("efc56b"))
	objective_label.add_theme_font_size_override("font_size", 16)
	summary.add_child(objective_label)
	alert_label = Label.new()
	alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alert_label.custom_minimum_size.y = 38
	summary.add_child(alert_label)
	var mood_header := Label.new()
	mood_header.text = "CREW MOOD"
	mood_header.add_theme_color_override("font_color", Color("8faeb7"))
	summary.add_child(mood_header)
	crew_mood_label = Label.new()
	crew_mood_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew_mood_label.custom_minimum_size.y = 38
	summary.add_child(crew_mood_label)
	crew_mood_bar = ProgressBar.new()
	crew_mood_bar.min_value = 0.0
	crew_mood_bar.max_value = 100.0
	crew_mood_bar.show_percentage = false
	crew_mood_bar.custom_minimum_size.y = 10
	summary.add_child(crew_mood_bar)
	var lighting_row := HBoxContainer.new()
	lighting_row.add_theme_constant_override("separation", 6)
	summary.add_child(lighting_row)
	lighting_label = Label.new()
	lighting_label.custom_minimum_size = Vector2(188, 26)
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
	summary.add_child(power_header)
	power_detail_label = Label.new()
	power_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_detail_label.custom_minimum_size.y = 62
	summary.add_child(power_detail_label)
	var oxygen_header := Label.new()
	oxygen_header.text = "VAULT ATMOSPHERE"
	oxygen_header.add_theme_color_override("font_color", Color("8faeb7"))
	summary.add_child(oxygen_header)
	oxygen_label = Label.new()
	oxygen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	oxygen_label.custom_minimum_size.y = 38
	summary.add_child(oxygen_label)
	oxygen_bar = ProgressBar.new()
	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = OxygenSystem.MAX_OXYGEN
	oxygen_bar.show_percentage = false
	oxygen_bar.custom_minimum_size.y = 10
	summary.add_child(oxygen_bar)
	var breach_header := Label.new()
	breach_header.text = "PRESSURE HATCH"
	breach_header.add_theme_color_override("font_color", Color("8faeb7"))
	summary.add_child(breach_header)
	breach_label = Label.new()
	breach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	breach_label.custom_minimum_size.y = 64
	summary.add_child(breach_label)
	breach_bar = ProgressBar.new()
	breach_bar.min_value = 0.0
	breach_bar.max_value = 100.0
	breach_bar.show_percentage = false
	breach_bar.custom_minimum_size.y = 10
	summary.add_child(breach_bar)
	breach_focus_button = Button.new()
	breach_focus_button.text = "FOCUS HATCH"
	breach_focus_button.custom_minimum_size.y = 26
	breach_focus_button.pressed.connect(func() -> void: game.focus_breach())
	summary.add_child(breach_focus_button)
	summary.add_child(HSeparator.new())
	right_scroll = ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(right_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(side)
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
	work_priorities_button.tooltip_text = "Edit priorities for the whole crew without changing the active map tool."
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
	_hide_fixture_controls()

	var bottom_panel := PanelContainer.new()
	bottom_panel.set_anchor(SIDE_RIGHT, 1.0)
	bottom_panel.set_anchor(SIDE_TOP, 1.0)
	bottom_panel.set_anchor(SIDE_BOTTOM, 1.0)
	bottom_panel.offset_left = 8.0
	bottom_panel.offset_right = -VaultGame.RIGHT_PANEL_WIDTH - 8.0
	bottom_panel.offset_top = -126.0
	bottom_panel.offset_bottom = -8.0
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color("121b21"), Color("45616a")))
	root.add_child(bottom_panel)
	var bottom_content := VBoxContainer.new()
	bottom_content.add_theme_constant_override("separation", 3)
	bottom_panel.add_child(bottom_content)
	tool_status = Label.new()
	tool_status.text = "SELECT"
	tool_status.add_theme_color_override("font_color", Color("efc56b"))
	bottom_content.add_child(tool_status)
	command_grid = GridContainer.new()
	command_grid.name = "CommandGrid"
	command_grid.columns = 8
	command_grid.add_theme_constant_override("h_separation", 5)
	command_grid.add_theme_constant_override("v_separation", 4)
	bottom_content.add_child(command_grid)
	var tools := [
		["select", "SELECT", "Inspect residents and fixtures; Esc returns here", 76],
		["dig", "DIG [E]", "Mark rock for excavation", 68],
		["cancel", "CANCEL [X]", "Clear zone cells, orders, and blueprints", 96],
		["bed", "BUNK $8", "Rest fixture", 80],
		["lamp", "LUMEN $5", "1 power; lights floor within %d tiles" % LightingSystem.LUMEN_RADIUS, 90],
		["generator", "CHARGE $18", "+7 power", 104],
		["grow", "GROW $12", "3 power; yields raw food for hauling", 90],
		["kitchen", "NUTRI $10", "2 power; cooks meals for hauling", 96],
		["zone", "ZONE", "Paint drop-offs for salvage, raw food, and meals; CANCEL [X] clears", 76],
		["stockpile", "BAY $4", "Fallback destination for salvage and food hauling", 64],
		["air", "AIR $14", "Air Recycler: 3 power; restores vault oxygen", 86],
		["medical", "MED $8", "Medical Bed: automatic injury recovery, +2 HP/s; no power", 82],
		["rec", "REC $8", "Rec Console: 1 power; restores one resident's mood", 82],
	]
	for definition in tools:
		var button := Button.new()
		button.text = definition[1]
		button.tooltip_text = definition[2]
		button.custom_minimum_size = Vector2(float(definition[3]), 36)
		button.clip_text = true
		button.pressed.connect(_on_tool_pressed.bind(definition[0]))
		command_buttons[definition[0]] = button
		command_grid.add_child(button)
	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.tooltip_text = "Save one local wing slot"
	save_button.custom_minimum_size = Vector2(56, 36)
	save_button.pressed.connect(func() -> void: game.save_game())
	command_grid.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "LOAD"
	load_button.tooltip_text = "Load the local wing slot"
	load_button.custom_minimum_size = Vector2(56, 36)
	load_button.pressed.connect(func() -> void: game.load_game())
	command_grid.add_child(load_button)
	help_button = Button.new()
	help_button.text = "HELP"
	help_button.tooltip_text = "Pause behind the live first-shift checklist"
	help_button.custom_minimum_size = Vector2(62, 36)
	help_button.pressed.connect(open_help)
	command_grid.add_child(help_button)

	_build_work_priorities_board()
	_build_briefing()
	_build_breach_warning()
	_build_outcome()


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
	eyebrow.text = "CREW SCHEDULER // ORDINARY WORK"
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
	explanation.text = "Click a cell to cycle.  1 = highest  ·  4 = lowest  ·  OFF = never claim. HAUL covers salvage, raw food, and meals. Drafted residents keep editable schedules that resume after undraft. Hatch work overrides numbered ranks, but OFF still blocks it. Recreation is autonomous."
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
	briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	briefing_panel.custom_minimum_size = Vector2(640, 520)
	briefing_panel.size = Vector2(640, 520)
	briefing_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	briefing_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("72cdb8"), 3))
	briefing_overlay.add_child(briefing_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	briefing_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	var title := Label.new()
	title.text = "VAULT WING 07 // SEAL STABILIZATION"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("75d4b4"))
	content.add_child(title)
	var intro := Label.new()
	intro.text = "Dig and haul salvage, add bunks, then power food and an Air Recycler. Keep Haul enabled to store Grow Tray and Nutrient Station output. Reserve 4 salvage and keep Haul + Craft enabled for the hatch warning."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.y = 54
	content.add_child(intro)
	var checklist_scroll := ScrollContainer.new()
	checklist_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	checklist_scroll.custom_minimum_size.y = 180
	checklist_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(checklist_scroll)
	checklist = RichTextLabel.new()
	checklist.bbcode_enabled = true
	checklist.fit_content = true
	checklist.scroll_active = false
	checklist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checklist_scroll.add_child(checklist)
	var controls := Label.new()
	controls.text = "LMB order/select · Select resident then R draft/undraft · RMB: drafted = move, undrafted = force context job · Esc return to Select · X cancel · P priorities · L light map · WASD pan · wheel zoom · Space pause · 1/2/3 speed · F recenter"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_color_override("font_color", Color("a9bec3"))
	content.add_child(controls)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	content.add_child(buttons)
	briefing_load_button = Button.new()
	briefing_load_button.text = "LOAD LOCAL SAVE"
	briefing_load_button.pressed.connect(func() -> void: game.load_game())
	buttons.add_child(briefing_load_button)
	briefing_close_button = Button.new()
	briefing_close_button.text = "CLOSE HELP [ESC]"
	briefing_close_button.pressed.connect(show_briefing.bind(false))
	buttons.add_child(briefing_close_button)
	briefing_begin_button = Button.new()
	briefing_begin_button.text = "BEGIN SHIFT"
	briefing_begin_button.pressed.connect(func() -> void: game.begin_shift())
	buttons.add_child(briefing_begin_button)


func _build_outcome() -> void:
	outcome_panel = PanelContainer.new()
	outcome_panel.set_anchors_preset(Control.PRESET_CENTER)
	outcome_panel.position = Vector2(-260, -145)
	outcome_panel.size = Vector2(520, 290)
	outcome_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	outcome_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("efc56b"), 3))
	root.add_child(outcome_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	outcome_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	outcome_title = Label.new()
	outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_title.add_theme_font_size_override("font_size", 26)
	content.add_child(outcome_title)
	outcome_text = Label.new()
	outcome_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_text.custom_minimum_size.y = 92
	content.add_child(outcome_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var load_button := Button.new()
	load_button.text = "LOAD LAST CHECKPOINT"
	load_button.pressed.connect(func() -> void: game.load_game())
	row.add_child(load_button)
	var restart_button := Button.new()
	restart_button.text = "NEW WING"
	restart_button.pressed.connect(func() -> void: game.new_game(true))
	row.add_child(restart_button)
	outcome_panel.visible = false


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
	if game == null or clock_label == null:
		return
	clock_label.text = game.day_cycle.get_clock_text()
	resource_label.text = "MEALS %d (+%d)  RAW %d (+%d)  SALVAGE %d" % [
		game.food_system.meals,
		game.job_system.get_pending_meals(),
		game.food_system.raw_food,
		game.job_system.get_pending_raw_food(),
		game.food_system.salvage,
	]
	resource_label.tooltip_text = "Stored inventory; values in parentheses are produced food still awaiting Haul delivery."
	command_buttons.zone.text = "ZONE %d" % game.map_grid.stockpile_cells.size()
	command_buttons.zone.tooltip_text = "Stockpile: %d cells. Salvage, raw food, and meals prefer reachable zones; otherwise Salvage Bay / chamber center. Click/drag to paint; CANCEL [X] clears." % game.map_grid.stockpile_cells.size()
	_refresh_objective()
	power_label.text = game.power_grid.get_status_text()
	power_label.add_theme_color_override("font_color", Color("ef6860") if game.power_grid.brownout_active else Color("75d4b4"))
	_refresh_power_detail()
	pause_button.text = "RESUME" if game.user_paused else "PAUSE"
	var active_help := game.status_message if game.status_message_left > 0.0 else game._tool_help(game.active_tool)
	if game.status_message_left <= 0.0 and game.active_tool == "select":
		active_help = "Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
	tool_status.text = "%s // %s" % [game.active_tool.to_upper(), active_help]
	for key: String in command_buttons:
		var button: Button = command_buttons[key]
		button.disabled = game.tutorial_open or is_help_open() or game.ended
		button.modulate = Color("efc56b") if key == game.active_tool else Color.WHITE
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
	_refresh_roster()
	_refresh_work_priorities_board()
	_refresh_crew_mood()
	_refresh_lighting()
	_refresh_oxygen()
	_refresh_breach()
	_refresh_inspector()
	_refresh_alerts()
	_refresh_checklist()


func _refresh_objective() -> void:
	if game.day_cycle.completed and not game.ended:
		var blockers: Array[String] = []
		if not game.breach_system.is_sealed():
			blockers.append("SEAL HATCH")
		if not game.oxygen_system.is_breathable():
			blockers.append("RESTORE O2 TO 15%")
		objective_label.text = "VICTORY PENDING // %s" % " + ".join(blockers)
		objective_label.add_theme_color_override("font_color", Color("ef6860"))
		return
	objective_label.text = "OBJECTIVE // 7 DAYS · SEAL · O2"
	objective_label.add_theme_color_override("font_color", Color("efc56b"))


func _refresh_roster() -> void:
	var parts: Array[String] = []
	for resident in game.residents:
		parts.append("%d:%d:%d:%d:%d:%s:%s:%s:%s" % [
			resident.resident_id,
			floori(resident.needs.food),
			floori(resident.needs.rest),
			floori(resident.needs.mood),
			floori(resident.needs.health),
			resident.state,
			str(resident.drafted),
			str(resident.has_manual_move_order()),
			str(resident.is_forced_job),
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
		button.text = "%s · %s · HP %d · MOOD %d · LOW %d" % [resident.resident_name, resident_status, floori(resident.needs.health), floori(resident.needs.mood), floori(urgent)] if resident.alive else "%s · DECEASED" % resident.resident_name
		button.tooltip_text = button.text
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not resident.alive
		button.pressed.connect(_on_resident_pressed.bind(resident.resident_id))
		roster_box.add_child(button)


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
		if resident.recreating:
			if game.job_system.is_recreation_running(resident):
				mood_factors = "Rec Console · +%.0f mood/s" % ResidentNeeds.RECREATION_RECOVERY_PER_SECOND
			elif game.job_system.is_actively_recreating(resident):
				mood_factors = "Rec Console · paused"
			else:
				mood_factors = "Seeking Rec Console · %s" % resident.needs.get_mood_factors(is_lit, false, game.oxygen_system.is_low())
		inspector_state.text = "Current task: %s\nWork speed: %d%%\nMood: %s\n%s" % [
			_get_resident_order_status(resident),
			roundi(resident.get_work_multiplier() * 100.0),
			resident.needs.get_mood_state(),
			mood_factors,
		]
		_set_need("food", "FOOD", resident.needs.food)
		_set_need("rest", "REST", resident.needs.rest)
		_set_need("mood", "MOOD", resident.needs.mood)
		_set_need("health", "HEALTH", resident.needs.health)
		_show_resident_commands(resident)
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
					game.job_system.get_breach_response_status(),
				]
			BreachSystem.Phase.OPEN:
				inspector_state.text = "BREACH OPEN · O2 -%.1f%%/s\nPatch work remaining: %.1fs\n%s" % [
					OxygenSystem.OPEN_BREACH_LOSS_PER_SECOND,
					game.breach_system.patch_work_left,
					game.job_system.get_breach_response_status(),
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
					floori(building.production_progress / FoodSystem.GROW_SECONDS * 100.0),
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
			_hide_fixture_controls()
		_hide_needs_and_work()
		return
	_last_inspected_building_id = -1
	inspector_title.text = "INSPECTOR"
	inspector_state.text = "Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job. Select a fixture to inspect it; PRIORITIES [P] schedules ordinary work."
	_hide_needs_and_work()
	_hide_fixture_controls()


func _refresh_alerts() -> void:
	var alerts: Array[String] = []
	var drafted_count := 0
	for resident: VaultResident in game.residents:
		if resident.alive and resident.drafted:
			drafted_count += 1
	if drafted_count > 0:
		alerts.append("DRAFTED CREW %d · AUTO WORK PAUSED" % drafted_count)
		if game.breach_system.phase == BreachSystem.Phase.WARNING or game.breach_system.phase == BreachSystem.Phase.OPEN:
			alerts.append("HATCH RESPONSE EXCLUDES DRAFTED CREW")
	if game.day_cycle.completed and not game.ended:
		var victory_blockers: Array[String] = []
		if not game.breach_system.is_sealed():
			victory_blockers.append("SEAL HATCH")
		if not game.oxygen_system.is_breathable():
			victory_blockers.append("O2 >= 15%")
		alerts.append("VICTORY PENDING · %s" % " + ".join(victory_blockers))
	if game.oxygen_system.is_critical():
		alerts.append("OXYGEN CRITICAL")
	elif game.oxygen_system.is_low():
		alerts.append("OXYGEN LOW")
	if game.breach_system.phase == BreachSystem.Phase.OPEN:
		alerts.append("BREACH OPEN · O2 VENTING")
	elif game.breach_system.phase == BreachSystem.Phase.WARNING:
		alerts.append("SEAL WARNING · %s" % _format_seconds(game.breach_system.get_time_to_open()))
	if game.food_system.meals < game.get_alive_count():
		alerts.append("LOW MEALS")
	var pending_food := game.job_system.get_pending_raw_food() + game.job_system.get_pending_meals()
	if pending_food > 0 and not _has_eligible_worker("haul"):
		alerts.append("FOOD WAITING · ENABLE HAUL")
	if game.power_grid.brownout_active:
		alerts.append("POWER BROWNOUT · SHED %s" % game.power_grid.get_shed_summary())
	var dark_residents := game.get_dark_resident_count()
	if dark_residents > 0:
		alerts.append("DARKNESS · %d CREW UNLIT" % dark_residents)
	if game.get_completed_building_count(VaultBuilding.Kind.BED) < game.get_alive_count():
		alerts.append("BED SHORTAGE")
	var injured := 0
	var free_medical := 0
	for resident: VaultResident in game.residents:
		if resident.alive and resident.needs.health < 100.0:
			injured += 1
	for bed: VaultBuilding in game.buildings:
		if bed.kind == VaultBuilding.Kind.MEDICAL_BED and bed.complete and not bed.manually_disabled and bed.reserved_by < 0:
			free_medical += 1
	if injured > 0 or game.get_completed_building_count(VaultBuilding.Kind.MEDICAL_BED) > 0:
		alerts.append("INJURED %d · MED BEDS FREE %d" % [injured, free_medical])
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
	var cook_enabled := _has_eligible_worker("cook")
	if not cook_enabled:
		alerts.append("NO COOK ENABLED")
	for resident in game.residents:
		if resident.alive and (resident.needs.food < 20.0 or resident.needs.rest < 15.0):
			alerts.append("CRITICAL: %s" % resident.resident_name)
			break
	alert_label.text = "STATUS NOMINAL" if alerts.is_empty() else "  ·  ".join(alerts)
	alert_label.add_theme_color_override("font_color", Color("75d4b4") if alerts.is_empty() else Color("ef6860"))


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
	oxygen_bar.value = oxygen.oxygen
	if oxygen.is_critical():
		oxygen_bar.modulate = Color("ef6860")
	elif oxygen.is_low():
		oxygen_bar.modulate = Color("efc56b")
	else:
		oxygen_bar.modulate = Color("75d4b4")


func _refresh_breach() -> void:
	var breach := game.breach_system
	breach_focus_button.visible = breach.phase != BreachSystem.Phase.DORMANT
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
				game.job_system.get_breach_response_status(),
			]
			breach_bar.value = breach.get_pressure_percent()
			breach_bar.modulate = Color("efc56b")
		BreachSystem.Phase.OPEN:
			breach_label.text = "BREACH OPEN · O2 -%.1f%%/s\nPATCH %d/%d · WORK %.1fs\n%s" % [
				OxygenSystem.OPEN_BREACH_LOSS_PER_SECOND,
				breach.patch_delivered,
				BreachSystem.PATCH_COST,
				breach.patch_work_left,
				game.job_system.get_breach_response_status(),
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
	var initial_floor_count := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
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
	var lines: Array[String] = ["[color=#8faeb7]STABILIZATION CHECKLIST // REQUIRED[/color]"]
	for check in checks:
		var marker := "[color=#75d4b4][DONE][/color]" if check[0] else "[color=#efc56b][    ][/color]"
		lines.append("%s  %s" % [marker, check[1]])
	var rec_done := game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE) >= 1
	var rec_marker := "[color=#75d4b4][DONE][/color]" if rec_done else "[color=#8faeb7][OPTIONAL][/color]"
	lines.append("%s  Power a Rec Console; free 1 power if shed" % rec_marker)
	lines.append("[color=#efc56b]LIGHTING[/color]  Powered Lumens cover %d tiles. Shed Lumens stop lighting cells; darkness costs awake residents 30 extra mood/day. [L] maps coverage" % LightingSystem.LUMEN_RADIUS)
	lines.append("Optional: ZONE paints salvage + food drop-offs; CANCEL clears cells")
	lines.append("Optional: Medical Bed ($8) heals injuries; disable to deny care")
	lines.append("[color=#8faeb7][OPTIONAL][/color]  PRIORITIES [P]: 1 highest · 4 lowest · OFF disabled")
	lines.append("[color=#8faeb7][OPTIONAL][/color]  MANUAL ORDERS: select resident → [R] draft/undraft; right-click drafted = move, undrafted = force context job")
	checklist.text = "\n".join(lines)


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
	work_priorities_summary.text = "COVERAGE // %s" % "  ·  ".join(coverage_parts)
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
	briefing_overlay.visible = visible
	briefing_panel.visible = visible
	if briefing_begin_button != null:
		briefing_begin_button.visible = opening
	if briefing_close_button != null:
		briefing_close_button.visible = not opening
	if visible:
		show_work_priorities(false)
		_configure_briefing_focus(opening)
		_focus_first_briefing_control(opening)
	elif was_visible:
		get_viewport().gui_release_focus()


func _briefing_focus_controls(opening: bool) -> Array[Control]:
	var controls: Array[Control] = []
	var primary: Button = briefing_begin_button if opening else briefing_close_button
	if primary != null and primary.visible and not primary.disabled:
		controls.append(primary)
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


func show_outcome(won: bool, survivors: int) -> void:
	show_briefing(false)
	show_work_priorities(false)
	show_breach_warning(false)
	outcome_panel.visible = true
	if won:
		outcome_title.text = "SEAL STABILIZED"
		outcome_title.add_theme_color_override("font_color", Color("75d4b4"))
		outcome_text.text = "The pressure breach was contained, breathable air was restored, and the wing remained inhabited through seven full days. %d resident%s survived. Your local victory state has been saved." % [survivors, "" if survivors == 1 else "s"]
	else:
		outcome_title.text = "WING LOST"
		outcome_title.add_theme_color_override("font_color", Color("ef6860"))
		outcome_text.text = "No residents remain alive. Reopen the last daily checkpoint or initialize a new wing and stabilize supplies, powered air recycling, and the pressure hatch sooner."


func hide_outcome() -> void:
	if outcome_panel != null:
		outcome_panel.visible = false


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
		return
	var is_consumer := building.is_power_consumer() or building.kind == VaultBuilding.Kind.MEDICAL_BED
	fixture_header.text = "FIXTURE CONTROLS"
	fixture_power_button.visible = is_consumer
	fixture_power_button.text = "ENABLE" if building.manually_disabled else "DISABLE"
	fixture_power_button.disabled = not is_consumer
	fixture_power_button.tooltip_text = "Allow or deny medical care." if building.kind == VaultBuilding.Kind.MEDICAL_BED else "Remove or restore this fixture's power demand."
	fixture_deconstruct_button.disabled = building.is_emergency_core
	fixture_deconstruct_button.tooltip_text = "Emergency core cannot be deconstructed." if building.is_emergency_core else "Recover %d salvage and remove this fixture." % building.get_deconstruct_refund()


func _hide_fixture_controls() -> void:
	if fixture_header != null:
		fixture_header.visible = false
	if fixture_controls != null:
		fixture_controls.visible = false


func _on_tool_pressed(tool: String) -> void:
	game.set_tool(tool)


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
