extends Node

## Autoload: owns "what is selected", turns raw input into intent, and
## resolves intent into CommandTypes. Units never read input; they only
## expose issue_command()/set_selected().
##
## GESTURE STATE MACHINE
## Touch has to serve two conflicting jobs with one finger - move the
## camera, and draw a selection box - so a press is not committed to
## either until the player's intent is clear:
##
##   IDLE ──press on empty ground──> PENDING
##   PENDING ──moved before HOLD_TIME──> PANNING   (camera follows finger)
##   PENDING ──held past HOLD_TIME────> MARQUEE    (box appears, drag sizes it)
##   PENDING ──released quickly───────> tap (select / command)
##   PANNING | MARQUEE ──release──────> IDLE
##
## Once PANNING is entered the marquee can no longer start, and once
## MARQUEE is entered the camera is locked out, so the two gestures can
## never fight over the same finger. RTSCamera asks is_panning_allowed()
## before acting on a drag.
##
## Desktop skips the ambiguity: left-drag is always a marquee, right
## click is always a command, and the middle of the state machine is
## simply not used.
##
## INPUT PRIORITY
## HUD Controls consume their own clicks first (they are GUI, and this
## runs in _unhandled_input, which the GUI has already had a chance at).
## Then entity picks, then the selection gesture, then the camera.

signal marquee_changed(active: bool)

const DRAG_THRESHOLD_PX: float = 14.0
const HOLD_TIME: float = 0.20
const DOUBLE_TAP_TIME: float = 0.35
const DOUBLE_TAP_RADIUS: float = 40.0
const SAME_TYPE_RADIUS: float = 30.0
const RAY_LENGTH: float = 800.0
const TARGET_MASK: int = 0b11111 # ground(1) units(2) buildings(4) resources(8) infantry(16)

enum Gesture { IDLE, PENDING, PANNING, MARQUEE }

var selected_units: Array = []
var attack_move_armed: bool = false
## While armed, the next ground tap sets the rally point of every
## selected production building instead of issuing a move order.
var rally_armed: bool = false
## While armed, the next ground tap becomes a patrol destination.
var patrol_armed: bool = false

var _camera: Camera3D = null
var _gesture: int = Gesture.IDLE
var _press_pos: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _touch_index: int = -1
## Godot emulates mouse events from touch, and the GUI depends on that to
## keep buttons working on a phone. Gameplay must NOT also act on them:
## handling both meant every tap ran twice, and worse, the emulated
## left-drag hit the desktop rule that a drag is always a marquee - so on
## a touchscreen the camera could never be panned with one finger at all.
## Any real mouse the player also has goes quiet for a second after a
## touch, which nobody can notice.
const TOUCH_MOUSE_LOCKOUT: float = 1.0
var _last_touch_time: float = -99.0
var _pressed_on_entity: bool = false
var _press_is_touch: bool = false

var _last_tap_time: float = -99.0
var _last_tap_pos: Vector2 = Vector2.ZERO

var _control_groups: Dictionary = {1: [], 2: [], 3: []}

func _get_camera() -> Camera3D:
	if not is_instance_valid(_camera):
		_camera = get_tree().get_first_node_in_group("rts_camera") as Camera3D
	return _camera

## RTSCamera consults this so a drag that has become a marquee cannot
## also slide the battlefield underneath it.
## True while a finger is, or has just been, driving the game.
func _touch_is_driving() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - _last_touch_time < TOUCH_MOUSE_LOCKOUT

func is_panning_allowed() -> bool:
	return _gesture != Gesture.MARQUEE

func is_boxing() -> bool:
	return _gesture == Gesture.MARQUEE

func get_drag_rect() -> Rect2:
	if _gesture != Gesture.MARQUEE:
		return Rect2()
	return Rect2(_press_pos, Vector2.ZERO).expand(_current_pos)

func _process(_delta: float) -> void:
	## A press that is held still long enough becomes a marquee even
	## before the finger moves, so the box appears under the thumb and
	## the player can see the mode they are in.
	## Touch only. On a desktop a press that stays still is a click however
	## long it is held - the marquee there starts on movement. Applying the
	## hold rule to the mouse turned any slow click (over 0.2s) into an
	## empty box select that picked nothing: clicks "missed" at random,
	## and every time on a slow frame.
	if _gesture != Gesture.PENDING or _pressed_on_entity or not _press_is_touch:
		return
	if Time.get_ticks_msec() / 1000.0 - _press_time >= HOLD_TIME:
		_enter_marquee()

