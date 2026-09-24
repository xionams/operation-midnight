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
var _item_list: GridContainer
var _item_rows: Dictionary = {}
var _item_bars: Dictionary = {}
var _item_captions: Dictionary = {}
var _cameo_cache: Dictionary = {}
var _category_tabs: Dictionary = {}

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
var _subtitle_label: Label
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
	_build_sidebar()
	_build_overlays()
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

## An icon beside its number. Falls back to the label alone if the icon
## is missing, so the bar is never blank.
func _readout(icon_name: String, label: Label, tooltip: String) -> Control:
	var icon := Icons.get_icon(icon_name)
	if icon == null:
		return label
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 7)
	group.tooltip_text = tooltip
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(26, 26)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group.add_child(picture)
	group.add_child(label)
	return group

## The sidebar, in the shape every commander of this kind of game
## already knows: radar at the top, money under it, the build catalogue
## in the middle, orders at the bottom, and the battlefield filling
## everything to the left of it.
##
## The previous layout scattered those four things into four corners -
## money along the top, catalogue on the right, orders bottom left, radar
## bottom right - so reading the game meant sweeping the whole screen.
## Collecting them into one column is most of what makes this readable.
const SIDEBAR_W: float = 302.0
const CARD_H: float = 64.0
## Cameo tile height only. The WIDTH is left to the grid to divide, which
## is the whole point: a fixed 140 forced the two columns wider than the
## 302px sidebar and pushed the credits readout and the right-hand column
## off the panel. Two expanding columns fit whatever the sidebar is.
const TILE_H: float = 104.0

## Panel chrome. Flat fills with a light top edge and a dark bottom edge
## read as bevelled metal without a single texture.
func _plate(fill: Color, light: Color, dark: Color, border: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_width_top = border
	box.border_width_left = border
	box.border_width_right = border
	box.border_width_bottom = border
	## A light top/left edge and a dark bottom/right edge is what makes a
	## flat fill read as a raised plate.
	box.border_color = dark
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _build_top_bar() -> void:
	## The old top bar is gone; its readouts live in the sidebar now.
	## Kept as a hook so the build order in _ready reads unchanged.
	pass

## Every button in the sidebar wears the same plate, so the panel reads
## as one machine rather than as a stack of default widgets.
func _style_button(button: Button) -> void:
	var normal := _plate(Color(0.145, 0.160, 0.178), Color(0.30, 0.33, 0.36),
		Color(0.05, 0.06, 0.07), 2)
	var hover := _plate(Color(0.200, 0.220, 0.240), Color(0.42, 0.45, 0.48),
		Color(0.06, 0.07, 0.08), 2)
	var pressed := _plate(Color(0.235, 0.190, 0.090), Color(0.55, 0.45, 0.20),
		Color(0.08, 0.06, 0.03), 2)
	var disabled := _plate(Color(0.098, 0.106, 0.118), Color(0.18, 0.19, 0.21),
		Color(0.05, 0.05, 0.06), 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.86, 0.88, 0.86))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.46, 0.48))

