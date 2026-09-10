extends Node

## Temporary harness: drives the real HUD/selection/placement paths with
## synthetic input events. Not part of the game. Lives as a child of an
## instanced main.tscn so current_scene is genuinely the game scene.

var _main: Node3D
var _placer: BuildingPlacer
var _hud: CanvasLayer
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	print("TEST| current_scene=", get_tree().current_scene.name,
		" navregion_reachable=", get_tree().current_scene.get_node_or_null("Level/NavRegion") != null)
	_placer = _main.get_node("BuildingPlacer")
	_hud = _main.get_node("HUD")
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-42s %s %s" % [name, "PASS" if cond else "FAIL", detail])
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
	var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	return cam.unproject_position(node.global_position)

## Screen point for a world position, so placement tests aim at ground
## that is actually free rather than a hardcoded pixel that drifts
## whenever the camera or map layout changes.
func _screen_of_world(pos: Vector3) -> Vector2:
	var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	return cam.unproject_position(pos)

## Open ground near the player base, clear of the HQ footprint and
## chosen to project ABOVE screen centre - points below it land on the
## HUD bar, where the click is eaten by a button instead of the ground.
func _free_ground() -> Vector3:
	return Vector3(-78, 0, 62) + Vector3(20, 0, -6)

func _free_ground_b() -> Vector3:
	return Vector3(-78, 0, 62) + Vector3(-16, 0, -10)

func _run() -> void:
	var power_btn := _find_button("Power Plant")
	_check("HUD build button exists", power_btn != null)
	if power_btn == null:
		return

	# --- 1. build button starts placement ---
	await _click(power_btn.get_global_rect().get_center())
	_check("Build button starts placement", _placer.is_placing())

	# --- 2. cancel button while placing ---
	var cancel_btn := _find_button("Cancel")
	_check("Cancel button becomes visible", cancel_btn != null and cancel_btn.visible)
	var buildings_before: int = get_tree().get_nodes_in_group("buildings").size()
	var credits_before: int = GameState.credits
	if cancel_btn != null:
		await _click(cancel_btn.get_global_rect().get_center())
	_check("Cancel button cancels placement", not _placer.is_placing(),
		"(still placing after clicking Cancel)" if _placer.is_placing() else "")
	var buildings_after: int = get_tree().get_nodes_in_group("buildings").size()
	_check("Clicking Cancel did not place a building", buildings_after == buildings_before,
		"(buildings %d -> %d, credits %d -> %d)" % [buildings_before, buildings_after, credits_before, GameState.credits])

	_placer.cancel_placement()
	await get_tree().process_frame

	# --- 3. placement on valid ground ---
	await _click(power_btn.get_global_rect().get_center())
	var before_n: int = get_tree().get_nodes_in_group("buildings").size()
	var before_cr: int = GameState.credits
	await _click(_screen_of_world(_free_ground()))
	var after_n: int = get_tree().get_nodes_in_group("buildings").size()
	_check("Click on ground places a building", after_n == before_n + 1,
		"(%d -> %d)" % [before_n, after_n])
	_check("Placement deducted credits", GameState.credits == before_cr - 800,
		"(%d -> %d)" % [before_cr, GameState.credits])
	_check("Placement ended after confirm", not _placer.is_placing())
	_placer.cancel_placement()

	# --- 4. unit selection by click ---
	SelectionManager.clear_selection()
	var units: Array = get_tree().get_nodes_in_group("player_units")
	_check("Player units present", units.size() >= 2, "(%d)" % units.size())
	if units.size() >= 1:
		await _click(_screen_of(units[0]))
		_check("Clicking a unit selects it", SelectionManager.selected_units.size() == 1,
			"(%d selected)" % SelectionManager.selected_units.size())

	# --- 5. box select ---
	SelectionManager.clear_selection()
	await get_tree().process_frame
	if units.size() >= 2:
		var p0 := _screen_of(units[0])
		var p1 := _screen_of(units[1])
		var pad := Vector2(70, 70)
		await _drag(p0.min(p1) - pad, p0.max(p1) + pad)
		_check("Box-select picks up both units", SelectionManager.selected_units.size() == 2,
			"(%d selected)" % SelectionManager.selected_units.size())

	# --- 6. war factory production ---
	SelectionManager.clear_selection()
	var factory_btn := _find_button("War Factory")
	_check("War Factory build button exists", factory_btn != null)
	if factory_btn != null:
		GameState.add_credits(10000)
		await _click(factory_btn.get_global_rect().get_center())
		await _click(_screen_of_world(_free_ground_b()))
		var factory := get_tree().get_first_node_in_group("war_factories")
		_check("War Factory placed and registered", factory != null)
		if factory != null:
			var assault_btn := _find_button("Assault")
			_check("Assault button enabled once factory exists",
				assault_btn != null and not assault_btn.disabled)
			var before_units: int = get_tree().get_nodes_in_group("player_units").size()
			var cr: int = GameState.credits
			await _click(assault_btn.get_global_rect().get_center())
			_check("Queuing an Assault charges immediately", GameState.credits == cr - 1500,
				"(%d -> %d)" % [cr, GameState.credits])
			_check("Order is queued, not instant", factory.queue.queue_length() == 1
				and get_tree().get_nodes_in_group("player_units").size() == before_units)
			# assault build_time is 12s; run the clock out
			var waited := 0.0
			while waited < 16.0 and get_tree().get_nodes_in_group("player_units").size() == before_units:
				waited += get_process_delta_time()
				await get_tree().process_frame
			var after_units: int = get_tree().get_nodes_in_group("player_units").size()
			_check("Assault Vehicle spawns after build_time", after_units == before_units + 1,
				"(%d -> %d after %.1fs)" % [before_units, after_units, waited])
			_check("Queue empties after completion", factory.queue.queue_length() == 0)

	# --- 7. move order ---
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
		rc.position = _screen_of_world(_free_ground()); rc.global_position = rc.position
		Input.parse_input_event(rc)
		for i in 90:
			await get_tree().process_frame
		_check("Right-click issues a move order", u.global_position.distance_to(start) > 1.0,
			"(moved %.1f)" % u.global_position.distance_to(start))
