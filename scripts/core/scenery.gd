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
	## Ours: military, gameplay-adjacent, built from tools/asset_specs.py.
	"base_pad": preload("res://assets/models/base_pad.glb"),
	"road": preload("res://assets/models/road_segment.glb"),

	"barrier": preload("res://assets/models/concrete_barrier.glb"),
	"sandbags": preload("res://assets/models/sandbag_wall.glb"),
	"drum": preload("res://assets/models/fuel_drum.glb"),
	"crates": preload("res://assets/models/crate_stack.glb"),
	"debris": preload("res://assets/models/debris_pile.glb"),
	"mast": preload("res://assets/models/antenna_mast.glb"),

	## Kenney's Nature Kit, CC0 - see assets/models/nature/CREDITS.md.
	## Our generated tree was three stacked cylinders, because the spec
	## language is boxes and cylinders. That is fine for a war factory and
	## hopeless for a tree, and no lighting pass fixes a cone on a stick.
	"tree_pine": preload("res://assets/models/nature/tree_pineTallA.glb"),
	"tree_pine_b": preload("res://assets/models/nature/tree_pineTallB.glb"),
	"tree_pine_c": preload("res://assets/models/nature/tree_pineDefaultA.glb"),
	"tree_pine_d": preload("res://assets/models/nature/tree_pineDefaultB.glb"),
	"tree_pine_e": preload("res://assets/models/nature/tree_pineRoundC.glb"),
	"tree_small": preload("res://assets/models/nature/tree_pineSmallB.glb"),
	"tree_oak": preload("res://assets/models/nature/tree_oak.glb"),
	"tree_broad": preload("res://assets/models/nature/tree_default.glb"),
	"tree_detailed": preload("res://assets/models/nature/tree_detailed.glb"),
	"tree_bare": preload("res://assets/models/nature/stump_oldTall.glb"),
	"stump": preload("res://assets/models/nature/stump_old.glb"),
	"bush": preload("res://assets/models/nature/plant_bush.glb"),
	"bush_large": preload("res://assets/models/nature/plant_bushLarge.glb"),
	"bush_small": preload("res://assets/models/nature/plant_bushSmall.glb"),
	"flower_red": preload("res://assets/models/nature/flower_redA.glb"),
	"flower_yellow": preload("res://assets/models/nature/flower_yellowA.glb"),
	"rock_small": preload("res://assets/models/nature/rock_smallA.glb"),
	"rock_small_b": preload("res://assets/models/nature/rock_smallB.glb"),
	"rock_flat": preload("res://assets/models/nature/rock_smallFlatA.glb"),
	"rock_large": preload("res://assets/models/nature/rock_largeA.glb"),
	"rock_large_b": preload("res://assets/models/nature/rock_largeB.glb"),
	"log": preload("res://assets/models/nature/log.glb"),
	"log_stack": preload("res://assets/models/nature/log_stack.glb"),
	"fence": preload("res://assets/models/nature/fence_simple.glb"),
	"fence_low": preload("res://assets/models/nature/fence_simpleLow.glb"),
	## The blocker grid in dress_blocker steps every 4m, and this block is
	## authored as a unit cube - at root_scale 4 it tiles that grid exactly,
	## which our flat tan slab never did.
	"cliff": preload("res://assets/models/nature/cliff_block_rock.glb"),
	"cliff_slope": preload("res://assets/models/nature/cliff_blockSlope_rock.glb"),
	"rock_large_c": preload("res://assets/models/nature/rock_largeD.glb"),
	"rock_large_d": preload("res://assets/models/nature/rock_largeE.glb"),
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
	## Props sit ON the ground, which is no longer flat.
	Terrain.settle(node)
	_fog_paint(node, kind in DETAILED_KINDS)
	return node