func _build_sidebar() -> void:
	var frame := PanelContainer.new()
	frame.name = "Sidebar"
	frame.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	frame.offset_left = -SIDEBAR_W
	frame.offset_top = 0
	frame.offset_right = 0
	frame.offset_bottom = 0
	frame.add_theme_stylebox_override("panel",
		_plate(Color(0.086, 0.098, 0.110), Color(0.25, 0.27, 0.30),
			Color(0.04, 0.05, 0.06), 2))
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)

	# --- radar ---
	var radar_frame := PanelContainer.new()
	radar_frame.add_theme_stylebox_override("panel",
		_plate(Color(0.05, 0.06, 0.07), Color(0.2, 0.22, 0.25),
			Color(0.03, 0.03, 0.04), 2))
	column.add_child(radar_frame)
	var radar_centre := CenterContainer.new()
	radar_frame.add_child(radar_centre)
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	radar_centre.add_child(_minimap)

	# --- money, power, population ---
	var readouts := VBoxContainer.new()
	readouts.add_theme_constant_override("separation", 2)
	column.add_child(readouts)

	_credits_label = _label("0", 26)
	_credits_label.add_theme_color_override("font_color", Color(0.88, 0.72, 0.30))
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var money := PanelContainer.new()
	money.add_theme_stylebox_override("panel",
		_plate(Color(0.04, 0.05, 0.05), Color(0.2, 0.22, 0.25),
			Color(0.02, 0.03, 0.03), 2))
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 8)
	var coin := TextureRect.new()
	coin.texture = Icons.get_icon("ui_credits")
	coin.custom_minimum_size = Vector2(24, 24)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_row.add_child(coin)
	_credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_row.add_child(_credits_label)
	money.add_child(money_row)
	readouts.add_child(money)

	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 6)
	readouts.add_child(meters)
	_power_label = _label("0 / 0", 15)
	_population_label = _label("0 / 0", 15)
	meters.add_child(_readout("ui_power", _power_label, "Power"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(gap)
	meters.add_child(_readout("ui_unit_cap", _population_label, "Units"))

	_low_power_label = _label("LOW POWER", 15)
	_low_power_label.add_theme_color_override("font_color", Color(0.85, 0.24, 0.20))
	_low_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_low_power_label.visible = false
	readouts.add_child(_low_power_label)

	# --- category tabs ---
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(tabs)
	for category in BuildCatalog.categories():
		var tab := Button.new()
		tab.tooltip_text = category
		tab.toggle_mode = true
		tab.button_pressed = category == _category
		tab.custom_minimum_size = Vector2(68, TOUCH_MIN * 0.82)
		var tab_icon := Icons.for_category(category)
		if tab_icon != null:
			tab.icon = tab_icon
			tab.expand_icon = true
		else:
			tab.text = category.substr(0, 4)
		_style_button(tab)
		tab.pressed.connect(func(): _set_category(category))
		tabs.add_child(tab)
		_category_tabs[category] = tab

	# --- the catalogue, as cards ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	## The catalogue takes whatever is left after the controls below it,
	## with a floor of two rows of cameos. A floor of four looked better on
	## a desktop window and pushed the order buttons off the bottom of a
	## 720p phone screen, which is the size that actually matters.
	scroll.custom_minimum_size = Vector2(0, TILE_H * 2 + 6)
	scroll.add_theme_stylebox_override("panel",
		_plate(Color(0.06, 0.07, 0.08), Color(0.2, 0.22, 0.25),
			Color(0.03, 0.04, 0.04), 1))
	column.add_child(scroll)
	## Two columns of cameos rather than a list of rows. The cameo is the
	## thing a player learns to hit, so it should be the biggest element on
	## the card; in a full-width row it was a thumbnail beside the text.
	_item_list = GridContainer.new()
	_item_list.columns = 2
	_item_list.add_theme_constant_override("h_separation", 3)
	_item_list.add_theme_constant_override("v_separation", 3)
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_list)

	# --- what is being built right now ---
	_construction_panel = VBoxContainer.new()
	_construction_panel.add_theme_constant_override("separation", 2)
	_construction_panel.visible = false
	column.add_child(_construction_panel)
	_construction_label = _label("", 13)
	_construction_panel.add_child(_construction_label)
	_construction_bar = ProgressBar.new()
	_construction_bar.max_value = 1.0
	_construction_bar.show_percentage = false
	_construction_bar.custom_minimum_size = Vector2(0, 12)
	_construction_panel.add_child(_construction_bar)
	var cancel := Button.new()
	cancel.text = "Cancel (75% refund)"
	cancel.add_theme_font_size_override("font_size", 12)
	_style_button(cancel)
	cancel.pressed.connect(_on_cancel_construction)
	_construction_panel.add_child(cancel)

	# --- selection, then orders ---
	_info_panel = RichTextLabel.new()
	_info_panel.bbcode_enabled = true
	_info_panel.fit_content = true
	_info_panel.custom_minimum_size = Vector2(0, 50)
	_info_panel.add_theme_font_size_override("normal_font_size", 13)
	var info_frame := PanelContainer.new()
	info_frame.add_theme_stylebox_override("panel",
		_plate(Color(0.06, 0.07, 0.08), Color(0.2, 0.22, 0.25),
			Color(0.03, 0.04, 0.04), 1))
	info_frame.add_child(_info_panel)
	column.add_child(info_frame)

	_build_order_controls(column)
	## Nothing populated the catalogue after the old production panel was
	## replaced, so the sidebar came up with an empty middle.
	_set_category(_category)

func _build_order_controls(column: VBoxContainer) -> void:
	var orders := GridContainer.new()
	orders.columns = 3
	orders.add_theme_constant_override("h_separation", 3)
	orders.add_theme_constant_override("v_separation", 3)
	column.add_child(orders)
	_attack_move_button = _order_button(orders, "Atk Move",
		func(): SelectionManager.arm_attack_move(not SelectionManager.attack_move_armed),
		"cmd_attack_move")
	_order_button(orders, "Stop", func(): SelectionManager.command_stop(), "cmd_stop")
	_order_button(orders, "Guard", func(): SelectionManager.command_guard(), "cmd_guard")
	_order_button(orders, "Patrol", func(): SelectionManager.arm_patrol(), "cmd_patrol")
	_order_button(orders, "Hold",
		func(): SelectionManager.set_stance(UnitBase.Stance.HOLD), "cmd_hold")
	_order_button(orders, "Aggro",
		func(): SelectionManager.set_stance(UnitBase.Stance.AGGRESSIVE), "cmd_aggro")

	_building_actions = HBoxContainer.new()
	_building_actions.add_theme_constant_override("separation", 3)
	_building_actions.visible = false
	column.add_child(_building_actions)
	_order_button(_building_actions, "Sell", _on_sell_pressed, "cmd_sell")
	_order_button(_building_actions, "Repair", _on_repair_pressed, "cmd_repair")
	_order_button(_building_actions, "Rally",
		func(): SelectionManager.arm_rally_point(), "cmd_move")

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 3)
	column.add_child(groups)
	for index in [1, 2, 3]:
		var button := Button.new()
		button.text = str(index)
		button.custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN * 0.8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		_style_button(button)
		button.button_down.connect(func(): _begin_group_hold(index))
		button.button_up.connect(func(): _end_group_hold(index))
		groups.add_child(button)

	var debug_toggle := Button.new()
	debug_toggle.text = "Debug"
	debug_toggle.custom_minimum_size = Vector2(0, TOUCH_MIN * 0.72)
	debug_toggle.add_theme_font_size_override("font_size", 12)
	_style_button(debug_toggle)
	debug_toggle.pressed.connect(func():
		_debug_visible = not _debug_visible
		_debug_panel.visible = _debug_visible
		_ai_econ_panel.visible = _debug_visible
		if debug_overlay != null:
			debug_overlay.enabled = _debug_visible)
	column.add_child(debug_toggle)

