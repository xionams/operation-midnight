extends Node

## Photographs the setup screen and each map's opening, for review.

const MAPS: Array[String] = [
	"res://config/maps/ridgeline.tres",
	"res://config/maps/dry_basin.tres",
	"res://config/maps/cold_corridor.tres",
]

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var index: int = 0
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			index = arg.to_int()
	var wanted := load(MAPS[clampi(index, 0, MAPS.size() - 1)])

	if scene.map != wanted:
		GameState.selected_map = wanted
		GameState.skip_setup = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return

	var hud = scene.get_node_or_null("HUD")
	## Photograph the setup screen itself on the first map only.
	if index == 0 and hud != null and hud._setup_overlay != null:
		await _settle(1.0)
		await _shoot("setup_screen")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await _settle(6.0)
	var camera = scene.find_child("RTSCamera", true, false)
	if camera != null:
		camera.focus_on(Vector3((wanted.player_base.x + wanted.enemy_base.x) * 0.5,
			0, (wanted.player_base.z + wanted.enemy_base.z) * 0.5))
		camera.zoom_distance = 120.0
	## Disabling fog only stops it updating; the ground stays unexplored.
	## An overview shot needs the map actually revealed.
	for x in range(-5, 6):
		for z in range(-5, 6):
			FogOfWar.reveal_area(Vector3(x * 22.0, 0, z * 22.0), 26.0)
	FogOfWar.update_now()
	FogOfWar.enabled = false
	await _settle(2.0)
	await _shoot("map_" + wanted.display_name.to_lower().replace(" ", "_"))
	get_tree().quit()

func _settle(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/%s.png" % name)
	print("SHOT| %s" % name)
