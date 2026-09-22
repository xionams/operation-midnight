extends CanvasLayer
class_name HUD

## The match interface. Built entirely in code - there is no theme art
## yet - but structured the way a real RTS HUD is, so replacing the look
## later does not mean rewriting the behaviour.
##
## Layout, landscape:
##   top       resources, power, population, low-power warning
##   left      selection panel and contextual orders
##   right     production panel, construction progress, minimap
##
## Everything the panel offers comes from BuildCatalog and the stat
## resources, so a new unit appears in the UI by existing, not by editing
## layout code here.

## Minimum comfortable touch target. The project renders at a 1280x720
## reference and stretches, so on a 1080p phone these reference pixels
## land at 1.5x - 44 here is about 4.2mm of glass, against the ~3mm the
## old 30px buttons gave. Android's guideline is 48dp; a landscape RTS
## cannot spend that everywhere without eating the battlefield, so the
## controls a player actually jabs at mid-match get it and the rest sit
## just under.
const TOUCH_MIN: float = 44.0
const MARGIN: float = 16.0
const PANEL_W: float = 268.0
const ITEM_H: float = 52.0
const GROUP_ASSIGN_HOLD: float = 0.45

@export var placer: BuildingPlacer
@export var debug_overlay: DebugOverlay
@export var construction: ConstructionQueue

var _credits_label: Label
var _power_label: Label
var _population_label: Label
var _low_power_label: Label

var _category: String = "BUILDINGS"
var _item_list: VBoxContainer
var _item_rows: Dictionary = {}

var _info_panel: RichTextLabel
var _building_actions: HBoxContainer
var _attack_move_button: Button

var _construction_panel: VBoxContainer
var _construction_label: Label
var _construction_bar: ProgressBar

var _production_label: Label
var _event_label: Label
var _event_timer: float = 0.0
var _objective_label: RichTextLabel

var _minimap: Minimap
var _group_hold_index: int = 0
var _group_hold_time: float = 0.0

var _victory_overlay: Control
var _victory_label: Label
var _report_label: RichTextLabel
var _intro_overlay: Control
var _setup_overlay: Control
var _difficulty_buttons: Dictionary = {}
var _chosen_difficulty: int = AIDirector.Difficulty.NORMAL
var _debug_panel: Label
var _ai_econ_panel: Label
var _debug_visible: bool = false

const MAPS: Array[String] = [
	"res://config/maps/ridgeline.tres",
	"res://config/maps/dry_basin.tres",
	"res://config/maps/cold_corridor.tres",
]
var _map_buttons: Dictionary = {}
var _map_blurb: Label
var _chosen_map: Resource = null

func _ready() -> void:
	layer = 10
	_build_top_bar()
	_build_production_panel()
	_build_selection_panel()
	_build_right_column()
	_build_victory_overlay()
	## A reload carrying a map choice has already been through setup.
	if GameState.skip_setup:
		GameState.skip_setup = false
		call_deferred("_begin_match")
	else:
		_build_setup_screen()
	## The intro is built when the match starts, NOT here. Built at _ready
	## it was added after the setup screen and therefore drawn on top of
	## it, while _build_setup_screen() pauses the tree - so its fade tween
	## could never advance, and the START button sat invisible underneath
	## an overlay that would never clear. The game could not be started by
	## a player on any platform. Every harness hid it by calling
	## _begin_match() directly.
	_build_debug_overlay()

	## A phone takes the game away without warning - a call, the screen
	## locking, the task switcher. Save on the way out so the match is
	## still there afterwards.
	get_tree().auto_accept_quit = false
	GameState.selection_changed.connect(_on_selection_changed)
	GameState.match_ended.connect(_on_match_ended)
	EventBus.building_captured.connect(_on_building_captured)
	EventBus.building_infiltrated.connect(_on_building_infiltrated)
	EventBus.objective_changed.connect(_on_objective_changed)
	if construction:
		construction.order_ready.connect(_on_construction_ready)

	_refresh_top()
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
		draw_rect(rect, Color(0.3, 1.0, 0.4, 0.13), true)
		draw_rect(rect, Color(0.35, 1.0, 0.45, 0.9), false, 1.5)

