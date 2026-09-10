extends CanvasLayer
class_name HUD

## Minimal Android-friendly HUD, built entirely in code (no theme
## assets to keep track of yet). Shows credits/power/selection and
## exposes the three build actions. Talks to the rest of the game only
## through GameState signals and the BuildingPlacer reference — it
## never reaches into unit/building internals directly.

@export var power_plant_stats: BuildingStats
@export var refinery_stats: BuildingStats
@export var war_factory_stats: BuildingStats
@export var barracks_stats: BuildingStats
@export var harvester_stats: UnitStats
@export var assault_stats: UnitStats
@export var scout_stats: UnitStats
@export var soldier_stats: UnitStats
@export var engineer_stats: UnitStats
@export var spy_stats: UnitStats
@export var dog_stats: UnitStats
@export var placer: BuildingPlacer

const MARGIN: float = 28.0
const BUTTON_SIZE: Vector2 = Vector2(118, 56)
const BAR_HEIGHT: float = BUTTON_SIZE.y * 2.0 + 8.0
const GROUP_ASSIGN_HOLD: float = 0.45

var _credits_label: Label
var _power_label: Label
var _selection_label: Label
var _cancel_button: Button
var _build_power_button: Button
var _build_refinery_button: Button
var _build_factory_button: Button
var _build_barracks_button: Button
var _build_harvester_button: Button
var _build_assault_button: Button
var _build_scout_button: Button
var _build_soldier_button: Button
var _build_engineer_button: Button
var _build_spy_button: Button
var _build_dog_button: Button
var _production_label: Label
var _event_label: Label
var _event_timer: float = 0.0
var _minimap: Minimap
var _info_panel: Label
var _attack_move_button: Button
var _group_buttons: Dictionary = {}
var _group_hold_index: int = 0
var _group_hold_time: float = 0.0
var _victory_overlay: Control
var _victory_label: Label
var _debug_panel: Label
var _debug_visible: bool = false

func _ready() -> void:
	layer = 10
	_build_top_bar()
	_build_bottom_bar()
	_build_production_label()
	_build_minimap()
	_build_command_bar()
	_build_info_panel()
	_build_victory_overlay()
	_build_debug_overlay()

	GameState.credits_changed.connect(_on_credits_changed)
	GameState.power_changed.connect(_on_power_changed)
	GameState.selection_changed.connect(_on_selection_changed)
	GameState.match_ended.connect(_on_match_ended)
	if placer:
		placer.placement_started.connect(_on_placement_started)
		placer.placement_ended.connect(_on_placement_ended)

	_on_credits_changed(GameState.credits)
	_on_power_changed(GameState.power_generated, GameState.power_consumed)
	_on_selection_changed([])

	add_child(SelectionBoxOverlay.new())

