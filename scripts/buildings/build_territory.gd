extends Object
class_name BuildTerritory

## Where a side may build: the union of a circle around every structure it
## owns, radius BuildingStats.build_radius_bonus. A new structure is legal
## when its CENTRE falls inside the union - the ghost goes red the moment
## its centre crosses the drawn outline, so what the player sees is
## exactly what the rule checks.
##
## Radii are data, per building type, and sized so that the normal way of
## building - the next structure a couple of metres from the last - is
## always legal and always pushes the edge outward. (They used to barely
## cover each building's own footprint, so a base could only grow by
## hunting for a one-metre sliver at the edge of each circle.)
##
## Walls and gates are special:
##   - they grant NO territory (a wall line used to extend it by 2m per
##     segment, which let a player creep across the entire map), and
##   - they may be placed up to WALL_MARGIN beyond the edge, so a
##     perimeter can wrap around the outermost buildings instead of
##     cutting through them.

const WALL_MARGIN: float = 6.0

static func _group(is_player: bool) -> String:
	return "player_buildings" if is_player else "enemy_buildings"

## Circles that make up a side's territory, as [centre, radius] pairs.
static func circles(tree: SceneTree, is_player: bool) -> Array:
	var out: Array = []
	for building in tree.get_nodes_in_group(_group(is_player)):
		if not is_instance_valid(building) or building.stats == null:
			continue
		var radius: float = building.stats.build_radius_bonus
		if radius <= 0.0:
			continue
		out.append([building.global_position, radius])
	return out

## True if `point` lies inside the side's territory grown by `margin`.
static func contains(tree: SceneTree, point: Vector3, is_player: bool, margin: float = 0.0) -> bool:
	for circle in circles(tree, is_player):
		if _flat_distance(point, circle[0]) <= circle[1] + margin:
			return true
	return false

## How far past the territory edge this kind of structure may go.
static func margin_for(stats: BuildingStats) -> float:
	return WALL_MARGIN if stats != null and stats.is_wall else 0.0

## The territory rule for placing `stats` at `point`.
static func allows(tree: SceneTree, stats: BuildingStats, point: Vector3, is_player: bool) -> bool:
	return contains(tree, point, is_player, margin_for(stats))

## Line segments tracing the OUTLINE of the union (grown by `margin`):
## each circle's arc is kept only where no other circle covers it, so
## overlapping territories read as one continuous base rather than a
## tangle of rings. Pairs of points, for PRIMITIVE_LINES.
static func outline(tree: SceneTree, is_player: bool, margin: float = 0.0,
		segments: int = 72) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var all: Array = circles(tree, is_player)
	for i in all.size():
		var centre: Vector3 = all[i][0]
		var radius: float = all[i][1] + margin
		var previous: Vector3 = Vector3.INF
		for s in segments + 1:
			var angle: float = TAU * float(s) / float(segments)
			var point := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var exposed: bool = true
			for j in all.size():
				if j == i:
					continue
				## A hair inside another circle counts as covered, so two
				## touching circles do not draw a seam.
				if _flat_distance(point, all[j][0]) < all[j][1] + margin - 0.05:
					exposed = false
					break
			if exposed and previous.is_finite():
				lines.append(previous)
				lines.append(point)
			previous = point if exposed else Vector3.INF
	return lines

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
