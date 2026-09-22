extends Resource
class_name MapDefinition

## Everything that makes one battlefield different from another.
##
## The layout used to be a wall of constants in main.gd, which meant the
## game had exactly one map and no way to get a second without editing
## code. Pulling it into a resource keeps main.gd as the thing that
## assembles a match and makes a new map a .tres file - which is also how
## the rest of this project's balance already works.
##
## Positions are metres in world space, origin at the map centre.

@export var display_name: String = "Unnamed"
@export_multiline var description: String = ""

## Playable extent, in metres. The camera bounds and the fog grid derive
## from this, so it is not decoration.
@export var size: float = 220.0

@export_group("Bases")
@export var player_base: Vector3 = Vector3(-78, 0, 62)
@export var enemy_base: Vector3 = Vector3(76, 0, -70)
## How much of their own ground each side starts knowing.
@export var start_reveal_radius: float = 34.0

@export_group("Economy")
## Ore fields as (x, z, amount). Kept as a flat array of Vector3 so the
## resource stays editable in the inspector: x and z are position, y is
## the amount in credits.
@export var resource_fields: Array[Vector3] = []

@export_group("Neutral structures")
@export var civilian_positions: Array[Vector3] = []
@export var comms_outpost: Vector3 = Vector3.ZERO
@export var repair_depot: Vector3 = Vector3.ZERO
@export var supply_depot: Vector3 = Vector3.ZERO

@export_group("Terrain")
## Impassable masses as (position, size) pairs, flattened: even indices
## are positions, odd indices the box size that follows.
@export var blockers: Array[Vector3] = []

## Ore reachable from a base without crossing the middle. Used by the
## setup screen to describe a map honestly rather than by adjective.
func home_ore_for(base: Vector3, radius: float = 45.0) -> int:
	var total: int = 0
	for field in resource_fields:
		if Vector2(field.x, field.z).distance_to(Vector2(base.x, base.z)) <= radius:
			total += int(field.y)
	return total

func total_ore() -> int:
	var total: int = 0
	for field in resource_fields:
		total += int(field.y)
	return total

## Ore that belongs to neither side's doorstep - what the map forces you
## to fight over.
func contested_ore() -> int:
	return total_ore() - home_ore_for(player_base) - home_ore_for(enemy_base)

func blocker_pairs() -> Array:
	var pairs: Array = []
	var index: int = 0
	while index + 1 < blockers.size():
		pairs.append([blockers[index], blockers[index + 1]])
		index += 2
	return pairs