# ------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = MARGIN
	bar.offset_top = MARGIN * 0.5
	bar.offset_right = -MARGIN
	bar.offset_bottom = MARGIN * 0.5 + 46
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	bar.add_child(row)

	_credits_label = _label("Credits: 0", 20)
	_power_label = _label("Power: 0 / 0", 20)
	_population_label = _label("Units: 0 / 0", 20)
	_low_power_label = _label("LOW POWER", 20)
	_low_power_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	_low_power_label.visible = false
	row.add_child(_credits_label)
	row.add_child(_power_label)
	row.add_child(_population_label)
	row.add_child(_low_power_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var debug_toggle := Button.new()
	debug_toggle.text = "Debug"
	debug_toggle.custom_minimum_size = Vector2(80, TOUCH_MIN * 0.86)
	debug_toggle.pressed.connect(_toggle_debug)
	row.add_child(debug_toggle)

func _refresh_top() -> void:
	_credits_label.text = "Credits: %s" % _thousands(GameState.credits)
	_power_label.text = "Power: %d / %d" % [GameState.power_consumed, GameState.power_generated]
	var low: bool = GameState.is_low_power(true)
	_power_label.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.25) if low else Color.WHITE)
	_low_power_label.visible = low
	_population_label.text = "Units: %d / %d" % [
		TechTree.population_used(true), TechTree.population_cap(true)]

func _thousands(value: int) -> String:
	var text: String = str(value)
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

# --------------------------------------------------- production panel

func _build_production_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -(PANEL_W + MARGIN)
	panel.offset_top = -(MARGIN + Minimap.SIZE + 300)
	panel.offset_right = -MARGIN
	panel.offset_bottom = -(MARGIN + Minimap.SIZE + 10)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	column.add_child(tabs)
	for category in BuildCatalog.categories():
		var tab := Button.new()
		tab.text = category.substr(0, 4)
		tab.tooltip_text = category
		var tab_icon := Icons.for_category(category)
		if tab_icon != null:
			tab.icon = tab_icon
			tab.expand_icon = true
		tab.custom_minimum_size = Vector2(64, TOUCH_MIN * 0.86)
		tab.add_theme_font_size_override("font_size", 12)
		tab.pressed.connect(func(): _set_category(category))
		tabs.add_child(tab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(PANEL_W - 16, 236)
	column.add_child(scroll)

	_item_list = VBoxContainer.new()
	_item_list.add_theme_constant_override("separation", 3)
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_list)

	_set_category("BUILDINGS")

func _set_category(category: String) -> void:
	_category = category
	for child in _item_list.get_children():
		child.queue_free()
	_item_rows.clear()

	for stats in BuildCatalog.items(category):
		var row := Button.new()
		row.custom_minimum_size = Vector2(PANEL_W - 30, ITEM_H)
		row.add_theme_font_size_override("font_size", 13)
		row.clip_text = true
		var row_icon := Icons.for_name(stats.display_name)
		if row_icon != null:
			row.icon = row_icon
			row.expand_icon = true
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_theme_constant_override("h_separation", 8)
		row.pressed.connect(func(): _on_item_pressed(stats))
		_item_list.add_child(row)
		_item_rows[stats] = row
	_refresh_items()

## Locked items stay listed with the reason, so the tech tree teaches
## itself instead of hiding progression behind an empty panel.
func _refresh_items() -> void:
	for stats in _item_rows:
		var row: Button = _item_rows[stats]
		if not is_instance_valid(row):
			continue
		var missing: Array = TechTree.missing_prerequisites(stats, true)
		if missing.is_empty():
			row.text = "%s\n$%d   %ds" % [stats.display_name, stats.cost, int(round(stats.build_time))]
			row.disabled = GameState.credits < stats.cost
			row.modulate = Color(1, 1, 1)
		else:
			row.text = "%s\nRequires: %s" % [stats.display_name, ", ".join(missing)]
			row.disabled = true
			row.modulate = Color(0.62, 0.62, 0.68)

