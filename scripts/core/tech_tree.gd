extends Node

## Autoload: the single authority on "may this side build that yet?".
##
## Availability is derived from data - each stat resource lists the
## structures it needs by display name - so the production panel, the AI
## and the build placer all ask the same question and can never disagree.
## Adding a new unit or building means writing its prerequisites in its
## .tres, not editing UI code.
##
## Prerequisites are evaluated live against what the owner currently has
## standing. Losing a Radar Center therefore locks new Anti-Armor Turrets
## until it is rebuilt, while turrets already built keep working - the
## behaviour the brief asks for.

## Unit capacity granted before any structure is counted.
const BASE_POPULATION: int = 0

func _building_names_for(is_player: bool) -> Dictionary:
	var owned: Dictionary = {}
	var group: String = "player_buildings" if is_player else "enemy_buildings"
	for building in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(building) or building.stats == null:
			continue
		if building.has_method("is_under_construction") and building.is_under_construction():
			continue
		owned[building.stats.display_name] = true
	return owned

## `stats` may be BuildingStats or UnitStats; both carry `prerequisites`.
func is_available(stats, is_player: bool = true) -> bool:
	return missing_prerequisites(stats, is_player).is_empty()

func missing_prerequisites(stats, is_player: bool = true) -> Array:
	if stats == null:
		return ["unknown"]
	var owned := _building_names_for(is_player)
	var missing: Array = []
	for requirement in stats.prerequisites:
		if not owned.has(requirement):
			missing.append(requirement)
	return missing

# ------------------------------------------------------------ population

func population_cap(is_player: bool = true) -> int:
	var cap: int = BASE_POPULATION
	var group: String = "player_buildings" if is_player else "enemy_buildings"
	for building in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(building) or building.stats == null:
			continue
		if building.has_method("is_under_construction") and building.is_under_construction():
			continue
		cap += building.stats.population_provided
	return cap

func population_used(is_player: bool = true) -> int:
	var used: int = 0
	var group: String = "player_units" if is_player else "enemy_units"
	for unit in get_tree().get_nodes_in_group(group):
		if is_instance_valid(unit) and unit.stats != null:
			used += unit.stats.population
	## Queued orders count too, or a player could queue an unlimited army
	## and watch it all arrive at once.
	for building in get_tree().get_nodes_in_group("player_buildings" if is_player else "enemy_buildings"):
		if not is_instance_valid(building):
			continue
		var queue = building.get("queue")
		if queue != null:
			used += queue.queued_population()
	return used

func has_population_for(stats: UnitStats, is_player: bool = true) -> bool:
	if stats == null:
		return false
	return population_used(is_player) + stats.population <= population_cap(is_player)
