extends Object
class_name CombatTarget

## What every attacker needs to know about the thing it is shooting,
## independent of whether that thing is a man, a tank or a building.
##
## Range used to be measured centre to centre. That is right for units,
## which are small, but wrong for a structure: a Vehicle Factory is ten
## metres across, so a short-ranged weapon could stand against its wall -
## as close as the navmesh lets anything get - and still be "out of range"
## of the centre, and would then sit there forever neither closing nor
## firing. Measuring to the footprint edge makes every weapon engage a
## building from where it can actually see the wall.

## True for anything that takes damage as a structure.
static func is_structure(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	return health != null and health.armor_type == Armor.Type.STRUCTURE

## Which layer of the battlefield a target is in, for weapon domains:
##   LAND       anything on land, units and structures alike
##   NAVAL      ships, surfaced submarines, structures built on water
##   SUBMERGED  a submarine running under water
## WeaponStats.target_domains is a mask of these bits.
enum Domain { LAND = 1, NAVAL = 2, SUBMERGED = 4 }

static func domain_of(target: Node) -> int:
	if not is_instance_valid(target):
		return Domain.LAND
	var stats = target.get("stats")
	if stats is UnitStats:
		if stats.movement_domain != PlacementDomain.Domain.WATER:
			return Domain.LAND
		return Domain.SUBMERGED if Stealth.is_submerged(target) else Domain.NAVAL
	if stats is BuildingStats and stats.placement_domain == PlacementDomain.Domain.WATER:
		return Domain.NAVAL
	return Domain.LAND

static func domain_name(domain: int) -> String:
	match domain:
		Domain.NAVAL:
			return "naval"
		Domain.SUBMERGED:
			return "submerged"
	return "land"

## Half-extents of a target's ground footprint. Zero for units, which are
## treated as points exactly as before.
static func half_extents(target: Node) -> Vector2:
	if target is BuildingBase and (target as BuildingBase).stats != null:
		var size: Vector3 = (target as BuildingBase).stats.body_size
		return Vector2(size.x, size.z) * 0.5
	return Vector2.ZERO

## Ground distance from `from` to the nearest point of the target.
static func distance(from: Vector3, target: Node3D) -> float:
	var centre: Vector3 = target.global_position
	var half: Vector2 = half_extents(target)
	if half == Vector2.ZERO:
		return from.distance_to(centre)
	## Footprints are axis-aligned boxes in world space (structures are
	## never rotated), so the nearest point is a clamp.
	var dx: float = maxf(absf(from.x - centre.x) - half.x, 0.0)
	var dz: float = maxf(absf(from.z - centre.z) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)