func _on_item_pressed(stats) -> void:
	if stats is BuildingStats:
		## Walls are cheap and placed directly; everything else is queued
		## and only placeable once its build timer completes.
		if stats.is_wall:
			placer.construction_queue = null
			placer.start_placement(stats)
			return
		if construction != null and construction.start(stats):
			_flash_event("%s under construction" % stats.display_name, Color(0.6, 0.85, 1.0))
		return

	var producer := BuildCatalog.producer_for(stats, true)
	if producer == null:
		_flash_event("Requires %s" % stats.produced_by, Color(1.0, 0.6, 0.3))
		return
	if not TechTree.has_population_for(stats, true):
		_flash_event("Unit cap reached", Color(1.0, 0.6, 0.3))
		return
	producer.produce(stats)

func _on_construction_ready(stats: BuildingStats) -> void:
	_flash_event("%s ready — place it" % stats.display_name, Color(0.4, 1.0, 0.5))
	placer.construction_queue = construction
	placer.start_placement(stats)

# ---------------------------------------------------- selection panel

func _build_selection_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = MARGIN
	panel.offset_top = -(MARGIN + 306)
	panel.offset_right = MARGIN + PANEL_W
	panel.offset_bottom = -MARGIN
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	_info_panel = RichTextLabel.new()
	_info_panel.bbcode_enabled = true
	_info_panel.fit_content = true
	_info_panel.custom_minimum_size = Vector2(PANEL_W - 24, 104)
	_info_panel.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_info_panel)

	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 3)
	column.add_child(orders)
	_attack_move_button = _order_button(orders, "Atk Move",
		func(): SelectionManager.arm_attack_move(not SelectionManager.attack_move_armed),
		"cmd_attack_move")
	_order_button(orders, "Stop", func(): SelectionManager.command_stop(), "cmd_stop")
	_order_button(orders, "Guard", func(): SelectionManager.command_guard(), "cmd_guard")

	var stance_row := HBoxContainer.new()
	stance_row.add_theme_constant_override("separation", 3)
	column.add_child(stance_row)
	_order_button(stance_row, "Patrol", func(): SelectionManager.arm_patrol(), "cmd_patrol")
	_order_button(stance_row, "Hold",
		func(): SelectionManager.set_stance(UnitBase.Stance.HOLD), "cmd_hold")
	_order_button(stance_row, "Aggro",
		func(): SelectionManager.set_stance(UnitBase.Stance.AGGRESSIVE), "cmd_aggro")

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 3)
	column.add_child(groups)
	for index in [1, 2, 3]:
		var button := Button.new()
		button.text = str(index)
		button.custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN)
		button.add_theme_font_size_override("font_size", 13)
		button.button_down.connect(func(): _begin_group_hold(index))
		button.button_up.connect(func(): _end_group_hold(index))
		groups.add_child(button)

	_building_actions = HBoxContainer.new()
	_building_actions.add_theme_constant_override("separation", 3)
	_building_actions.visible = false
	column.add_child(_building_actions)
	_order_button(_building_actions, "Sell", _on_sell_pressed, "cmd_sell")
	_order_button(_building_actions, "Repair", _on_repair_pressed, "cmd_repair")
	_order_button(_building_actions, "Rally",
		func(): SelectionManager.arm_rally_point(), "cmd_move")

