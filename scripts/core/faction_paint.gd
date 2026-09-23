class_name FactionPaint
extends RefCounted

## Recolours the `Faction` material slot on a greybox at runtime.
##
## Faction colour is never baked into a mesh: one model serves both sides
## and the neutral state, and a captured structure changes hands by
## repainting rather than by swapping assets. See docs/ART_DIRECTION.md
## section 8 - this is the game's single most important readability rule.

const PLAYER: Color = Color(0.180, 0.435, 0.851)
const ENEMY: Color = Color(0.851, 0.204, 0.180)
const NEUTRAL: Color = Color(0.851, 0.784, 0.478)

const SLOT: String = "Faction"

## One material per faction for the whole game rather than one per
## instance: 120 units each owning a private material would defeat
## batching for no visual gain.
static var _cache: Dictionary = {}

static func color_for(is_player: bool, is_neutral: bool = false) -> Color:
	if is_neutral:
		return NEUTRAL
	return PLAYER if is_player else ENEMY

static func _material(color: Color) -> StandardMaterial3D:
	var key: String = str(color)
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	material.metallic = 0.0
	## This material replaces an imported one, so it has to opt into the
	## baked occlusion the same way - otherwise the faction band is the one
	## stripe on the model with no contact shading, which is conspicuous
	## precisely because it is the part players look at.
	material.vertex_color_use_as_albedo = true
	_cache[key] = material
	return material

## Godot's glTF importer enables vertex_color_use_as_albedo on every
## material in a file except the first one, so exactly one surface per
## model - the first, which on a vehicle is the whole Hull - silently
## discards the ambient occlusion baked into COLOR_0 by
## tools/mesh_refine.py. Measured across all 42 models: 39 of 176
## surfaces, always the first of its file.
##
## Fixed here rather than in the exporter because the glTF itself is
## correct; and here rather than in a loader of its own because the only
## models this matters for are units and structures, which is exactly the
## set that passes through apply(). Scenery is drawn with the fog shader,
## which writes ALBEDO itself and never reads vertex colour.
static var _ao_fixed: Dictionary = {}

static func _enable_baked_ao(mesh: Mesh) -> void:
	if _ao_fixed.has(mesh.get_rid()):
		return
	_ao_fixed[mesh.get_rid()] = true
	for surface in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if material is StandardMaterial3D:
			material.vertex_color_use_as_albedo = true

## Walks a freshly instanced model and overrides every surface whose
## source material is named `Faction`.
static func apply(root: Node, color: Color) -> void:
	var material := _material(color)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		## Cheap after the first instance: the imported materials are one
		## shared resource per model, not one per unit on the field.
		_enable_baked_ao(mesh)
		for surface in mesh.get_surface_count():
			var source: Material = mesh.surface_get_material(surface)
			if source != null and source.resource_name == SLOT:
				node.set_surface_override_material(surface, material)
