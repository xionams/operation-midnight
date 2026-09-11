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
	_cache[key] = material
	return material

## Walks a freshly instanced model and overrides every surface whose
## source material is named `Faction`.
static func apply(root: Node, color: Color) -> void:
	var material := _material(color)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var source: Material = mesh.surface_get_material(surface)
			if source != null and source.resource_name == SLOT:
				node.set_surface_override_material(surface, material)
