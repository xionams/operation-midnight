extends Node

## Does the game LOOK right? Measured, not judged by eye.
##
## Two phases were spent driving draw calls, triangles and bone counts
## down. Every one of those numbers is blind to the image, so the game
## got cheaper while it rendered flat grey mud and nothing in the loop
## noticed. This is the missing meter.
##
## It renders fixed reference shots and reports what is actually in the
## frame. The battlefield area only - the HUD is a fixed dark slab and
## would drag every statistic toward black.
##
##     godot --path . scenes/dev/image_probe.tscn

const HUD_LEFT: int = 975

var _main: Node3D
var _cam: Camera3D

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"): hud._begin_match()
	await get_tree().process_frame
	## Measure the rendered WORLD. The HUD is a fixed dark slab and would
	## drag every statistic toward black whatever the battlefield does.
	if hud: hud.visible = false
	var d = _main.get_node_or_null("AIDirector")
	if d: d.enabled = false
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, FogOfWar.get_map_size())
	GameState.add_credits(90000)
	for i in 20: await get_tree().physics_frame

	var base: Vector3 = _main.map.player_base
	_cam = Camera3D.new()
	_main.add_child(_cam)
	_cam.fov = 50.0
	_cam.make_current()
	## The first frame after make_current() is still the old camera's, and
	## capturing it reports a black shot that looks like a broken scene.
	for i in 10:
		await get_tree().process_frame

	await _shot("base", base, 30.0)

	## Armour and infantry on open ground, plus wrecks, which are the
	## darkest thing the game draws and the easiest to crush to black.
	var field: Vector3 = base + Vector3(26, 0, -20)
	for i in 5:
		_unit("res://scenes/units/main_battle_tank.tscn",
			"res://config/units/main_battle_tank.tres", true,
			field + Vector3(-6 + i * 3.0, 0, 3))
		_unit("res://scenes/units/rifle_soldier.tscn",
			"res://config/units/rifle_soldier.tres", true,
			field + Vector3(-5 + i * 2.4, 0, 7))
	## The ACTUAL vehicle wrecks, not the generic ruin: these are the
	## darkest thing the game draws and the easiest to crush to black.
	for i in 3:
		Wreckage.spawn(_main, field + Vector3(-6 + i * 4.0, 0, -5), 0.0,
			load("res://assets/models/props/vehicle_wreck_heavy.glb"), 1.0)
		Wreckage.spawn(_main, field + Vector3(-4 + i * 4.0, 0, -9), 0.0,
			load("res://assets/models/props/vehicle_wreck_light.glb"), 1.0)
	await _wait(1.5)
	await _shot("field", field, 26.0)

	_wreck_stats()
	print("PROBE| DONE")
	get_tree().quit()

# ------------------------------------------------------------ measuring

func _shot(name: String, at: Vector3, height: float) -> void:
	_cam.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z) + height,
		at.z + height * 0.9)
	_cam.look_at(Vector3(at.x, Terrain.height_at(at.x, at.z), at.z), Vector3.UP)
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/probe_%s.png" % name)
	_report(name, img)

func _report(name: String, img: Image) -> void:
	var lum: Array = []
	var sat_total: float = 0.0
	var n: int = 0
	var w: int = mini(HUD_LEFT, img.get_width())
	for y in range(0, img.get_height(), 2):
		for x in range(0, w, 2):
			var c: Color = img.get_pixel(x, y)
			lum.append(c.get_luminance())
			var hi: float = maxf(c.r, maxf(c.g, c.b))
			var lo: float = minf(c.r, minf(c.g, c.b))
			sat_total += 0.0 if hi <= 0.0 else (hi - lo) / hi
			n += 1
	lum.sort()
	var black: int = 0
	var bright: int = 0
	for v in lum:
		if v < 0.02:
			black += 1
		if v > 0.75:
			bright += 1
	print("PROBE| %-6s p5=%.3f p50=%.3f p95=%.3f range=%.3f  crushed=%.1f%%  highlights=%.1f%%  sat=%.3f" % [
		name, _at(lum, 0.05), _at(lum, 0.50), _at(lum, 0.95),
		_at(lum, 0.95) - _at(lum, 0.05),
		100.0 * black / n, 100.0 * bright / n, sat_total / n])

func _at(sorted: Array, q: float) -> float:
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]

# ------------------------------------------------------------- staging

func _unit(scene: String, stats: String, player: bool, at: Vector3) -> void:
	_main._spawn_unit(load(scene), load(stats), player, at)

func _wait(s: float) -> void:
	var t: float = 0.0
	while t < s:
		t += get_process_delta_time()
		await get_tree().process_frame


## What luminance the wrecks actually land on. Authored as SOOT 0.105
## sRGB, so anything near zero means the colour is being crushed on its
## way to the screen rather than painted dark on purpose.
func _wreck_stats() -> void:
	var cam := get_viewport().get_camera_3d()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var lum: Array = []
	for w in get_tree().get_nodes_in_group("wreckage"):
		var at: Vector2 = cam.unproject_position((w as Node3D).global_position)
		for dx in range(-14, 15, 4):
			for dy in range(-10, 11, 4):
				var x: int = int(at.x) + dx
				var y: int = int(at.y) + dy
				if x < 0 or y < 0 or x >= 975 or y >= img.get_height():
					continue
				lum.append(img.get_pixel(x, y).get_luminance())
	if lum.is_empty():
		print("PROBE| wrecks  not on screen")
		return
	lum.sort()
	print("PROBE| wrecks  n=%d  p10=%.3f median=%.3f p90=%.3f  (SOOT albedo is 0.105)" % [
		lum.size(), lum[lum.size() / 10], lum[lum.size() / 2],
		lum[lum.size() * 9 / 10]])