func _enter_marquee() -> void:
	_gesture = Gesture.MARQUEE
	marquee_changed.emit(true)

func _unhandled_input(event: InputEvent) -> void:
	if GameState.match_state != GameState.MatchState.PLAYING:
		return

	if event is InputEventMouseButton:
		if _touch_is_driving():
			return
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if _touch_is_driving():
			return
		_current_pos = (event as InputEventMouseMotion).position
		if _gesture == Gesture.PENDING and _press_pos.distance_to(_current_pos) >= DRAG_THRESHOLD_PX:
			_enter_marquee()
	elif event is InputEventScreenTouch:
		_last_touch_time = Time.get_ticks_msec() / 1000.0
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_last_touch_time = Time.get_ticks_msec() / 1000.0
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)

# ---------------------------------------------------------------- desktop

func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_begin_press(mb.position, false)
			## Desktop has a dedicated command button, so a left drag is
			## unambiguously a marquee - no hold needed.
			_pressed_on_entity = false
		else:
			_end_press(mb.position, mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_resolve_command_at(mb.position)

func _handle_key(key: InputEventKey) -> void:
	match key.physical_keycode:
		KEY_A:
			arm_attack_move(true)
		KEY_S:
			command_stop()
		KEY_P:
			arm_patrol()
		KEY_C:
			toggle_infantry_stance()
		KEY_1, KEY_2, KEY_3:
			var index: int = key.physical_keycode - KEY_0
			if key.ctrl_pressed:
				assign_control_group(index)
			else:
				recall_control_group(index)

# ------------------------------------------------------------------ touch

func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touch_index != -1:
			## A second finger means pinch-zoom; abandon any selection
			## gesture so zooming never issues a command.
			_cancel_gesture()
			return
		_touch_index = touch.index
		_begin_press(touch.position, true)
	elif touch.index == _touch_index:
		_touch_index = -1
		_end_press(touch.position, false)

func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index != _touch_index:
		return
	_current_pos = drag.position
	if _gesture != Gesture.PENDING:
		return
	## Moved before the hold elapsed: the player wants to pan, not select.
	if _press_pos.distance_to(_current_pos) >= DRAG_THRESHOLD_PX:
		_gesture = Gesture.PANNING

# --------------------------------------------------------------- shared

func _begin_press(pos: Vector2, from_touch: bool) -> void:
	_press_is_touch = from_touch
	_press_pos = pos
	_current_pos = pos
	_press_time = Time.get_ticks_msec() / 1000.0
	_gesture = Gesture.PENDING
	if from_touch:
		## Pressing directly on something is never a marquee - it is a
		## tap on that thing.
		var hit := _raycast(pos)
		var collider = hit.get("collider") if not hit.is_empty() else null
		_pressed_on_entity = collider != null and not collider.is_in_group("ground")

func _end_press(pos: Vector2, additive: bool) -> void:
	_current_pos = pos
	var gesture := _gesture
	_gesture = Gesture.IDLE
	_pressed_on_entity = false

	if gesture == Gesture.MARQUEE:
		marquee_changed.emit(false)
		## A box too small to hold anything was a tap that lingered.
		if _press_pos.distance_to(pos) >= DRAG_THRESHOLD_PX:
			_marquee_select(Rect2(_press_pos, Vector2.ZERO).expand(pos), additive)
			return
	if gesture == Gesture.PANNING:
		return
	if _press_pos.distance_to(pos) >= DRAG_THRESHOLD_PX:
		return

	_handle_tap(pos, additive)

func _cancel_gesture() -> void:
	if _gesture == Gesture.MARQUEE:
		marquee_changed.emit(false)
	_gesture = Gesture.IDLE
	_touch_index = -1
	_pressed_on_entity = false

func _handle_tap(pos: Vector2, additive: bool) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var is_double: bool = (now - _last_tap_time) < DOUBLE_TAP_TIME \
		and _last_tap_pos.distance_to(pos) < DOUBLE_TAP_RADIUS
	_last_tap_time = now
	_last_tap_pos = pos

	var hit := _raycast(pos)
	var collider: Node = hit.get("collider") if not hit.is_empty() else null

	if collider != null and collider.is_in_group("player_units"):
		if is_double:
			_select_same_type_near(collider)
		else:
			if not additive:
				clear_selection()
			_select_unit(collider)
		return

	## Structures are selectable too - that is how sell, repair and rally
	## points are reached - but only one at a time, and never mixed into
	## an army selection by the marquee.
	if collider != null and collider.is_in_group("player_buildings"):
		clear_selection()
		_select_unit(collider)
		return

	## Tapping anything else with units selected is a command; with
	## nothing selected it clears.
	if selected_units.is_empty():
		clear_selection()
		return
	_resolve_command_at(pos)

# ------------------------------------------------------------- selection

## What the player pointed at: {"collider": entity-or-ground, "position":
## the ground point under the pointer}.
##
## Entities are picked in their own pass that ignores the ground layer.
## The ground collider is a flat box at y=0 but the visible terrain rolls
## +-1.6m (see Terrain), so a tank sitting in a hollow is partly or
## wholly BELOW the pick surface: a single ray hit the ground first and
## the click silently became a move order. With the ground skipped, the
## ray reaches the unit the player can actually see.
##
## A miss then falls back to screen space: the nearest selectable thing
## whose on-screen centre is within PICK_TOLERANCE_PX, so a soldier a few
## pixels wide - or a fingertip on a phone - is not a pixel hunt.
func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := _get_camera()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var space_state := camera.get_world_3d().direct_space_state
	var ground := space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, GROUND_MASK))
	var entity_hit := space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, ENTITY_MASK))
	var collider: Node = entity_hit.get("collider") if not entity_hit.is_empty() else null
	if collider == null:
		collider = _nearest_on_screen(screen_pos)
	var point: Vector3 = ground.get("position", entity_hit.get("position", Vector3.ZERO))
	if collider == null:
		if ground.is_empty():
			return {}
		collider = ground.get("collider")
	return {"collider": collider, "position": point}

