extends Node

## Photographs infantry mid-stride: a running rank and a crouched rank,
## so the two postures can be compared by eye.

const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const AT := preload("res://config/units/at_squad.tres")
const ENGINEER := preload("res://config/units/engineer.tres")
const SPY := preload("res://config/units/spy.tres")
const DOG := preload("res://config/units/attack_dog.tres")

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	## The intro card fades over the first few seconds and would dim the
	## whole frame; wait it out rather than photograph through it.
	var wait: float = 0.0
	while wait < 7.0:
		wait += get_process_delta_time()
		await get_tree().process_frame

	var base: Vector3 = main.map.player_base + Vector3(0, 0, 16)
	var kinds := [SOLDIER, AT, ENGINEER, SPY, DOG]
	var walkers: Array = []
	for row in 2:
		for i in kinds.size():
			var stats = kinds[i]
			var u = stats.unit_scene.instantiate()
			u.stats = stats
			u.is_player_faction = true
			main.get_node("Level").add_child(u)
			var p := base + Vector3(float(i) * 2.4 - 4.8, 0, float(row) * 4.0)
			u.global_position = Vector3(p.x, Terrain.height_at(p.x, p.z), p.z)
			if row == 1:
				var st = InfantryStance.of(u)
				if st != null:
					st.set_mode(InfantryStance.Mode.CROUCH)
			walkers.append(u)
	for i in 6:
		await get_tree().process_frame
	for u in walkers:
		u.move_to(u.global_position + Vector3(0, 0, -30))

	var cam = get_tree().get_first_node_in_group("rts_camera")
	cam.focus_on(base + Vector3(0, 0, -4))
	cam.zoom_distance = 14.0
	cam.snap()
	var t: float = 0.0
	while t < 2.2:
		t += get_process_delta_time()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/infantry_anim.png")
	print("SHOT| DONE")
	get_tree().quit()
