extends Node

## Photographs the build sidebar with something actually in production, so
## the cameo and the grey-out can be reviewed together.

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	## Start a structure so one card is mid-build.
	var catalog = BuildCatalog.items("BUILDINGS")
	if hud.construction != null and catalog.size() > 1:
		hud.construction.start(catalog[1])
	var elapsed: float = 0.0
	while elapsed < 4.0:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/sidebar.png")
	print("SIDEBAR| DONE")
	get_tree().quit()
