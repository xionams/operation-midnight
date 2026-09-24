extends Node3D

## Is an animated, rigged soldier affordable at RTS unit counts?
##
## Kenney's CC0 character is 1,604 triangles and 58 bones against our
## generated soldier's 304 triangles and no rig at all. Triangles have
## never been what costs frames in this game - it is fill rate - but
## skeletal animation is CPU work per unit per frame, which is a
## different budget entirely and one nothing here has spent yet.
##
## Measured head to head, same count, same camera, same scene.

const COUNT: int = 120
const HEAVY: int = 360
const SECONDS: float = 6.0

const SKINNED: String = "res://assets/models/_experiment/character.glb"
const GENERATED: String = "res://assets/models/rifle_soldier.glb"

func _ready() -> void:
	## Both arms hit the 60 FPS vsync cap on the first run, which measured
	## nothing at all. This scene holds only the units under test, so the
	## cap has to come off for the comparison to say anything.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 1.0
	env_node.environment = env
	add_child(env_node)

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 26, 26)
	camera.rotation_degrees = Vector3(-42, 0, 0)
	camera.current = true

	for count in [COUNT, HEAVY]:
		var generated := await _measure(GENERATED, false, count)
		var skinned := await _measure(SKINNED, true, count)
		print("SKIN| %3d units | generated static %7.1f FPS | skinned+animated %7.1f FPS | %+.1f"
			% [count, generated, skinned, skinned - generated])
	print("SKIN| DONE")
	get_tree().quit()

func _measure(path: String, animate: bool, count: int) -> float:
	var holder := Node3D.new()
	add_child(holder)
	var scene = load(path)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var players: Array = []
	for i in count:
		var node: Node3D = scene.instantiate()
		holder.add_child(node)
		node.position = Vector3(rng.randf_range(-16, 16), 0.0, rng.randf_range(-11, 11))
		node.rotation.y = rng.randf_range(0.0, TAU)
		if animate:
			var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
			if player != null:
				var clip: String = "run" if player.has_animation("run") else \
					player.get_animation_list()[0]
				player.play(clip)
				## Offset each so they are not a drill squad in lockstep,
				## and so the sampling cost is spread across the frame.
				player.seek(rng.randf_range(0.0, 1.0), true)
				players.append(player)
	if animate:
		print("SKIN|   animation players: %d of %d" % [players.size(), count])

	## Warm up: first frames pay for shader compilation, not for the thing
	## being measured.
	for i in 30:
		await get_tree().process_frame

	var frames: int = 0
	var elapsed: float = 0.0
	while elapsed < SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		frames += 1
	holder.queue_free()
	await get_tree().process_frame
	return float(frames) / maxf(elapsed, 0.001)
