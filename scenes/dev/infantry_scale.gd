extends Node

## How infantry scale. They are the unit type that appears in numbers,
## every one carries a jointed rig posed in script each frame, and the
## Phase 4 animation work must not be what stops a battle being playable.

const SOLDIER := "res://config/units/rifle_soldier.tres"
const TANK := "res://config/units/assault_vehicle.tres"

var _main: Node3D

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"): hud._begin_match()
	await get_tree().process_frame
	var d = _main.get_node_or_null("AIDirector")
	if d != null: d.enabled = false
	FogOfWar.enabled = false
	for i in 30: await get_tree().physics_frame

	print("SCALE| %-22s %7s %7s %9s %8s %8s" % ["case", "fps", "draws", "tris", "nodes", "anim"])
	await _case("20 infantry", 20, 0)
	await _case("60 infantry", 60, 0)
	await _case("120 infantry", 120, 0)
	await _case("60 inf + 30 vehicles", 60, 30)
	print("SCALE| DONE")
	get_tree().quit()

func _case(label: String, infantry: int, vehicles: int) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u): u.queue_free()
	await _wait(1.0)
	var base: Vector3 = _main.map.player_base
	for i in infantry:
		_spawn(SOLDIER, base + Vector3(-16.0 + (i % 16) * 2.0, 0, -10.0 + (i / 16) * 2.0))
	for i in vehicles:
		_spawn(TANK, base + Vector3(-16.0 + (i % 10) * 3.0, 0, 12.0 + (i / 10) * 3.0))
	var cam = get_tree().get_first_node_in_group("rts_camera")
	cam.focus_on(base); cam.zoom_distance = 32.0; cam.snap()
	await _wait(3.0)
	var frames := 0
	var t := 0.0
	var draws := 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time(); frames += 1
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var animated := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get_node_or_null("InfantryAnimator") != null:
			animated += 1
	print("SCALE| %-22s %7.1f %7.0f %9.0f %8d %8d" % [label, float(frames) / t,
		draws / float(frames),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), animated])

func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		t += get_process_delta_time(); await get_tree().process_frame

func _spawn(path: String, pos: Vector3) -> void:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats; u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
