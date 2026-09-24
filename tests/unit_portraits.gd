extends Node3D

## One framed portrait per unit, for the roster artifact. Each model is
## shot on its own so the card shows the unit rather than a crop of a
## contact sheet, and every shot uses the same light and camera so the
## roster can be compared like for like.

const IDS: Array = [
	"scout_vehicle", "assault_vehicle", "main_battle_tank",
	"artillery_vehicle", "harvester",
	"rifle_soldier", "at_squad", "engineer", "spy", "attack_dog",
]

func _ready() -> void:
	get_viewport().transparent_bg = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = false
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 140, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.72, 0.80, 0.95)
	fill.shadow_enabled = false
	add_child(fill)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.25
	env_node.environment = env
	add_child(env_node)

	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	for id in IDS:
		var scene = load("res://assets/models/%s.glb" % id)
		if scene == null:
			print("PORTRAIT| missing ", id)
			continue
		var node: Node3D = scene.instantiate()
		add_child(node)
		FactionPaint.apply(node, FactionPaint.color_for(true))

		## Frame each unit to its own size, so a soldier is not a speck
		## beside a tank. The roster carries the real metres in text.
		var aabb := AABB()
		var first := true
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.mesh.get_aabb()
			box.position += mi.position
			if first:
				aabb = box
				first = false
			else:
				aabb = aabb.merge(box)
		var reach: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var centre: Vector3 = aabb.position + aabb.size * 0.5
		## Three-quarter view: shows the flank silhouette and the roof
		## faction marking at once, which top-down alone does not.
		var dir := Vector3(0.62, 0.55, 0.78).normalized()
		camera.position = centre + dir * (reach * 2.05 + 1.0)
		camera.look_at(centre, Vector3.UP)
		camera.fov = 40.0

		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("res://screenshots/portraits/%s.png" % id)
		print("PORTRAIT| %s" % id)
		node.queue_free()
		await get_tree().process_frame

	print("PORTRAIT| DONE")
	get_tree().quit()
