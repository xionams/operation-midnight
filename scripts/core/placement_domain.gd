extends Object
class_name PlacementDomain

## Land or sea: where a structure may stand and where a unit may move.
##
## One vocabulary for both, so a building and a unit that belong to the
## sea are described the same way:
##   BuildingStats.placement_domain  where it can be BUILT
##   UnitStats.movement_domain       where it can MOVE (see NavLayers)
##
## Placement is judged on the whole footprint, not the centre: a shipyard
## half on a beach or a power plant with a corner in the surf are both
## refused, with a reason the player can act on.

enum Domain { LAND, WATER }

## How close to the waterline a `requires_shore` structure's footprint
## must come, in metres.
const SHORE_REACH: float = 4.0

## Footprint corners, edge midpoints and centre.
static func footprint_samples(stats: BuildingStats, pos: Vector3) -> Array:
	var hx: float = stats.footprint.x * 0.5
	var hz: float = stats.footprint.y * 0.5
	var out: Array = []
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			out.append(Vector2(pos.x + sx * hx, pos.z + sz * hz))
	return out

## "" when `stats` may stand at `pos` as far as land and sea go.
static func error_for(stats: BuildingStats, pos: Vector3) -> String:
	if stats == null:
		return ""
	var samples := footprint_samples(stats, pos)
	if stats.placement_domain == Domain.WATER:
		if not Water.has_water():
			return "Needs open water - this map has none"
		for s in samples:
			if not Water.is_water(s.x, s.y):
				return "Must be built entirely on water"
		if stats.requires_shore:
			var closest: float = INF
			for s in samples:
				closest = minf(closest, Water.distance_to_shore(s.x, s.y))
			if closest > SHORE_REACH:
				return "Must be built against the shore (within %dm)" % int(SHORE_REACH)
		return ""
	for s in samples:
		if Water.is_water(s.x, s.y):
			return "Must be built on land"
	return ""

## Where a structure of this kind stands vertically: on the ground, or
## floating at the waterline (not on the sea floor under it).
static func surface_y(stats: BuildingStats, x: float, z: float) -> float:
	if stats != null and stats.placement_domain == Domain.WATER:
		return Water.level
	return Terrain.height_at(x, z)

static func name_of(domain: int) -> String:
	return "Sea" if domain == Domain.WATER else "Land"