func _refresh_top() -> void:
	_credits_label.text = "%s" % _thousands(GameState.credits)
	_power_label.text = "%d / %d" % [GameState.power_consumed, GameState.power_generated]
	var low: bool = GameState.is_low_power(true)
	_power_label.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.25) if low else Color.WHITE)
	_low_power_label.visible = low
	_population_label.text = "%d / %d" % [
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

func _set_category(category: String) -> void:
	_category = category
	for key in _category_tabs:
		_category_tabs[key].set_pressed_no_signal(key == category)
	for child in _item_list.get_children():
		child.queue_free()
	_item_rows.clear()
	_item_bars.clear()
	_item_captions.clear()

	## A card rather than a row of text: the icon is what a player learns
	## to hit, and the cost is what they check. The name still leads the
	## button text so anything searching by name keeps working.
	for stats in BuildCatalog.items(category):
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, TILE_H)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(row)
		row.pressed.connect(func(): _on_item_pressed(stats))

		## The tile's contents are children rather than the Button's own
		## icon and text: a Button lays those out side by side, and a cameo
		## has to sit ABOVE its label to read at this size. Everything
		## inside ignores the mouse so the whole tile stays one click
		## target.
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.set_anchors_preset(Control.PRESET_FULL_RECT)
		body.offset_left = 3.0
		body.offset_right = -3.0
		body.offset_top = 3.0
		body.offset_bottom = -3.0
		body.add_theme_constant_override("separation", 1)
		row.add_child(body)

		var art := TextureRect.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var cameo := _cameo_for(stats)
		## Vector glyph fallback, for anything without a model.
		art.texture = cameo if cameo != null else Icons.for_name(stats.display_name)
		body.add_child(art)

		var caption := Label.new()
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", 11)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.clip_text = true
		body.add_child(caption)

		var price := Label.new()
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_theme_font_size_override("font_size", 11)
		price.add_theme_color_override("font_color", Color(0.878, 0.651, 0.235))
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.clip_text = true
		body.add_child(price)
		_item_captions[stats] = [caption, price]

		## A progress bar lying along the bottom edge of the card, the way
		## Red Alert marks the thing currently being built. Anchored rather
		## than laid out, so it sits ON the card instead of taking a row of
		## its own and pushing the list around whenever something starts.
		var progress := ProgressBar.new()
		progress.max_value = 1.0
		progress.show_percentage = false
		progress.visible = false
		progress.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		progress.offset_top = -7.0
		progress.offset_bottom = 0.0
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress.add_theme_stylebox_override("background",
			_plate(Color(0.08, 0.09, 0.10), Color(0.16, 0.17, 0.19),
				Color(0.05, 0.05, 0.06), 1))
		progress.add_theme_stylebox_override("fill",
			_plate(Color(0.878, 0.651, 0.235), Color(0.95, 0.76, 0.36),
				Color(0.62, 0.44, 0.14), 1))
		row.add_child(progress)

		_item_list.add_child(row)
		_item_rows[stats] = row
		_item_bars[stats] = progress
	_refresh_items()

