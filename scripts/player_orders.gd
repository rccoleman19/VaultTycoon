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
var roster_box: VBoxContainer
var inspector_title: Label
var inspector_state: Label
var need_labels: Dictionary = {}
var need_bars: Dictionary = {}
var work_buttons: Dictionary = {}
var command_buttons: Dictionary = {}
var tool_status: Label
var checklist: RichTextLabel
var briefing_panel: PanelContainer
var outcome_panel: PanelContainer
var outcome_title: Label
var outcome_text: Label

var _last_roster_signature := ""


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
	power_label.custom_minimum_size.x = 150
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
	right_panel.offset_bottom = -92.0
	right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	right_panel.add_theme_stylebox_override("panel", _panel_style(Color("152129"), Color("3d5962")))
	root.add_child(right_panel)
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 12)
	right_margin.add_theme_constant_override("margin_right", 12)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(right_margin)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	right_margin.add_child(side)
	objective_label = Label.new()
	objective_label.text = "OBJECTIVE // SURVIVE 7 DAYS"
	objective_label.add_theme_color_override("font_color", Color("efc56b"))
	objective_label.add_theme_font_size_override("font_size", 16)
	side.add_child(objective_label)
	alert_label = Label.new()
	alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alert_label.custom_minimum_size.y = 38
	side.add_child(alert_label)
	side.add_child(HSeparator.new())
	var roster_header := Label.new()
	roster_header.text = "RESIDENT ROSTER"
	roster_header.add_theme_color_override("font_color", Color("8faeb7"))
	side.add_child(roster_header)
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
	for need_name in ["food", "rest", "light_mood", "health"]:
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
	var work_header := Label.new()
	work_header.text = "WORK PERMISSIONS"
	work_header.add_theme_color_override("font_color", Color("8faeb7"))
	side.add_child(work_header)
	var work_row := GridContainer.new()
	work_row.columns = 2
	work_row.add_theme_constant_override("h_separation", 5)
	work_row.add_theme_constant_override("v_separation", 4)
	for work_type in ["dig", "haul", "craft", "cook"]:
		var work_button := Button.new()
		work_button.toggle_mode = true
		work_button.custom_minimum_size = Vector2(130, 28)
		work_button.pressed.connect(_on_work_pressed.bind(work_type))
		work_buttons[work_type] = work_button
		work_row.add_child(work_button)
	side.add_child(work_row)

	var bottom_panel := PanelContainer.new()
	bottom_panel.set_anchor(SIDE_RIGHT, 1.0)
	bottom_panel.set_anchor(SIDE_TOP, 1.0)
	bottom_panel.set_anchor(SIDE_BOTTOM, 1.0)
	bottom_panel.offset_left = 8.0
	bottom_panel.offset_right = -VaultGame.RIGHT_PANEL_WIDTH - 8.0
	bottom_panel.offset_top = -86.0
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
	var command_row := HBoxContainer.new()
	command_row.add_theme_constant_override("separation", 4)
	bottom_content.add_child(command_row)
	var tools := [
		["select", "SELECT [Esc]", "Inspect residents and fixtures"],
		["dig", "DIG [D]", "Mark rock for excavation"],
		["cancel", "CANCEL [X]", "Remove orders and blueprints"],
		["bed", "BUNK $8", "Rest fixture"],
		["lamp", "LUMEN $5", "1 power; lights nearby tiles"],
		["generator", "CHARGE $18", "+7 power"],
		["grow", "GROW $12", "3 power; yields raw food"],
		["kitchen", "NUTRIENT $10", "2 power; cooks meals"],
		["stockpile", "SALVAGE $4", "Hauling destination"],
	]
	for definition in tools:
		var button := Button.new()
		button.text = definition[1]
		button.tooltip_text = definition[2]
		button.custom_minimum_size = Vector2(92, 36)
		button.pressed.connect(_on_tool_pressed.bind(definition[0]))
		command_buttons[definition[0]] = button
		command_row.add_child(button)
	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.tooltip_text = "Save one local wing slot"
	save_button.custom_minimum_size = Vector2(64, 36)
	save_button.pressed.connect(func() -> void: game.save_game())
	command_row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "LOAD"
	load_button.tooltip_text = "Load the local wing slot"
	load_button.custom_minimum_size = Vector2(64, 36)
	load_button.pressed.connect(func() -> void: game.load_game())
	command_row.add_child(load_button)

	_build_briefing()
	_build_outcome()


