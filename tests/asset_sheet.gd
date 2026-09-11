extends Node3D

## Lays every greybox out on a lit turntable and photographs the lot.
##
## A contact sheet is the only honest way to review an art pass: a test
## can say a model loaded, but only looking at it says whether the
## silhouette reads, the pivot is right and the faction band is visible.

const SPACING: float = 11.0
const COLUMNS: int = 6

func _ready() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(220, 220)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.24, 0.26, 0.24)
	ground.material_override = ground_material
	add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	add_child(sun)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.09, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.45)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)

	var dir := DirAccess.open("res://assets/models")
	var names: Array = []
	for file in dir.get_files():
		if file.ends_with(".glb"):
			names.append(file.get_basename())
	names.sort()

	var index: int = 0
	for name in names:
		var scene = load("res://assets/models/%s.glb" % name)
		if scene == null:
			continue
		var node = scene.instantiate()
		add_child(node)
		var column: int = index % COLUMNS
		var row: int = index / COLUMNS
		node.position = Vector3(
			(column - (COLUMNS - 1) / 2.0) * SPACING, 0, (row - 3.0) * SPACING)
		## Half the sheet wears player blue and half enemy red, so the
		## faction slot is proven to repaint rather than assumed.
		FactionPaint.apply(node, FactionPaint.color_for(index % 2 == 0))
		var label := Label3D.new()
		label.text = name
		label.font_size = 96
		label.pixel_size = 0.006
		label.position = Vector3(0, -0.3, SPACING * 0.42)
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.modulate = Color(0.9, 0.9, 0.85)
		node.add_child(label)
		index += 1

	var camera := Camera3D.new()
	camera.position = Vector3(0, 38, 34)
	camera.rotation_degrees = Vector3(-42, 0, 0)
	camera.fov = 55.0
	add_child(camera)
	camera.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://screenshots/asset_sheet.png")
	print("SHEET| %d models rendered" % index)
	get_tree().quit()
