extends Node

## Phase 2 / parts 1-2: selection reliability and command feedback.
##
## Proves the terrain-vs-collider pick bug is gone (a tank in a real
## hollow of the map is clicked, not the ground over it), and that every
## kind of order now answers: a target lock for attacks, a reason for
## refusals, confirmations for posture / garrison / unload / rally,
## lines for what selected units are doing, and a live info card.

const TANK := preload("res://config/units/assault_vehicle.tres")
const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const DOG := preload("res://config/units/attack_dog.tres")
const BARRACKS := preload("res://config/buildings/barracks.tres")
const POWER := preload("res://config/buildings/power_plant.tres")
const HOUSE := preload("res://config/buildings/civilian_house.tres")

var _main: Node3D
var _fails: Array = []
var _feedback: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	var director = get_parent().get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	EventBus.feedback.connect(func(text, kind, pos): _feedback.append([text, kind, pos]))
	for u in get_tree().get_nodes_in_group("player_units"):
		var gun = u.get_node_or_null("AttackerComponent")
		if gun != null:
			gun.set_physics_process(false)
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-60s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _spawn_building(stats: BuildingStats, player: bool, pos: Vector3, neutral := false) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	b.is_neutral = neutral
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _cam() -> Camera3D:
	return get_tree().get_first_node_in_group("rts_camera") as Camera3D

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	Input.parse_input_event(m)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await get_tree().process_frame

func _last_feedback() -> Array:
	return _feedback[-1] if not _feedback.is_empty() else ["", -1, Vector3.INF]

