extends Node3D

## Free rigged soldier candidates, one render each.
##
## Laying them out in a single row and normalising by AABB failed: some
## packs ship a weapon or a prop far from the body, so the bounds are
## huge, the body scales to nothing and whatever is left fills the lens.
## One at a time, each framed on its own bounds, is immune to that.

const TARGET_H: float = 1.8

var _cam: Camera3D

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -38, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.19, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env_node.environment = env
	add_child(env_node)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.33, 0.28)
	ground.material_override = gm
	add_child(ground)

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 42.0
	_cam.current = true

	var dir := DirAccess.open("res://assets/models/_candidates")
	var files: Array = []
	if dir:
		for f in dir.get_files():
			if f.ends_with(".glb"):
				files.append("res://assets/models/_candidates/" + f)
	files.sort()
	files.append("res://assets/models/units/rifle_soldier.glb")

	for path in files:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate()
		add_child(inst)
		for i in 3:
			await get_tree().process_frame
		var box: AABB = _bounds(inst)
		if box.size.y < 0.2:
			print("CAND| %-42s unusable bounds - skipped" % path.get_file())
			inst.queue_free()
			continue
		var k: float = TARGET_H / box.size.y
		inst.scale = Vector3(k, k, k)
		inst.position = Vector3(-box.get_center().x * k, -box.position.y * k,
			-box.get_center().z * k)
		_cam.position = Vector3(0, 1.0, 3.4)
		_cam.look_at(Vector3(0, 0.92, 0), Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tag: String = path.get_file().replace(".glb", "")
		get_viewport().get_texture().get_image().save_png(
			"res://screenshots/cand_%s.png" % tag)
		print("CAND| %-42s %5.2fm raw  x%.2f" % [path.get_file(), box.size.y, k])
		inst.queue_free()
		await get_tree().process_frame

	print("CAND| DONE")
	get_tree().quit()

## Bounds in the INSTANCE's own space, from the whole transform chain.
func _bounds(root: Node3D) -> AABB:
	var to_local: Transform3D = root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var v := n as VisualInstance3D
		var b: AABB = (to_local * v.global_transform) * v.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
