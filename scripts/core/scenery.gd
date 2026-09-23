class_name Scenery
extends Node3D

## Dresses the battlefield: base pads, roads and scattered props.
##
## Everything here is presentation. Nothing has collision, so the navmesh
## and every existing path are untouched by definition - a prop that could
## block a harvester would be a gameplay change wearing an art costume.
##
## Placement is driven by a fixed seed, so the map looks the same every
## run and a screenshot taken today still matches the build tomorrow.

const SEED: int = 0x0DDBA11

const FOG_SHADER: Shader = preload("res://shaders/fog_terrain.gdshader")

## Set once by main before anything is spawned; the fog shader needs it to
## turn a world position into a fog cell.
var map_size: float = 220.0

## One fog material per distinct colour, not per surface. The first cut
## built a fresh ShaderMaterial for every surface of every prop - roughly
## four hundred unique materials across the map - which defeats batching
## and cost about 10 FPS at 120 units for no visual difference.
var _fog_materials: Dictionary = {}

## Built surfaces - poured concrete and asphalt - take the same panel and
## grime sheet the structures wear, so a pad reads as something laid down
## rather than as a hole cut in the grass. Rocks, trees and sandbags do
## not: panel seams on a boulder look like a mistake, and they are small
## enough on screen that flat colour costs nothing.
const DETAILED_KINDS: Array = ["base_pad", "road"]
const SURFACE_DETAIL: Texture2D = preload("res://assets/textures/surface_detail.png")
const SURFACE_NORMAL: Texture2D = preload("res://assets/textures/surface_normal.png")
## Metres per tile of that sheet. Wider than the structures use it: a pad
## is a big continuous pour, and seams at the vehicle scale would read as
## paving slabs.
const DETAIL_SCALE: float = 12.0

const MODELS: Dictionary = {
	"base_pad": preload("res://assets/models/base_pad.glb"),
	"road": preload("res://assets/models/road_segment.glb"),
	"rock_small": preload("res://assets/models/rock_small.glb"),
	"rock_large": preload("res://assets/models/rock_large.glb"),
	"cliff": preload("res://assets/models/cliff_block.glb"),
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_bare": preload("res://assets/models/tree_bare.glb"),
	"barrier": preload("res://assets/models/concrete_barrier.glb"),
	"sandbags": preload("res://assets/models/sandbag_wall.glb"),
	"drum": preload("res://assets/models/fuel_drum.glb"),
	"crates": preload("res://assets/models/crate_stack.glb"),
	"debris": preload("res://assets/models/debris_pile.glb"),
	"mast": preload("res://assets/models/antenna_mast.glb"),
}

## Props are scattered anywhere except these: bases need clear ground to
## build on, ore fields need clear ground to harvest, and a prop sitting
## in a road looks like a mistake rather than like scenery.
var _exclusions: Array = []

func _spawn(kind: String, position: Vector3, rotation_y: float = 0.0,
		scale: float = 1.0) -> Node3D:
	var node: Node3D = MODELS[kind].instantiate()
	add_child(node)
	node.position = position
	node.rotation.y = rotation_y
	if not is_equal_approx(scale, 1.0):
		node.scale = Vector3.ONE * scale
	_fog_paint(node, kind in DETAILED_KINDS)
	return node

## Scenery has no collision, so it cannot use FogHideable the way units and
## resource fields do - that needs a CollisionObject3D. Instead each
## surface is re-shaded with the terrain fog shader, carrying its own
## colour across. Without this, props would show through the shroud and
## hand the player a free map outline.
func _fog_paint(node: Node3D, detailed: bool = false) -> void:
	var fog_texture: Texture2D = FogOfWar.get_texture()
	for mesh_instance in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as StandardMaterial3D
			var colour: Color = source.albedo_color if source != null else Color(0.5, 0.5, 0.5)
			mesh_instance.set_surface_override_material(
				surface, _fog_material(colour, fog_texture, detailed))

