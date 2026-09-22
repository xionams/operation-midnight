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
## The AI keeps its own balance here. Both sides run the same production
## and harvesting code, so without a separate pool an enemy refinery
## would pay the player and enemy production would spend the player's
## money. Only the player's balance drives HUD signals.
var enemy_credits: int = 0
var power_generated: int = 0
var power_consumed: int = 0
var match_state: MatchState = MatchState.PLAYING

var _player_refineries: Array = []
var _enemy_refineries: Array = []

## Chosen on the skirmish setup screen. Read by main.gd when the scene
## builds, which is why picking a map reloads the scene rather than
## editing a battlefield that already exists.
var selected_map: Resource = null
## Set when the setup screen has already been answered, so the reload
## that applies the choice does not ask again.
var skip_setup: bool = false

func _ready() -> void:
	var economy: EconomyConfig = load("res://config/economy/default_economy.tres")
	if economy:
		credits = economy.starting_credits
		enemy_credits = economy.starting_credits
	credits_changed.emit(credits)

# ---------------------------------------------------------- faction economy

func balance_of(is_player: bool) -> int:
	return credits if is_player else enemy_credits

func add_credits_for(is_player: bool, amount: int) -> void:
	if is_player:
		add_credits(amount)
	else:
		enemy_credits += amount

func try_spend_for(is_player: bool, amount: int) -> bool:
	if is_player:
		return try_spend(amount)
	if enemy_credits < amount:
		return false
	enemy_credits -= amount
	return true

func add_credits(amount: int) -> void:
	credits += amount
	credits_changed.emit(credits)

## Removes a share of the player's balance and returns what was taken.
## Used when an enemy Spy loots a player Refinery.
func take_credits_fraction(fraction: float) -> int:
	var taken: int = int(credits * clampf(fraction, 0.0, 1.0))
	if taken <= 0:
		return 0
	credits -= taken
	credits_changed.emit(credits)
	return taken

func try_spend(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	credits_changed.emit(credits)
	return true

func has_power_shortage() -> bool:
	return power_consumed > power_generated

## LOW POWER is the consequence layer: defences go offline, radar
## degrades and production halves. Only the player's grid is simulated;
## the AI is assumed to keep its own house in order, so its structures
## are never browned out by the player's spending.
func is_low_power(is_player: bool = true) -> bool:
	if not is_player:
		return false
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

func _refinery_list(is_player: bool) -> Array:
	return _player_refineries if is_player else _enemy_refineries

func register_refinery(refinery: Node, is_player: bool = true) -> void:
	var list := _refinery_list(is_player)
	if not list.has(refinery):
		list.append(refinery)

func unregister_refinery(refinery: Node, is_player: bool = true) -> void:
	_refinery_list(is_player).erase(refinery)

func has_refinery(is_player: bool = true) -> bool:
	for refinery in _refinery_list(is_player):
		if is_instance_valid(refinery):
			return true
	return false

func get_first_refinery(is_player: bool = true) -> Node:
	for refinery in _refinery_list(is_player):
		if is_instance_valid(refinery):
			return refinery
	return null

func get_nearest_refinery(from_position: Vector3, is_player: bool = true) -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for refinery in _refinery_list(is_player):
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
