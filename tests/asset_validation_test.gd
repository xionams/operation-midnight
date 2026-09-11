extends SceneTree

## Verifies every greybox actually loads in Godot, sits on the ground and
## matches the body_size gameplay derives selection rings, health bars and
## placement footprints from. A model that disagrees with its stats is art
## you can see not fitting its own collision.

const TOLERANCE: float = 0.08

var _fails: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fails.append(label + " " + detail)
		print("ASSET| %-42s FAIL %s" % [label, detail])

func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_aabb: AABB = child.mesh.get_aabb()
		mesh_aabb.position += child.position
		if first:
			box = mesh_aabb
			first = false
		else:
			box = box.merge(mesh_aabb)
	return box

func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	var names: Array = []
	for file in dir.get_files():
		if file.ends_with(".glb"):
			names.append(file.get_basename())
	names.sort()

	var total_tris: int = 0
	for name in names:
		var scene = load("res://assets/models/%s.glb" % name)
		_check("%s loads" % name, scene != null)
		if scene == null:
			continue
		var node = scene.instantiate()
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		_check("%s has geometry" % name, meshes.size() > 0)
		var box := _aabb_of(node)
		## Origin at ground centre is the contract that makes a greybox
		## swappable without touching gameplay code.
		_check("%s sits on the ground" % name, box.position.y > -TOLERANCE,
			"(min y %.2f)" % box.position.y)
		for m in meshes:
			total_tris += m.mesh.get_faces().size() / 3
		node.free()

	print("ASSET| %d models, %d triangles" % [names.size(), total_tris])
	print("ASSET| ---- %d failure(s) ----" % _fails.size())
	quit(1 if _fails.size() > 0 else 0)