class SelectionBoxOverlay extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not SelectionManager.is_boxing():
			return
		var rect: Rect2 = SelectionManager.get_drag_rect()
		draw_rect(rect, Color(0.3, 1.0, 0.4, 0.15), true)
		draw_rect(rect, Color(0.3, 1.0, 0.4, 0.9), false, 2.0)

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = MARGIN
	bar.offset_top = MARGIN * 0.5
	bar.offset_right = -MARGIN
	bar.offset_bottom = MARGIN * 0.5 + 56
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	bar.add_child(row)

	_credits_label = _make_label("Credits: 0", 24)
	_power_label = _make_label("Power: 0 / 0", 24)
	_selection_label = _make_label("Selected: 0", 24)
	row.add_child(_credits_label)
	row.add_child(_power_label)
	row.add_child(_selection_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var debug_toggle := Button.new()
	debug_toggle.text = "Debug"
	debug_toggle.custom_minimum_size = Vector2(90, 48)
	debug_toggle.pressed.connect(_toggle_debug)
	row.add_child(debug_toggle)

## Two rows: structures on top, units below. One row cannot hold twelve
## actions at phone width, and splitting them by "what you place" versus
## "what you train" matches how the player thinks about them.
func _build_bottom_bar() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	column.offset_left = MARGIN
	column.offset_top = -(MARGIN + BAR_HEIGHT)
	## Stop short of the minimap column on the right, or the last build
	## button ends up underneath it.
	column.offset_right = -(Minimap.SIZE + MARGIN * 2.0)
	column.offset_bottom = -MARGIN
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var structures := _make_row()
	column.add_child(structures)
	var units := _make_row()
	column.add_child(units)

	_build_power_button = _add_build_button(structures, "Power Plant", power_plant_stats)
	_build_refinery_button = _add_build_button(structures, "Refinery", refinery_stats)
	_build_factory_button = _add_build_button(structures, "War Factory", war_factory_stats)
	_build_barracks_button = _add_build_button(structures, "Barracks", barracks_stats)

	_cancel_button = _make_build_button("Cancel")
	_cancel_button.visible = false
	_cancel_button.pressed.connect(_on_cancel_pressed)
	structures.add_child(_cancel_button)

	_build_harvester_button = _add_unit_button(units, "Harvester", harvester_stats, _on_build_harvester_pressed)
	_build_assault_button = _add_unit_button(units, "Assault", assault_stats,
		func(): _produce_from("war_factories", "produce_assault"))
	_build_scout_button = _add_unit_button(units, "Scout", scout_stats,
		func(): _produce_from("war_factories", "produce_scout"))
	_build_soldier_button = _add_unit_button(units, "Soldier", soldier_stats,
		func(): _produce_from("barracks", "produce_soldier"))
	_build_engineer_button = _add_unit_button(units, "Engineer", engineer_stats,
		func(): _produce_from("barracks", "produce_engineer"))
	_build_spy_button = _add_unit_button(units, "Spy", spy_stats,
		func(): _produce_from("barracks", "produce_spy"))
	_build_dog_button = _add_unit_button(units, "Dog", dog_stats,
		func(): _produce_from("barracks", "produce_dog"))

func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	return row

func _add_build_button(row: HBoxContainer, label: String, stats: BuildingStats) -> Button:
	var button := _make_build_button("%s\n%d cr" % [label, stats.cost if stats else 0])
	button.pressed.connect(func(): _start_building_placement(stats))
	row.add_child(button)
	return button

func _add_unit_button(row: HBoxContainer, label: String, stats: UnitStats, handler: Callable) -> Button:
	var button := _make_build_button(_unit_label(label, stats))
	button.pressed.connect(handler)
	row.add_child(button)
	return button

func _make_build_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 20)
	return button

func _unit_label(name: String, stats: UnitStats) -> String:
	return "%s\n%d cr" % [name, stats.cost if stats else 0]

## Minimap sits bottom-right, clear of the build rows on the left.
func _build_minimap() -> void:
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -(Minimap.SIZE + MARGIN)
	_minimap.offset_top = -(Minimap.SIZE + MARGIN)
	_minimap.offset_right = -MARGIN
	_minimap.offset_bottom = -MARGIN
	add_child(_minimap)

## Order buttons and control groups, stacked above the minimap on the
## right so command actions are never mixed in with production actions.
func _build_command_bar() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	column.offset_left = -(Minimap.SIZE + MARGIN)
	column.offset_top = -(Minimap.SIZE + MARGIN + 104)
	column.offset_right = -MARGIN
	column.offset_bottom = -(Minimap.SIZE + MARGIN + 4)
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 6)
	column.add_child(orders)

	_attack_move_button = _make_command_button("Attack Move")
	_attack_move_button.toggle_mode = true
	_attack_move_button.toggled.connect(func(on): SelectionManager.arm_attack_move(on))
	orders.add_child(_attack_move_button)

	var stop_button := _make_command_button("Stop")
	stop_button.pressed.connect(func(): SelectionManager.command_stop())
	orders.add_child(stop_button)

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 6)
	column.add_child(groups)
	for index in [1, 2, 3]:
		var button := _make_command_button(str(index))
		button.custom_minimum_size = Vector2(58, 42)
		## Tap recalls, press-and-hold assigns - the same two-verbs-on-one-
		## button pattern the marquee uses, so touch never needs a modifier.
		button.button_down.connect(func(): _begin_group_hold(index))
		button.button_up.connect(func(): _end_group_hold(index))
		groups.add_child(button)
		_group_buttons[index] = button

func _make_command_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(96, 42)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _begin_group_hold(index: int) -> void:
	_group_hold_index = index
	_group_hold_time = 0.0

func _end_group_hold(index: int) -> void:
	if _group_hold_index != index:
		return
	if _group_hold_time >= GROUP_ASSIGN_HOLD:
		SelectionManager.assign_control_group(index)
		_flash_event("Group %d assigned (%d units)" % [index, SelectionManager.control_group_size(index)], Color.GOLD)
	else:
		SelectionManager.recall_control_group(index)
	_group_hold_index = 0

