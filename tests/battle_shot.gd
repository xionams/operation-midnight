extends Node

## Photographs a fight in progress: rounds in flight, damaged vehicles
## burning, and ground already marked by earlier hits. A still of a
## healthy line-up says nothing about whether combat reads.

const UNITS: Dictionary = {
	"tank": ["res://scenes/units/main_battle_tank.tscn",
		"res://config/units/main_battle_tank.tres"],
	"assault": ["res://scenes/units/assault_vehicle.tscn",
		"res://config/units/assault_vehicle.tres"],
	"rifle": ["res://scenes/units/rifle_soldier.tscn",
		"res://config/units/rifle_soldier.tres"],
}

var _main: Node3D

func _spawn(kind: String, is_player: bool, position: Vector3) -> Node:
	var entry: Array = UNITS[kind]
	return _main._spawn_unit(load(entry[0]), load(entry[1]), is_player, position)

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	var centre := Vector3(6, 0, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	## Earlier fighting, so the ground is not pristine.
	for i in 16:
		VFX.explosion_small(_main, centre + Vector3(
			rng.randf_range(-15, 15), 0, rng.randf_range(-10, 10)))

	## Two lines facing each other, most of them hurt.
	var ours: Array = []
	for i in 5:
		var unit := _spawn("tank" if i % 2 == 0 else "assault", true,
			centre + Vector3(-9 + i * 0.6, 0, 7 - i * 1.4))
		ours.append(unit)
	for i in 4:
		_spawn("tank" if i % 2 else "assault", false,
			centre + Vector3(7 - i * 0.7, 0, -6 + i * 1.5))
	for i in 3:
		_spawn("rifle", true, centre + Vector3(-12, 0, 2 + i * 1.3))

	await get_tree().physics_frame
	var hurt: int = 0
	for unit in get_tree().get_nodes_in_group("player_units") \
		+ get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.body_size.y < 1.2:
			continue
		var hp = unit.get_node_or_null("HealthComponent")
		if hp == null:
			continue
		hp.current_health = hp.max_health * [0.22, 0.45, 0.95][hurt % 3]
		hurt += 1
	print("BATTLE| vehicles staged: %d" % hurt)

	var camera := Camera3D.new()
	_main.add_child(camera)
	camera.global_position = centre + Vector3(0, 31, 30)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.fov = 55.0
	camera.current = true

	## Drive the line across the field first, so the ground carries ruts
	## as well as craters by the time the shutter opens.
	for unit in ours:
		if is_instance_valid(unit) and unit.has_method("move_to"):
			unit.move_to(centre + Vector3(rng.randf_range(4, 10), 0,
				rng.randf_range(-8, -2)))
	await _wait(6.0)

	## Fire a volley so streaks are mid-flight when the shutter opens.
	for unit in ours:
		if not is_instance_valid(unit):
			continue
		for child in unit.get_children():
			if child.has_method("_spawn_tracer"):
				child._spawn_tracer(unit.global_position + Vector3(0, 1.2, 0),
					centre + Vector3(rng.randf_range(2, 9), 1.0,
						rng.randf_range(-7, -1)))
	## Four frames: far enough for the streaks to have left their muzzles,
	## not so far that they have arrived.
	for i in 4:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://screenshots/battle.png")
	print("BATTLE| scorch: %d  ruts: %d" % [
		GroundMarks.count(GroundMarks.SCORCH),
		GroundMarks.count(GroundMarks.TRACK)])
	print("BATTLE| DONE")
	get_tree().quit()