func _build_briefing() -> void:
	briefing_panel = PanelContainer.new()
	briefing_panel.set_anchors_preset(Control.PRESET_CENTER)
	briefing_panel.position = Vector2(-300, -225)
	briefing_panel.size = Vector2(600, 450)
	briefing_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	briefing_panel.add_theme_stylebox_override("panel", _panel_style(Color("111b21"), Color("72cdb8"), 3))
	root.add_child(briefing_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	briefing_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.text = "VAULT WING 07 // SEAL STABILIZATION"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("75d4b4"))
	content.add_child(title)
	var intro := Label.new()
	intro.text = "Four residents are sealed below ground with emergency rations and a failing core. Carve new rooms, assemble bunks, restore charge capacity, and establish nutrient production. Keep at least one resident alive through seven complete days."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.y = 78
	content.add_child(intro)
	checklist = RichTextLabel.new()
	checklist.bbcode_enabled = true
	checklist.fit_content = false
	checklist.custom_minimum_size.y = 210
	checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(checklist)
	var controls := Label.new()
	controls.text = "LMB order/select · RMB/Esc cancel tool · WASD pan · wheel zoom · Space pause · 1/2/3 speed · F recenter"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_color_override("font_color", Color("a9bec3"))
	content.add_child(controls)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(buttons)
	var load_button := Button.new()
	load_button.text = "LOAD LOCAL SAVE"
	load_button.pressed.connect(func() -> void: game.load_game())
	buttons.add_child(load_button)
	var begin_button := Button.new()
	begin_button.text = "BEGIN SHIFT"
	begin_button.pressed.connect(func() -> void: game.begin_shift())
	buttons.add_child(begin_button)


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


func refresh() -> void:
	if game == null or clock_label == null:
		return
	clock_label.text = game.day_cycle.get_clock_text()
	resource_label.text = "MEALS %d  RAW %d  SALVAGE %d" % [game.food_system.meals, game.food_system.raw_food, game.food_system.salvage]
	power_label.text = game.power_grid.get_status_text()
	power_label.add_theme_color_override("font_color", Color("ef6860") if game.power_grid.demand > game.power_grid.supply else Color("75d4b4"))
	pause_button.text = "RESUME" if game.user_paused else "PAUSE"
	tool_status.text = "%s // %s" % [game.active_tool.to_upper(), game.status_message]
	for key: String in command_buttons:
		var button: Button = command_buttons[key]
		button.disabled = game.tutorial_open or game.ended
		button.modulate = Color("efc56b") if key == game.active_tool else Color.WHITE
	_refresh_roster()
	_refresh_inspector()
	_refresh_alerts()
	_refresh_checklist()


func _refresh_roster() -> void:
	var parts: Array[String] = []
	for resident in game.residents:
		parts.append("%d:%d:%d:%s" % [resident.resident_id, floori(resident.needs.food), floori(resident.needs.rest), resident.state])
	var signature := "|".join(parts)
	if signature == _last_roster_signature:
		return
	_last_roster_signature = signature
	for child in roster_box.get_children():
		child.queue_free()
	for resident in game.residents:
		var button := Button.new()
		var urgent := minf(resident.needs.food, minf(resident.needs.rest, resident.needs.health))
		button.text = "%s  |  %s  |  LOW %d" % [resident.resident_name, resident.state, floori(urgent)] if resident.alive else "%s  |  DECEASED" % resident.resident_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not resident.alive
		button.pressed.connect(_on_resident_pressed.bind(resident.resident_id))
		roster_box.add_child(button)


func _refresh_inspector() -> void:
	var resident := game.get_resident_by_id(game.selected_resident_id)
	if resident != null:
		inspector_title.text = "%s // RESIDENT" % resident.resident_name.to_upper()
		inspector_state.text = "Current task: %s\nWork speed: %d%%" % [resident.state, roundi(resident.get_work_multiplier() * 100.0)]
		_set_need("food", "FOOD", resident.needs.food)
		_set_need("rest", "REST", resident.needs.rest)
		_set_need("light_mood", "LIGHT", resident.needs.light_mood)
		_set_need("health", "HEALTH", resident.needs.health)
		for key: String in work_buttons:
			var button: Button = work_buttons[key]
			button.visible = true
			button.button_pressed = bool(resident.work_allowed[key])
			button.text = "%s: %s" % [key.to_upper(), "ON" if resident.work_allowed[key] else "OFF"]
		return
	var building := game.get_building_by_id(game.selected_building_id)
	if building != null:
		inspector_title.text = building.get_display_name().to_upper()
		if building.complete:
			var power_text := "Powered" if building.get_power_demand() == 0 or building.powered else "UNPOWERED"
			inspector_state.text = "Online · %s\nPower: %d use / %d output" % [power_text, building.get_power_demand(), building.get_power_output()]
			if building.kind == VaultBuilding.Kind.GROW_TRAY:
				inspector_state.text += "\nGrowth: %d%% · yields 1 raw" % floori(building.production_progress / FoodSystem.GROW_SECONDS * 100.0)
			elif building.kind == VaultBuilding.Kind.KITCHEN:
				inspector_state.text += "\nRecipe: 1 raw -> 1 meal"
		else:
			inspector_state.text = "Blueprint · Salvage %d/%d\nAssembly remaining: %.1fs" % [building.delivered, building.get_cost(), building.construction_left]
		_hide_needs_and_work()
		return
	inspector_title.text = "INSPECTOR"
	inspector_state.text = "Select a resident or fixture. Dig and build orders are completed through work permissions."
	_hide_needs_and_work()


