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
@export var harvester_stats: UnitStats
@export var assault_stats: UnitStats
@export var scout_stats: UnitStats
@export var placer: BuildingPlacer

const MARGIN: float = 28.0
const BUTTON_SIZE: Vector2 = Vector2(150, 70)

var _credits_label: Label
var _power_label: Label
var _selection_label: Label
var _cancel_button: Button
var _build_power_button: Button
var _build_refinery_button: Button
var _build_factory_button: Button
var _build_harvester_button: Button
var _build_assault_button: Button
var _build_scout_button: Button
var _production_label: Label
var _victory_overlay: Control
var _victory_label: Label
var _debug_panel: Label
var _debug_visible: bool = false

func _ready() -> void:
	layer = 10
	_build_top_bar()
	_build_bottom_bar()
	_build_production_label()
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

func _build_bottom_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = MARGIN
	row.offset_top = -(MARGIN + BUTTON_SIZE.y)
	row.offset_right = -MARGIN
	row.offset_bottom = -MARGIN
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	_build_power_button = _make_build_button("Power Plant\n%d cr" % (power_plant_stats.cost if power_plant_stats else 800))
	_build_power_button.pressed.connect(func(): _start_building_placement(power_plant_stats))
	row.add_child(_build_power_button)

	_build_refinery_button = _make_build_button("Refinery\n%d cr" % (refinery_stats.cost if refinery_stats else 2000))
	_build_refinery_button.pressed.connect(func(): _start_building_placement(refinery_stats))
	row.add_child(_build_refinery_button)

	_build_factory_button = _make_build_button("War Factory\n%d cr" % (war_factory_stats.cost if war_factory_stats else 2500))
	_build_factory_button.pressed.connect(func(): _start_building_placement(war_factory_stats))
	row.add_child(_build_factory_button)

	_build_harvester_button = _make_build_button(_unit_label("Harvester", harvester_stats))
	_build_harvester_button.pressed.connect(_on_build_harvester_pressed)
	row.add_child(_build_harvester_button)

	_build_assault_button = _make_build_button(_unit_label("Assault", assault_stats))
	_build_assault_button.pressed.connect(func(): _produce_from_factory("produce_assault"))
	row.add_child(_build_assault_button)

	_build_scout_button = _make_build_button(_unit_label("Scout", scout_stats))
	_build_scout_button.pressed.connect(func(): _produce_from_factory("produce_scout"))
	row.add_child(_build_scout_button)

	_cancel_button = _make_build_button("Cancel")
	_cancel_button.visible = false
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)

func _make_build_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 20)
	return button

func _unit_label(name: String, stats: UnitStats) -> String:
	return "%s\n%d cr" % [name, stats.cost if stats else 0]

func _build_production_label() -> void:
	_production_label = Label.new()
	_production_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_production_label.offset_top = -(MARGIN + BUTTON_SIZE.y + 40)
	_production_label.offset_bottom = -(MARGIN + BUTTON_SIZE.y + 8)
	_production_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_production_label.add_theme_font_size_override("font_size", 20)
	_production_label.visible = false
	add_child(_production_label)

func _first_factory() -> Node:
	return get_tree().get_first_node_in_group(WarFactory.GROUP)

func _produce_from_factory(method: String) -> void:
	var factory := _first_factory()
	if factory != null:
		factory.call(method)

## Two producers can be building at once (refinery and factory), so the
## readout shows whichever is furthest along rather than inventing a
## combined progress number that matches neither.
func _active_queue() -> ProductionQueue:
	var best: ProductionQueue = null
	var producers: Array = get_tree().get_nodes_in_group(WarFactory.GROUP)
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
	var has_refinery: bool = GameState.has_refinery()
	var has_factory: bool = _first_factory() != null
	_build_harvester_button.disabled = not has_refinery
	_build_assault_button.disabled = not has_factory
	_build_scout_button.disabled = not has_factory

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
