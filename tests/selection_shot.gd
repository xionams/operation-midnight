extends Node

## Photographs selection and health readout together: a selected group,
## a damaged unit, and a harvester, which rings amber.

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	var centre: Vector3 = main.map.player_base + Vector3(0, 0, 24)
	var specs := [
		["res://scenes/units/main_battle_tank.tscn", "res://config/units/main_battle_tank.tres", 1.0],
		["res://scenes/units/main_battle_tank.tscn", "res://config/units/main_battle_tank.tres", 0.55],
		["res://scenes/units/assault_vehicle.tscn", "res://config/units/assault_vehicle.tres", 0.22],
		["res://scenes/units/harvester.tscn", "res://config/units/harvester.tres", 0.8],
		["res://scenes/units/rifle_soldier.tscn", "res://config/units/rifle_soldier.tres", 0.45],
	]
	var made: Array = []
	for i in specs.size():
		var spec = specs[i]
		var unit = main._spawn_unit(load(spec[0]), load(spec[1]), true,
			centre + Vector3(-7.0 + i * 3.5, 0, 0))
		made.append(unit)
	await get_tree().physics_frame
	for i in made.size():
		var unit = made[i]
		if not is_instance_valid(unit):
			continue
		var hp = unit.get_node_or_null("HealthComponent")
		if hp: hp.take_damage(hp.max_health * (1.0 - specs[i][2]))
		if unit.selection_ring: unit.selection_ring.visible = true
		if unit.health_bar: unit.health_bar.set_selected(true)

	var camera := Camera3D.new()
	main.add_child(camera)
	camera.global_position = centre + Vector3(0, 9.5, 11.0)
	camera.look_at(centre + Vector3(0, 0.8, 0), Vector3.UP)
	camera.fov = 46.0
	camera.current = true
	## Long enough for the intro overlay to fade; it is built when the
	## match begins and runs for a few seconds.
	var elapsed: float = 0.0
	while elapsed < 4.5:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/selection.png")
	print("SELECT| DONE")
	get_tree().quit()
