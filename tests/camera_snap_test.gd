extends Node

## The camera must hold still where it is put.
##
## snap() copied an UNCLAMPED pan_target into the live pan, and _process
## clamped the target underneath it on the next frame. So focusing on
## anything outside the bounds snapped there and then slid away over the
## following frames toward the legal point: measured, a fixed world point
## drifted from 428px to 120px across ten frames. Any code that aims the
## camera and then reads screen positions - a click, a minimap jump, a
## test harness - was reading a view that was still moving.

const COAST := preload("res://config/maps/coastline.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _cam() -> RTSCamera:
	return get_tree().get_first_node_in_group("rts_camera") as RTSCamera

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Largest distance a fixed world point wanders on screen after a snap.
func _drift_after_snap(focus: Vector3) -> float:
	_cam().focus_on(focus)
	_cam().snap()
	await _frames(2)
	var probe := Vector3(-90.0, 0.0, 40.0)
	var first: Vector2 = _cam().unproject_position(probe)
	var worst: float = 0.0
	for i in 12:
		await get_tree().process_frame
		worst = maxf(worst, first.distance_to(_cam().unproject_position(probe)))
	return worst

func _ready() -> void:
	GameState.selected_map = COAST
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	for i in 20:
		await get_tree().physics_frame

	## The case that used to drift: a point far outside the bounds.
	var out: float = await _drift_after_snap(Vector3(-260.0, 0.0, 120.0))
	_check("snap() on an out-of-bounds point holds still", out < 1.0,
		"drifted %.1f px over 12 frames" % out)
	var inb: float = await _drift_after_snap(Vector3(-40.0, 0.0, 30.0))
	_check("snap() on an in-bounds point holds still", inb < 1.0,
		"drifted %.1f px over 12 frames" % inb)

	## The fix must not mean "the camera may go anywhere".
	_cam().focus_on(Vector3(-5000.0, 0.0, 5000.0))
	_cam().snap()
	await _frames(2)
	var pan: Vector3 = _cam().pan_target
	_check("Map bounds still hold the camera in",
		pan.x >= _cam().bounds_min.x - 0.01 and pan.x <= _cam().bounds_max.x + 0.01
		and pan.z >= _cam().bounds_min.y - 0.01 and pan.z <= _cam().bounds_max.y + 0.01,
		"pan %s in %s..%s" % [pan, _cam().bounds_min, _cam().bounds_max])

	## Easing is still how the camera moves in play - snap is the explicit
	## exception, not the new default.
	_cam().focus_on(Vector3(60.0, 0.0, 60.0))
	await _frames(1)
	var eased: bool = _cam().global_position.distance_to(
		Vector3(60.0, 0.0, 60.0) + _cam().CAMERA_DIR * _cam().zoom_distance) > 5.0
	_check("Without snap() the camera still eases rather than jumping", eased)

	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