func _fog_material(colour: Color, fog_texture: Texture2D,
		detailed: bool = false) -> ShaderMaterial:
	## Keyed on both, or the first pad to be built would hand its textured
	## material to every rock that happens to share its grey.
	var key: String = "%s|%s" % [colour, detailed]
	if _fog_materials.has(key):
		return _fog_materials[key]
	var material := ShaderMaterial.new()
	material.shader = FOG_SHADER
	material.set_shader_parameter("fog_tex", fog_texture)
	material.set_shader_parameter("map_size", map_size)
	material.set_shader_parameter("base_color", colour)
	if detailed and ModelSurfacing.enabled():
		## macro_tex is left at its default white, so the pad keeps its own
		## colour and only picks up the grain and seams.
		material.set_shader_parameter("textured", 1.0)
		material.set_shader_parameter("detail_tex", SURFACE_DETAIL)
		material.set_shader_parameter("normal_tex", SURFACE_NORMAL)
		material.set_shader_parameter("detail_scale", DETAIL_SCALE)
		material.set_shader_parameter("normal_strength", 0.35)
	_fog_materials[key] = material
	return material

func _exclude(centre: Vector3, radius: float) -> void:
	_exclusions.append([centre, radius * radius])

func _is_clear(point: Vector3) -> bool:
	for entry in _exclusions:
		if point.distance_squared_to(entry[0]) < entry[1]:
			return false
	return true

## Base pads sit slightly proud of the terrain so a base reads as
## deliberate ground rather than structures dropped on grass.
func decorate_base(centre: Vector3, is_player: bool) -> void:
	_exclude(centre, 26.0)
	## Exactly 10m apart so the slabs abut and read as one apron.
	for x in [-5.0, 5.0]:
		for z in [-5.0, 5.0]:
			_spawn("base_pad", centre + Vector3(x, 0, z))
	var facing: float = -1.0 if is_player else 1.0
	_spawn("mast", centre + Vector3(-13, 0, 13 * facing))
	for i in range(3):
		_spawn("barrier", centre + Vector3(-16 + i * 5.5, 0, -14 * facing), 0.0)
	_spawn("sandbags", centre + Vector3(14, 0, -12 * facing), PI * 0.5)
	_spawn("crates", centre + Vector3(15, 0, 8 * facing))
	_spawn("drum", centre + Vector3(17, 0, 10 * facing))

## A dashed road between the two bases, which is also the route most
## fighting happens along - it makes the battlefield legible at a glance.
func lay_road(from_point: Vector3, to_point: Vector3) -> void:
	var distance: float = from_point.distance_to(to_point)
	var steps: int = int(distance / 8.0)
	var direction: Vector3 = (to_point - from_point).normalized()
	var angle: float = atan2(direction.x, direction.z)
	for i in range(steps + 1):
		var point: Vector3 = from_point + direction * (i * 8.0)
		_spawn("road", point, angle)
		_exclude(point, 7.0)

func scatter(map_size: float, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var half: float = map_size / 2.0 - 12.0
	var kinds: Array = ["tree_pine", "tree_pine", "tree_bare", "rock_small",
		"rock_small", "rock_large", "debris", "drum", "crates", "sandbags"]

	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 12:
		attempts += 1
		var point := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if not _is_clear(point):
			continue
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		_spawn(kind, point, rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25))
		_exclude(point, 5.0)
		placed += 1

## Terrain blockers keep their collision box and get a rock face instead
## of a grey cube. Purely a swap of what is drawn.
func dress_blocker(position: Vector3, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 131.0 + position.z * 17.0) & 0x7FFFFFFF
	var columns: int = maxi(1, int(size.x / 4.0))
	var rows: int = maxi(1, int(size.z / 4.0))
	for cx in range(columns):
		for cz in range(rows):
			var point := position + Vector3(
				(cx - (columns - 1) / 2.0) * 4.0, 0.0, (cz - (rows - 1) / 2.0) * 4.0)
			var node := _spawn("cliff", point, rng.randf_range(0.0, TAU),
				rng.randf_range(0.95, 1.15))
			node.position.y = -0.4
	_exclude(position, maxf(size.x, size.z) * 0.6)
