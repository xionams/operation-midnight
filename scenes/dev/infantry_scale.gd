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

	print("SCALE| %-20s %6s %7s %7s %7s %9s %7s %6s" % [
		"case", "fps", "draws", "inf", "shadow", "tris", "nodes", "meshes"])
	await _case("20 infantry", 20, 0)
	await _case("60 infantry", 60, 0)
	await _case("120 infantry", 120, 0)
	await _case("200 infantry", 200, 0)
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
	var total: float = draws / float(frames)

	## Infantry's own cost, main pass and shadow pass separately: every
	## surface is drawn again into the shadow map, so a rig that is
	## expensive to draw is expensive twice.
	_set_infantry_shadows(false)
	await _wait(0.6)
	var no_shadow: float = await _sample(1.5)
	_set_infantry(false)
	await _wait(0.6)
	var without: float = await _sample(1.5)
	_set_infantry(true)
	_set_infantry_shadows(true)
	await _wait(0.4)

	var meshes := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.stats != null and u.stats.is_infantry:
			meshes += _count_meshes(u)
	print("SCALE| %-20s %6.1f %7.0f %7.0f %7.0f %9.0f %7d %6d" % [
		label, float(frames) / t, total, total - without, total - no_shadow,
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), meshes])

func _sample(seconds: float) -> float:
	var t := 0.0
	var n := 0
	var d := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time(); n += 1
		d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return d / maxf(float(n), 1.0)

func _set_infantry(on: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.stats != null and u.stats.is_infantry \
			and u.get("_model") != null:
			(u._model as Node3D).visible = on

func _set_infantry_shadows(on: bool) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.stats == null or not u.stats.is_infantry:
			continue
		for n in _visuals(u):
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _visuals(root: Node) -> Array:
	var out: Array = []
	if root is GeometryInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_visuals(c))
	return out

func _count_meshes(root: Node) -> int:
	var n := 0
	if root is MeshInstance3D:
		n += 1
	for c in root.get_children():
		n += _count_meshes(c)
	return n

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