const PICK_TOLERANCE_PX: float = 22.0
const GROUND_MASK: int = 0b00001
const ENTITY_MASK: int = TARGET_MASK & ~GROUND_MASK

## Screen-space fallback for _raycast: units first (they are small),
## then structures, only what the player may interact with.
func _nearest_on_screen(screen_pos: Vector2) -> Node:
	var camera := _get_camera()
	var best: Node = null
	var best_d: float = PICK_TOLERANCE_PX
	for group in ["player_units", "enemy_units"]:
		for unit in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(unit) or not unit.is_inside_tree():
				continue
			if FogHideable.is_hidden(unit) or not DisguiseAbility.visible_to(unit, true) \
				or not Stealth.visible_to(unit, true):
				continue
			var height: float = unit.stats.body_size.y * 0.5 if unit.get("stats") != null else 0.8
			var centre: Vector3 = unit.global_position + Vector3.UP * height
			if camera.is_position_behind(centre):
				continue
			var d: float = camera.unproject_position(centre).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = unit
	return best

## Marquee selection is screen-space: a unit is caught if the point the
## player actually sees it at falls inside the rectangle they drew. It
## deliberately never picks up buildings or enemies.
func _marquee_select(rect: Rect2, additive: bool) -> void:
	var camera := _get_camera()
	if camera == null:
		return
	if not additive:
		clear_selection()
	for unit in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(unit):
			continue
		if camera.is_position_behind(unit.global_position):
			continue
		if rect.has_point(camera.unproject_position(unit.global_position)):
			_select_unit(unit)

## Double-tap: grab the rest of this unit's kind nearby, which on a phone
## is far easier than drawing an accurate box around them.
func _select_same_type_near(unit: Node) -> void:
	clear_selection()
	var kind: String = unit.stats.display_name if unit.stats else ""
	var origin: Vector3 = unit.global_position
	for other in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(other) or other.stats == null:
			continue
		if other.stats.display_name != kind:
			continue
		if other.global_position.distance_to(origin) > SAME_TYPE_RADIUS:
			continue
		_select_unit(other)

