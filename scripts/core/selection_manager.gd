extends Node

## Autoload: single source of truth for "what is selected" and how
## selection/command input turns into calls on units. Units never read
## input directly for this — they only expose select()/move_to()/
## attack_target() and this manager drives them.
##
## Desktop: left click = select/box-select, right click = move/attack.
## Android: tap a unit = select, tap ground/enemy after selecting =
## move/attack. One-finger drag pans the camera (see RTSCamera, which
## listens to the same raw events without consuming them).

const DRAG_THRESHOLD_PX: float = 14.0
const RAY_LENGTH: float = 500.0
const TARGET_MASK: int = 0b1111 # ground(1) + units(2) + buildings(4) + resources(8)

var selected_units: Array = []

var _camera: Camera3D = null
var _pressing: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
var _touch_index: int = -1

func _get_camera() -> Camera3D:
	if not is_instance_valid(_camera):
		var found := get_tree().get_first_node_in_group("rts_camera")
		_camera = found as Camera3D
	return _camera

func _unhandled_input(event: InputEvent) -> void:
	if GameState.match_state != GameState.MatchState.PLAYING:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
				_current_pos = mb.position
			elif _pressing:
				_pressing = false
				_current_pos = mb.position
				if _press_pos.distance_to(mb.position) < DRAG_THRESHOLD_PX:
					_desktop_select(mb.position, mb.shift_pressed)
				else:
					_desktop_box_select(_press_pos, mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_issue_command(mb.position)

	elif event is InputEventMouseMotion and _pressing:
		_current_pos = (event as InputEventMouseMotion).position

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index == -1:
				_touch_index = touch.index
				_pressing = true
				_press_pos = touch.position
				_current_pos = touch.position
		elif touch.index == _touch_index:
			_pressing = false
			_touch_index = -1
			if _press_pos.distance_to(touch.position) < DRAG_THRESHOLD_PX:
				_touch_tap(touch.position)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_current_pos = drag.position

func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := _get_camera()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, TARGET_MASK)
	return space_state.intersect_ray(query)

func _desktop_select(screen_pos: Vector2, additive: bool) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		clear_selection()
		return
	var collider: Node = hit.get("collider")
	if collider != null and collider.is_in_group("player_units"):
		if not additive:
			clear_selection()
		_select_unit(collider)
	else:
		if not additive:
			clear_selection()

func _desktop_box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	if not additive:
		clear_selection()
	_box_select_in_rect(rect)

func _touch_tap(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var collider: Node = hit.get("collider")
	if collider == null:
		return
	if collider.is_in_group("player_units"):
		clear_selection()
		_select_unit(collider)
	elif not selected_units.is_empty():
		if collider.is_in_group("enemy_units") or collider.is_in_group("enemy_buildings"):
			_command_attack(collider)
		elif collider.is_in_group("ground"):
			_command_move(hit.get("position"))

func _issue_command(screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var collider: Node = hit.get("collider")
	if collider != null and (collider.is_in_group("enemy_units") or collider.is_in_group("enemy_buildings")):
		_command_attack(collider)
	else:
		_command_move(hit.get("position"))

func _command_move(target_pos: Vector3) -> void:
	var count: int = selected_units.size()
	var spacing := 2.0
	var per_row: int = maxi(1, ceili(sqrt(count)))
	var i := 0
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		var row: int = i / per_row
		var col: int = i % per_row
		var offset := Vector3((col - per_row / 2.0) * spacing, 0.0, (row) * spacing)
		unit.move_to(target_pos + offset)
		i += 1

func _command_attack(target: Node) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("attack_target"):
			unit.attack_target(target)

func _select_unit(unit) -> void:
	if unit == null or selected_units.has(unit):
		return
	selected_units.append(unit)
	if unit.has_method("set_selected"):
		unit.set_selected(true)
	GameState.selection_changed.emit(selected_units)

func _box_select_in_rect(rect: Rect2) -> void:
	var camera := _get_camera()
	if camera == null:
		return
	var candidates: Array = get_tree().get_nodes_in_group("player_units")
	for unit in candidates:
		if not is_instance_valid(unit):
			continue
		if camera.is_position_behind(unit.global_position):
			continue
		var screen_pos := camera.unproject_position(unit.global_position)
		if rect.has_point(screen_pos):
			_select_unit(unit)

func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("set_selected"):
			unit.set_selected(false)
	selected_units.clear()
	GameState.selection_changed.emit(selected_units)

func notify_unit_removed(unit: Node) -> void:
	if selected_units.has(unit):
		selected_units.erase(unit)
		GameState.selection_changed.emit(selected_units)

func get_drag_rect() -> Rect2:
	if not _pressing:
		return Rect2()
	return Rect2(_press_pos, Vector2.ZERO).expand(_current_pos)

func is_boxing() -> bool:
	return _pressing and _press_pos.distance_to(_current_pos) >= DRAG_THRESHOLD_PX