func _order_button(parent: Control, text: String, handler: Callable,
		icon_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(86, TOUCH_MIN)
	button.add_theme_font_size_override("font_size", 13)
	var icon := Icons.get_icon(icon_name)
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.add_theme_constant_override("h_separation", 4)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button

func _begin_group_hold(index: int) -> void:
	_group_hold_index = index
	_group_hold_time = 0.0

## Tap recalls, press-and-hold assigns: two verbs on one button, so touch
## never needs a modifier key.
func _end_group_hold(index: int) -> void:
	if _group_hold_index != index:
		return
	if _group_hold_time >= GROUP_ASSIGN_HOLD:
		SelectionManager.assign_control_group(index)
		_flash_event("Group %d assigned (%d)" % [index, SelectionManager.control_group_size(index)], Color.GOLD)
	else:
		SelectionManager.recall_control_group(index)
	_group_hold_index = 0

func _on_sell_pressed() -> void:
	for entity in SelectionManager.selected_units.duplicate():
		if is_instance_valid(entity) and entity is BuildingBase:
			(entity as BuildingBase).sell()
	SelectionManager.clear_selection()

func _on_repair_pressed() -> void:
	for entity in SelectionManager.selected_units:
		if is_instance_valid(entity) and entity is BuildingBase:
			(entity as BuildingBase).toggle_repair()

func _on_selection_changed(selected: Array) -> void:
	var has_building: bool = false
	for entity in selected:
		if is_instance_valid(entity) and entity is BuildingBase:
			has_building = true
			break
	_building_actions.visible = has_building

	if selected.is_empty():
		_info_panel.text = "[color=#8b8f7a]Nothing selected[/color]"
		return
	if selected.size() == 1:
		_info_panel.text = _describe_one(selected[0])
		return

	var counts: Dictionary = {}
	for entity in selected:
		if not is_instance_valid(entity) or entity.stats == null:
			continue
		var display: String = entity.stats.display_name
		counts[display] = counts.get(display, 0) + 1
	var lines: Array = ["[b]SELECTED: %d[/b]\n" % selected.size()]
	for display in counts:
		lines.append("%s × %d" % [display, counts[display]])
	_info_panel.text = "\n".join(lines)

func _describe_one(entity) -> String:
	if not is_instance_valid(entity) or entity.stats == null:
		return ""
	var health: HealthComponent = entity.get_node_or_null("HealthComponent")
	var hp: String = "%d / %d" % [int(health.current_health), int(health.max_health)] if health else "-"

	if entity is BuildingBase:
		var building := entity as BuildingBase
		var power: String = "+%d" % building.stats.power_generation if building.stats.power_generation > 0 \
			else "-%d" % building.stats.power_consumption
		var extra: String = ""
		var queue = building.get("queue")
		if queue != null and queue.queue_length() > 0:
			extra = "\n\n[color=#9fd0ff]Building %s  %d%%[/color]" % [
				queue.current_stats().display_name, int(queue.progress() * 100.0)]
		if building.repairing:
			extra += "\n[color=#7fe08a]Repairing[/color]"
		return "[b]%s[/b]\n\n%s HP\nPower: %s\nVision: %dm%s" % [
			building.stats.display_name.to_upper(), hp, power,
			int(building.stats.vision_range), extra]

	var weapon: WeaponStats = entity.stats.weapon_stats
	var vet: VeterancyComponent = entity.get_node_or_null("VeterancyComponent")
	var rank: String = VeterancyComponent.rank_name(vet.rank) if vet else "—"
	var rank_colour: String = "#ffd479" if vet != null and vet.rank != VeterancyComponent.Rank.REGULAR else "#c8ccbb"
	var damage_line: String = "—"
	if weapon != null:
		damage_line = "%d %s" % [int(weapon.damage),
			DamageTypes.type_name(weapon.damage_type).to_lower().replace("_", " ")]
	return "[b]%s[/b]\n\n%s HP\nRank: [color=%s]%s[/color]\nArmor: %s\nDamage: %s\nVision: %dm\n\n[color=#9fd0ff]Order: %s   Stance: %s[/color]" % [
		entity.stats.display_name.to_upper(), hp,
		rank_colour, rank,
		Armor.type_name(entity.stats.armor_type).capitalize(),
		damage_line,
		int(entity.stats.vision_range),
		CommandTypes.type_name(entity.current_command).capitalize(),
		UnitBase.Stance.keys()[entity.stance].capitalize()]

# ------------------------------------------------------ right column

func _build_right_column() -> void:
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -(Minimap.SIZE + MARGIN)
	_minimap.offset_top = -(Minimap.SIZE + MARGIN)
	_minimap.offset_right = -MARGIN
	_minimap.offset_bottom = -MARGIN
	add_child(_minimap)

	_construction_panel = VBoxContainer.new()
	_construction_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_construction_panel.offset_left = -(PANEL_W + MARGIN)
	_construction_panel.offset_top = MARGIN + 54
	_construction_panel.offset_right = -MARGIN
	_construction_panel.offset_bottom = MARGIN + 140
	_construction_panel.visible = false
	add_child(_construction_panel)

	_construction_label = _label("", 14)
	_construction_panel.add_child(_construction_label)
	_construction_bar = ProgressBar.new()
	_construction_bar.max_value = 1.0
	_construction_bar.show_percentage = false
	_construction_bar.custom_minimum_size = Vector2(PANEL_W, 14)
	_construction_panel.add_child(_construction_bar)
	var cancel := Button.new()
	cancel.text = "Cancel (75% refund)"
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(_on_cancel_construction)
	_construction_panel.add_child(cancel)

	_objective_label = RichTextLabel.new()
	_objective_label.bbcode_enabled = true
	_objective_label.fit_content = true
	_objective_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_label.offset_left = MARGIN
	_objective_label.offset_top = MARGIN + 54
	_objective_label.offset_right = MARGIN + 300
	_objective_label.offset_bottom = MARGIN + 190
	_objective_label.add_theme_font_size_override("normal_font_size", 14)
	add_child(_objective_label)

	_production_label = _label("", 15)
	_production_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_production_label.offset_left = -200
	_production_label.offset_top = -40
	_production_label.offset_right = 200
	_production_label.offset_bottom = -14
	_production_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_production_label.visible = false
	add_child(_production_label)

	_event_label = _label("", 18)
	_event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_label.offset_left = -280
	_event_label.offset_top = 62
	_event_label.offset_right = 280
	_event_label.offset_bottom = 92
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.visible = false
	add_child(_event_label)

func _on_cancel_construction() -> void:
	if construction == null:
		return
	if placer != null and placer.is_placing():
		placer.cancel_placement()
	construction.cancel()

func _on_objective_changed(title: String, lines: PackedStringArray) -> void:
	var body: String = "[b][color=#ffd479]%s[/color][/b]\n" % title
	for line in lines:
		body += "\n• %s" % line
	_objective_label.text = body
	_flash_event(title, Color(1.0, 0.83, 0.47))

# ------------------------------------------------------------ overlays

func _build_victory_overlay() -> void:
	_victory_overlay = Control.new()
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.visible = false
	_victory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_victory_overlay)

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.72)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)

	_victory_label = _label("", 60)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_victory_label)

	## After-action report: what the match actually cost, which is what
	## makes an ending feel like a conclusion rather than a stop.
	_report_label = RichTextLabel.new()
	_report_label.bbcode_enabled = true
	_report_label.fit_content = true
	_report_label.custom_minimum_size = Vector2(420, 210)
	_report_label.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(_report_label)

	var restart := Button.new()
	restart.text = "Restart"
	restart.custom_minimum_size = Vector2(200, 60)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	column.add_child(restart)

