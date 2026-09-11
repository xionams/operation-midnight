extends Node

## Flies the camera to the places that matter and saves a frame at each.
##
## Screenshots are how an art pass is actually reviewed - a passing test
## says the models loaded, not that the battlefield reads. Camera stops
## are named after what they are meant to prove.

const SETTLE: float = 1.2
const OUT_DIR: String = "res://screenshots"

var _main: Node3D
var _camera: Node3D

## (name, look-at point, zoom, seconds to wait before shooting)
var _stops: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_camera = _main.find_child("RTSCamera", true, false)
	if _camera == null:
		for child in _main.get_children():
			if child.has_method("focus_on"):
				_camera = child
				break
	_stops = [
		["player_base", Vector3(-78, 0, 62), 30.0, 3.0],
		["battlefield_overview", Vector3(-10, 0, 0), 95.0, 3.0],
		["resource_harvesting", Vector3(-56, 0, 34), 26.0, 26.0],
		["vehicle_group", Vector3(-78, 0, 62), 20.0, 40.0],
		["enemy_base", Vector3(76, 0, -70), 32.0, 60.0],
		["defensive_walls", Vector3(-78, 0, 62), 24.0, 90.0],
		["combat", Vector3(0, 0, 0), 40.0, 200.0],
	]
	await _run()
	get_tree().quit()

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	var err: int = image.save_png(path)
	print("SHOT| %-24s %s (%dx%d)" % [
		name, "ok" if err == OK else "FAIL %d" % err, image.get_width(), image.get_height()])

func _run() -> void:
	var elapsed: float = 0.0
	for stop in _stops:
		var target_time: float = stop[3]
		while elapsed < target_time:
			elapsed += get_process_delta_time()
			await get_tree().process_frame
		if _camera != null:
			if _camera.has_method("focus_on"):
				_camera.focus_on(stop[1])
			if "zoom_distance" in _camera:
				_camera.zoom_distance = stop[2]
		var settle: float = 0.0
		while settle < SETTLE:
			settle += get_process_delta_time()
			elapsed += get_process_delta_time()
			await get_tree().process_frame
		await _shoot(stop[0])
	print("SHOT| done")