## Kenney's Nature Kit is authored in a deliberate teal-and-coral palette
## - its leaves are genuinely cyan, not a broken import. Handsome, and
## nothing to do with this game, which docs/ART_DIRECTION.md section 2
## sets in muted temperate greens and browns.
##
## Remapping by MATERIAL NAME rather than by colour: the kit names its
## materials semantically (leafsDark, woodBark, dirt), so one small table
## re-skins every model in the pack, including any added later. Doing it
## by colour would need a fresh entry per shade and would silently miss
## anything that did not match exactly.
##
## This is also what stops the props reading as off-the-shelf art sitting
## on our terrain: they end up in our palette, not the pack's.
const NATURE_PALETTE: Dictionary = {
	"grass": Color(0.286, 0.404, 0.216),
	"leafsGreen": Color(0.310, 0.427, 0.224),
	"leafsDark": Color(0.212, 0.318, 0.180),
	"woodBark": Color(0.353, 0.278, 0.204),
	"woodBarkDark": Color(0.278, 0.220, 0.165),
	"wood": Color(0.420, 0.333, 0.235),
	"woodDark": Color(0.278, 0.224, 0.169),
	"woodInner": Color(0.565, 0.478, 0.365),
	"dirt": Color(0.345, 0.290, 0.216),
	"_defaultMat": Color(0.451, 0.451, 0.427),
	## Flowers keep their hue: they are the only saturated thing out there
	## and they are what stops a meadow being one green mass. Muted down,
	## so they never compete with the faction colours, which are the one
	## thing on screen that has to win.
	"colorRed": Color(0.545, 0.243, 0.235),
	"colorYellow": Color(0.639, 0.510, 0.239),
	"colorPurple": Color(0.404, 0.361, 0.545),
}

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
			if source != null and NATURE_PALETTE.has(source.resource_name):
				colour = NATURE_PALETTE[source.resource_name]
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

## Ground cover answers a different question to a prop. A tree must not
## grow inside another tree, but grass absolutely does grow around the
## foot of one - and treating every prop as an obstacle rejected over half
## the tufts, which is why the first pass laid 2,600 of them across 40,000
## square metres and read as bare ground.
##
## So cover ignores the small per-prop clearances and respects only the
## large ones: bases, roads and ore fields, the places where the ground is
## meant to be visibly clear.
const COVER_MIN_CLEARANCE: float = 4.0

func _is_clear_for_cover(point: Vector3) -> bool:
	var floor_sq: float = COVER_MIN_CLEARANCE * COVER_MIN_CLEARANCE
	for entry in _exclusions:
		if entry[1] < floor_sq:
			continue
		if point.distance_squared_to(entry[0]) < entry[1]:
			return false
	return true

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

## Props do not sit on an even lattice in the world, and an even scatter
## is what made ninety of them read as "a field with some cones in it"
## rather than as terrain. Vegetation grows in stands; rock gathers where
## rock is. So placement picks a handful of centres and clusters around
## them, and the kinds available depend on what the cluster IS.
const CLUSTERS: Dictionary = {
	"wood": ["tree_pine", "tree_pine_b", "tree_pine_c", "tree_pine_d",
		"tree_pine_e", "tree_small", "tree_small", "bush", "bush_small",
		"stump", "log"],
	"copse": ["tree_oak", "tree_broad", "tree_detailed", "tree_small",
		"bush_large", "bush", "flower_yellow", "log"],
	"scree": ["rock_small", "rock_small_b", "rock_flat", "rock_flat",
		"rock_large", "rock_large_b", "rock_large_c", "rock_large_d",
		"bush_small"],
	"meadow": ["bush_small", "bush", "flower_red", "flower_yellow",
		"flower_red", "grass_prop", "tree_bare"],
	"ruin": ["debris", "drum", "crates", "sandbags", "barrier", "log_stack",
		"fence", "fence_low", "stump"],
}
## Roughly how far a cluster's members spread from its centre, in metres.
const CLUSTER_SPREAD: Dictionary = {
	"wood": 16.0, "copse": 11.0, "scree": 13.0, "meadow": 14.0, "ruin": 7.0,
}

