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
	if _gesture != Gesture.PENDING or _pressed_on_entity:
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

func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := _get_camera()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, TARGET_MASK)
	return space_state.intersect_ray(query)

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
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.stance = stance

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

	var hostile: bool = collider != null \
		and (collider.is_in_group("enemy_units") or collider.is_in_group("enemy_buildings"))

	if hostile:
		_command_on_target(collider)
		EventBus.command_issued.emit(CommandTypes.Type.ATTACK, collider.global_position)
		return

	if collider != null and collider.is_in_group("resource_nodes"):
		_issue_to_selection(CommandTypes.Type.HARVEST, collider.global_position, collider)
		EventBus.command_issued.emit(CommandTypes.Type.HARVEST, collider.global_position)
		return

	## Infantry tapped onto a garrisonable friendly structure move in.
	if collider != null and collider is BuildingBase:
		var garrison = collider.get_node_or_null("GarrisonComponent")
		if garrison != null and (collider.is_player_faction or collider.is_neutral):
			_issue_to_selection(CommandTypes.Type.GARRISON, collider.global_position, collider)
			EventBus.command_issued.emit(CommandTypes.Type.GARRISON, collider.global_position)
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

	_command_move(point)
	EventBus.command_issued.emit(CommandTypes.Type.MOVE, point)

## Engineers and Spies answer a click on an enemy structure with their
## ability; everything else attacks it, so a mixed group does the
## sensible thing per unit rather than all-or-nothing.
func _command_on_target(target: Node) -> void:
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("special_order") and unit.special_order(target):
			continue
		if unit.has_method("issue_command"):
			unit.issue_command(CommandTypes.Type.ATTACK, Vector3.ZERO, target)

func _issue_to_selection(type: int, point: Vector3, target: Node) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("issue_command"):
			unit.issue_command(type, point, target)

## Formation offsets keep a group from piling onto one coordinate. The
## grid is computed once per order, not maintained per frame.
func _command_move(target_pos: Vector3) -> void:
	var count: int = selected_units.size()
	var spacing: float = 2.4
	var per_row: int = maxi(1, ceili(sqrt(float(count))))
	var i: int = 0
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		var row: int = i / per_row
		var col: int = i % per_row
		var offset := Vector3(
			(col - (per_row - 1) / 2.0) * spacing,
			0.0,
			(row - (per_row - 1) / 2.0) * spacing)
		if unit.has_method("issue_command"):
			unit.issue_command(CommandTypes.Type.MOVE, target_pos + offset, null)
		i += 1