## Difficulty is chosen before anything happens. The tree is paused
## meanwhile, so the AI does not get a free head start while the player
## reads the screen.
func _build_setup_screen() -> void:
	_setup_overlay = Control.new()
	_setup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_setup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_setup_overlay)

	var background := ColorRect.new()
	background.color = Color(0.03, 0.05, 0.04, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_setup_overlay.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_setup_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := _label("OPERATION MIDNIGHT", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := _label("Skirmish", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.74, 0.62))
	column.add_child(subtitle)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 10)
	column.add_child(map_row)
	for path in MAPS:
		var definition: Resource = load(path)
		if definition == null:
			continue
		if _chosen_map == null:
			_chosen_map = definition
		var button := Button.new()
		button.text = definition.display_name
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(164, TOUCH_MIN)
		button.button_pressed = definition == _chosen_map
		button.pressed.connect(func(): _choose_map(definition))
		map_row.add_child(button)
		_map_buttons[definition] = button

	## Describe a map by what it does to the economy, not by adjective:
	## how much ore sits at home decides whether you can turtle.
	_map_blurb = _label("", 14)
	_map_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_blurb.custom_minimum_size = Vector2(540, 56)
	_map_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_blurb.add_theme_color_override("font_color", Color(0.62, 0.66, 0.58))
	column.add_child(_map_blurb)
	_refresh_map_blurb()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for entry in [["Easy", AIDirector.Difficulty.EASY],
				  ["Normal", AIDirector.Difficulty.NORMAL],
				  ["Hard", AIDirector.Difficulty.HARD]]:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(130, 46)
		button.button_pressed = entry[1] == AIDirector.Difficulty.NORMAL
		button.pressed.connect(func(): _choose_difficulty(entry[1]))
		row.add_child(button)
		_difficulty_buttons[entry[1]] = button

	## A saved match is offered first, because someone who was
	## interrupted mid-game wants that far more than a new one.
	if SaveGame.has_save():
		var resume := Button.new()
		resume.text = "RESUME OPERATION"
		resume.custom_minimum_size = Vector2(280, 56)
		resume.add_theme_font_size_override("font_size", 20)
		resume.pressed.connect(_resume_match)
		column.add_child(resume)

	var start := Button.new()
	start.text = "START OPERATION"
	start.custom_minimum_size = Vector2(280, 56)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_begin_match)
	column.add_child(start)

	get_tree().paused = true

