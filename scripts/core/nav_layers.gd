extends Object
class_name NavLayers

## Navigation layer bits, in one place.
##
## There are two navmeshes: the land mesh (Level/NavRegion, layer LAND)
## and the sea mesh (Level/WaterNav, layer WATER). A unit's agent carries
## exactly the layers of the domain it moves in, so the ONE pathfinding
## system answers both "how does this tank get there" and "how does this
## boat get there" - land agents simply never see sea polygons and naval
## agents never see land ones.
##
## Each side also has its own layer, which is what gate passages are on
## (see Gate): a unit can use its own side's gates and never the enemy's.

const LAND: int = 1 << 0
const PLAYER_GATE: int = 1 << 1
const ENEMY_GATE: int = 1 << 2
const WATER: int = 1 << 3

static func gate_layer_for(is_player: bool) -> int:
	return PLAYER_GATE if is_player else ENEMY_GATE

## The layers a unit's agent should carry.
static func for_unit(stats: UnitStats, is_player: bool) -> int:
	if stats != null and stats.movement_domain == PlacementDomain.Domain.WATER:
		return WATER
	return LAND | gate_layer_for(is_player)
