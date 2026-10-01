extends Node

## The soldier from the side, in each pose, so a gait can actually be
## judged. Gameplay zoom looks almost straight down and hides exactly the
## rotation a walk cycle lives in.

const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const DOG := preload("res://config/units/attack_dog.tres")

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"): hud._begin_match()
	await get_tree().process_frame
	if hud: hud.visible = false
	FogOfWar.enabled = false
	var d = main.get_node_or_null("AIDirector")
	if d: d.enabled = false
	for i in 20: await get_tree().physics_frame

	var base: Vector3 = main.map.player_base + Vector3(0, 0, 20)
	var walker = _spawn(SOLDIER, base + Vector3(-3, 0, 0))
	var croucher = _spawn(SOLDIER, base + Vector3(0, 0, 0))
	var dog = _spawn(DOG, base + Vector3(3, 0, 0))
	InfantryStance.of(croucher).set_mode(InfantryStance.Mode.CROUCH)
	await _wait(0.5)
	for u in [walker, croucher, dog]:
		u.move_to(u.global_position + Vector3(0, 0, -40))

	## A low side-on camera: the RTS rig looks down too steeply.
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.global_position = base + Vector3(0, 1.4, 7.0)
	cam.look_at(base + Vector3(0, 0.9, 0), Vector3.UP)
	cam.fov = 38.0
	cam.make_current()

	for i in 4:
		await _wait(0.42)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://screenshots/poses_%d.png" % i)
		print("POSE| frame %d" % i)
	print("POSE| DONE")
	get_tree().quit()

func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		t += get_process_delta_time(); await get_tree().process_frame

func _spawn(stats, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats; u.is_player_faction = true
	get_parent().get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	return u
