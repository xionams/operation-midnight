extends Node

## The benchmark that has to be run on a real phone before anyone claims
## this game runs on one.
##
##   godot res://tests/android_benchmark.tscn        (desktop baseline)
##
## On a device, install the APK and read the same lines back over adb:
##
##   adb logcat -s godot | grep BENCH
##   adb shell run-as <package> cat files/benchmark.txt
##
## Every number is also written to user://benchmark.txt, because logcat
## on a phone drops lines under load - which is exactly when the numbers
## matter.
##
## VSync off and the FPS cap removed on purpose: at a 60 cap every build
## and every device looks identical and the benchmark measures nothing.
## Desktop numbers here are a BASELINE to compare a device against, not a
## prediction of it - a phone's fill rate and memory bandwidth are the
## limits that actually bite, and neither shows up on a desktop GPU.

const SETTLE: float = 2.5
const SAMPLE: float = 7.0

const LAND_MIX := [
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/assault_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
	"res://config/units/artillery_vehicle.tres",
]
const SEA_MIX := [
	"res://config/units/patrol_boat.tres",
	"res://config/units/submarine.tres",
]

var _main: Node3D
var _report: Array = []

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
	GameState.add_credits(90000)
	for i in 40:
		await get_tree().physics_frame

	_say("BENCH| device=%s renderer=%s cpu=%s" % [
		OS.get_model_name(), RenderingServer.get_video_adapter_name(),
		OS.get_processor_name()])
	_say("BENCH| %-26s %7s %7s %7s %9s %8s %8s" % [
		"scenario", "fps", "1%low", "draws", "tris", "nodes", "vram_mb"])

	await _scenario_a_idle_base()
	await _scenario_b_land_battle()
	await _scenario_c_coastal()
	await _scenario_d_effects_storm()
	await _scenario_e_wide_view()

	var text: String = "\n".join(_report) + "\n"
	var file := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
		_say("BENCH| written to %s" % ProjectSettings.globalize_path("user://benchmark.txt"))
	_say("BENCH| DONE")
	GameState.selected_map = null
	get_tree().quit()

func _say(line: String) -> void:
	print(line)
	_report.append(line)

func _cam():
	return get_tree().get_first_node_in_group("rts_camera")

func _spawn(path: String, player: bool, at: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = at
	return u

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame

# ------------------------------------------------------------ scenarios

## A: the floor. A base at rest with nothing happening - anything this
## costs is paid in every other scenario too.
func _scenario_a_idle_base() -> void:
	_cam().focus_on(COAST_BASE)
	_cam().zoom_distance = 26.0
	_cam().snap()
	await _measure("A idle base")

## B: the common case - a land engagement at fighting zoom.
func _scenario_b_land_battle() -> void:
	var base: Vector3 = COAST_BASE
	for i in 30:
		var lane: float = -18.0 + float(i % 15) * 2.6
		_spawn(LAND_MIX[i % LAND_MIX.size()], true, base + Vector3(-14, 0, lane))
		_spawn(LAND_MIX[(i + 2) % LAND_MIX.size()], false, base + Vector3(14, 0, lane))
	await _wait(3.0)
	_cam().focus_on(base)
	_cam().zoom_distance = 30.0
	_cam().snap()
	await _measure("B land battle 60")

## C: the coast, which is the most expensive thing the game draws - see
## through water, a shoreline, hulls and wakes all in one frame.
func _scenario_c_coastal() -> void:
	var sea: Vector3 = Water.nearest_water(COAST_BASE + Vector3(0, 0, 66), 150.0)
	for i in 10:
		var offset := Vector3(float(i % 5) * 5.0 - 10.0, 0, float(i / 5) * 6.0)
		_spawn(SEA_MIX[i % SEA_MIX.size()], i % 2 == 0,
			Vector3(sea.x + offset.x, Water.level, sea.z + offset.z))
	await _wait(3.0)
	_cam().focus_on(sea)
	_cam().zoom_distance = 30.0
	_cam().snap()
	await _measure("C coastal fleet")

## D: the worst honest case - everything shooting, buildings burning,
## wrecks and corpses on the ground. This is what Phase 4 added, and the
## scenario that has to be watched on a device.
func _scenario_d_effects_storm() -> void:
	var base: Vector3 = COAST_BASE
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.health != null:
			b.health.take_damage(b.health.max_health * 0.75)
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.health != null:
			u.health.take_damage(u.health.max_health * 0.55)
	await _wait(2.0)
	_cam().focus_on(base)
	_cam().zoom_distance = 28.0
	_cam().snap()
	await _measure("D effects storm")

## E: pulled back as far as the camera allows, which is where draw calls
## and triangle count peak even though nothing is close enough to see.
func _scenario_e_wide_view() -> void:
	_cam().focus_on(COAST_BASE + Vector3(0, 0, 24))
	_cam().zoom_distance = _cam().max_zoom
	_cam().snap()
	await _measure("E max zoom out")

const COAST_BASE := Vector3(-78, 0, -20)

# ------------------------------------------------------------- measure

func _measure(label: String) -> void:
	await _wait(SETTLE)
	var frames: Array = []
	var draws: float = 0.0
	var prims: float = 0.0
	var t: float = 0.0
	while t < SAMPLE:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		frames.append(dt)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	frames.sort()
	var n: int = frames.size()
	## The 1% low, not the worst single frame: one stall while a shader
	## compiles says nothing about how the scene actually runs.
	var low: float = frames[int(n * 0.99)]
	_say("BENCH| %-26s %7.1f %7.1f %7.0f %9.0f %8d %8.1f" % [
		label, float(n) / t, 1.0 / low, draws / n, prims / n,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
