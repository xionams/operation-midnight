class_name SaveGame
extends RefCounted

## Saves and restores a match in progress.
##
## A phone game is interrupted constantly - a call, a notification, the
## screen locking - so a match that cannot survive being put down is a
## match most people will never finish. This writes the state that
## actually matters and rebuilds it; anything derivable (navmesh,
## scenery, selection rings, health bars) is recreated by the normal
## spawn path rather than stored.
##
## Entities are identified by their stats' display_name and looked up in
## BuildCatalog, so a save does not embed scene paths that a later build
## might move.

const PATH: String = "user://savegame.json"
const VERSION: int = 1

# ------------------------------------------------------------- writing

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

static func save(scene: Node) -> bool:
	var data := capture(scene)
	if data.is_empty():
		return false
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open %s for writing" % PATH)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

static func load_data() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if int(parsed.get("version", 0)) != VERSION:
		## A save from an older build describes a game that no longer
		## exists. Refusing it is kinder than restoring half of it.
		return {}
	return parsed

# ------------------------------------------------------------ capture

static func _v3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]

static func _to_v3(value) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func capture(scene: Node) -> Dictionary:
	if scene == null or not is_instance_valid(scene):
		return {}
	var tree := scene.get_tree()
	if tree == null:
		return {}

	var data := {
		"version": VERSION,
		"map": scene.map.resource_path if scene.get("map") != null else "",
		"match_time": MatchStats.match_time,
		"credits": GameState.credits,
		"enemy_credits": GameState.enemy_credits,
		"stats": {
			"units_produced": MatchStats.units_produced,
			"units_lost": MatchStats.units_lost,
			"enemies_destroyed": MatchStats.enemies_destroyed,
			"buildings_constructed": MatchStats.buildings_constructed,
			"buildings_lost": MatchStats.buildings_lost,
			"resources_harvested": MatchStats.resources_harvested,
		},
		"fog": Marshalls.raw_to_base64(FogOfWar.export_explored()),
		"units": [],
		"buildings": [],
		"resources": [],
	}

	for group in ["player_units", "enemy_units"]:
		for unit in tree.get_nodes_in_group(group):
			var entry := _capture_unit(unit)
			if not entry.is_empty():
				data["units"].append(entry)

	for group in ["player_buildings", "enemy_buildings", "neutral_buildings"]:
		for building in tree.get_nodes_in_group(group):
			var entry := _capture_building(building)
			if not entry.is_empty():
				data["buildings"].append(entry)

	for node in tree.get_nodes_in_group("resource_nodes"):
		if is_instance_valid(node):
			data["resources"].append({
				"position": _v3(node.global_position),
				"remaining": snappedf(node.remaining, 1.0),
			})

	var director = scene.get_node_or_null("AIDirector")
	if director != null:
		data["ai"] = {
			"difficulty": director.difficulty,
			"strategy": director.strategy,
			"build_slot": director._build_slot,
			"match_time": director._match_time,
		}
	return data

static func _capture_unit(unit: Node) -> Dictionary:
	if not is_instance_valid(unit) or unit.stats == null:
		return {}
	var entry := {
		"name": unit.stats.display_name,
		"player": unit.is_player_faction,
		"position": _v3(unit.global_position),
		"rotation": snappedf(unit.rotation.y, 0.01),
		"health": snappedf(unit.health.current_health, 0.1) if unit.health else 0.0,
		"stance": unit.stance,
	}
	if unit.veterancy != null:
		entry["xp"] = snappedf(unit.veterancy.experience, 0.1)
	## Harvesters keep their cargo; losing it on resume is a small theft
	## the player would notice.
	if unit.stats.is_harvester:
		entry["cargo"] = snappedf(unit.get("cargo"), 1.0)
	return entry

static func _capture_building(building: Node) -> Dictionary:
	if not is_instance_valid(building) or building.stats == null:
		return {}
	var entry := {
		"name": building.stats.display_name,
		"player": building.is_player_faction,
		"neutral": building.is_neutral,
		"position": _v3(building.global_position),
		"health": snappedf(building.health.current_health, 0.1) if building.health else 0.0,
		"rally": _v3(building.rally_point),
	}
	if building.get("benefit") != null:
		entry["benefit"] = building.benefit
	return entry