func scatter(map_size: float, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var half: float = map_size / 2.0 - 12.0
	var names: Array = CLUSTERS.keys()

	var placed: int = 0
	var guard: int = 0
	while placed < count and guard < count * 20:
		guard += 1
		var centre := Vector3(
			rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if not _is_clear(centre):
			continue
		var kind: String = names[rng.randi_range(0, names.size() - 1)]
		var members: Array = CLUSTERS[kind]
		var spread: float = CLUSTER_SPREAD[kind]
		var size: int = rng.randi_range(4, 11)
		for i in size:
			if placed >= count:
				break
			## Biased toward the centre, so a stand has a dense middle and
			## thins at its edge instead of being a disc of even density.
			var offset := Vector3(rng.randfn(0.0, spread * 0.5), 0.0,
				rng.randfn(0.0, spread * 0.5))
			var point: Vector3 = centre + offset
			if absf(point.x) > half or absf(point.z) > half:
				continue
			if not _is_clear(point):
				continue
			var model: String = members[rng.randi_range(0, members.size() - 1)]
			if model == "grass_prop":
				model = "bush_small"
			_spawn(model, point, rng.randf_range(0.0, TAU),
				rng.randf_range(0.75, 1.35))
			## Much tighter than the old 5m: these are meant to crowd.
			_exclude(point, 1.6)
			placed += 1

## --- Ground cover -----------------------------------------------------
##
## The single largest reason the battlefield read as a prototype: there
## was no grass anywhere in the project. "Grass" was a colour in a
## texture, and a flat plane with ninety props on it looks flat however
## well it is lit or surfaced.
##
## Thousands of tufts, drawn as MultiMesh so the whole field costs a
## handful of draw calls rather than thousands of nodes.
const COVER_MODEL: PackedScene = preload("res://assets/models/nature/grass.glb")
const COVER_MODEL_ALT: PackedScene = preload("res://assets/models/nature/grass_leafs.glb")

## Split into a grid, because Godot frustum-culls a MultiMesh by its whole
## bounding box and never per instance. One MultiMesh spanning the map
## would draw every tuft on it including the ones behind the camera; at
## this chunk count the camera holds only a few at a time.
## 12x12 rather than 8x8: the chunk is the culling unit, so smaller
## chunks mean less grass drawn for ground the camera cannot see.
const COVER_CHUNKS: int = 12
const COVER_PER_CHUNK: int = 78

var _cover_root: Node3D

func lay_ground_cover(map_size: float) -> void:
	if not ModelSurfacing.enabled():
		return
	var meshes: Array = [_mesh_of(COVER_MODEL), _mesh_of(COVER_MODEL_ALT)]
	var scales: Array = [_scale_of(COVER_MODEL), _scale_of(COVER_MODEL_ALT)]
	if meshes[0] == null:
		return

	_cover_root = Node3D.new()
	_cover_root.name = "GroundCover"
	add_child(_cover_root)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ 0x5EED
	var half: float = map_size / 2.0 - 10.0
	var span: float = (half * 2.0) / float(COVER_CHUNKS)
	var fog_texture: Texture2D = FogOfWar.get_texture()

	for cx in COVER_CHUNKS:
		for cz in COVER_CHUNKS:
			var origin := Vector3(-half + cx * span, 0.0, -half + cz * span)
			var pick: int = (cx + cz) % meshes.size()
			var transforms: Array = []
			for i in COVER_PER_CHUNK:
				var point := origin + Vector3(
					rng.randf_range(0.0, span), 0.0, rng.randf_range(0.0, span))
				if not _is_clear_for_cover(point):
					continue
				point.y = Terrain.height_at(point.x, point.z)
				var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				var size: float = scales[pick] * rng.randf_range(0.8, 1.6)
				transforms.append(Transform3D(
					basis * Basis.from_scale(Vector3.ONE * size), point))
			if transforms.is_empty():
				continue

			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = meshes[pick]
			multi.instance_count = transforms.size()
			for i in transforms.size():
				multi.set_instance_transform(i, transforms[i])

			var node := MultiMeshInstance3D.new()
			node.multimesh = multi
			## Grass casting shadows is thousands of extra draws into the
			## shadow map for a shadow the size of a leaf.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			## Same green the pack's own `grass` slot is remapped to, so a
			## tuft of ground cover and a scattered bush are the same plant.
			node.material_override = _fog_material(
				NATURE_PALETTE["grass"], fog_texture)
			_cover_root.add_child(node)

## The kit is authored at roughly 1 unit per tile, so each model carries a
## root_scale in its .import. MultiMesh takes the Mesh alone and would
## drop that, so it is read back off the instanced node and folded into
## every instance transform instead.
func _mesh_of(scene: PackedScene) -> Mesh:
	var node: Node3D = scene.instantiate()
	var mesh: Mesh = null
	for instance in node.find_children("*", "MeshInstance3D", true, false):
		mesh = instance.mesh
		break
	node.queue_free()
	return mesh

func _scale_of(scene: PackedScene) -> float:
	var node: Node3D = scene.instantiate()
	var size: float = node.scale.x
	for instance in node.find_children("*", "MeshInstance3D", true, false):
		size *= instance.scale.x
		break
	node.queue_free()
	return size

## Terrain blockers keep their collision box and get a rock face instead
## of a grey cube. Purely a swap of what is drawn.
## Rock formations, not a grid of cubes.
##
## The first version tiled a 4m cube across the blocker footprint on a
## regular lattice. Kenney's cliff block is a unit cube with a grass top,
## so a 40m ridge came out as a wall of identical green-topped boxes -
## unmistakably Minecraft, and the single most out-of-place thing on the
## screen. A lattice of cubes cannot read as rock at any scale.
##
## Boulders instead: several sizes, jittered off the grid, freely rotated
## and overlapping, so the formation has a ragged outline and no two
## pieces line up. The cubes are kept only as a buried core, which is what
## stops a player seeing ground THROUGH a ridge they cannot walk past -
## the collision box is still a box and the silhouette has to cover it.
const BOULDERS: Array = ["rock_large", "rock_large_b", "rock_large_c",
	"rock_large_d"]

func dress_blocker(position: Vector3, size: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 131.0 + position.z * 17.0) & 0x7FFFFFFF

	## A buried core so nothing shows through the mass. Sunk far enough
	## that its flat top never reads as a surface.
	var columns: int = maxi(1, int(size.x / 4.0))
	var rows: int = maxi(1, int(size.z / 4.0))
	for cx in range(columns):
		for cz in range(rows):
			var point := position + Vector3(
				(cx - (columns - 1) / 2.0) * 4.0, 0.0,
				(cz - (rows - 1) / 2.0) * 4.0)
			var core := _spawn("cliff", point, snappedf(
				rng.randf_range(0.0, TAU), TAU / 4.0), 1.0)
			Terrain.settle(core, 2.1)

	## Boulders over the top, at roughly one per 9 square metres of
	## footprint, so a long ridge gets more rock than a small outcrop
	## rather than the same handful stretched thin.
	var count: int = maxi(6, int(size.x * size.z / 9.0))
	for i in count:
		var point := position + Vector3(
			rng.randf_range(-size.x * 0.52, size.x * 0.52), 0.0,
			rng.randf_range(-size.z * 0.52, size.z * 0.52))
		var kind: String = BOULDERS[rng.randi_range(0, BOULDERS.size() - 1)]
		var node := _spawn(kind, point, rng.randf_range(0.0, TAU),
			rng.randf_range(1.1, 2.3))
		## Varied sinking, so they sit IN the ground at different depths
		## instead of all resting on it like dropped props.
		Terrain.settle(node, rng.randf_range(0.2, 0.9))
		## Tip them off level. A boulder that is perfectly upright reads
		## as placed; one leaning reads as fallen.
		node.rotation.x = rng.randf_range(-0.22, 0.22)
		node.rotation.z = rng.randf_range(-0.22, 0.22)
	_exclude(position, maxf(size.x, size.z) * 0.6)