## Loads the saved match and rebuilds the battlefield from it.
func _resume_match() -> void:
	var data := SaveGame.load_data()
	if data.is_empty():
		## The file is gone or from an older build; fall through to a new
		## match rather than leaving a dead button on screen.
		_begin_match()
		return
	var map_path: String = String(data.get("map", ""))
	if not map_path.is_empty() and ResourceLoader.exists(map_path):
		GameState.selected_map = load(map_path)
	GameState.pending_save = data
	GameState.skip_setup = true
	get_tree().paused = false
	get_tree().reload_current_scene()

func _choose_map(definition: Resource) -> void:
	_chosen_map = definition
	for key in _map_buttons:
		_map_buttons[key].set_pressed_no_signal(key == definition)
	_refresh_map_blurb()

func _refresh_map_blurb() -> void:
	if _map_blurb == null or _chosen_map == null:
		return
	_map_blurb.text = "%s\nHome ore %s  ·  contested %s" % [
		_chosen_map.description,
		_thousands(_chosen_map.home_ore_for(_chosen_map.player_base)),
		_thousands(_chosen_map.contested_ore())]

func _choose_difficulty(value: int) -> void:
	_chosen_difficulty = value
	for key in _difficulty_buttons:
		_difficulty_buttons[key].set_pressed_no_signal(key == value)

func _begin_match() -> void:
	var director = get_tree().current_scene.get_node_or_null("AIDirector")
	if director:
		director.difficulty = _chosen_difficulty
	## Picking a different battlefield means rebuilding it, so the choice
	## is stored and the scene reloaded; the reload skips setup. Compared
	## against the map actually built, not against GameState - otherwise
	## keeping the default still triggers a pointless reload.
	var built: Resource = null
	var scene := get_tree().current_scene
	if scene != null and "map" in scene:
		built = scene.map
	if _chosen_map != null and _chosen_map != built:
		GameState.selected_map = _chosen_map
		GameState.skip_setup = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return

	MatchStats.reset()
	if _setup_overlay != null:
		_setup_overlay.visible = false
	get_tree().paused = false
	if _intro_overlay == null:
		_build_intro()