# ------------------------------------------------------------ restore

## Called by main.gd once the level exists but before the default bases
## are spawned, so a restored match never mixes with a fresh one.
static func restore(scene: Node, data: Dictionary, spawn_unit: Callable,
		spawn_building: Callable, spawn_resource: Callable) -> void:
	if data.is_empty():
		return

	GameState.credits = int(data.get("credits", 0))
	GameState.enemy_credits = int(data.get("enemy_credits", 0))
	GameState.credits_changed.emit(GameState.credits)

	for entry in data.get("resources", []):
		spawn_resource.call(_to_v3(entry.get("position")), float(entry.get("remaining", 0.0)))

	for entry in data.get("buildings", []):
		var stats = _find_building(String(entry.get("name", "")))
		if stats == null:
			continue
		var building = spawn_building.call(stats, bool(entry.get("player", true)),
			_to_v3(entry.get("position")), bool(entry.get("neutral", false)))
		if building == null:
			continue
		if building.health != null and entry.has("health"):
			building.health.current_health = clampf(float(entry["health"]), 1.0,
				building.health.max_health)
		building.rally_point = _to_v3(entry.get("rally"))
		if entry.has("benefit") and building.get("benefit") != null:
			building.benefit = int(entry["benefit"])

	for entry in data.get("units", []):
		var stats = _find_unit(String(entry.get("name", "")))
		if stats == null:
			continue
		var unit = spawn_unit.call(stats, bool(entry.get("player", true)),
			_to_v3(entry.get("position")))
		if unit == null:
			continue
		unit.rotation.y = float(entry.get("rotation", 0.0))
		if unit.health != null and entry.has("health"):
			unit.health.current_health = clampf(float(entry["health"]), 1.0,
				unit.health.max_health)
		unit.stance = int(entry.get("stance", unit.stance))
		if unit.veterancy != null and entry.has("xp"):
			unit.veterancy.award_damage(float(entry["xp"]))
		if stats.is_harvester and entry.has("cargo"):
			unit.set("cargo", float(entry["cargo"]))

	if data.has("fog"):
		FogOfWar.import_explored(Marshalls.base64_to_raw(String(data["fog"])))

	var stats_data: Dictionary = data.get("stats", {})
	MatchStats.match_time = float(data.get("match_time", 0.0))
	MatchStats.units_produced = int(stats_data.get("units_produced", 0))
	MatchStats.units_lost = int(stats_data.get("units_lost", 0))
	MatchStats.enemies_destroyed = int(stats_data.get("enemies_destroyed", 0))
	MatchStats.buildings_constructed = int(stats_data.get("buildings_constructed", 0))
	MatchStats.buildings_lost = int(stats_data.get("buildings_lost", 0))
	MatchStats.resources_harvested = int(stats_data.get("resources_harvested", 0))

	var director = scene.get_node_or_null("AIDirector")
	var ai: Dictionary = data.get("ai", {})
	if director != null and not ai.is_empty():
		director.difficulty = int(ai.get("difficulty", director.difficulty))
		director.strategy = int(ai.get("strategy", director.strategy))
		director._build_slot = int(ai.get("build_slot", 0))
		director._match_time = float(ai.get("match_time", 0.0))

static func _find_unit(display_name: String):
	for category in BuildCatalog.categories():
		for stats in BuildCatalog.items(category):
			if stats is UnitStats and stats.display_name == display_name:
				return stats
	## Harvesters and other units that are produced but never listed in
	## the build menu still have to come back.
	for path in ["res://config/units/harvester.tres"]:
		var stats = load(path)
		if stats != null and stats.display_name == display_name:
			return stats
	return null

static func _find_building(display_name: String):
	for category in BuildCatalog.categories():
		for stats in BuildCatalog.items(category):
			if stats is BuildingStats and stats.display_name == display_name:
				return stats
	for path in ["res://config/buildings/command_hq.tres",
			"res://config/buildings/civilian_structure.tres",
			"res://config/buildings/comms_outpost.tres",
			"res://config/buildings/comms_relay.tres",
			"res://config/buildings/repair_depot.tres",
			"res://config/buildings/supply_depot.tres"]:
		var stats = load(path)
		if stats != null and stats.display_name == display_name:
			return stats
	return null
