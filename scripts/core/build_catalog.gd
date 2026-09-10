extends Node

## Autoload: everything that can be built, in one place.
##
## The production panel, the AI and any future balance pass all read this
## list, so adding a unit means writing one .tres and one line here -
## never touching UI layout code. Costs, build times, prerequisites and
## population all live in the resources themselves.

const BUILDINGS: Array[String] = [
	"res://config/buildings/power_plant.tres",
	"res://config/buildings/refinery.tres",
	"res://config/buildings/barracks.tres",
	"res://config/buildings/war_factory.tres",
	"res://config/buildings/radar_center.tres",
	"res://config/buildings/tech_center.tres",
]

const DEFENSES: Array[String] = [
	"res://config/buildings/wall.tres",
	"res://config/buildings/gate.tres",
	"res://config/buildings/mg_tower.tres",
	"res://config/buildings/at_turret.tres",
]

const INFANTRY: Array[String] = [
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/engineer.tres",
	"res://config/units/spy.tres",
	"res://config/units/attack_dog.tres",
]

const VEHICLES: Array[String] = [
	"res://config/units/harvester.tres",
	"res://config/units/scout_vehicle.tres",
	"res://config/units/assault_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
	"res://config/units/artillery_vehicle.tres",
]

var _cache: Dictionary = {}

func _ready() -> void:
	for category in ["BUILDINGS", "DEFENSE", "INFANTRY", "VEHICLES"]:
		_cache[category] = []
	_load_into("BUILDINGS", BUILDINGS)
	_load_into("DEFENSE", DEFENSES)
	_load_into("INFANTRY", INFANTRY)
	_load_into("VEHICLES", VEHICLES)

func _load_into(category: String, paths: Array[String]) -> void:
	for path in paths:
		var resource = load(path)
		if resource != null:
			_cache[category].append(resource)

func categories() -> Array:
	return ["BUILDINGS", "DEFENSE", "INFANTRY", "VEHICLES"]

func items(category: String) -> Array:
	return _cache.get(category, [])

func is_structure(stats) -> bool:
	return stats is BuildingStats

## Which standing building would train this unit, or null if the player
## does not own one yet.
func producer_for(stats: UnitStats, is_player: bool = true) -> Node:
	if stats == null or stats.produced_by == "":
		return null
	var group: String = "player_buildings" if is_player else "enemy_buildings"
	for building in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(building) or building.stats == null:
			continue
		if building.stats.display_name != stats.produced_by:
			continue
		if building.get("queue") != null:
			return building
	return null