## The cameo is a render of the very model that gets placed, keyed off the
## stats' own visual_scene, so a card can never show something the game
## does not build. See tools/render_cameos.gd.
func _cameo_for(stats) -> Texture2D:
	if stats == null or stats.visual_scene == null:
		return null
	var id: String = stats.visual_scene.resource_path.get_file().get_basename()
	if _cameo_cache.has(id):
		return _cameo_cache[id]
	var path: String = "res://assets/cameos/%s.png" % id
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cameo_cache[id] = texture
	return texture

## How far along this item is, or -1 if it is not being built right now.
## Structures go through the shared ConstructionQueue; units go through
## the queue on whichever building trains them.
func _production_progress(stats) -> float:
	if stats is BuildingStats:
		if construction != null and construction.current() == stats:
			return construction.progress()
		return -1.0
	var producer := BuildCatalog.producer_for(stats, true)
	if producer == null or producer.queue == null:
		return -1.0
	if producer.queue.current_stats() == stats:
		return producer.queue.progress()
	return -1.0

func _refresh_items() -> void:
	for stats in _item_rows:
		var row: Button = _item_rows[stats]
		if not is_instance_valid(row):
			continue
		var bar: ProgressBar = _item_bars.get(stats)
		var building: float = _production_progress(stats)
		var missing: Array = TechTree.missing_prerequisites(stats, true)

		if bar != null:
			bar.visible = building >= 0.0
			if building >= 0.0:
				bar.value = building

		var labels: Array = _item_captions.get(stats, [])
		var caption: Label = labels[0] if labels.size() > 0 else null
		var price: Label = labels[1] if labels.size() > 1 else null
		if caption != null:
			caption.text = stats.display_name

		if building >= 0.0:
			## In production: greyed and showing its own progress, so the
			## tile the player pressed is visibly the one working. Left
			## enabled - queueing a second is a normal thing to want.
			if price != null:
				price.text = "%d%%" % int(building * 100.0)
			row.disabled = false
			row.modulate = Color(0.55, 0.57, 0.60)
		elif missing.is_empty():
			if price != null:
				price.text = "$%s" % _thousands(stats.cost)
			var affordable: bool = GameState.credits >= stats.cost
			row.disabled = not affordable
			## Dim rather than hide what is merely unaffordable: knowing
			## what you are saving toward is half of an RTS build order.
			row.modulate = Color(1, 1, 1) if affordable else Color(0.72, 0.70, 0.66)
		else:
			if price != null:
				price.text = "LOCKED"
			row.tooltip_text = "Needs %s" % ", ".join(missing)
			row.disabled = true
			row.modulate = Color(0.52, 0.52, 0.58)

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
	_style_button(button)
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