func _run() -> void:
	# --- 1. the buried-unit pick ---
	## Find a real hollow near the player base: ground at least 0.9m below
	## the flat pick collider (y=0).
	var hollow := Vector3.INF
	var deepest: float = 0.0
	for x in range(-94, 95, 3):
		for z in range(-94, 95, 3):
			var h: float = Terrain.height_at(x, z)
			if h < deepest:
				deepest = h
				hollow = Vector3(x, 0, z)
	if deepest > -1.0:
		hollow = Vector3.INF
	_check("The map has a hollow at least 1m under the pick surface", hollow.is_finite(),
		"(%.2fm at %s)" % [deepest, str(hollow)])
	if hollow.is_finite():
		var tank = _spawn(TANK, true, hollow)
		await _wait(0.3)
		_cam().focus_on(tank.global_position)
		await _frames(4)
		## The lower hull: visible (the terrain is lower still) but under
		## the flat collider's top at y=0.
		var screen: Vector2 = _cam().unproject_position(tank.global_position + Vector3.UP * 0.3)
		## What the old single ray against every layer returned.
		var from := _cam().project_ray_origin(screen)
		var old_hit := _cam().get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + _cam().project_ray_normal(screen) * 800.0,
				SelectionManager.TARGET_MASK))
		_check("Old pick: the flat ground swallowed the click on the tank",
			old_hit.get("collider") != tank, "(old hit %s)" % str(old_hit.get("collider")))
		_check("New pick: the click lands on the tank in the hollow",
			SelectionManager._raycast(screen).get("collider") == tank)
		SelectionManager.clear_selection()
		await _click(screen)
		_check("A real left click selects the tank in the hollow",
			SelectionManager.selected_units == [tank], "(%d selected)" % SelectionManager.selected_units.size())

	# --- 1b. a slow click (held 0.4s, not moved) is still a click ---
	if hollow.is_finite():
		var slow_target = SelectionManager.selected_units[0] if not SelectionManager.selected_units.is_empty() else null
		if slow_target != null:
			var sp: Vector2 = _cam().unproject_position(slow_target.global_position + Vector3.UP * 0.3)
			SelectionManager.clear_selection()
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = sp
			down.global_position = sp
			Input.parse_input_event(down)
			await _wait(0.4)
			var up := down.duplicate()
			up.pressed = false
			Input.parse_input_event(up)
			await _frames(2)
			_check("A slow click (held 0.4s) still selects - no empty marquee",
				SelectionManager.selected_units == [slow_target])

	# --- 2. screen-space tolerance for small units ---
	var soldier = _spawn(SOLDIER, true, Vector3(-60, 0, 50))
	await _wait(0.2)
	_cam().focus_on(soldier.global_position)
	await _frames(4)
	var near_miss: Vector2 = _cam().unproject_position(soldier.global_position + Vector3.UP * 0.9) + Vector2(14, 10)
	SelectionManager.clear_selection()
	await _click(near_miss)
	_check("A click 17px off a soldier still selects him",
		SelectionManager.selected_units.has(soldier))

	# --- 3. attack order: target lock, and a reason when nobody can ---
	var wall_target = _spawn_building(POWER, false, Vector3(-40, 0, 40))
	var dog = _spawn(DOG, true, Vector3(-46, 0, 50))
	await _wait(0.3)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(dog)
	_feedback.clear()
	_cam().focus_on(wall_target.global_position)
	await _frames(4)
	await _click(_cam().unproject_position(wall_target.global_position + Vector3.UP * 2.8), MOUSE_BUTTON_RIGHT)
	var fb := _last_feedback()
	_check("Dog on a building: the order is refused with a reason",
		fb[1] == Feedback.Kind.REJECT and String(fb[0]).contains("can attack"), "(%s)" % fb[0])
	_check("...and a rejected mark is dropped on the target",
		_main.get_node("Level").find_child("RejectedMarker", false, false) != null)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(soldier)
	await _click(_cam().unproject_position(wall_target.global_position + Vector3.UP * 2.8), MOUSE_BUTTON_RIGHT)
	_check("Rifleman on the same building: accepted, target lock shown",
		wall_target.get_node_or_null("TargetMarker") != null
		and soldier.get_node("AttackerComponent").target == wall_target)

	# --- 4. order lines show what the selection is doing ---
	await _wait(0.2)
	var lines: OrderLines = _main.get_node("Level").find_child("OrderLines", false, false)
	_check("An order line is drawn for the attacking soldier", lines != null and lines.line_count() >= 1)
	soldier.issue_command(CommandTypes.Type.STOP)
	await _wait(0.2)
	_check("No line once he is idle", lines != null and lines.line_count() == 0)

	# --- 5. live info card ---
	var hud = _main.get_node("HUD")
	soldier.issue_command(CommandTypes.Type.MOVE, soldier.global_position + Vector3(10, 0, 0))
	await _wait(0.5)
	var card: String = hud._info_panel.text
	_check("Card: owner, class, reach and activity",
		card.contains("(yours)") and card.contains("Infantry") and card.contains("hits land, naval")
		and card.contains("Moving"), "(%s)" % card.replace("\n", " | "))

	# --- 6. posture confirmation / refusal ---
	_feedback.clear()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.keycode = KEY_C
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_check("C confirms the posture change",
		_last_feedback()[1] == Feedback.Kind.OK and String(_last_feedback()[0]).contains("CROUCH"),
		"(%s)" % _last_feedback()[0])
	SelectionManager.clear_selection()
	SelectionManager._select_unit(_spawn(TANK, true, Vector3(-60, 0, 44)))
	_feedback.clear()
	SelectionManager.toggle_infantry_stance()
	_check("...and refuses with a reason when no infantry are selected",
		_last_feedback()[1] == Feedback.Kind.REJECT)

	# --- 7. garrison: full house refused, unload of an empty building refused ---
	var house = _spawn_building(HOUSE, false, Vector3(-30, 0, 62), true)
	await _wait(0.3)
	var hold: OccupantHold = house.get_node("GarrisonComponent")
	for i in 2:
		hold.enter(_spawn(SOLDIER, true, house.global_position + Vector3(4, 0, i)))
	var extra = _spawn(SOLDIER, true, house.global_position + Vector3(6, 0, 4))
	await _frames(2)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(extra)
	_feedback.clear()
	_cam().focus_on(house.global_position)
	await _frames(4)
	await _click(_cam().unproject_position(house.global_position + Vector3.UP * 3.0), MOUSE_BUTTON_RIGHT)
	_check("Right-click on a full house: refused, says it is full",
		_last_feedback()[1] == Feedback.Kind.REJECT and String(_last_feedback()[0]).contains("full"),
		"(%s)" % _last_feedback()[0])
	SelectionManager.clear_selection()
	SelectionManager._select_unit(house)
	_feedback.clear()
	SelectionManager.command_evacuate()
	_check("Unload reports how many came out", String(_last_feedback()[0]) == "Unloaded 2",
		"(%s)" % _last_feedback()[0])
	SelectionManager.command_evacuate()
	_check("Unloading an empty building is refused", _last_feedback()[1] == Feedback.Kind.REJECT)

	# --- 8. building-only selection: right-click sets the rally point ---
	var barracks = _spawn_building(BARRACKS, true, Vector3(-60, 0, 76))
	await _wait(0.3)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(barracks)
	await _frames(2)
	_check("Unit order buttons disable with only a building selected",
		hud._attack_move_button.disabled)
	_cam().focus_on(barracks.global_position)
	await _frames(4)
	await _click(_cam().unproject_position(barracks.global_position + Vector3(10, 0, 6)), MOUSE_BUTTON_RIGHT)
	_check("Right-click with a Barracks selected sets its rally point",
		barracks.rally_point != Vector3.ZERO and String(_last_feedback()[0]).contains("Rally"))

	# --- 9. placement explains itself ---
	var placer: BuildingPlacer = _main.get_node("BuildingPlacer")
	placer.start_placement(POWER)
	var far := Vector3(60, 0, -60)
	_check("Placing outside territory gives the reason",
		placer.placement_error(far) == "Outside your construction territory", "(%s)" % placer.placement_error(far))
	_check("Placing on a building names what blocks it",
		placer.placement_error(barracks.global_position).begins_with("Blocked by Barracks"))
	placer.construction_queue = null
	_feedback.clear()
	_cam().focus_on(barracks.global_position)
	await _frames(4)
	var on_barracks: Vector2 = _cam().unproject_position(Vector3(barracks.global_position.x, 0, barracks.global_position.z))
	var m := InputEventMouseMotion.new()
	m.position = on_barracks
	m.global_position = on_barracks
	Input.parse_input_event(m)
	await _frames(3)
	var label: Label3D = placer.get_node_or_null("PlacementReason")
	_check("The ghost floats the reason while it is red",
		label != null and label.visible and label.text.begins_with("Blocked by"), "(%s)" % (label.text if label else "no label"))
	await _click(on_barracks)
	_check("A refused placement click reports why",
		_last_feedback()[1] == Feedback.Kind.REJECT and String(_last_feedback()[0]).contains("Blocked by"),
		"(%s)" % _last_feedback()[0])
	placer.cancel_placement()

	# --- 10. group move: formation slots, no pile-up ---
	var group: Array = []
	for i in 6:
		group.append(_spawn(SOLDIER, true, Vector3(-66 + (i % 3) * 2.0, 0, 30 + (i / 3) * 2.0)))
	await _frames(2)
	SelectionManager.clear_selection()
	for u in group:
		SelectionManager._select_unit(u)
	var dest := Vector3(-50, 0, 20)
	SelectionManager._command_move(dest)
	var targets: Array = group.map(func(u): return u.nav_agent.target_position)
	var min_gap: float = INF
	for i in targets.size():
		for j in range(i + 1, targets.size()):
			min_gap = minf(min_gap, targets[i].distance_to(targets[j]))
	_check("Group move gives every unit its own slot", min_gap >= 2.0, "(closest %.1fm)" % min_gap)
	await _wait(8.0)
	var arrived: int = 0
	for u in group:
		if u.nav_agent.is_navigation_finished() and u.global_position.distance_to(u.nav_agent.target_position) < 2.0:
			arrived += 1
	_check("The whole group arrives", arrived == group.size(), "(%d of %d)" % [arrived, group.size()])
