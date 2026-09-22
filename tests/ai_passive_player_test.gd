extends Node

## The milestone's acceptance test.
##
## The player does nothing at all: builds nothing, produces nothing,
## issues no orders, never fights back. NORMAL AI must destroy the
## player's Command HQ within the time limit using the same economy the
## player has - no injected credits, no spawned waves.
##
## Passing is binary and deliberately harsh: HQ destroyed, or FAIL.
## Everything else printed is diagnosis for when it fails.

const TIME_LIMIT: float = 900.0
const SNAPSHOT_INTERVAL: float = 30.0

var _main: Node3D
var _director: AIDirector
var _economy: AIEconomy

var _peak_army_value: int = 0
var _peak_units: int = 0
var _peak_harvesters: int = 0
var _peak_refineries: int = 0
var _total_income: int = 0
var _total_spend: int = 0
var _attacks: int = 0
var _retreats: int = 0
var _player_structures_destroyed: int = 0
var _was_committed: bool = false
var _last_credits: int = 0
var _snapshot_timer: float = 0.0
var _start_player_buildings: int = 0
var _first_attack: float = -1.0

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	_director = _main.get_node("AIDirector")
	## Difficulty from a user argument, so the ladder can be measured
	## against an identical opponent: a passive player is the least noisy
	## board there is, which makes it the right place to compare how soon
	## and how hard each setting commits.
	var level: int = AIDirector.Difficulty.NORMAL
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			level = clampi(arg.to_int(), 0, 2)
	_director.difficulty = level
	_economy = _director.economy
	_last_credits = GameState.enemy_credits
	_start_player_buildings = get_tree().get_nodes_in_group("player_buildings").size()

	print("PASSIVE| difficulty=%s strategy=%s" % [
		["EASY", "NORMAL", "HARD"][_director.difficulty], _director.strategy_name()])

	await _run()
	get_tree().quit()

func _player_hq() -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			return b
	return null

func _run() -> void:
	var elapsed: float = 0.0
	var victory_time: float = -1.0

	while elapsed < TIME_LIMIT:
		var delta: float = get_process_delta_time()
		elapsed += delta
		await get_tree().process_frame

		## The player is passive by construction: never issue an order and
		## never let the selection layer act on its behalf.
		var army := _economy.army_value()
		_peak_army_value = maxi(_peak_army_value, army["total"])
		_peak_units = maxi(_peak_units, get_tree().get_nodes_in_group("enemy_units").size())
		_peak_harvesters = maxi(_peak_harvesters, _economy.harvesters().size())
		_peak_refineries = maxi(_peak_refineries, _economy.refineries().size())

		var now: int = GameState.enemy_credits
		if now > _last_credits:
			_total_income += now - _last_credits
		else:
			_total_spend += _last_credits - now
		_last_credits = now

		if _director._attack_committed and not _was_committed:
			_attacks += 1
			if _first_attack < 0.0:
				_first_attack = elapsed
		elif _was_committed and not _director._attack_committed:
			_retreats += 1
		_was_committed = _director._attack_committed

		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_INTERVAL
			print(_economy.format_line(elapsed))

		if _player_hq() == null:
			victory_time = elapsed
			break

	_player_structures_destroyed = _start_player_buildings \
		- get_tree().get_nodes_in_group("player_buildings").size()

	print("")
	print("PASSIVE| ===== RESULT =====")
	if victory_time >= 0.0:
		print("PASSIVE| VICTORY at %d:%02d" % [int(victory_time) / 60, int(victory_time) % 60])
	else:
		print("PASSIVE| FAIL - player HQ survived %d:%02d" % [int(elapsed) / 60, int(elapsed) % 60])
	print("PASSIVE| peak army value      %d credits" % _peak_army_value)
	print("PASSIVE| peak unit count      %d" % _peak_units)
	print("PASSIVE| peak harvesters      %d" % _peak_harvesters)
	print("PASSIVE| peak refineries      %d" % _peak_refineries)
	print("PASSIVE| total harvested      %d credits" % _total_income)
	print("PASSIVE| total spent          %d credits" % _total_spend)
	print("PASSIVE| first attack at      %s" % (
		"%d:%02d" % [int(_first_attack) / 60, int(_first_attack) % 60]
		if _first_attack >= 0.0 else "never"))
	print("PASSIVE| attacks committed    %d" % _attacks)
	print("PASSIVE| retreats             %d" % _retreats)
	print("PASSIVE| player structures destroyed %d of %d" % [
		_player_structures_destroyed, _start_player_buildings])
	print("PASSIVE| %s" % ("PASS" if victory_time >= 0.0 else "FAIL"))
