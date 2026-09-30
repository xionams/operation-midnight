extends Node
func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"): hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	for i in 40: await get_tree().physics_frame
	var counts := {}
	var multi := {}
	_walk(get_tree().current_scene, "", counts, multi)
	var rows := []
	for k in counts: rows.append([counts[k], k])
	rows.sort_custom(func(a,b): return a[0] > b[0])
	print("CENSUS| --- MeshInstance3D count by owner ---")
	for r in rows.slice(0, 14): print("CENSUS| %6d  %s" % [r[0], r[1]])
	print("CENSUS| total MeshInstance3D: %d" % counts.values().reduce(func(a,b): return a+b, 0))
	var mrows := []
	for k in multi: mrows.append([multi[k], k])
	mrows.sort_custom(func(a,b): return a[0] > b[0])
	print("CENSUS| --- MultiMeshInstance3D ---")
	for r in mrows.slice(0, 8): print("CENSUS| %6d  %s" % [r[0], r[1]])
	print("CENSUS| DONE")
	get_tree().quit()

func _walk(n: Node, path: String, counts: Dictionary, multi: Dictionary) -> void:
	var here := path
	var level = get_tree().current_scene.get_node_or_null("Level")
	## Group by the direct child of Level that owns each mesh, which is
	## what actually maps to a system.
	var scen = level.get_node_or_null("Scenery") if level else null
	if scen != null and n.get_parent() != null and n.get_parent().get_parent() == scen:
		here = "Scenery/%s/*" % n.get_parent().name
	elif scen != null and n.get_parent() == scen:
		here = "Scenery/%s [%s]" % [n.name, n.get_class()]
	elif n.get_parent() == level:
		here = "%s [%s]" % [n.name, n.get_class()]
	elif path == "":
		here = String(n.name)
	if n is MultiMeshInstance3D:
		multi[here] = multi.get(here, 0) + 1
	elif n is MeshInstance3D:
		counts[here] = counts.get(here, 0) + 1
	for c in n.get_children():
		_walk(c, here, counts, multi)
