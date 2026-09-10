extends Node

## Autoload: match bookkeeping for the after-action report.
##
## Everything is counted by listening to signals the gameplay already
## emits, so no system has to know statistics exist.

var match_time: float = 0.0
var units_produced: int = 0
var units_lost: int = 0
var enemies_destroyed: int = 0
var buildings_constructed: int = 0
var buildings_lost: int = 0
var resources_harvested: int = 0

var _running: bool = true

func _ready() -> void:
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.building_placed.connect(_on_building_placed)
	GameState.match_ended.connect(func(_v): _running = false)

func reset() -> void:
	match_time = 0.0
	units_produced = 0
	units_lost = 0
	enemies_destroyed = 0
	buildings_constructed = 0
	buildings_lost = 0
	resources_harvested = 0
	_running = true

func _process(delta: float) -> void:
	if _running and GameState.match_state == GameState.MatchState.PLAYING:
		match_time += delta

func _on_unit_spawned(unit: Node) -> void:
	if unit != null and unit.get("is_player_faction"):
		units_produced += 1

func _on_building_placed(building: Node) -> void:
	if building != null and building.get("is_player_faction") and not building.get("is_neutral"):
		buildings_constructed += 1

## Called from the death paths, which know which side died.
func record_unit_death(is_player: bool) -> void:
	if is_player:
		units_lost += 1
	else:
		enemies_destroyed += 1

func record_building_death(is_player: bool) -> void:
	if is_player:
		buildings_lost += 1

func record_harvest(amount: int) -> void:
	resources_harvested += amount

func formatted_time() -> String:
	return "%d:%02d" % [int(match_time) / 60, int(match_time) % 60]

func summary_lines() -> Array:
	return [
		["MATCH TIME", formatted_time()],
		["UNITS PRODUCED", str(units_produced)],
		["UNITS LOST", str(units_lost)],
		["ENEMIES DESTROYED", str(enemies_destroyed)],
		["BUILDINGS CONSTRUCTED", str(buildings_constructed)],
		["BUILDINGS LOST", str(buildings_lost)],
		["RESOURCES HARVESTED", _thousands(resources_harvested)],
	]

func _thousands(value: int) -> String:
	var text: String = str(value)
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
