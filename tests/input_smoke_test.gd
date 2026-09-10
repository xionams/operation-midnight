extends Node

## Drives the real HUD, construction and placement paths with synthetic
## input. Lives as a child of an instanced main.tscn so current_scene is
## genuinely the game scene.

var _main: Node3D
var _placer: BuildingPlacer
var _construction: ConstructionQueue
var _hud: CanvasLayer
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	_placer = _main.get_node("BuildingPlacer")
	_hud = _main.get_node("HUD")
	_construction = _main.get_node("ConstructionQueue")
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-46s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _find_button(prefix: String) -> Button:
	var stack: Array = [_hud]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and (n as Button).text.begins_with(prefix):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _move(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await get_tree().process_frame

func _click(pos: Vector2) -> void:
	await _move(pos)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame

func _drag(a: Vector2, b: Vector2) -> void:
	await _move(a)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT; d.pressed = true; d.position = a; d.global_position = a
	Input.parse_input_event(d)
	await get_tree().process_frame
	await _move(a.lerp(b, 0.5))
	await _move(b)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false; u.position = b; u.global_position = b
	Input.parse_input_event(u)
	await get_tree().process_frame
	await get_tree().process_frame

func _screen_of(node: Node3D) -> Vector2:
	return (get_tree().get_first_node_in_group("rts_camera") as Camera3D).unproject_position(node.global_position)

func _screen_of_world(pos: Vector3) -> Vector2:
	return (get_tree().get_first_node_in_group("rts_camera") as Camera3D).unproject_position(pos)

## Open ground near the base, clear of the HQ footprint, and chosen to
## project above screen centre - points low on screen land on HUD panels.
func _free_ground() -> Vector3:
	return Vector3(-78, 0, 62) + Vector3(14, 0, -8)

func _run() -> void:
	GameState.add_credits(20000)
	await get_tree().process_frame

	# --- production panel drives a timed construction order ---
	var power_btn := _find_button("Power Plant")
	_check("Production panel lists Power Plant", power_btn != null)
	if power_btn == null:
		return

	await _click(power_btn.get_global_rect().get_center())
	_check("Clicking an item starts construction", _construction.is_busy(),
		"(%s)" % (_construction.current().display_name if _construction.is_busy() else "idle"))
	_check("Construction is not instant", not _construction.is_ready())

	## Power Plant build time is 8s.
	var waited: float = 0.0
	while waited < 16.0 and not _construction.is_ready():
		waited += get_process_delta_time()
		await get_tree().process_frame
	_check("Construction completes after its build time", _construction.is_ready(),
		"(%.1fs)" % waited)
	_check("Completion opens placement mode", _placer.is_placing())

	var before: int = get_tree().get_nodes_in_group("buildings").size()
	await _click(_screen_of_world(_free_ground()))
	var after: int = get_tree().get_nodes_in_group("buildings").size()
	_check("Placing puts the structure on the map", after == before + 1,
		"(%d -> %d)" % [before, after])
	_check("Construction slot frees up after placing", not _construction.is_busy())
	_check("New Power Plant feeds the grid", GameState.power_generated >= 100,
		"(%d)" % GameState.power_generated)

	# --- build radius is enforced ---
	_check("Ground near the base is inside build radius",
		BuildingPlacer.in_build_radius(get_tree(), _free_ground(), true))
	_check("Ground across the map is outside build radius",
		not BuildingPlacer.in_build_radius(get_tree(), Vector3(40, 0, -40), true))

	# --- selection ---
	SelectionManager.clear_selection()
	var units: Array = get_tree().get_nodes_in_group("player_units")
	_check("Player units present", units.size() >= 2, "(%d)" % units.size())
	if units.size() >= 1:
		await _click(_screen_of(units[0]))
		_check("Clicking a unit selects it", SelectionManager.selected_units.size() == 1,
			"(%d)" % SelectionManager.selected_units.size())

	SelectionManager.clear_selection()
	await get_tree().process_frame
	if units.size() >= 2:
		var p0 := _screen_of(units[0])
		var p1 := _screen_of(units[1])
		var pad := Vector2(70, 70)
		await _drag(p0.min(p1) - pad, p0.max(p1) + pad)
		_check("Box-select picks up both units", SelectionManager.selected_units.size() >= 2,
			"(%d)" % SelectionManager.selected_units.size())

	# --- move order ---
	SelectionManager.clear_selection()
	await get_tree().process_frame
	if not units.is_empty():
		await _click(_screen_of(units[0]))
	_check("A unit is selected for the move order", not SelectionManager.selected_units.is_empty())
	if not SelectionManager.selected_units.is_empty():
		var u = SelectionManager.selected_units[0]
		var start: Vector3 = u.global_position
		var rc := InputEventMouseButton.new()
		rc.button_index = MOUSE_BUTTON_RIGHT; rc.pressed = true
		rc.position = _screen_of_world(_free_ground() + Vector3(8, 0, -8))
		rc.global_position = rc.position
		Input.parse_input_event(rc)
		for i in 120:
			await get_tree().process_frame
		_check("Right-click issues a move order", u.global_position.distance_to(start) > 1.0,
			"(moved %.1f)" % u.global_position.distance_to(start))
