extends Node

## Where the draw calls actually come from.
##
## The Android benchmark reported ~3,059 draw calls in a land battle, and
## a number that size decides whether this runs on a phone: a mobile
## driver charges far more per call than a desktop one. Guessing which
## system owns them is worthless, so this turns each one off in turn and
## measures what the frame costs without it.
##
## Deltas, not absolutes: the renderer culls and batches, so a category's
## real cost is what disappears when it does.

const MIX := [
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/assault_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
	"res://config/units/artillery_vehicle.tres",
]
const SETTLE: float = 1.5
const SAMPLE: float = 2.5

var _main: Node3D
var _hud: Node
var _units: Array = []

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = get_parent()
	await get_tree().process_frame
	_hud = _main.get_node_or_null("HUD")
	if _hud and _hud.has_method("_begin_match"):
		_hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	GameState.add_credits(90000)
	for i in 30:
		await get_tree().physics_frame

	## Scenario B: 60 units in contact, the benchmark's worst draw case.
	var base: Vector3 = _main.map.player_base
	for i in 30:
		var lane: float = -18.0 + float(i % 15) * 2.6
		_units.append(_spawn(MIX[i % MIX.size()], true, base + Vector3(-14, 0, lane)))
		_units.append(_spawn(MIX[(i + 2) % MIX.size()], false, base + Vector3(14, 0, lane)))
	var cam = get_tree().get_first_node_in_group("rts_camera")
	cam.focus_on(base)
	cam.zoom_distance = 30.0
	cam.snap()
	await _wait(4.0)

	var base_draws: float = await _measure()
	print("AUDIT| baseline                         %6.0f draws  %8.0f tris  %d units" % [
		base_draws, _tris(), _units.size()])

	## --- each category, measured by its absence ---
	await _category("UI (whole HUD)", func(t): _hud.visible = not t)
	await _category("health bars", func(t): _toggle_group("health_bars", not t))
	await _category("selection rings", func(t): _toggle_rings(not t))
	await _category("unit models", func(t): _toggle_models(not t))
	await _category("scenery props", func(t): _toggle_scenery(not t))
	await _category("shadows (all casters)", func(t): _toggle_shadows(not t))
	await _category("ground marks (scorch/ruts)", func(t): _toggle_node("GroundMarks", not t))

	print("AUDIT| DONE")
	get_tree().quit()

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame

func _measure() -> float:
	await _wait(SETTLE)
	var total: float = 0.0
	var n: int = 0
	var t: float = 0.0
	while t < SAMPLE:
		await get_tree().process_frame
		t += get_process_delta_time()
		total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	return total / maxf(float(n), 1.0)

func _tris() -> float:
	return Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

## Turn a category off, measure, turn it back on. The delta is its cost.
func _category(label: String, setter: Callable) -> void:
	var before: float = await _measure()
	setter.call(true)
	await _wait(0.4)
	var without: float = await _measure()
	setter.call(false)
	await _wait(0.4)
	print("AUDIT| %-32s %6.0f draws  (%.0f%% of frame)" % [
		label, before - without, (before - without) / maxf(before, 1.0) * 100.0])

func _spawn(path: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	return u

func _toggle_group(group: String, on: bool) -> void:
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D:
			(n as Node3D).visible = on

func _toggle_rings(on: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get("selection_ring") != null:
			(u.selection_ring as Node3D).visible = on and u.get("_ring_wanted") == true

func _toggle_models(on: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get("_model") != null:
			(u._model as Node3D).visible = on

func _toggle_scenery(on: bool) -> void:
	var level := _main.get_node_or_null("Level")
	if level == null:
		return
	for child in level.get_children():
		if child is Node3D and String(child.name).begins_with("Scenery"):
			(child as Node3D).visible = on
	for n in get_tree().get_nodes_in_group("scenery"):
		if n is Node3D:
			(n as Node3D).visible = on

func _toggle_shadows(on: bool) -> void:
	for n in _all_visuals(get_tree().current_scene):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _toggle_node(name: String, on: bool) -> void:
	var n = get_tree().current_scene.find_child(name, true, false)
	if n is Node3D:
		(n as Node3D).visible = on

func _all_visuals(root: Node) -> Array:
	var out: Array = []
	if root is GeometryInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_visuals(c))
	return out
