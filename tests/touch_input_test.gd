extends Node

## Exercises the touch gestures the Android build depends on.
##
## The mouse paths are covered by input_smoke_test; these are not, and
## they are the ones that only fail once the game is on a phone - by
## which point the feedback loop is a device, a cable and a rebuild.
## Everything here drives the real SelectionManager and RTSCamera through
## synthetic InputEventScreenTouch/Drag, the same events Android sends.

const HOLD_FOR_MARQUEE: float = 0.30

var _main: Node3D
var _camera: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_camera = _main.find_child("RTSCamera", true, false)
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-48s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(1)

func _drag(index: int, from: Vector2, to: Vector2, steps: int = 4) -> void:
	for i in range(1, steps + 1):
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = from.lerp(to, float(i) / steps)
		event.relative = (to - from) / steps
		Input.parse_input_event(event)
		await _frames(1)

## Where a world position lands on screen, so a tap can aim at a unit.
func _screen_of(world: Vector3) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	return camera.unproject_position(world)

func _player_units() -> Array:
	return get_tree().get_nodes_in_group("player_units")

func _run() -> void:
	var units := _player_units()
	_check("Player units exist to touch", units.size() >= 2, "(%d)" % units.size())
	if units.size() < 2:
		return

	var first = units[0]
	_camera.focus_on(first.global_position)
	await _frames(20)

	# --- tap to select ---
	SelectionManager.clear_selection()
	var point := _screen_of(first.global_position)
	await _touch(0, point, true)
	await _frames(2)
	await _touch(0, point, false)
	await _frames(2)
	_check("Tap selects a unit", SelectionManager.selected_units.size() == 1,
		"(%d)" % SelectionManager.selected_units.size())

	# --- tap ground with a selection is a move order, not a deselect ---
	var empty := _screen_of(first.global_position + Vector3(0, 0, 26))
	var where_before: Vector3 = first.global_position
	await _touch(0, empty, true)
	await _frames(2)
	await _touch(0, empty, false)
	await _frames(30)
	_check("Tap on ground keeps the selection and orders a move",
		SelectionManager.selected_units.size() == 1
			and first.global_position.distance_to(where_before) > 0.5,
		"(%d selected, moved %.1f m)" % [SelectionManager.selected_units.size(),
			first.global_position.distance_to(where_before)])

	# --- press and hold, then drag: marquee, and the camera holds still ---
	SelectionManager.clear_selection()
	var centre := Vector2(get_viewport().get_visible_rect().size) * 0.5
	var before_pan: Vector3 = _camera.pan_target
	await _touch(0, centre - Vector2(150, 110), true)
	var waited: float = 0.0
	while waited < HOLD_FOR_MARQUEE + 0.12:
		waited += get_process_delta_time()
		await get_tree().process_frame
	await _drag(0, centre - Vector2(150, 110), centre + Vector2(150, 110), 6)
	_check("Holding then dragging does not pan the camera",
		_camera.pan_target.distance_to(before_pan) < 0.5,
		"(moved %.2f m)" % _camera.pan_target.distance_to(before_pan))
	await _touch(0, centre + Vector2(150, 110), false)
	await _frames(2)

	# --- one finger drag pans ---
	SelectionManager.clear_selection()
	await _frames(2)
	before_pan = _camera.pan_target
	await _touch(0, centre, true)
	await _drag(0, centre, centre + Vector2(0, -180), 6)
	await _touch(0, centre + Vector2(0, -180), false)
	await _frames(4)
	_check("One finger drag pans the camera",
		_camera.pan_target.distance_to(before_pan) > 1.0,
		"(moved %.1f m)" % _camera.pan_target.distance_to(before_pan))

	# --- pinch zooms out, spread zooms back in ---
	var zoom_before: float = _camera.zoom_distance
	await _touch(0, centre - Vector2(160, 0), true)
	await _touch(1, centre + Vector2(160, 0), true)
	await _drag(0, centre - Vector2(160, 0), centre - Vector2(40, 0), 5)
	await _drag(1, centre + Vector2(160, 0), centre + Vector2(40, 0), 5)
	await _frames(2)
	var pinched: float = _camera.zoom_distance
	_check("Pinching together zooms out", pinched > zoom_before + 0.5,
		"(%.1f -> %.1f)" % [zoom_before, pinched])

	await _drag(0, centre - Vector2(40, 0), centre - Vector2(200, 0), 5)
	await _drag(1, centre + Vector2(40, 0), centre + Vector2(200, 0), 5)
	await _frames(2)
	_check("Spreading zooms back in", _camera.zoom_distance < pinched - 0.5,
		"(%.1f -> %.1f)" % [pinched, _camera.zoom_distance])
	await _touch(0, centre - Vector2(200, 0), false)
	await _touch(1, centre + Vector2(200, 0), false)
	await _frames(2)

	# --- a second finger must not fire a command ---
	SelectionManager.clear_selection()
	await _frames(2)
	await _touch(0, centre, true)
	await _touch(1, centre + Vector2(140, 20), true)
	await _touch(0, centre, false)
	await _touch(1, centre + Vector2(140, 20), false)
	await _frames(2)
	_check("A two finger gesture never issues a selection",
		SelectionManager.selected_units.is_empty(),
		"(%d)" % SelectionManager.selected_units.size())

	_check("Zoom stayed inside its limits",
		_camera.zoom_distance >= _camera.min_zoom - 0.01
			and _camera.zoom_distance <= _camera.max_zoom + 0.01,
		"(%.1f)" % _camera.zoom_distance)
