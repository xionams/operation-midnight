extends SceneTree
func _init():
	for n in ["command_hq", "power_plant", "main_battle_tank", "wall"]:
		var s = load("res://assets/models/%s.glb" % n)
		var node = s.instantiate()
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var a = mi.mesh.get_aabb()
			print("DBG| %s node=%s aabb pos=%s size=%s surfaces=%d" % [
				n, mi.name, a.position, a.size, mi.mesh.get_surface_count()])
			for i in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(i)
				print("DBG|    surf%d name=%s albedo=%s" % [
					i, m.resource_name if m else "none",
					(m as StandardMaterial3D).albedo_color if m is StandardMaterial3D else "?"])
	quit(0)