## Left edge, above the build rows: what is selected and what it can do.
func _build_info_panel() -> void:
	_info_panel = Label.new()
	_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_panel.offset_left = MARGIN
	_info_panel.offset_top = -(MARGIN + BAR_HEIGHT + 190)
	_info_panel.offset_right = MARGIN + 260
	_info_panel.offset_bottom = -(MARGIN + BAR_HEIGHT + 46)
	_info_panel.add_theme_font_size_override("font_size", 17)
	_info_panel.visible = false
	add_child(_info_panel)
	GameState.selection_changed.connect(_on_selection_panel_update)

## One unit gets its stat block; a group gets a tally by type, which is
## what the player actually needs when 20 things are selected.
func _on_selection_panel_update(selected: Array) -> void:
	if selected.is_empty():
		_info_panel.visible = false
		return
	_info_panel.visible = true

	if selected.size() == 1:
		var unit = selected[0]
		if not is_instance_valid(unit) or unit.stats == null:
			return
		var hp: HealthComponent = unit.get_node_or_null("HealthComponent")
		var weapon: WeaponStats = unit.stats.weapon_stats
		_info_panel.text = "%s\n\nHealth  %d / %d\nArmor   %s\nDamage  %s\nVision  %dm\nOrder   %s" % [
			unit.stats.display_name.to_upper(),
			int(hp.current_health) if hp else 0,
			int(hp.max_health) if hp else 0,
			Armor.type_name(unit.stats.armor_type).capitalize(),
			str(int(weapon.damage)) if weapon else "-",
			int(unit.stats.vision_range),
			CommandTypes.type_name(unit.current_command).capitalize(),
		]
		return

	var counts: Dictionary = {}
	for unit in selected:
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		var name: String = unit.stats.display_name
		counts[name] = counts.get(name, 0) + 1
	var lines: Array = ["SELECTED: %d\n" % selected.size()]
	for name in counts:
		lines.append("%s x %d" % [name, counts[name]])
	_info_panel.text = "\n".join(lines)

func _build_production_label() -> void:
	_production_label = Label.new()
	_production_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_production_label.offset_right = -(Minimap.SIZE + MARGIN * 2.0)
	_production_label.offset_top = -(MARGIN + BAR_HEIGHT + 36)
	_production_label.offset_bottom = -(MARGIN + BAR_HEIGHT + 6)
	_production_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_production_label.add_theme_font_size_override("font_size", 20)
	_production_label.visible = false
	add_child(_production_label)

	## Captures and infiltrations are easy to miss on a busy screen, and
	## both can decide a match, so they get an explicit callout.
	_event_label = Label.new()
	_event_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_event_label.offset_right = -(Minimap.SIZE + MARGIN * 2.0)
	_event_label.offset_top = -(MARGIN + BAR_HEIGHT + 70)
	_event_label.offset_bottom = -(MARGIN + BAR_HEIGHT + 40)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 22)
	_event_label.add_theme_color_override("font_color", Color.GOLD)
	_event_label.visible = false
	add_child(_event_label)

	EventBus.building_captured.connect(_on_building_captured)
	EventBus.building_infiltrated.connect(_on_building_infiltrated)

func _on_building_captured(building: Node, by_player: bool) -> void:
	var name: String = building.stats.display_name if building.stats else "Structure"
	_flash_event(("Captured %s" % name) if by_player else ("Lost %s to capture" % name),
		Color.GOLD if by_player else Color.ORANGE_RED)

func _on_building_infiltrated(building: Node, effect: String) -> void:
	var name: String = building.stats.display_name if building.stats else "Structure"
	_flash_event("Spy in %s — %s" % [name, effect], Color.GOLD)

func _flash_event(text: String, color: Color) -> void:
	_event_label.text = text
	_event_label.add_theme_color_override("font_color", color)
	_event_label.visible = true
	_event_timer = 4.0

func _produce_from(group: String, method: String) -> void:
	var producer := get_tree().get_first_node_in_group(group)
	if producer != null:
		producer.call(method)

## Two producers can be building at once (refinery and factory), so the
## readout shows whichever is furthest along rather than inventing a
## combined progress number that matches neither.
func _active_queue() -> ProductionQueue:
	var best: ProductionQueue = null
	var producers: Array = get_tree().get_nodes_in_group(WarFactory.GROUP)
	producers.append_array(get_tree().get_nodes_in_group(Barracks.GROUP))
	var refinery := GameState.get_first_refinery()
	if refinery != null:
		producers.append(refinery)
	for p in producers:
		if not is_instance_valid(p):
			continue
		var q: ProductionQueue = p.get("queue")
		if q == null or q.queue_length() == 0:
			continue
		if best == null or q.progress() > best.progress():
			best = q
	return best

