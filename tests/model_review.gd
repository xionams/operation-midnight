extends Node

## Art review in the real game: the lighting, post-processing, terrain and
## fog shaders of an actual match, not a studio turntable.
##
##   OM_REVIEW="res://assets/models/units/scout_vehicle.glb,..." \
##   OM_SHOT=/some/dir  godot res://tests/model_review.tscn
##
## For every model: a close-up (inspect), and all of them together in a
## row seen from the RTS camera at its default gameplay zoom (judge).
## docs/ART_DIRECTION.md 3b: an asset that only reads close-up is not done.

var _main: Node3D

func _ready() -> void:
	var map_path: String = OS.get_environment("OM_MAP")
	if not map_path.is_empty():
		GameState.selected_map = load(map_path)
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	var out: String = OS.get_environment("OM_SHOT")
	var paths: PackedStringArray = OS.get_environment("OM_REVIEW").split(",", false)
	var origin := Vector3(-60, 0, 40)
	var at := OS.get_environment("OM_AT")
	if not at.is_empty():
		var parts := at.split(",")
		origin = Vector3(float(parts[0]), 0, float(parts[1]))
	FogOfWar.reveal_area(origin, 60.0)
	FogOfWar.enabled = false
	var placed: Array = []
	var spacing: float = float(OS.get_environment("OM_SPACING")) if not OS.get_environment("OM_SPACING").is_empty() else 7.0
	for i in paths.size():
		var scene: PackedScene = load(paths[i])
		if scene == null:
			print("REVIEW| missing ", paths[i])
			continue
		var node: Node3D = scene.instantiate()
		_main.get_node("Level").add_child(node)
		var p: Vector3 = origin + Vector3((i - (paths.size() - 1) / 2.0) * spacing, 0, 0)
		var y: float = Water.level if paths[i].contains("/naval/") and Water.has_water() \
			and Water.is_water(p.x, p.z) else Terrain.height_at(p.x, p.z)
		node.global_position = Vector3(p.x, y, p.z)
		node.rotation.y = deg_to_rad(float(OS.get_environment("OM_YAW")) if not OS.get_environment("OM_YAW").is_empty() else 30.0)
		ModelSurfacing.apply(node)
		FactionPaint.apply(node, FactionPaint.color_for(true))
		placed.append([paths[i].get_file().get_basename(), node])

	## The intro card and sidebar would cover the close-ups.
	if hud != null:
		hud.visible = false
	var rts := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	var close := Camera3D.new()
	close.fov = 38.0
	_main.add_child(close)
	for entry in placed:
		var node: Node3D = entry[1]
		var aabb := _aabb(node)
		var size: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var focus: Vector3 = aabb.get_center()
		close.global_position = focus + Vector3(0.55, 0.62, 0.9).normalized() * (size * 2.1 + 2.0)
		close.look_at(focus, Vector3.UP)
		close.make_current()
		await _frames(6)
		get_viewport().get_texture().get_image().save_png(out.path_join("close_%s.png" % entry[0]))
	if hud != null:
		hud.visible = true
	rts.make_current()
	rts.focus_on(origin)
	await _frames(20)
	get_viewport().get_texture().get_image().save_png(out.path_join("rts_row.png"))
	rts.zoom_distance = rts.max_zoom
	await _frames(40)
	get_viewport().get_texture().get_image().save_png(out.path_join("rts_row_far.png"))
	for entry in placed:
		var node: Node3D = entry[1]
		var tris: int = 0
		var surfaces: int = 0
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			tris += mi.mesh.get_faces().size() / 3
			surfaces += mi.mesh.get_surface_count()
		print("REVIEW| %-22s %6d tris %2d surfaces  size %s" % [entry[0], tris, surfaces, str(_aabb(node).size)])
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
