extends Node
class_name AIDirector

## The enemy commander.
##
## It plays the same game the player does - same buildings, same
## production queues, same credits, same harvest loop - rather than
## cheating units into existence. If the player kills its harvesters its
## economy stalls; if they raze its Barracks it stops making infantry.
##
## Decisions run on a slow think tick (THINK_INTERVAL), not per frame.
## Everything it does is expressed as the same CommandTypes the player
## issues, so the AI cannot do anything the player could not.
##
## Deliberately NOT modelled yet: the AI does not use fog. It knows where
## the player's base is from the start, because giving it real scouting
## needs a second fog grid, and a passive opponent teaches the player
## nothing. It is honest about resources and production instead.

const THINK_INTERVAL: float = 1.5
const ATTACK_WAVE_SIZE: int = 4
const MAX_HARVESTERS: int = 3
const BUILD_SPACING: float = 13.0

@export var refinery_stats: BuildingStats
@export var power_plant_stats: BuildingStats
@export var barracks_stats: BuildingStats
@export var war_factory_stats: BuildingStats

var base_position: Vector3 = Vector3.ZERO
var player_base_position: Vector3 = Vector3.ZERO
var enabled: bool = true

var _nav_region: Node
var _level: Node
var _timer: float = 0.0
var _wave: Array = []
var _build_slot: int = 0

func setup(nav_region: Node, level: Node, base: Vector3, player_base: Vector3) -> void:
	_nav_region = nav_region
	_level = level
	base_position = base
	player_base_position = player_base

func _process(delta: float) -> void:
	if not enabled or GameState.match_state != GameState.MatchState.PLAYING:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK_INTERVAL
	_think()

func _think() -> void:
	_run_economy()
	_run_construction()
	_run_production()
	_run_offense()

# ------------------------------------------------------------- economy

## Harvesters first and always: an AI that builds tanks before income
## simply stops after its opening money runs out.
func _run_economy() -> void:
	var refinery := GameState.get_first_refinery(false)
	if refinery == null:
		return
	if _count_harvesters() >= MAX_HARVESTERS:
		return
	if refinery.queue.queue_length() > 0:
		return
	refinery.produce_harvester()

func _count_harvesters() -> int:
	var count: int = 0
	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(unit) and unit.stats != null and unit.stats.is_harvester:
			count += 1
	return count

# --------------------------------------------------------- construction

## A fixed opening: income, then power, then the two production
## buildings. Simple and legible, and it fails visibly if the player
## denies it - which is the point.
func _run_construction() -> void:
	var wanted: BuildingStats = null
	if not _has_building("Resource Refinery"):
		wanted = refinery_stats
	elif not _has_building("Power Plant"):
		wanted = power_plant_stats
	elif not _has_building("Barracks"):
		wanted = barracks_stats
	elif not _has_building("War Factory"):
		wanted = war_factory_stats
	if wanted == null:
		return
	if not GameState.try_spend_for(false, wanted.cost):
		return
	_place(wanted)

func _has_building(display_name: String) -> bool:
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == display_name:
			return true
	return false

## Ring of slots around the base. Crude, but it keeps structures apart
## without a placement search, and the AI never needs to shuffle a base
## it cannot see.
func _place(stats: BuildingStats) -> void:
	var angle: float = TAU * float(_build_slot) / 6.0
	_build_slot += 1
	var offset := Vector3(cos(angle), 0, sin(angle)) * BUILD_SPACING
	var building = stats.scene.instantiate()
	building.stats = stats
	building.is_player_faction = false
	_nav_region.add_child(building)
	building.global_position = base_position + offset
	EventBus.building_placed.emit(building)

# ---------------------------------------------------------- production

func _run_production() -> void:
	var factory := _find_enemy_building("War Factory")
	if factory != null and factory.queue.queue_length() == 0:
		## Scouts are cheap and fast; a couple of tanks matter more.
		if randf() < 0.75:
			factory.produce_assault()
		else:
			factory.produce_scout()
		return

	var barracks := _find_enemy_building("Barracks")
	if barracks != null and barracks.queue.queue_length() == 0:
		barracks.produce_soldier()

func _find_enemy_building(display_name: String) -> Node:
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == display_name:
			return building
	return null

# ------------------------------------------------------------- offense

## Idle combat units gather until there are enough to be worth sending,
## then attack-move at the player's base together. Attacking in dribs and
## drabs feeds the defender; waiting for a wave is what makes the AI feel
## like an opponent rather than a stream of free kills.
func _run_offense() -> void:
	_wave = _wave.filter(func(u): return is_instance_valid(u))

	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.is_harvester or unit.get_node_or_null("AttackerComponent") == null:
			continue
		if _wave.has(unit):
			continue
		if unit.current_command == CommandTypes.Type.ATTACK_MOVE:
			continue
		## Units carrying an EnemyAIController are the standing garrison.
		## Drafting them empties the base the moment the first wave forms,
		## which hands the player a free counter-attack.
		if unit.get_node_or_null("AI") != null:
			continue
		_wave.append(unit)

	if _wave.size() < ATTACK_WAVE_SIZE:
		return

	for unit in _wave:
		unit.issue_command(CommandTypes.Type.ATTACK_MOVE, player_base_position)
	_wave.clear()
