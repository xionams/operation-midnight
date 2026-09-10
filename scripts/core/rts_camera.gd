extends Camera3D
class_name RTSCamera

## Angled RTS camera rig. Pans over a ground point (pan_target) and
## dollies toward/away from it along a fixed direction to zoom, so the
## viewing angle stays constant like a classic C&C-style camera.
##
## Desktop: WASD/arrows pan, mouse wheel zooms.
## Android: one-finger drag pans, two-finger pinch zooms.
## Not attached to any unit — purely a free-floating battlefield camera.

@export var bounds_min: Vector2 = Vector2(-50, -50)
@export var bounds_max: Vector2 = Vector2(50, 50)
@export var min_zoom: float = 15.0
@export var max_zoom: float = 65.0
@export var pan_speed: float = 35.0
@export var wheel_zoom_step: float = 5.0
@export var follow_speed: float = 8.0
@export var touch_pan_sensitivity: float = 0.0035

var CAMERA_DIR: Vector3 = Vector3(0, 1.15, 1).normalized()

var pan_target: Vector3 = Vector3.ZERO
var zoom_distance: float = 40.0

var _current_pan: Vector3 = Vector3.ZERO
var _current_zoom: float = 40.0
var _forward_flat: Vector3
var _right_flat: Vector3
var _touches: Dictionary = {}
var _pinch_start_distance: float = -1.0
var _pinch_start_zoom: float = 0.0

func _ready() -> void:
	add_to_group("rts_camera")
	_forward_flat = -Vector3(CAMERA_DIR.x, 0.0, CAMERA_DIR.z).normalized()
	_right_flat = _forward_flat.rotated(Vector3.UP, -PI / 2.0)
	_current_pan = pan_target
	_current_zoom = zoom_distance
	_apply_transform()

func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		move += _forward_flat
	if Input.is_action_pressed("move_back"):
		move -= _forward_flat
	if Input.is_action_pressed("move_right"):
		move += _right_flat
	if Input.is_action_pressed("move_left"):
		move -= _right_flat
	if move != Vector3.ZERO:
		pan_target += move.normalized() * pan_speed * delta

	pan_target.x = clamp(pan_target.x, bounds_min.x, bounds_max.x)
	pan_target.z = clamp(pan_target.z, bounds_min.y, bounds_max.y)
	zoom_distance = clamp(zoom_distance, min_zoom, max_zoom)

	var t: float = clamp(follow_speed * delta, 0.0, 1.0)
	_current_pan = _current_pan.lerp(pan_target, t)
	_current_zoom = lerp(_current_zoom, zoom_distance, t)

	_apply_transform()

func _apply_transform() -> void:
	global_position = _current_pan + CAMERA_DIR * _current_zoom
	look_at(_current_pan, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance = clamp(zoom_distance - wheel_zoom_step, min_zoom, max_zoom)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance = clamp(zoom_distance + wheel_zoom_step, min_zoom, max_zoom)

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
			if _touches.size() == 2:
				_pinch_start_distance = _touch_distance()
				_pinch_start_zoom = zoom_distance
		else:
			_touches.erase(touch.index)
			_pinch_start_distance = -1.0

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			_touches[drag.index] = drag.position
			return
		var previous: Vector2 = _touches[drag.index]
		_touches[drag.index] = drag.position

		if _touches.size() == 1:
			var screen_delta: Vector2 = drag.position - previous
			var scale: float = zoom_distance * touch_pan_sensitivity
			pan_target -= _right_flat * screen_delta.x * scale
			pan_target += _forward_flat * screen_delta.y * scale
		elif _touches.size() == 2 and _pinch_start_distance > 0.0:
			var distance := _touch_distance()
			var factor: float = _pinch_start_distance / max(distance, 1.0)
			zoom_distance = clamp(_pinch_start_zoom * factor, min_zoom, max_zoom)

func _touch_distance() -> float:
	var values := _touches.values()
	if values.size() < 2:
		return 0.0
	return (values[0] as Vector2).distance_to(values[1] as Vector2)

func focus_on(world_position: Vector3) -> void:
	pan_target = Vector3(world_position.x, 0.0, world_position.z)
