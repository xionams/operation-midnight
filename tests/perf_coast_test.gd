extends Node

## Frame cost of a busy coastal battle - land armies, fleets, submerged
## submarines, the sea and the shore all on screen - measured the same way
## on any revision so Phase 3's visual systems can be compared against the
## code before them. Uses only APIs both revisions have.
##
##   godot res://tests/perf_coast_test.tscn   -> PERF| lines
##
## VSync is off and the FPS cap removed: at the 60 cap every build looks
## the same. Reports mean FPS, the 1% worst frame, draw calls and
## primitives from the rendering server's own monitors.

const SETTLE: float = 3.0
const SAMPLE: float = 8.0

var _main: Node3D

func _ready() -> void:
	GameState.selected_map = load("res://config/maps/coastline.tres")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, 400.0)
	_stage()
	var cam = get_tree().get_first_node_in_group("rts_camera")
	cam.focus_on(Vector3(-20, 0, 26))
	cam.zoom_distance = cam.max_zoom
	await _measure("coast_battle_max_zoom")
	cam.zoom_distance = 24.0
	cam.focus_on(Vector3(-20, 0, 40))
	await _measure("naval_close")
	cam.zoom_distance = cam.max_zoom
	cam.focus_on(Vector3(-20, 0, -18))
	await _measure("land_battle")
	print("PERF| DONE")
	get_tree().quit()

func _spawn(path: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	var wet: bool = stats.movement_domain == PlacementDomain.Domain.WATER
	u.global_position = Vector3(pos.x, Water.level if wet else Terrain.height_at(pos.x, pos.z), pos.z)
	return u

func _stage() -> void:
	var land := ["rifle_soldier", "rifle_soldier", "at_squad", "main_battle_tank",
		"assault_vehicle", "scout_vehicle"]
	var armies: Array = [[], []]
	for side in 2:
		var player: bool = side == 0
		for i in 36:
			var id: String = land[i % land.size()]
			var x: float = (-40.0 if player else 0.0) + float(i % 6) * 3.0
			var z: float = -30.0 + float(i / 6) * 3.0
			armies[side].append(_spawn("res://config/units/%s.tres" % id, player, Vector3(x, 0, z)))
		for i in 6:
			armies[side].append(_spawn("res://config/units/patrol_boat.tres", player,
				Vector3((-40.0 if player else 0.0) + i * 5.0, 0, 44 + (i % 2) * 5)))
		for i in 2:
			armies[side].append(_spawn("res://config/units/submarine.tres", player,
				Vector3((-34.0 if player else -6.0) + i * 6.0, 0, 58)))
	for side in 2:
		for u in armies[side]:
			var toward: Vector3 = Vector3(10, 0, u.global_position.z) if side == 0 \
				else Vector3(-50, 0, u.global_position.z)
			u.issue_command(CommandTypes.Type.ATTACK_MOVE, toward)

func _measure(label: String) -> void:
	var t: float = 0.0
	while t < SETTLE:
		await get_tree().process_frame
		t += get_process_delta_time()
	var frames: Array = []
	var draws: float = 0.0
	var prims: float = 0.0
	t = 0.0
	while t < SAMPLE:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		frames.append(dt)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	frames.sort()
	var n: int = frames.size()
	var mean: float = t / float(n)
	var worst1: float = frames[int(n * 0.99)]
	print("PERF| %-22s fps %6.1f  1%%-low %6.1f  draws %5.0f  tris %8.0f  units %d" % [
		label, 1.0 / mean, 1.0 / worst1, draws / n, prims / n,
		get_tree().get_nodes_in_group("player_units").size() + get_tree().get_nodes_in_group("enemy_units").size()])
