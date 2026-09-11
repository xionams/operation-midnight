class_name Icons
extends RefCounted

## Look-up from a thing's display name to its icon.
##
## Keyed by display name rather than by scene path because that is what
## the catalogue, the selection panel and the production queue all
## already have in hand. A missing entry returns null and the caller
## simply shows text, which is what the HUD did before icons existed.

const DIR: String = "res://assets/icons/"

const BY_NAME: Dictionary = {
	# Structures
	"Command Headquarters": "bld_command_hq",
	"Power Plant": "bld_power_plant",
	"Resource Refinery": "bld_refinery",
	"Barracks": "bld_barracks",
	"Vehicle Factory": "bld_war_factory",
	"Radar Center": "bld_radar_center",
	"Technology Center": "bld_tech_center",
	"Forward Command Post": "bld_forward_post",
	"Machine Gun Tower": "bld_mg_tower",
	"Anti-Armor Turret": "bld_at_turret",
	"Concrete Wall": "bld_wall",
	"Security Gate": "bld_gate",
	"Communications Outpost": "bld_comms_outpost",
	"Repair Depot": "bld_repair_depot",
	"Supply Depot": "bld_supply_depot",
	"Civilian Structure": "bld_civilian",
	# Units
	"Rifle Squad": "unit_rifle_soldier",
	"Anti-Armor Squad": "unit_at_squad",
	"Engineer": "unit_engineer",
	"Spy": "unit_spy",
	"Attack Dog": "unit_attack_dog",
	"Scout Vehicle": "unit_scout_vehicle",
	"Assault Vehicle": "unit_assault_vehicle",
	"Main Battle Tank": "unit_main_battle_tank",
	"Artillery Vehicle": "unit_artillery_vehicle",
	"Supply Harvester": "unit_harvester",
}

const BY_CATEGORY: Dictionary = {
	"BUILDINGS": "cat_buildings",
	"DEFENSE": "cat_defense",
	"INFANTRY": "cat_infantry",
	"VEHICLES": "cat_vehicles",
}

static var _cache: Dictionary = {}

static func get_icon(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path: String = DIR + icon_name + ".svg"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[icon_name] = texture
	return texture

static func for_name(display_name: String) -> Texture2D:
	return get_icon(BY_NAME.get(display_name, ""))

static func for_category(category: String) -> Texture2D:
	return get_icon(BY_CATEGORY.get(category, ""))
