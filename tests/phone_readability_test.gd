extends Node

## Is this playable on a phone held in two hands?
##
## The project stretches canvas_items from a 1280x720 base, so this IS
## the phone layout - every device gets these logical pixels. That makes
## the question answerable on a desktop: a control smaller than a
## fingertip here is smaller than a fingertip there, and a label too
## small to read here is worse on a 6-inch screen at arm's length.
##
## Walks the live HUD rather than checking a list of controls, so
## anything added later is covered without being registered anywhere.

## Android and iOS both put the minimum touch target at ~48dp / 44pt.
## The project's own TOUCH_MIN is 44, so that is the bar.
const MIN_TOUCH: float = 44.0
## A hair under, to allow for a control that rounds to 43.99 in a
## container; anything genuinely smaller is a real finding.
const TOUCH_SLACK: float = 1.0
const MIN_FONT: int = 11

var _fails: Array = []
var _main: Node3D

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_walk(child, out)

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	GameState.add_credits(40000)
	await _frames(20)

	var screen: Vector2 = get_viewport().get_visible_rect().size
	_check("The game lays out at the phone base resolution",
		screen == Vector2(1280, 720), "%s" % screen)

	## Exercise the states that put the most on screen at once.
	var hq = get_tree().get_nodes_in_group("player_buildings")[0]
	var unit = get_tree().get_nodes_in_group("player_units")[0]
	var catalog = BuildCatalog.items("BUILDINGS")
	if hud.construction != null and catalog.size() > 1:
		hud.construction.start(catalog[1])
	SelectionManager.clear_selection()
	SelectionManager._select_unit(hq)
	SelectionManager._select_unit(unit)
	await _frames(20)

	var controls: Array = []
	_walk(hud, controls)

	# --- every button a thumb has to hit ---
	var small: Array = []
	var offscreen: Array = []
	for c in controls:
		if not (c is Button) or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < MIN_TOUCH - TOUCH_SLACK or r.size.y < MIN_TOUCH - TOUCH_SLACK:
			small.append("%s %.0fx%.0f" % [_label_of(c), r.size.x, r.size.y])
		if r.position.x < -0.5 or r.position.y < -0.5 \
			or r.position.x + r.size.x > screen.x + 0.5 \
			or r.position.y + r.size.y > screen.y + 0.5:
			offscreen.append("%s at %s" % [_label_of(c), r])
	_check("Every visible button is at least a fingertip across",
		small.is_empty(), "too small: %s" % str(small))
	_check("Every visible button is fully on screen",
		offscreen.is_empty(), "off: %s" % str(offscreen))

	# --- text a player has to read at arm's length ---
	var tiny: Array = []
	for c in controls:
		if not c.is_visible_in_tree():
			continue
		var size: int = 0
		if c is Label:
			size = (c as Label).get_theme_font_size("font_size")
		elif c is Button:
			size = (c as Button).get_theme_font_size("font_size")
		elif c is RichTextLabel:
			size = (c as RichTextLabel).get_theme_font_size("normal_font_size")
		else:
			continue
		if size > 0 and size < MIN_FONT:
			tiny.append("%s %dpt" % [_label_of(c), size])
	_check("No text is smaller than %dpt" % MIN_FONT, tiny.is_empty(),
		"tiny: %s" % str(tiny))

	# --- nothing spills out of the frame ---
	var spill: Array = []
	for c in controls:
		if not c.is_visible_in_tree() or c.get_parent() is ScrollContainer:
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.y + r.size.y > screen.y + 0.5:
			spill.append("%s bottom %.0f" % [c.name, r.position.y + r.size.y])
	_check("No panel runs off the bottom of the screen", spill.is_empty(),
		"%s" % str(spill))

	# --- the battlefield is not buried under UI ---
	var covered: float = 0.0
	for c in controls:
		if not c.is_visible_in_tree() or not (c is PanelContainer):
			continue
		if c.get_parent() is ScrollContainer:
			continue
		var r: Rect2 = c.get_global_rect()
		covered = maxf(covered, r.size.x if r.size.y > screen.y * 0.5 else 0.0)
	_check("The sidebar leaves most of the screen to the battlefield",
		covered < screen.x * 0.33, "%.0f of %.0f px wide" % [covered, screen.x])

	# --- the performance overlay a device session needs ---
	_check("A performance readout exists for on-device profiling",
		hud._perf != null and hud._perf.to_text().contains("fps"))

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

func _label_of(c: Control) -> String:
	if c is Button and not (c as Button).text.is_empty():
		return (c as Button).text
	return String(c.name)
