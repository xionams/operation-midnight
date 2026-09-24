extends Node3D

## Side by side: the generated soldier and the imported rigged one, both
## faction-painted, both at the scale the game uses.

var _phased: Array = []

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.3
	env_node.environment = env
	add_child(env_node)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.29, 0.40, 0.22)
	ground.material_override = gm
	add_child(ground)

	var specs := [
		["res://assets/models/rifle_soldier.glb", Vector3(-1.5, 0, 0), true, ""],
		["res://assets/models/_experiment/soldier.glb", Vector3(-0.3, 0, 0), true, "idle"],
		["res://assets/models/_experiment/soldier.glb", Vector3(0.9, 0, 0), true, "run"],
		["res://assets/models/_experiment/soldier.glb", Vector3(2.1, 0, 0), false, "run"],
	]
	print("PREVIEW| start")
	for spec in specs:
		print("PREVIEW| loading %s" % spec[0])
		var node: Node3D = load(spec[0]).instantiate()
		add_child(node)
		node.position = spec[1]
		node.rotation.y = PI
		FactionPaint.apply(node, FactionPaint.color_for(spec[2]))
		if spec[3] != "":
			var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
			if player != null and player.has_animation(spec[3]):
				player.play(spec[3])
				_phased.append([player, 0.15 + 0.18 * specs.find(spec)])
		print("PREVIEW| placed %s" % spec[0].get_file())

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.3, 1.5, 4.4)
	camera.look_at(Vector3(0.3, 0.85, 0), Vector3.UP)
	camera.fov = 40.0
	camera.current = true

	## Let the players enter the tree and start processing before seeking;
	## advancing on the same frame as play() does nothing.
	for i in 4:
		await get_tree().process_frame
	for entry in _phased:
		entry[0].seek(entry[1], true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/soldier_preview.png")
	print("PREVIEW| DONE")
	get_tree().quit()