func _select_unit(unit) -> void:
	if unit == null or selected_units.has(unit):
		return
	selected_units.append(unit)
	if unit.has_method("set_selected"):
		unit.set_selected(true)
	GameState.selection_changed.emit(selected_units)

func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("set_selected"):
			unit.set_selected(false)
	selected_units.clear()
	GameState.selection_changed.emit(selected_units)

func notify_unit_removed(unit: Node) -> void:
	var changed: bool = false
	if selected_units.has(unit):
		selected_units.erase(unit)
		changed = true
	## Dead units must not linger in a control group and resurrect the
	## next time it is recalled.
	for index in _control_groups:
		if _control_groups[index].has(unit):
			_control_groups[index].erase(unit)
	if changed:
		GameState.selection_changed.emit(selected_units)

# --------------------------------------------------------- control groups

func assign_control_group(index: int) -> void:
	if not _control_groups.has(index):
		return
	_control_groups[index] = selected_units.duplicate()

func recall_control_group(index: int) -> void:
	if not _control_groups.has(index):
		return
	clear_selection()
	for unit in _control_groups[index]:
		if is_instance_valid(unit):
			_select_unit(unit)

func control_group_size(index: int) -> int:
	if not _control_groups.has(index):
		return 0
	var count: int = 0
	for unit in _control_groups[index]:
		if is_instance_valid(unit):
			count += 1
	return count

# -------------------------------------------------------------- commands

func arm_attack_move(armed: bool) -> void:
	attack_move_armed = armed and not selected_units.is_empty()

## Hold position and engage what comes close, without chasing.
func command_guard() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.issue_command(CommandTypes.Type.GUARD, unit.global_position)
	attack_move_armed = false

func arm_rally_point() -> void:
	rally_armed = true

func arm_patrol() -> void:
	patrol_armed = not selected_units.is_empty()

func set_stance(stance: int) -> void:
	var n: int = 0
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.stance = stance
			n += 1
	if n == 0:
		Feedback.reject("Stance: no units selected")
		return
	var label: String = UnitBase.Stance.keys()[stance].capitalize()
	Feedback.ok("%s stance — %d unit%s" % [label, n, "" if n == 1 else "s"])
	GameState.selection_changed.emit(selected_units)

## RUN / CROUCH for every selected soldier. Vehicles in a mixed
## selection have no posture and are simply skipped.
func set_infantry_stance(mode: int) -> void:
	for unit in selected_units:
		var posture := InfantryStance.of(unit)
		if posture != null:
			posture.set_mode(mode)
	GameState.selection_changed.emit(selected_units)

## One key / one button: if anyone selected is still running, everyone
## crouches; only when the whole group is already down do they get up.
func toggle_infantry_stance() -> void:
	var any_running: bool = false
	var any_infantry: bool = false
	for unit in selected_units:
		var posture := InfantryStance.of(unit)
		if posture == null:
			continue
		any_infantry = true
		if not posture.is_crouched():
			any_running = true
	if not any_infantry:
		Feedback.reject("Posture: no infantry selected")
		return
	var mode: int = InfantryStance.Mode.CROUCH if any_running else InfantryStance.Mode.RUN
	set_infantry_stance(mode)
	var count: int = _units_with_posture()
	Feedback.ok("%s — %d infantry %s" % [InfantryStance.mode_name(mode).to_upper(), count,
		"slower, hitting harder" if mode == InfantryStance.Mode.CROUCH else "at full speed"])

func _units_with_posture() -> int:
	var n: int = 0
	for unit in selected_units:
		if InfantryStance.of(unit) != null:
			n += 1
	return n

## Everyone out of every selected garrison (or, later, transport).
## Returns how many units left.
func command_evacuate() -> int:
	var count: int = 0
	for entity in selected_units:
		if not is_instance_valid(entity):
			continue
		for child in entity.get_children():
			if child is OccupantHold:
				count += (child as OccupantHold).exit_all().size()
	GameState.selection_changed.emit(selected_units)
	if count > 0:
		Feedback.ok("Unloaded %d" % count)
	else:
		Feedback.reject("Nobody inside to unload")
	return count

