class_name ModelSurfacing
extends RefCounted

## Gives every imported greybox a surface, without UVs or per-model art.
##
## The models are built from tools/asset_specs.py and carry no UV layout
## at all, so the normal way to texture them - unwrap 42 meshes and paint
## each one - is not available and would not be worth it at greybox stage
## anyway. Triplanar projection needs no UVs: it samples the texture from
## three world axes and blends by surface normal, which on box-shaped
## assets is very nearly a correct unwrap for free.
##
## One greyscale sheet serves the whole game. Godot multiplies
## albedo_texture into albedo_color, so the same seams and grime darken a
## blue Faction band, a grey Hull and a concrete pad while leaving each
## its own colour. A texture with any hue in it would tint all three.
##
## docs/ART_DIRECTION.md section 3 used to forbid this outright. That
## ceiling is what made the game read as untextured boxes, and it was
## lifted deliberately - see section 9.

const DETAIL: Texture2D = preload("res://assets/textures/surface_detail.png")
const DETAIL_NORMAL: Texture2D = preload("res://assets/textures/surface_normal.png")

## World units per texture tile is 1.0 / this. At 0.12 the sheet spans
## ~8m, putting panel seams every 1-2m, which is the size real armour
## plate and wall panels come in. A first attempt at 0.25 put a seam every
## half metre and read as brickwork rather than plating - on this camera
## the failure mode of a detail texture is looking like masonry.
const SCALE: float = 0.12
const NORMAL_STRENGTH: float = 0.45

## Triplanar is three texture samples per map, so albedo plus normal is
## six per fragment. That is free on desktop and measured at zero in the
## 120-unit stress test, but a phone GPU is a different budget - hence a
## switch, like the other visual layers, so the cost can be established
## on device rather than guessed at. See docs/ART_DIRECTION.md section 15.
static func enabled() -> bool:
	return OS.get_environment("OM_NO_DETAIL").is_empty()

## Imported materials are one shared resource per model, not one per unit
## on the field, so this runs once per model however many are spawned.
## Keyed by the material rather than the mesh: several meshes in one file
## share a slot, and doing the work twice would be wasted.
static var _done: Dictionary = {}

## Godot's glTF importer enables vertex_color_use_as_albedo on every
## material in a file except the first, so exactly one surface per model -
## the first, which on a vehicle is the whole Hull - silently discarded
## the ambient occlusion tools/mesh_refine.py bakes into COLOR_0.
## Measured across all 42 models: 39 of 176 surfaces, always the first of
## their file.
static func prepare(material: StandardMaterial3D) -> void:
	if material == null or _done.has(material.get_instance_id()):
		return
	_done[material.get_instance_id()] = true

	## The baked occlusion is vertex data and costs nothing, so it stays on
	## even when the detail sheet is switched off.
	material.vertex_color_use_as_albedo = true
	if not enabled():
		return

	material.albedo_texture = DETAIL
	material.uv1_triplanar = true
	## Local rather than world triplanar: the texture has to travel with a
	## vehicle. World-space projection would slide the panel seams across
	## a tank as it drove, which reads as the hull being see-through.
	material.uv1_scale = Vector3(SCALE, SCALE, SCALE)

	material.normal_enabled = true
	material.normal_texture = DETAIL_NORMAL
	material.normal_scale = NORMAL_STRENGTH


## Walks a freshly instanced model. Cheap after the first instance.
static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface)
			if material is StandardMaterial3D:
				prepare(material)
