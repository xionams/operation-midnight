extends Node

## Autoload: global match state shared by every system (economy, power,
## win condition). Nothing here holds gameplay behavior — it is a data
## hub that other systems read/write and react to via signals.

enum Faction { PLAYER, ENEMY }
enum MatchState { PLAYING, VICTORY, DEFEAT }

signal credits_changed(new_amount: int)
signal power_changed(generated: int, consumed: int)
signal match_ended(victory: bool)
signal selection_changed(selected_units: Array)

var credits: int = 0
var power_generated: int = 0
var power_consumed: int = 0
var match_state: MatchState = MatchState.PLAYING

var _refineries: Array = []

func _ready() -> void:
	var economy: EconomyConfig = load("res://config/economy/default_economy.tres")
	if economy:
		credits = economy.starting_credits
	credits_changed.emit(credits)

func add_credits(amount: int) -> void:
	credits += amount
	credits_changed.emit(credits)

func try_spend(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	credits_changed.emit(credits)
	return true

func has_power_shortage() -> bool:
	return power_consumed > power_generated

func register_power_generation(amount: int) -> void:
	power_generated += amount
	power_changed.emit(power_generated, power_consumed)

func unregister_power_generation(amount: int) -> void:
	power_generated -= amount
	power_changed.emit(power_generated, power_consumed)

func register_power_consumption(amount: int) -> void:
	power_consumed += amount
	power_changed.emit(power_generated, power_consumed)

func unregister_power_consumption(amount: int) -> void:
	power_consumed -= amount
	power_changed.emit(power_generated, power_consumed)

func register_refinery(refinery: Node) -> void:
	if not _refineries.has(refinery):
		_refineries.append(refinery)

func unregister_refinery(refinery: Node) -> void:
	_refineries.erase(refinery)

func has_refinery() -> bool:
	for refinery in _refineries:
		if is_instance_valid(refinery):
			return true
	return false

func get_first_refinery() -> Node:
	for refinery in _refineries:
		if is_instance_valid(refinery):
			return refinery
	return null

func get_nearest_refinery(from_position: Vector3) -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for refinery in _refineries:
		if not is_instance_valid(refinery):
			continue
		var dist: float = refinery.global_position.distance_squared_to(from_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = refinery
	return nearest

func report_hq_destroyed(faction: Faction) -> void:
	if match_state != MatchState.PLAYING:
		return
	if faction == Faction.PLAYER:
		match_state = MatchState.DEFEAT
		match_ended.emit(false)
	else:
		match_state = MatchState.VICTORY
		match_ended.emit(true)
