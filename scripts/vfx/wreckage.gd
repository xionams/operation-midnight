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

const MODEL: PackedScene = preload("res://assets/models/destroyed_building.glb")
const VEHICLE_MODEL: PackedScene = preload("res://assets/models/vehicle_wreck.glb")
const FOG_SHADER: Shader = preload("res://shaders/fog_terrain.gdshader")

## Rubble persists for the match rather than fading, but not without
## limit: a long match on a small map would otherwise accumulate wrecks
## until they cost more than the buildings did.
const MAX_WRECKS: int = 24

## A dead vehicle leaves a hull. Same budget as a structure ruin, and
## the same cap covers both - a battlefield strewn with a hundred wrecks
## costs more than the units did.
static func spawn_vehicle(context: Node, position: Vector3) -> void:
	spawn(context, position, 0.0, VEHICLE_MODEL, 1.0)

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
	wreck.global_position = Vector3(position.x, 0.0, position.z)
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
			material.set_shader_parameter("base_color",
				source.albedo_color if source != null else Color(0.35, 0.34, 0.31))
			mesh_instance.set_surface_override_material(surface, material)
