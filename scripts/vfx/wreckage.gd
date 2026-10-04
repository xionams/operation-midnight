class_name Wreckage
extends Node3D

## What is left where a structure stood.
##
## A razed base that leaves bare grass reads as though nothing happened
## there - the player loses the record of their own match. Rubble is that
## record, and it is also information: an opponent scouting a ruin knows
## this ground was fought over.
##
## The model already existed and nothing spawned it, which is the kind of
## gap that only shows up when someone goes looking.

## One generic burnt hull used to stand in for every vehicle in the game,
## from a scout car to a main battle tank, and a ship left nothing at
## all. A wreck is information as much as decoration - it says what died
## here and roughly how big it was - so there is now one per weight
## class, picked from the unit's own armour rather than a list of names.
const MODEL: PackedScene = preload("res://assets/models/props/building_ruin.glb")
const LIGHT_MODEL: PackedScene = preload("res://assets/models/props/vehicle_wreck_light.glb")
const HEAVY_MODEL: PackedScene = preload("res://assets/models/props/vehicle_wreck_heavy.glb")
const NAVAL_MODEL: PackedScene = preload("res://assets/models/props/naval_debris.glb")
const FOG_SHADER: Shader = preload("res://shaders/fog_terrain.gdshader")
## What a burnt hull is, if a model ever arrives without vertex colours.
const SOOT: Color = Color(0.105, 0.098, 0.094)

## Rubble persists for the match rather than fading, but not without
## limit: a long match on a small map would otherwise accumulate wrecks
## until they cost more than the buildings did.
const MAX_WRECKS: int = 24

## A dead vehicle leaves a hull, sized to what it was. Same budget as a
## structure ruin, and the same cap covers both - a battlefield strewn
## with a hundred wrecks costs more than the units did.
static func spawn_vehicle(context: Node, position: Vector3, heavy: bool = false) -> void:
	spawn(context, position, 0.0, HEAVY_MODEL if heavy else LIGHT_MODEL, 1.0)

## A sunk ship leaves a slick and floating debris, never a hulk - which
## is the whole difference between losing a boat and losing a tank. It
## rides the waterline rather than the ground.
static func spawn_naval_debris(context: Node, position: Vector3) -> void:
	spawn(context, Vector3(position.x, Water.level, position.z), 0.0, NAVAL_MODEL, 1.0)

## Is this unit heavy enough to leave a tank-sized wreck? Read from its
## armour, so a new vehicle gets the right hull without being listed
## anywhere.
static func is_heavy(stats) -> bool:
	return stats != null and stats.armor_type >= Armor.Type.MEDIUM

static func spawn(context: Node, position: Vector3, footprint: float,
		model_scene: PackedScene = null, fixed_scale: float = 0.0) -> void:
	if context == null or not is_instance_valid(context):
		return
	var tree := context.get_tree()
	if tree == null or tree.current_scene == null:
		return
	var level := tree.current_scene.get_node_or_null("Level")
	if level == null:
		return

	_trim(tree)

	var wreck := Wreckage.new()
	wreck.name = "Wreckage"
	wreck.add_to_group("wreckage")
	level.add_child(wreck)
	## Ground wrecks sit at y=0; floating debris keeps the height it was
	## given, so a slick rides the water instead of sinking to the seabed.
	wreck.global_position = Vector3(position.x, position.y, position.z)
	wreck.rotation.y = randf_range(0.0, TAU)

	var model := (model_scene if model_scene != null else MODEL).instantiate()
	wreck.add_child(model)
	## The model is built for a 4.4m shell; scale it to whatever stood
	## here so a Command HQ does not leave the same pile as a wall.
	var scale: float = fixed_scale if fixed_scale > 0.0 \
		else clampf(footprint / 4.4, 0.55, 2.1)
	model.scale = Vector3(scale, clampf(scale * 0.85, 0.5, 1.6), scale)
	wreck._fog_paint(model, tree)

static func _trim(tree: SceneTree) -> void:
	var wrecks: Array = tree.get_nodes_in_group("wreckage")
	var excess: int = wrecks.size() - (MAX_WRECKS - 1)
	for i in maxi(0, excess):
		if i < wrecks.size() and is_instance_valid(wrecks[i]):
			wrecks[i].queue_free()

## Rubble hides under the shroud like the ground it is lying on -
## otherwise a ruin the player has never seen marks the map for them.
func _fog_paint(model: Node, tree: SceneTree) -> void:
	var map_size: float = FogOfWar.get_map_size()
	var fog_texture: Texture2D = FogOfWar.get_texture()
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = FOG_SHADER
			material.set_shader_parameter("fog_tex", fog_texture)
			material.set_shader_parameter("map_size", map_size)
			## These models keep their colour in VERTEX colours and leave
			## the glTF base-colour factor at its default white, so
			## painting from albedo_color alone rendered every wreck as a
			## flat white sheet several metres across. Scenery dodges this
			## with palette lookups keyed on material name; a wreck has no
			## such table, so read the colour off the mesh.
			##
			## Read on the CPU rather than in the shader: COLOR arrives
			## white in a spatial shader for these imported meshes even
			## though the surface carries the array, so a shader-side
			## vertex-colour path looks right and renders white.
			material.set_shader_parameter("base_color",
				_surface_colour(mesh, surface,
					source.albedo_color if source != null else SOOT))
			mesh_instance.set_surface_override_material(surface, material)


## The average colour of a surface, taken from its vertex colours.
##
## These models are flat-shaded out of a deliberately tight palette -
## soot, char, ash - so one colour per surface is faithful to how they
## were authored. Sampled rather than walked: a hull has thousands of
## vertices and this runs the moment something dies.
static func _surface_colour(mesh: Mesh, surface: int, fallback: Color) -> Color:
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_COLOR:
		return fallback
	var colours = arrays[Mesh.ARRAY_COLOR]
	if colours == null or colours.size() == 0:
		return fallback
	var step: int = maxi(1, colours.size() / 48)
	var total := Color(0.0, 0.0, 0.0)
	var n: int = 0
	var i: int = 0
	while i < colours.size():
		total += colours[i]
		n += 1
		i += step
	return Color(total.r / n, total.g / n, total.b / n)