func _refresh_production_ui() -> void:
	var has_factory: bool = get_tree().get_first_node_in_group(WarFactory.GROUP) != null
	var has_barracks: bool = get_tree().get_first_node_in_group(Barracks.GROUP) != null
	_build_harvester_button.disabled = not GameState.has_refinery()
	_build_assault_button.disabled = not has_factory
	_build_scout_button.disabled = not has_factory
	_build_soldier_button.disabled = not has_barracks
	_build_engineer_button.disabled = not has_barracks
	_build_spy_button.disabled = not has_barracks
	_build_dog_button.disabled = not has_barracks

	var queue := _active_queue()
	if queue == null:
		_production_label.visible = false
		return
	var stats := queue.current_stats()
	var extra: int = queue.queue_length() - 1
	var suffix: String = "  (+%d queued)" % extra if extra > 0 else ""
	_production_label.text = "Building %s  %d%%%s" % [stats.display_name, int(queue.progress() * 100.0), suffix]
	_production_label.visible = true

func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _build_victory_overlay() -> void:
	_victory_overlay = Control.new()
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.visible = false
	_victory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_victory_overlay)

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	_victory_label = Label.new()
	_victory_label.add_theme_font_size_override("font_size", 64)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_victory_label)

	var restart_button := Button.new()
	restart_button.text = "Restart"
	restart_button.custom_minimum_size = Vector2(220, 80)
	restart_button.add_theme_font_size_override("font_size", 26)
	restart_button.pressed.connect(func(): get_tree().reload_current_scene())
	column.add_child(restart_button)

func _build_debug_overlay() -> void:
	_debug_panel = Label.new()
	_debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_panel.offset_left = MARGIN
	_debug_panel.offset_top = -220
	_debug_panel.offset_right = MARGIN + 260
	_debug_panel.offset_bottom = -(MARGIN + BUTTON_SIZE.y + 12)
	_debug_panel.add_theme_font_size_override("font_size", 16)
	_debug_panel.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_debug_panel.visible = false
	add_child(_debug_panel)

func _process(_delta: float) -> void:
	_refresh_production_ui()
	if _group_hold_index != 0:
		_group_hold_time += _delta
	## The button reflects the real armed state, which clears itself once
	## the order is placed.
	if _attack_move_button.button_pressed != SelectionManager.attack_move_armed:
		_attack_move_button.set_pressed_no_signal(SelectionManager.attack_move_armed)
	if _event_timer > 0.0:
		_event_timer -= _delta
		if _event_timer <= 0.0:
			_event_label.visible = false
	if not _debug_visible:
		return
	var units := get_tree().get_nodes_in_group("units").size()
	_debug_panel.text = "FPS: %d\nUnits: %d\nCredits: %d\nPower: %d / %d\nMatch: %s" % [
		Engine.get_frames_per_second(),
		units,
		GameState.credits,
		GameState.power_generated,
		GameState.power_consumed,
		GameState.MatchState.keys()[GameState.match_state],
	]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F3:
		_toggle_debug()

func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug_panel.visible = _debug_visible

func _start_building_placement(stats: BuildingStats) -> void:
	if stats == null or placer == null:
		return
	placer.start_placement(stats)

func _on_cancel_pressed() -> void:
	if placer:
		placer.cancel_placement()

func _on_build_harvester_pressed() -> void:
	var refinery := GameState.get_first_refinery()
	if refinery == null:
		return
	refinery.call("produce_harvester")

func _on_placement_started(_stats: BuildingStats) -> void:
	_cancel_button.visible = true

func _on_placement_ended() -> void:
	_cancel_button.visible = false

func _on_credits_changed(new_amount: int) -> void:
	_credits_label.text = "Credits: %d" % new_amount

func _on_power_changed(generated: int, consumed: int) -> void:
	_power_label.text = "Power: %d / %d" % [consumed, generated]
	_power_label.add_theme_color_override("font_color", Color.ORANGE_RED if consumed > generated else Color.WHITE)

func _on_selection_changed(selected: Array) -> void:
	_selection_label.text = "Selected: %d" % selected.size()

func _on_match_ended(victory: bool) -> void:
	_victory_label.text = "VICTORY" if victory else "DEFEAT"
	_victory_label.add_theme_color_override("font_color", Color.GOLD if victory else Color.CRIMSON)
	_victory_overlay.visible = true