## A short opening so the match does not begin in a silent sandbox.
func _build_intro() -> void:
	_intro_overlay = Control.new()
	_intro_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intro_overlay)

	## Every node in the intro must ignore the mouse. A ColorRect defaults
	## to MOUSE_FILTER_STOP, which silently swallowed every HUD click for
	## the whole fade - the player could see the interface but not use it.
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_overlay.add_child(fade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	var title := _label("OPERATION MIDNIGHT", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := _label("Establish the forward operating base.", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.78, 0.68))
	column.add_child(subtitle)

	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(title, "modulate:a", 0.0, 0.8)
	tween.parallel().tween_property(subtitle, "modulate:a", 0.0, 0.8)
	tween.parallel().tween_property(fade, "color:a", 0.0, 1.2)
	tween.tween_callback(func(): _intro_overlay.visible = false)

func _build_debug_overlay() -> void:
	_debug_panel = Label.new()
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_panel.offset_left = MARGIN
	_debug_panel.offset_top = MARGIN + 210
	_debug_panel.offset_right = MARGIN + 280
	_debug_panel.offset_bottom = MARGIN + 430
	_debug_panel.add_theme_font_size_override("font_size", 13)
	_debug_panel.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_debug_panel.visible = false
	add_child(_debug_panel)

	## The AI's own economy, shown beside the player's debug readout. It
	## exists because the previous milestone's bottleneck was invisible
	## without it - the commander looked busy while quietly bankrupt.
	_ai_econ_panel = Label.new()
	_ai_econ_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ai_econ_panel.offset_left = MARGIN + 300
	_ai_econ_panel.offset_top = MARGIN + 60
	_ai_econ_panel.offset_right = MARGIN + 600
	_ai_econ_panel.offset_bottom = MARGIN + 320
	_ai_econ_panel.add_theme_font_size_override("font_size", 13)
	_ai_econ_panel.add_theme_color_override("font_color", Color(1.0, 0.65, 0.35))
	_ai_econ_panel.visible = false
	add_child(_ai_econ_panel)

func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug_panel.visible = _debug_visible
	_ai_econ_panel.visible = _debug_visible
	if debug_overlay:
		debug_overlay.set_enabled(_debug_visible)

func _flash_event(text: String, color: Color) -> void:
	_event_label.text = text
	_event_label.add_theme_color_override("font_color", color)
	_event_label.visible = true
	_event_timer = 3.5

func _on_building_captured(building: Node, by_player: bool) -> void:
	var display: String = building.stats.display_name if building.stats else "Structure"
	_flash_event(("Captured %s" % display) if by_player else ("Lost %s" % display),
		Color.GOLD if by_player else Color.ORANGE_RED)

func _on_building_infiltrated(building: Node, effect: String) -> void:
	var display: String = building.stats.display_name if building.stats else "Structure"
	_flash_event("Spy in %s — %s" % [display, effect], Color.GOLD)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_WM_CLOSE_REQUEST:
			_autosave()
			if what == NOTIFICATION_WM_CLOSE_REQUEST:
				get_tree().quit()

## Only mid-match state is worth keeping: saving a finished or
## unstarted match would offer the player a resume that goes nowhere.
func _autosave() -> void:
	if get_tree() == null or get_tree().paused:
		return
	if GameState.match_state != GameState.MatchState.PLAYING:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.get("map") != null:
		SaveGame.save(scene)

func _on_match_ended(victory: bool) -> void:
	## The match is over; a save of it would only mislead.
	SaveGame.delete()
	var lines: Array = []
	for entry in MatchStats.summary_lines():
		lines.append("[color=#9aa48a]%-24s[/color]%s" % [entry[0], entry[1]])
	_report_label.text = "\n".join(lines)
	_victory_label.text = "VICTORY" if victory else "DEFEAT"
	_victory_label.add_theme_color_override("font_color", Color.GOLD if victory else Color.CRIMSON)
	_victory_overlay.visible = true

# --------------------------------------------------------------- tick

func _process(delta: float) -> void:
	_refresh_top()
	_refresh_items()
	_refresh_construction()
	_refresh_production()

	if _group_hold_index != 0:
		_group_hold_time += delta
	if _attack_move_button.button_pressed != SelectionManager.attack_move_armed:
		_attack_move_button.set_pressed_no_signal(SelectionManager.attack_move_armed)
	if _event_timer > 0.0:
		_event_timer -= delta
		if _event_timer <= 0.0:
			_event_label.visible = false

	if not _debug_visible:
		return
	var lead: String = ""
	if not SelectionManager.selected_units.is_empty():
		var unit = SelectionManager.selected_units[0]
		if is_instance_valid(unit) and unit.stats != null and unit.has_method("issue_command"):
			lead = "\n\n%s\n  cmd %s" % [unit.stats.display_name,
				CommandTypes.type_name(unit.current_command)]
	_refresh_ai_economy_panel()
	_debug_panel.text = "FPS: %d\nUnits: %d\nCredits: %d\nPower: %d / %d\nExplored: %.1f%%%s" % [
		Engine.get_frames_per_second(),
		get_tree().get_nodes_in_group("units").size(),
		GameState.credits, GameState.power_generated, GameState.power_consumed,
		FogOfWar.explored_fraction() * 100.0, lead]

## Debug-only AI economy readout. Disabled with the rest of the debug
## overlay, and reads the same AIEconomy the commander decides from.
func _refresh_ai_economy_panel() -> void:
	var director = get_tree().current_scene.get_node_or_null("AIDirector")
	if director == null or director.economy == null:
		_ai_econ_panel.text = ""
		return
	var s: Dictionary = director.economy.snapshot()
	_ai_econ_panel.text = ("AI ECONOMY (%s)\n\nCredits:   %d\nIncome:    %d/min\nSpend:     %d/min\n"
		+ "Harvesters: %d / %d active (want %d)\nRefineries: %d\nRound trip: %.0fs\n"
		+ "Reserve:   %d\nArmy value: %d\nSiege share: %.0f%%\nStrategy:  %s") % [
		AIDirector.Difficulty.keys()[director.difficulty],
		s["credits"], s["income_per_min"], s["spend_per_min"],
		s["active_harvesters"], s["harvesters"], s["target_harvesters"],
		s["refineries"], s["round_trip"], s["reserve"],
		s["army_value"], s["siege_share"] * 100.0,
		director.strategy_name()]

func _refresh_construction() -> void:
	if construction == null or not construction.is_busy():
		_construction_panel.visible = false
		return
	_construction_panel.visible = true
	var stats := construction.current()
	if construction.is_ready():
		_construction_label.text = "%s — READY TO PLACE" % stats.display_name
		_construction_bar.value = 1.0
		return
	_construction_label.text = "%s   %ds" % [stats.display_name, int(ceil(construction.remaining_seconds()))]
	_construction_bar.value = construction.progress()

## Whichever producer is furthest along, so the readout means something
## when several buildings are working at once.
func _refresh_production() -> void:
	var best: ProductionQueue = null
	for building in get_tree().get_nodes_in_group("player_buildings"):
		if not is_instance_valid(building):
			continue
		var queue = building.get("queue")
		if queue == null or queue.queue_length() == 0:
			continue
		if best == null or queue.progress() > best.progress():
			best = queue
	if best == null:
		_production_label.visible = false
		return
	var extra: int = best.queue_length() - 1
	var bars: int = int(best.progress() * 10.0)
	_production_label.text = "%s  %s %d%%%s" % [
		best.current_stats().display_name,
		"█".repeat(bars) + "░".repeat(10 - bars),
		int(best.progress() * 100.0),
		"  (+%d)" % extra if extra > 0 else ""]
	_production_label.visible = true

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
