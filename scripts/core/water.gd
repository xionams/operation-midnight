class_name Water
extends RefCounted

## The sea: where it is, how deep, and how the ground meets it.
##
## Water regions are polygons on the map definition (MapDefinition.
## water_polygons), and this is the single place every system asks about
## them - terrain shaping, the water surface mesh, the two navmeshes,
## building placement and the minimap. Nothing else keeps its own idea of
## where the coast is.
##
## The ground under water is lowered to a sea floor and eased up into a
## beach just outside, so every coastline reads as a shore rather than a
## blue sheet laid on grass. Like the rest of the terrain this is visual
## relief only: gameplay keeps its flat collision, and what stops a tank
## driving into the sea is the land navmesh, not the slope.

## Height of the water surface. Below the lowest rolling land (Terrain
## AMPLITUDE is 1.6) only where the ground has been shaped down to meet
## it, so dry land never floods.
static var level: float = -0.9
const SEA_FLOOR: float = -4.5
## Metres over which the sea floor falls away from the waterline.
const SHELF: float = 9.0
## Metres of beach outside the waterline that are eased down to meet it.
const BEACH: float = 8.0

static var _polygons: Array = []
static var _bounds: Array = []

static func configure(polygons: Array, water_level: float = -0.9) -> void:
	_polygons.clear()
	_bounds.clear()
	level = water_level
	for poly in polygons:
		var packed := poly as PackedVector2Array
		if packed == null or packed.size() < 3:
			continue
		_polygons.append(packed)
		var rect := Rect2(packed[0], Vector2.ZERO)
		for point in packed:
			rect = rect.expand(point)
		_bounds.append(rect.grow(BEACH + 1.0))

static func reset() -> void:
	configure([])

static func has_water() -> bool:
	return not _polygons.is_empty()

static func polygons() -> Array:
	return _polygons

static func is_water(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for i in _polygons.size():
		if not (_bounds[i] as Rect2).has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, _polygons[i]):
			return true
	return false

## Distance to the nearest waterline, whichever side of it the point is.
## INF on a map with no sea.
static func distance_to_shore(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best: float = INF
	for poly in _polygons:
		var packed := poly as PackedVector2Array
		for i in packed.size():
			var a: Vector2 = packed[i]
			var b: Vector2 = packed[(i + 1) % packed.size()]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

## Terrain hook: sink the sea floor, ease the beach down to the waterline.
static func shape_height(x: float, z: float, height: float) -> float:
	if _polygons.is_empty():
		return height
	var p := Vector2(x, z)
	var near: bool = false
	for rect in _bounds:
		if (rect as Rect2).has_point(p):
			near = true
			break
	if not near:
		return height
	var shore: float = distance_to_shore(x, z)
	if is_water(x, z):
		var t: float = clampf(shore / SHELF, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(level - 0.3, SEA_FLOOR, t)
	if shore >= BEACH:
		return height
	## Beach: blend from the land's own height down to just above the water.
	var w: float = 1.0 - shore / BEACH
	w = w * w * (3.0 - 2.0 * w)
	return lerpf(height, level + 0.35, w)

## Nearest point on water to `point` (or `point` itself if already wet),
## by walking outward. Used to put a unit built by a shipyard, or nudged
## by the unstick logic, somewhere it can actually float.
static func nearest_water(point: Vector3, max_reach: float = 30.0) -> Vector3:
	if is_water(point.x, point.z):
		return point
	for r in range(2, int(max_reach) + 1, 2):
		for step in 16:
			var a: float = TAU * float(step) / 16.0
			var c := point + Vector3(cos(a), 0.0, sin(a)) * float(r)
			if is_water(c.x, c.z):
				return c
	return point
