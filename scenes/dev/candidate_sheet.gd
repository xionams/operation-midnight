extends Node3D

## Free rigged soldier candidates, side by side with ours, all scaled to
## the same height so the comparison is about the MODEL and not about
## whatever units each pack happened to be authored in.

const CANDIDATES := [
	"res://assets/models/_candidates/quat_soldier.glb",
	"res://assets/models/_candidates/quat_swat.glb",
	"res://assets/models/_candidates/madtroll_military.glb",
	"res://assets/models/_candidates/jtoastie_soldier.glb",
	"res://assets/models/_candidates/kolos_soldier.glb",
	"res://assets/models/units/rifle_soldier.glb",
]
const TARGET_H: float = 1.8

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
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.33, 0.28)
	ground.material_override = gm
	add_child(ground)

	var x: float = -3.6
	for path in CANDIDATES:
		var scene: PackedScene = load(path)
		if scene == null:
			push_warning("missing %s" % path)
			continue
		var inst: Node3D = scene.instantiate()
		add_child(inst)
		for i in 2:
			await get_tree().process_frame
		var box: AABB = _bounds(inst)
		## A Mixamo-rigged export reports a near-zero bind AABB; skip it
		## rather than scale it by two thousand.
		if box.size.y < 0.2:
			print("CAND| %-26s unusable bounds (%.3fm) - skipped" % [
				path.get_file(), box.size.y])
			inst.queue_free()
			continue
		var k: float = TARGET_H / maxf(box.size.y, 0.001)
		inst.scale = Vector3(k, k, k)
		## Sit on the floor and centre horizontally, whatever origin the
		## pack used.
		inst.position = Vector3(x - box.get_center().x * k,
			-box.position.y * k, -box.get_center().z * k)
		print("CAND| %-26s %5.2fm raw  x%.2f" % [
			path.get_file(), box.size.y, k])
		x += 1.5

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.30, 7.4)
	cam.look_at(Vector3(0, 0.92, 0), Vector3.UP)
	cam.fov = 46.0
	cam.current = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://screenshots/candidates.png")
	print("CAND| DONE")
	get_tree().quit()

## Bounds in the INSTANCE's own space. Using each visual's local
## transform instead of the whole chain to the root reported half these
## packs as six centimetres tall.
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
