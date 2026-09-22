extends Node

## Photographs the after-action report, which is the last thing a player
## sees and therefore worth actually looking at.

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	var elapsed: float = 0.0
	while elapsed < 200.0:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			b.get_node("HealthComponent").take_damage(999999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/after_action.png")
	print("SHOT| after_action")
	get_tree().quit()
