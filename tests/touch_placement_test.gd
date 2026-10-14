extends Node

## Positioning a building by finger must not also drag the world.
##
## On touch, BuildingPlacer tracks the pointer in _input (it does not
## consume the event) and RTSCamera pans in _unhandled_input, guarded
## only by SelectionManager.is_panning_allowed(), which knows about the
## marquee and nothing else. So a drag during placement moved the ghost
## AND the ground under it, which is the one gesture the player needs to
## be precise with - and it is the primary platform's primary input.

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-56s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _drag(from: Vector2, to: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = from
	Input.parse_input_event(touch)
	await get_tree().process_frame
	var steps := 6
	for i in range(1, steps + 1):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = from.lerp(to, float(i) / steps)
		drag.relative = (to - from) / steps
		Input.parse_input_event(drag)
		await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = to
	Input.parse_input_event(up)
	await get_tree().process_frame

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
	GameState.add_credits(50000)
	for i in 20:
		await get_tree().physics_frame

	var camera = get_tree().get_first_node_in_group("rts_camera")
	var placer = _main.get_node_or_null("BuildingPlacer")
	_check("The placer exists", placer != null)
	_check("The camera exists", camera != null)
	if placer == null or camera == null:
		_finish()
		return

	# --- a drag with nothing being placed SHOULD pan ---
	camera.snap()
	await _frames(6)
	var before: Vector3 = camera.pan_target
	await _drag(Vector2(700, 400), Vector2(450, 300))
	await _frames(4)
	var free_pan: float = before.distance_to(camera.pan_target)
	_check("A drag pans the camera normally", free_pan > 1.0,
		"moved %.2fm" % free_pan)

	# --- the same drag WHILE PLACING must not pan ---
	var stats: BuildingStats = load("res://config/buildings/power_plant.tres")
	placer.start_placement(stats)
	await _frames(6)
	_check("The placer reports it is placing", placer.is_placing())
	camera.snap()
	await _frames(6)
	var held: Vector3 = camera.pan_target
	await _drag(Vector2(700, 400), Vector2(450, 300))
	await _frames(4)
	var placing_pan: float = held.distance_to(camera.pan_target)
	_check("Dragging to position a building does NOT pan the camera",
		placing_pan < 0.5, "moved %.2fm" % placing_pan)

	placer.cancel_placement()
	await _frames(6)
	_check("Panning works again once placement ends",
		SelectionManager.is_panning_allowed())

	_finish()

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