func _refresh_alerts() -> void:
	var alerts: Array[String] = []
	if game.food_system.meals < game.get_alive_count():
		alerts.append("LOW MEALS")
	if game.power_grid.demand > game.power_grid.supply:
		alerts.append("POWER OVERLOAD")
	if game.get_completed_building_count(VaultBuilding.Kind.BED) < game.get_alive_count():
		alerts.append("BED SHORTAGE")
	var cook_enabled := false
	for resident in game.residents:
		if resident.alive and bool(resident.work_allowed.cook):
			cook_enabled = true
	if not cook_enabled:
		alerts.append("NO COOK ENABLED")
	for resident in game.residents:
		if resident.alive and (resident.needs.food < 20.0 or resident.needs.rest < 15.0):
			alerts.append("CRITICAL: %s" % resident.resident_name)
			break
	alert_label.text = "STATUS NOMINAL" if alerts.is_empty() else "  ·  ".join(alerts)
	alert_label.add_theme_color_override("font_color", Color("75d4b4") if alerts.is_empty() else Color("ef6860"))


func _refresh_checklist() -> void:
	if checklist == null:
		return
	var initial_floor_count := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
	var checks := [
		[game.selected_resident_id >= 0, "Select a resident"],
		[game.map_grid.get_floor_cells().size() >= initial_floor_count + 6, "Complete six excavations"],
		[game.get_completed_building_count(VaultBuilding.Kind.BED) >= 2, "Assemble at least two bunks"],
		[game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true) >= 1, "Add a charge node"],
		[game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY) >= 1, "Power a grow tray"],
		[game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) >= 1, "Assemble a nutrient station"],
		[game.day_cycle.completed, "Survive seven full days"],
	]
	var lines: Array[String] = ["[color=#8faeb7]STABILIZATION CHECKLIST[/color]"]
	for check in checks:
		var marker := "[color=#75d4b4][DONE][/color]" if check[0] else "[color=#efc56b][    ][/color]"
		lines.append("%s  %s" % [marker, check[1]])
	checklist.text = "\n".join(lines)


func show_briefing(visible: bool) -> void:
	if briefing_panel != null:
		briefing_panel.visible = visible


func show_outcome(won: bool, survivors: int) -> void:
	briefing_panel.visible = false
	outcome_panel.visible = true
	if won:
		outcome_title.text = "SEAL STABILIZED"
		outcome_title.add_theme_color_override("font_color", Color("75d4b4"))
		outcome_text.text = "The wing remained inhabited through seven full days. %d resident%s survived. Your local victory state has been saved." % [survivors, "" if survivors == 1 else "s"]
	else:
		outcome_title.text = "WING LOST"
		outcome_title.add_theme_color_override("font_color", Color("ef6860"))
		outcome_text.text = "No residents remain alive. Reopen the last daily checkpoint or initialize a new wing and stabilize food, rest, light, and power sooner."


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
	bar.modulate = Color("ef6860") if value < 25.0 else (Color("efc56b") if value < 50.0 else Color("75d4b4"))


func _hide_needs_and_work() -> void:
	for label: Label in need_labels.values():
		label.visible = false
	for bar: ProgressBar in need_bars.values():
		bar.visible = false
	for button: Button in work_buttons.values():
		button.visible = false


func _on_tool_pressed(tool: String) -> void:
	game.set_tool(tool)


func _on_speed_pressed(speed: int) -> void:
	game.set_speed(speed)


func _on_resident_pressed(resident_id: int) -> void:
	game.select_resident(resident_id)


func _on_work_pressed(work_type: String) -> void:
	if game.selected_resident_id >= 0:
		game.toggle_work(game.selected_resident_id, work_type)


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