## Everything that sits over the battlefield rather than in the sidebar.
func _build_overlays() -> void:
	_objective_label = RichTextLabel.new()
	_objective_label.bbcode_enabled = true
	_objective_label.fit_content = true
	_objective_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_label.offset_left = MARGIN
	_objective_label.offset_top = MARGIN
	_objective_label.offset_right = MARGIN + 320
	_objective_label.offset_bottom = MARGIN + 150
	_objective_label.add_theme_font_size_override("normal_font_size", 14)
	add_child(_objective_label)

	_production_label = _label("", 15)
	_production_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_production_label.offset_left = -240
	_production_label.offset_top = -40
	_production_label.offset_right = 160
	_production_label.offset_bottom = -14
	_production_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_production_label.visible = false
	add_child(_production_label)

	_event_label = _label("", 18)
	_event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_label.offset_left = -300
	_event_label.offset_top = 20
	_event_label.offset_right = 140
	_event_label.offset_bottom = 50
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
	_victory_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_victory_overlay)

	## Nearly opaque, and the same ground as the setup screen. At 0.72 the
	## battlefield read straight through the report and the numbers sat on
	## top of a building.
	var background := ColorRect.new()
	background.color = Color(0.03, 0.05, 0.04, 0.94)
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

	_subtitle_label = _label("", 16)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.64))
	column.add_child(_subtitle_label)

	## After-action report: what the match actually cost, which is what
	## makes an ending feel like a conclusion rather than a stop.
	_report_label = RichTextLabel.new()
	_report_label.bbcode_enabled = true
	_report_label.fit_content = true
	_report_label.custom_minimum_size = Vector2(420, 210)
	_report_label.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(_report_label)

	## Two ways out, because after a match people want one of exactly two
	## things: the same fight again, or a different one.
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var again := Button.new()
	again.text = "PLAY AGAIN"
	again.custom_minimum_size = Vector2(220, 56)
	again.add_theme_font_size_override("font_size", 18)
	again.pressed.connect(_play_again)
	buttons.add_child(again)

	var change := Button.new()
	change.text = "NEW SKIRMISH"
	change.custom_minimum_size = Vector2(220, 56)
	change.add_theme_font_size_override("font_size", 18)
	change.pressed.connect(_new_skirmish)
	buttons.add_child(change)

## Same map, same difficulty, straight back in.
func _play_again() -> void:
	GameState.skip_setup = true
	GameState.pending_save = {}
	get_tree().paused = false
	get_tree().reload_current_scene()

## Back to the setup screen to pick a different battlefield.
func _new_skirmish() -> void:
	GameState.skip_setup = false
	GameState.pending_save = {}
	GameState.selected_map = null
	get_tree().paused = false
	get_tree().reload_current_scene()

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
		if String(entry[0]).is_empty():
			lines.append("")
			continue
		lines.append("[color=#9aa48a]%-22s[/color]%s" % [entry[0], entry[1]])
	_report_label.text = "\n".join(lines)
	_victory_label.text = "VICTORY" if victory else "DEFEAT"
	_victory_label.add_theme_color_override("font_color",
		Color(0.88, 0.72, 0.30) if victory else Color(0.85, 0.24, 0.20))
	_subtitle_label.text = "Command HQ destroyed in %s" % MatchStats.formatted_time() \
		if victory else "Your Command HQ was lost after %s" % MatchStats.formatted_time()
	_victory_overlay.visible = true
	## The match is over, so nothing should still be shooting behind the
	## report while the player reads it.
	get_tree().paused = true

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
