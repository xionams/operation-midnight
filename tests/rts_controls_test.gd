extends Node

## Covers the RTS interaction model: marquee selection in screen space,
## control groups, contextual commands, attack-move and the defensive
## stance leash.

const TANK := preload("res://scenes/units/assault_vehicle.tscn")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")
const SCOUT := preload("res://scenes/units/scout_vehicle.tscn")
const SCOUT_STATS := preload("res://config/units/scout_vehicle.tres")

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	## The skirmish setup screen pauses the tree until START is pressed;
	## harnesses start the match themselves.
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-50s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(scene: PackedScene, stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _camera() -> Camera3D:
	return get_tree().get_first_node_in_group("rts_camera") as Camera3D

func _screen_of(node: Node3D) -> Vector2:
	return _camera().unproject_position(node.global_position)

func _press(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame

func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	Input.parse_input_event(m)
	await get_tree().process_frame

func _run() -> void:
	var base := Vector3(-78, 0, 62)

	# --- marquee selects friendly units, and only friendly units ---
	SelectionManager.clear_selection()
	var a = _spawn(TANK, TANK_STATS, true, base + Vector3(6, 0, -4))
	var b = _spawn(TANK, TANK_STATS, true, base + Vector3(12, 0, -4))
	var enemy = _spawn(TANK, TANK_STATS, false, base + Vector3(9, 0, -8))
	await get_tree().process_frame
	FogOfWar.update_now()
	await get_tree().process_frame

	var pa := _screen_of(a)
	var pb := _screen_of(b)
	var pe := _screen_of(enemy)
	var topleft := pa.min(pb).min(pe) - Vector2(60, 60)
	var bottomright := pa.max(pb).max(pe) + Vector2(60, 60)

	await _press(topleft, true)
	await _motion(topleft.lerp(bottomright, 0.5))
	_check("Marquee becomes active while dragging", SelectionManager.is_boxing())
	var rect := SelectionManager.get_drag_rect()
	_check("Marquee rectangle has real size", rect.size.length() > 20.0,
		"(%.0fx%.0f)" % [rect.size.x, rect.size.y])
	_check("Camera panning is locked out during a marquee",
		not SelectionManager.is_panning_allowed())
	await _motion(bottomright)
	await _press(bottomright, false)

	## The map already has starting units near the base, and the marquee
	## correctly catches those too - so assert on what must be in the box
	## rather than on a total that depends on the spawn layout.
	var picked: int = SelectionManager.selected_units.size()
	_check("Marquee selected both friendly units",
		SelectionManager.selected_units.has(a) and SelectionManager.selected_units.has(b),
		"(%d selected in box)" % picked)
	_check("Marquee did not select the enemy",
		not SelectionManager.selected_units.has(enemy))
	_check("Marquee clears once released", not SelectionManager.is_boxing())
	_check("Camera panning is allowed again", SelectionManager.is_panning_allowed())

	# --- control groups ---
	SelectionManager.assign_control_group(1)
	_check("Control group stores the selection",
		SelectionManager.control_group_size(1) == picked,
		"(%d of %d)" % [SelectionManager.control_group_size(1), picked])
	SelectionManager.clear_selection()
	_check("Selection cleared", SelectionManager.selected_units.is_empty())
	SelectionManager.recall_control_group(1)
	_check("Recalling the group reselects it",
		SelectionManager.selected_units.size() == picked,
		"(%d of %d)" % [SelectionManager.selected_units.size(), picked])

	a.get_node("HealthComponent").take_damage(99999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Dead units drop out of control groups",
		SelectionManager.control_group_size(1) == picked - 1,
		"(%d, expected %d)" % [SelectionManager.control_group_size(1), picked - 1])

	# --- formation spread: a group does not stack on one point ---
	SelectionManager.clear_selection()
	var squad: Array = []
	for i in 6:
		squad.append(_spawn(TANK, TANK_STATS, true, base + Vector3(-14 + i * 3.0, 0, 10)))
	await get_tree().process_frame
	for unit in squad:
		SelectionManager._select_unit(unit)
	var destination := base + Vector3(4, 0, 16)
	SelectionManager._command_move(destination)
	var targets: Array = []
	var duplicates: int = 0
	for unit in squad:
		var t: Vector3 = unit.nav_agent.target_position
		for other in targets:
			if other.distance_to(t) < 0.5:
				duplicates += 1
		targets.append(t)
	_check("Multi-unit move spreads into a formation", duplicates == 0,
		"(%d overlapping destinations)" % duplicates)

	# --- attack-move ---
	SelectionManager.clear_selection()
	var mover = _spawn(TANK, TANK_STATS, true, base + Vector3(0, 0, 20))
	await get_tree().process_frame
	SelectionManager._select_unit(mover)
	SelectionManager.arm_attack_move(true)
	_check("Attack-move arms", SelectionManager.attack_move_armed)
	mover.issue_command(CommandTypes.Type.ATTACK_MOVE, base + Vector3(30, 0, 20))
	_check("Attack-move is recorded as the current command",
		mover.current_command == CommandTypes.Type.ATTACK_MOVE)

	## Put a hostile in its path; it should stop and engage rather than
	## walking past.
	var blocker = _spawn(TANK, TANK_STATS, false, base + Vector3(14, 0, 20))
	await get_tree().process_frame
	FogOfWar.update_now()
	var engaged := false
	for i in 240:
		await get_tree().physics_frame
		var att: AttackerComponent = mover.get_node("AttackerComponent")
		if att.has_target():
			engaged = true
			break
	_check("Attack-move engages a hostile met on the way", engaged)

	# --- stop ---
	SelectionManager.clear_selection()
	SelectionManager._select_unit(mover)
	SelectionManager.command_stop()
	_check("Stop sets the STOP command", mover.current_command == CommandTypes.Type.STOP)
	_check("Stop clears the attack target",
		not mover.get_node("AttackerComponent").has_target())

	# --- defensive leash: an idle unit does not chase forever ---
	var guard = _spawn(TANK, TANK_STATS, true, base + Vector3(-20, 0, 30))
	await get_tree().process_frame
	var home: Vector3 = guard.global_position
	for i in 30:
		await get_tree().physics_frame
	_check("Idle unit holds position instead of drifting",
		guard.global_position.distance_to(home) < 3.0,
		"(drifted %.1fm)" % guard.global_position.distance_to(home))