func command_stop() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.issue_command(CommandTypes.Type.STOP)
	attack_move_armed = false

## Turns "the player pointed here" into an actual order. All contextual
## intent lives in this one place, so a new unit role means teaching this
## resolver one more case rather than adding another input path.
func _resolve_command_at(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var collider: Node = hit.get("collider")
	var point: Vector3 = hit.get("position")

	## Rally placement takes priority: the player explicitly armed it.
	if rally_armed:
		rally_armed = false
		var any: bool = false
		for entity in selected_units:
			if is_instance_valid(entity) and entity is BuildingBase:
				entity.rally_point = point
				any = true
		if any:
			EventBus.command_issued.emit(CommandTypes.Type.MOVE, point)
		return

	if patrol_armed:
		patrol_armed = false
		_issue_to_selection(CommandTypes.Type.PATROL, point, null)
		EventBus.command_issued.emit(CommandTypes.Type.PATROL, point)
		return

	if attack_move_armed:
		attack_move_armed = false
		_issue_to_selection(CommandTypes.Type.ATTACK_MOVE, point, null)
		EventBus.command_issued.emit(CommandTypes.Type.ATTACK_MOVE, point)
		return

	## A selection of structures only: a right-click on the ground sets the
	## rally point, as in Red Alert, rather than silently doing nothing.
	if _commandable_units().is_empty():
		var producers: int = 0
		for entity in selected_units:
			if is_instance_valid(entity) and entity is BuildingBase and entity.get("queue") != null:
				entity.rally_point = point
				producers += 1
		if producers > 0:
			EventBus.command_issued.emit(CommandTypes.Type.MOVE, point)
			Feedback.ok("Rally point set")
		return

	var hostile: bool = collider != null \
		and (collider.is_in_group("enemy_units") or collider.is_in_group("enemy_buildings"))

	if hostile:
		var accepted: int = _command_on_target(collider)
		if accepted == 0:
			Feedback.reject("No selected unit can attack %s" % _name_of(collider),
				collider.global_position)
			return
		EventBus.command_issued.emit(CommandTypes.Type.ATTACK, collider.global_position)
		CommandMarker.spawn_on_target(collider as Node3D)
		return

	if collider != null and collider.is_in_group("resource_nodes"):
		_issue_to_selection(CommandTypes.Type.HARVEST, collider.global_position, collider)
		EventBus.command_issued.emit(CommandTypes.Type.HARVEST, collider.global_position)
		return

	## Infantry tapped onto a garrisonable friendly structure move in.
	if collider != null and collider is BuildingBase:
		var garrison = collider.get_node_or_null("GarrisonComponent")
		if garrison != null and (collider.is_player_faction or collider.is_neutral):
			_order_garrison(collider, garrison)
			return

	## Guard mode armed at a friendly unit escorts it.
	if collider != null and collider.is_in_group("player_units") and not selected_units.has(collider):
		_issue_to_selection(CommandTypes.Type.GUARD, collider.global_position, collider)
		EventBus.command_issued.emit(CommandTypes.Type.GUARD, collider.global_position)
		return

	if collider != null and collider.is_in_group("player_buildings"):
		## Harvesters treat a friendly refinery as "unload here"; anything
		## else just walks over.
		_issue_to_selection(CommandTypes.Type.RETURN, collider.global_position, collider)
		EventBus.command_issued.emit(CommandTypes.Type.RETURN, collider.global_position)
		return

	_warn_wrong_domain(point)
	_command_move(point)
	EventBus.command_issued.emit(CommandTypes.Type.MOVE, point)

## Engineers and Spies answer a click on an enemy structure with their
## ability; everything else attacks it, so a mixed group does the
## sensible thing per unit rather than all-or-nothing.
## Returns how many units took the order - an ability, or an attack their
## weapon accepted - so the caller can say "no" when nobody could.
func _command_on_target(target: Node) -> int:
	var accepted: int = 0
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("special_order") and unit.special_order(target):
			accepted += 1
			continue
		if unit.has_method("issue_command"):
			unit.issue_command(CommandTypes.Type.ATTACK, Vector3.ZERO, target)
			var attacker = unit.get_node_or_null("AttackerComponent")
			if attacker != null and attacker.target == target:
				accepted += 1
	return accepted

## Send the selected infantry in, telling the player up front if the
## building cannot take them all - or anyone.
func _order_garrison(building: Node, hold: OccupantHold) -> void:
	var infantry: Array = []
	for unit in _commandable_units():
		if unit.stats != null and unit.stats.is_infantry:
			infantry.append(unit)
	var at: Vector3 = building.global_position
	if infantry.is_empty():
		Feedback.reject("Only infantry can garrison %s" % _name_of(building), at)
		_command_move(at)
		return
	if hold.free_slots() == 0:
		Feedback.reject("%s is full (%d/%d)" % [_name_of(building), hold.occupancy(), hold.capacity], at)
		return
	_issue_to_selection(CommandTypes.Type.GARRISON, at, building)
	EventBus.command_issued.emit(CommandTypes.Type.GARRISON, at)
	var going: int = mini(infantry.size(), hold.free_slots())
	if going < infantry.size():
		Feedback.warn("%d of %d will fit in %s (%d/%d)" % [going, infantry.size(),
			_name_of(building), hold.occupancy(), hold.capacity])
	else:
		Feedback.ok("Garrisoning %s — %d going in (%d/%d)" % [_name_of(building), going,
			hold.occupancy(), hold.capacity])

## Tanks cannot drive into the sea and ships cannot sail up the beach;
## each still goes as far as it can (the navmesh takes it to the nearest
## reachable point), but the player is told why it stopped short.
func _warn_wrong_domain(point: Vector3) -> void:
	if not Water.has_water():
		return
	var wet: bool = Water.is_water(point.x, point.z)
	var stranded: int = 0
	var total: int = 0
	for unit in _commandable_units():
		if unit.stats == null:
			continue
		total += 1
		if unit.is_naval() != wet:
			stranded += 1
	if stranded == 0:
		return
	if wet:
		Feedback.warn("Land units can't enter the sea - %d heading to the shore" % stranded, point)
	else:
		Feedback.warn("Ships can't go ashore - %d heading to the coast" % stranded, point)

func _commandable_units() -> Array:
	var out: Array = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			out.append(unit)
	return out

static func _name_of(node: Node) -> String:
	var stats = node.get("stats") if node != null else null
	return stats.display_name if stats != null else "that"

func _issue_to_selection(type: int, point: Vector3, target: Node) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.issue_command(type, point, target)

## Formation offsets keep a group from piling onto one coordinate. The
## grid is computed once per order, not maintained per frame.
##
## Slots are handed out nearest-first rather than in selection order, so
## units do not cross through each other to reach an arbitrary slot - the
## main source of the shuffle and jam at the end of a group move. Spacing
## follows the largest unit in the group so tanks are not packed like
## riflemen.
func _command_move(target_pos: Vector3) -> void:
	var units: Array = _commandable_units()
	var count: int = units.size()
	if count == 0:
		return
	var spacing: float = 2.4
	for unit in units:
		if unit.stats != null:
			spacing = maxf(spacing, maxf(unit.stats.body_size.x, unit.stats.body_size.z) + 0.8)
	var per_row: int = maxi(1, ceili(sqrt(float(count))))
	var slots: Array = []
	for i in count:
		var row: int = i / per_row
		var col: int = i % per_row
		slots.append(target_pos + Vector3(
			(col - (per_row - 1) / 2.0) * spacing,
			0.0,
			(row - (per_row - 1) / 2.0) * spacing))
	## Farthest units choose first: they have the longest walk, and the
	## ones already close take whatever is left nearby.
	units.sort_custom(func(a, b): return a.global_position.distance_squared_to(target_pos) \
		> b.global_position.distance_squared_to(target_pos))
	for unit in units:
		var best: int = 0
		var best_d: float = INF
		for j in slots.size():
			var d: float = unit.global_position.distance_squared_to(slots[j])
			if d < best_d:
				best_d = d
				best = j
		unit.issue_command(CommandTypes.Type.MOVE, slots[best], null)
		slots.remove_at(best)
