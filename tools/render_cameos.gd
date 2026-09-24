extends Node3D

## Renders a cameo per buildable item: a small picture of the actual model
## for the sidebar, the way Red Alert 2 does it.
##
## The sidebar used flat vector glyphs. A glyph tells you a category; a
## cameo tells you what you are about to build, and it is the thing a
## player learns to hit without reading. These are renders of the shipping
## models, so a cameo can never drift from what gets placed.
##
##     godot --path . tools/render_cameos.gd  (as a scene)

const SIZE: int = 192

func _ready() -> void:
	var viewport := get_viewport()
	viewport.transparent_bg = false

	## Lit harder and flatter than the battlefield. A cameo is read at
	## 48 pixels on a dark sidebar, so the model has to be bright and the
	## silhouette unambiguous - the game's own low sun would put half of
	## every structure in shadow.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -42, 0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = false
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14, 130, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.68, 0.78, 0.96)
	fill.shadow_enabled = false
	add_child(fill)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	## The sidebar plate colour, so a cameo sits in its frame rather than
	## floating on a rectangle of some other grey.
	env.background_color = Color(0.105, 0.120, 0.140)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.74)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.3
	env_node.environment = env
	add_child(env_node)

	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	var seen := {}
	var count: int = 0
	for category in BuildCatalog.categories():
		for stats in BuildCatalog.items(category):
			if stats == null or stats.visual_scene == null:
				continue
			var id: String = stats.visual_scene.resource_path.get_file().get_basename()
			if seen.has(id):
				continue
			seen[id] = true
			await _shoot(camera, stats, id)
			count += 1
	print("CAMEO| %d rendered" % count)
	get_tree().quit()

func _shoot(camera: Camera3D, stats, id: String) -> void:
	var node: Node3D = stats.visual_scene.instantiate()
	add_child(node)
	FactionPaint.apply(node, FactionPaint.color_for(true))

	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = mesh.mesh.get_aabb()
		part.position += mesh.position
		if first:
			box = part
			first = false
		else:
			box = box.merge(part)

	var reach: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var centre: Vector3 = box.position + box.size * 0.5
	## Three-quarter and slightly above: shows the flank silhouette and the
	## roof faction marking at once, which is how the unit will actually be
	## seen in play.
	var dir := Vector3(0.58, 0.52, 0.80).normalized()
	camera.position = centre + dir * (reach * 1.72 + 0.9)
	camera.look_at(centre, Vector3.UP)
	camera.fov = 42.0

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	## Square crop from the centre of the frame, then down to cameo size.
	var side: int = mini(image.get_width(), image.get_height())
	image.blit_rect(image, Rect2i(
		(image.get_width() - side) / 2, (image.get_height() - side) / 2,
		side, side), Vector2i.ZERO)
	image.crop(side, side)
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	image.save_png("res://assets/cameos/%s.png" % id)
	print("CAMEO| %s" % id)
	node.queue_free()
	await get_tree().process_frame
