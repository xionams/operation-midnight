extends Node
class_name AIDirector

## The enemy commander: a goal-driven controller rather than a wave timer.
##
## It plays the same game the player does - same buildings, same queues,
## same credits, same prerequisites, same population cap - and it reasons
## only from its own state plus what AIMemory actually observed. It never
## reads hidden player state, so it can be baited, out-scouted and
## surprised.
##
## Each tick runs several goals in priority order rather than switching
## between exclusive states. Economy and construction always tick, so the
## AI never stops harvesting because it is "in ATTACK mode".
##
## Difficulty adjusts decision quality and tempo, never raw numbers: an
## EASY commander thinks slower and commits smaller groups; a HARD one
## scouts more and counter-produces sooner. Neither gets free money.

enum Difficulty { EASY, NORMAL, HARD }
enum Strategy { ECONOMY, INFANTRY_PRESSURE, FAST_VEHICLES, TECH }

const HARVESTER: UnitStats = preload("res://config/units/harvester.tres")
const RIFLE: UnitStats = preload("res://config/units/rifle_soldier.tres")
const AT_SQUAD: UnitStats = preload("res://config/units/at_squad.tres")
const SCOUT: UnitStats = preload("res://config/units/scout_vehicle.tres")
const ASSAULT: UnitStats = preload("res://config/units/assault_vehicle.tres")
const TANK: UnitStats = preload("res://config/units/main_battle_tank.tres")
const ARTILLERY: UnitStats = preload("res://config/units/artillery_vehicle.tres")

const REFINERY: BuildingStats = preload("res://config/buildings/refinery.tres")
const POWER_PLANT: BuildingStats = preload("res://config/buildings/power_plant.tres")
const BARRACKS: BuildingStats = preload("res://config/buildings/barracks.tres")
const FACTORY: BuildingStats = preload("res://config/buildings/war_factory.tres")
const RADAR: BuildingStats = preload("res://config/buildings/radar_center.tres")
const TECH: BuildingStats = preload("res://config/buildings/tech_center.tres")
const MG_TOWER: BuildingStats = preload("res://config/buildings/mg_tower.tres")
const FORWARD_POST: BuildingStats = preload("res://config/buildings/forward_post.tres")

## Treasury floor per difficulty. An EASY commander manages money badly
## on purpose; HARD keeps a deeper buffer so it can absorb a raid.
const RESERVE_BY_DIFFICULTY: Dictionary = {
	Difficulty.EASY: 700,
	Difficulty.NORMAL: 1500,
	Difficulty.HARD: 2000,
}

const BUILD_SPACING: float = 17.0
const DEFEND_RADIUS: float = 46.0
const RETREAT_LOSS_FRACTION: float = 0.65
## How far short of the objective an attack force gathers.
const STAGING_STANDOFF: float = 42.0
## Reinforcements wait until they are worth sending as a body.
const REINFORCE_MIN_VALUE: int = 1800
const MIN_SIEGE_SHARE: float = 0.2
## How far a committed wave will divert for an economic target. Small on
## purpose: harassment is an opportunity taken on the way, not a reason
## to drag an army across the map.
const OPPORTUNITY_RADIUS: float = 55.0
## Each piece of player economy destroyed buys this much extra tolerance
## for losses, and the bonus decays. Killing an economy should encourage
## the AI to press, not to declare the objective complete and leave.
const CONFIDENCE_PER_KILL: float = 0.08
const CONFIDENCE_DECAY: float = 0.01
const MAX_CONFIDENCE: float = 0.25

## Difficulty -> [think interval, group size scale, scouts, rebuild delay,
##                counter-production responsiveness]
const TUNING: Dictionary = {
	Difficulty.EASY:   [2.6, 0.7, 1, 22.0, 0.35],
	Difficulty.NORMAL: [1.5, 1.0, 2, 10.0, 0.7],
	Difficulty.HARD:   [1.0, 1.25, 3, 4.0, 1.0],
}

## Weighted openings - ECONOMY is the sane default and the aggressive
## plans are the interesting minority, so matches differ without the AI
## behaving randomly.
const STRATEGY_WEIGHTS: Dictionary = {
	Strategy.ECONOMY: 40,
	Strategy.INFANTRY_PRESSURE: 25,
	Strategy.FAST_VEHICLES: 20,
	Strategy.TECH: 15,
}

@export var difficulty: Difficulty = Difficulty.NORMAL

## Which side this commander plays. The brain is identical for both - only
## the groups it reads and the treasury it spends change. Running a second
## instance on the player side is how the AI finally gets an opponent that
## fights back, instead of being measured against someone standing still.
@export var is_player: bool = false

var base_position: Vector3 = Vector3.ZERO
var enabled: bool = true
var strategy: int = Strategy.ECONOMY
var memory: AIMemory
var economy: AIEconomy

var _nav_region: Node
var _level: Node
var _timer: float = 0.0
var _match_time: float = 0.0
var _build_slot: int = 0
var _attack_group: Array = []
var _attack_committed: bool = false
var _attack_start_strength: int = 0
var _current_objective: Vector3 = Vector3.ZERO
var _rebuild_cooldown: float = 0.0
var _scouts: Array = []
var _reinforcements: Array = []
## Grows when the AI razes the player's economy, decays with time.
var _confidence: float = 0.0
## When the staging force first became worth sending, so a commander that
## keeps almost-attacking eventually commits.
var _ready_since: float = 0.0

func setup(nav_region: Node, level: Node, base: Vector3, _player_base: Vector3) -> void:
	_nav_region = nav_region
	_level = level
	base_position = base
	memory = AIMemory.new()
	memory.name = "AIMemory"
	memory.is_player = is_player
	add_child(memory)

	economy = AIEconomy.new()
	economy.name = "AIEconomy"
	economy.is_player = is_player
	economy.reserve_target = RESERVE_BY_DIFFICULTY[difficulty]
	add_child(economy)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	## The parameter name here used to be `is_player`, which shadowed this
	## commander's own is_player - so once a second commander existed,
	## BOTH of them recorded only the enemy's harvest trips and sized
	## their harvester fleets off the opponent's route. Identical
	## round-trip numbers for both sides in the same match is what gave
	## it away; it is not a value two economies can share by accident.
	EventBus.harvest_round_trip.connect(func(from_player_side, seconds):
		if from_player_side == is_player:
			economy.record_round_trip(seconds))

	strategy = _pick_strategy()

func _pick_strategy() -> int:
	var total: int = 0
	for weight in STRATEGY_WEIGHTS.values():
		total += weight
	var roll: int = randi() % total
	for option in STRATEGY_WEIGHTS:
		roll -= STRATEGY_WEIGHTS[option]
		if roll < 0:
			return option
	return Strategy.ECONOMY

func _tuning() -> Array:
	return TUNING[difficulty]

func strategy_name() -> String:
	return Strategy.keys()[strategy]

func _process(delta: float) -> void:
	if not enabled or GameState.match_state != GameState.MatchState.PLAYING:
		return
	_match_time += delta
	_rebuild_cooldown = maxf(0.0, _rebuild_cooldown - delta)
	_confidence = maxf(0.0, _confidence - CONFIDENCE_DECAY * delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _tuning()[0]
	_think()

func _think() -> void:
	_run_economy()
	_run_construction()
	_run_production()
	_run_scouting()
	_run_defence()
	_run_offense()

# ------------------------------------------------------------- helpers

func _own_units() -> String:
	return "player_units" if is_player else "enemy_units"

func _own_buildings() -> String:
	return "player_buildings" if is_player else "enemy_buildings"

func _foe_units() -> String:
	return "enemy_units" if is_player else "player_units"

func _foe_buildings() -> String:
	return "enemy_buildings" if is_player else "player_buildings"

func _own(display_name: String) -> Node:
	for building in get_tree().get_nodes_in_group(_own_buildings()):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == display_name:
			return building
	return null

func _count_units(predicate: Callable) -> int:
	var count: int = 0
	for unit in get_tree().get_nodes_in_group(_own_units()):
		if is_instance_valid(unit) and unit.stats != null and predicate.call(unit):
			count += 1
	return count

func _harvesters() -> int:
	return _count_units(func(u): return u.stats.is_harvester)

func _combat_units() -> Array:
	var list: Array = []
	for unit in get_tree().get_nodes_in_group(_own_units()):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.is_harvester or unit.get_node_or_null("AttackerComponent") == null:
			continue
		list.append(unit)
	return list

# ------------------------------------------------------------- economy

## Harvester count scales with refineries. An AI that builds tanks before
## income simply stops once its opening money is gone.
## Harvesters are the highest-value purchase the AI can make while its
## refineries are under-saturated, and replacing a lost one is CRITICAL -
## an economy with no earners cannot recover by saving.
func _run_economy() -> void:
	if not economy.needs_harvester():
		return
	var refinery := GameState.get_first_refinery(is_player)
	if refinery == null or refinery.queue.queue_length() > 0:
		return
	var urgency: AIEconomy.Priority = AIEconomy.Priority.CRITICAL \
		if economy.active_harvesters() == 0 else AIEconomy.Priority.ECONOMY
	if not economy.can_afford(HARVESTER.cost, urgency):
		return
	refinery.produce(HARVESTER)

# --------------------------------------------------------- construction

func _build_order() -> Array:
	match strategy:
		## Every opening takes a second refinery before the tech tier. One
		## refinery cannot fund continuous production, which is precisely
		## how the commander ended up pinned at zero credits all match.
		Strategy.INFANTRY_PRESSURE:
			return [REFINERY, BARRACKS, POWER_PLANT, REFINERY, FACTORY, POWER_PLANT, RADAR, TECH]
		Strategy.FAST_VEHICLES:
			return [REFINERY, POWER_PLANT, FACTORY, REFINERY, BARRACKS, POWER_PLANT, RADAR, TECH]
		Strategy.TECH:
			return [REFINERY, POWER_PLANT, REFINERY, BARRACKS, FACTORY, POWER_PLANT, RADAR, TECH]
		_:
			return [REFINERY, POWER_PLANT, REFINERY, BARRACKS, FACTORY, POWER_PLANT, RADAR, TECH]

## Rebuilding is the same code path as building: a razed structure simply
## becomes a gap in the wanted list again, and the AI pays for it like
## anything else.
func _run_construction() -> void:
	if _rebuild_cooldown > 0.0:
		return

	var wanted: BuildingStats = null
	if _power_shortfall() > 0:
		wanted = POWER_PLANT
	else:
		var counts: Dictionary = {}
		for building in get_tree().get_nodes_in_group(_own_buildings()):
			if is_instance_valid(building) and building.stats != null:
				var key: String = building.stats.display_name
				counts[key] = counts.get(key, 0) + 1
		var order := _build_order()
		for candidate in order:
			if counts.get(candidate.display_name, 0) < order.count(candidate):
				wanted = candidate
				break

	## Home ore running dry and another field known: plant a forward post
	## out there so a refinery can follow. This is the only construction
	## that happens away from the main base.
	if wanted == null and _should_expand():
		var site := _expansion_site()
		if site != Vector3.ZERO and GameState.try_spend_for(is_player, FORWARD_POST.cost):
			_place_at(FORWARD_POST, site)
			_rebuild_cooldown = _tuning()[3]
			return

	## A base that has been attacked wants a tower covering the approach.
	if wanted == null and not memory.recent_attack_positions.is_empty() \
		and _own("Machine Gun Tower") == null and TechTree.is_available(MG_TOWER, is_player):
		wanted = MG_TOWER

	if wanted == null or not TechTree.is_available(wanted, is_player):
		return

	## Infrastructure the economy cannot run without outranks the reserve;
	## everything else respects it.
	var priority: AIEconomy.Priority = AIEconomy.Priority.TECH
	if wanted == REFINERY and economy.refineries().is_empty():
		priority = AIEconomy.Priority.CRITICAL
	elif wanted == POWER_PLANT and _power_shortfall() > 0:
		priority = AIEconomy.Priority.CRITICAL
	elif wanted == REFINERY or wanted == FORWARD_POST:
		priority = AIEconomy.Priority.ECONOMY
	elif wanted == MG_TOWER:
		priority = AIEconomy.Priority.DEFENCE

	if not economy.can_afford(wanted.cost, priority):
		return
	if not GameState.try_spend_for(is_player, wanted.cost):
		return
	_place(wanted)
	_rebuild_cooldown = _tuning()[3]

## Expand when the ore near home is nearly gone and the commander knows
## of a field somewhere else.
## Expand when income is inadequate or the ore near home is thinning, and
## a field is known elsewhere. A post on its own earns nothing, so the
## build order follows it with a refinery out there.
func _should_expand() -> bool:
	if _own("Forward Command Post") != null:
		return false
	if memory.known_resource_fields.size() < 2:
		return false
	if economy.refineries().size() < 2:
		return false
	var home_remaining: float = 0.0
	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(field) and field.global_position.distance_to(base_position) < 60.0:
			home_remaining += field.remaining
	return home_remaining < 9000.0 or economy.income_per_minute < 2500.0

func _expansion_site() -> Vector3:
	var best := Vector3.ZERO
	var best_distance: float = INF
	for field in memory.known_resource_fields:
		var distance: float = field.distance_to(base_position)
		if distance < 50.0 or distance >= best_distance:
			continue
		best_distance = distance
		best = field
	if best == Vector3.ZERO:
		return Vector3.ZERO
	## Set down beside the ore, not on top of it.
	return best + (base_position - best).normalized() * 14.0

func _place_at(stats: BuildingStats, position: Vector3) -> void:
	var building = stats.scene.instantiate()
	building.stats = stats
	building.is_player_faction = is_player
	_nav_region.add_child(building)
	building.global_position = position
	EventBus.building_placed.emit(building)

func _power_shortfall() -> int:
	var generated: int = 0
	var consumed: int = 0
	for building in get_tree().get_nodes_in_group(_own_buildings()):
		if not is_instance_valid(building) or building.stats == null:
			continue
		generated += building.stats.power_generation
		consumed += building.stats.power_consumption
	return maxi(0, consumed - generated)

## A ring of slots that expands outward, wide enough that structures
## never seal the AI's own harvesters inside the base.
func _place(stats: BuildingStats) -> void:
	var angle: float = TAU * float(_build_slot % 7) / 7.0
	var ring: float = BUILD_SPACING + float(_build_slot / 7) * 9.0
	_build_slot += 1
	var offset := Vector3(cos(angle), 0, sin(angle)) * ring
	var building = stats.scene.instantiate()
	building.stats = stats
	building.is_player_faction = is_player
	_nav_region.add_child(building)
	building.global_position = base_position + offset
	EventBus.building_placed.emit(building)

# ---------------------------------------------------------- production

## Composition responds to what the AI has seen, scaled by difficulty.
## Counters are never instant: it has to scout first, and a low
## difficulty commander reacts sluggishly even once it knows.
## Credits held back so construction can always proceed. Without this the
## production queues drain the treasury every tick and the AI never
## affords its second refinery - it stalls at four buildings and a
## handful of units, which is exactly what it did.
func _construction_reserve() -> int:
	if _own("Resource Refinery") == null:
		return 0
	var order := _build_order()
	var counts: Dictionary = {}
	for building in get_tree().get_nodes_in_group(_own_buildings()):
		if is_instance_valid(building) and building.stats != null:
			var key: String = building.stats.display_name
			counts[key] = counts.get(key, 0) + 1
	for candidate in order:
		if counts.get(candidate.display_name, 0) < order.count(candidate):
			return candidate.cost
	return 0

func _run_production() -> void:
	var composition: Dictionary = memory.estimated_composition()
	var responsiveness: float = _tuning()[4]
	var reserve: int = _construction_reserve()

	var factory := _own("Vehicle Factory")
	if factory != null and factory.queue.queue_length() == 0:
		var vehicle := _pick_vehicle(composition, responsiveness)
		## Nothing in the army can dent a building: build something that
		## can, ahead of whatever the counter logic would rather have.
		if _lacks_siege():
			if TechTree.is_available(ARTILLERY, is_player):
				vehicle = ARTILLERY
			elif TechTree.is_available(TANK, is_player):
				vehicle = TANK
			elif TechTree.is_available(ASSAULT, is_player):
				vehicle = ASSAULT
		if GameState.balance_of(is_player) - vehicle.cost >= reserve \
			and economy.can_afford(vehicle.cost, AIEconomy.Priority.ARMY):
			factory.produce(vehicle)
			return

	var barracks := _own("Barracks")
	if barracks != null and barracks.queue.queue_length() == 0:
		var squad := _pick_infantry(composition, responsiveness)
		if GameState.balance_of(is_player) - squad.cost >= reserve \
			and economy.can_afford(squad.cost, AIEconomy.Priority.ARMY):
			barracks.produce(squad)

func _pick_infantry(composition: Dictionary, responsiveness: float) -> UnitStats:
	var armour_share: float = composition.get("armor", 0.0) + composition.get("vehicle", 0.0)
	if armour_share * responsiveness > 0.3 and TechTree.is_available(AT_SQUAD, is_player):
		return AT_SQUAD
	return RIFLE

## True when the standing army has nothing that meaningfully damages a
## structure. An all-infantry wave bounces off a Command HQ, which is a
## large part of why the AI could pressure but never finish.
func _lacks_siege() -> bool:
	for unit in _combat_units():
		var weapon: WeaponStats = unit.stats.weapon_stats
		if weapon == null:
			continue
		if weapon.multiplier_for(Armor.Type.STRUCTURE) >= 0.5:
			return false
	return true

func _pick_vehicle(composition: Dictionary, responsiveness: float) -> UnitStats:
	## A turtling player calls for something that outranges a turret.
	if memory.has_seen_building("Machine Gun Tower") or memory.has_seen_building("Anti-Armor Turret"):
		if TechTree.is_available(ARTILLERY, is_player) and randf() < 0.5 * responsiveness + 0.2:
			return ARTILLERY
	if composition.get("infantry", 0.0) > 0.5 and TechTree.is_available(ASSAULT, is_player):
		return ASSAULT
	if TechTree.is_available(TANK, is_player) and randf() < 0.45:
		return TANK
	if _count_units(func(u): return u.stats.display_name == "Scout Vehicle") < _tuning()[2]:
		return SCOUT
	return ASSAULT

# ------------------------------------------------------------ scouting

## Scouts sweep unexplored ground and known landmarks. They deliberately
## never join attack groups - their job is information, and losing them
## blinds the commander.
func _run_scouting() -> void:
	_scouts = _scouts.filter(func(s): return is_instance_valid(s))
	var wanted: int = _tuning()[2]

	if _scouts.size() < wanted:
		for unit in get_tree().get_nodes_in_group(_own_units()):
			if not is_instance_valid(unit) or unit.stats == null:
				continue
			if unit.stats.display_name != "Scout Vehicle" or _scouts.has(unit):
				continue
			_scouts.append(unit)
			if _scouts.size() >= wanted:
				break

	for scout in _scouts:
		if not is_instance_valid(scout):
			continue
		## Retreat rather than trade: a dead scout is a blind commander.
		if scout.health != null and scout.health.health_fraction() < 0.5:
			scout.issue_command(CommandTypes.Type.MOVE, base_position)
			continue
		if scout.nav_agent != null and not scout.nav_agent.is_navigation_finished():
			continue
		scout.issue_command(CommandTypes.Type.MOVE, _next_scout_target())

func _next_scout_target() -> Vector3:
	var half: float = FogOfWar.get_map_size() * 0.5 - 12.0
	if memory.has_base_guess and randf() < 0.3:
		return memory.player_base_guess
	if not memory.known_resource_fields.is_empty() and randf() < 0.3:
		return memory.known_resource_fields.pick_random()
	return Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))

# ------------------------------------------------------------- defence

## Respond in proportion. A lone scout shooting at a wall gets the local
## garrison; a real push pulls the standing army home.
func _run_defence() -> void:
	var threats: Array = []
	for unit in get_tree().get_nodes_in_group(_foe_units()):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.global_position.distance_to(base_position) > DEFEND_RADIUS:
			continue
		if not _visible_to_ai(unit.global_position):
			continue
		threats.append(unit)

	if threats.is_empty():
		return
	memory.record_attack_at(threats[0].global_position)

	var serious: bool = threats.size() >= 3
	for unit in _combat_units():
		if not is_instance_valid(unit):
			continue
		## Committed attackers keep going unless this is a real emergency.
		if not serious and _attack_group.has(unit):
			continue
		if not serious and unit.global_position.distance_to(base_position) > DEFEND_RADIUS:
			continue
		unit.issue_command(CommandTypes.Type.ATTACK_MOVE, threats[0].global_position)
		_attack_group.erase(unit)
		_reinforcements.erase(unit)

func _visible_to_ai(point: Vector3) -> bool:
	var eyes: Array = get_tree().get_nodes_in_group(_own_units())
	eyes.append_array(get_tree().get_nodes_in_group(_own_buildings()))
	for eye in eyes:
		if not is_instance_valid(eye) or eye.stats == null:
			continue
		if eye.global_position.distance_to(point) <= eye.stats.vision_range:
			return true
	return false

# ------------------------------------------------------------- offense

## Attack readiness is measured in credits committed, not bodies. Twenty
## rifle squads and four tanks are not the same army, and counting heads
## said they were - which is how the AI ended up trickling infantry into
## a base it could never break.
## How much army is worth committing.
##
## This used to ramp on the clock alone, which made the commander MORE
## passive the longer a match ran: after a failed attack the bar had
## risen, so it rebuilt toward a number it could no longer reach and
## never attacked again. Measured in AI-vs-AI, each side attacked exactly
## once in eight minutes.
##
## The bar is now mostly about the opponent. Enough to beat what has
## actually been seen, with a margin - floored so it never trickles, and
## capped so it never waits forever. The clock only raises the floor.
const ATTACK_MARGIN: float = 1.35
const ATTACK_FLOOR: float = 2600.0
const ATTACK_CEILING: float = 9000.0
## A force that has been ready this long goes anyway. Waiting past the
## point of readiness is how an army rots in its own base.
const PATIENCE: float = 75.0

func desired_group_value() -> int:
	var floor_value: float = ATTACK_FLOOR
	if _match_time > 330.0:
		floor_value = 4200.0
	elif _match_time > 180.0:
		floor_value = 3400.0

	var needed: float = float(memory.seen_army_value()) * ATTACK_MARGIN
	var target: float = clampf(maxf(needed, floor_value), ATTACK_FLOOR, ATTACK_CEILING)
	return int(target * _tuning()[1])

func desired_group_size() -> int:
	var base_size: float = 6.0
	if _match_time > 600.0:
		base_size = 14.0
	elif _match_time > 360.0:
		base_size = 10.0
	elif _match_time > 180.0:
		base_size = 7.0
	return maxi(3, int(base_size * _tuning()[1]))

func _group_value(units: Array) -> int:
	var total: int = 0
	for unit in units:
		if is_instance_valid(unit) and unit.stats != null:
			total += unit.stats.cost
	return total

## Share of the gathered force that can actually hurt a building. An
## all-infantry wave bounces off a Command HQ no matter how large it is.
func _group_siege_share(units: Array) -> float:
	var total: int = 0
	var siege: int = 0
	for unit in units:
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		var weapon: WeaponStats = unit.stats.weapon_stats
		if weapon == null:
			continue
		total += unit.stats.cost
		if weapon.multiplier_for(Armor.Type.STRUCTURE) >= 0.5:
			siege += unit.stats.cost
	return float(siege) / maxf(float(total), 1.0)

## Staging point: short of the objective, so the force gathers out of
## reach of whatever is defending it rather than arriving one unit at a
## time inside the enemy's guns.
func _staging_point(objective: Vector3) -> Vector3:
	var toward_home: Vector3 = (base_position - objective)
	if toward_home.length() < 1.0:
		return base_position
	return objective + toward_home.normalized() * STAGING_STANDOFF

## Gathers a group, commits it at a chosen target, and pulls the
## survivors out when it is clearly losing. Attacking piecemeal feeds the
## defender; never retreating makes every battle a suicide.
## Why no attack is being committed right now. Exists because "the AI
## does not attack again after a retreat" is a claim with five possible
## causes, and guessing which one has already cost two wrong fixes.
func offense_block_reason() -> String:
	if _attack_committed:
		return "committed"
	var value: int = _group_value(_reinforcements)
	var want: int = desired_group_value()
	if value < want and not (_ready_since > 0.0 and _match_time - _ready_since > PATIENCE):
		return "force %d < %d" % [value, want]
	if _group_siege_share(_reinforcements) < MIN_SIEGE_SHARE:
		return "siege %.0f%% < %.0f%%" % [
			_group_siege_share(_reinforcements) * 100.0, MIN_SIEGE_SHARE * 100.0]
	if not economy.can_sustain_offensive():
		return "economy: harv=%d ref=%d in/min=%d cr=%d" % [
			economy.active_harvesters(), economy.refineries().size(),
			int(economy.income_per_minute), GameState.balance_of(is_player)]
	return "ready"

func _run_offense() -> void:
	_attack_group = _attack_group.filter(func(u): return is_instance_valid(u))
	_reinforcements = _reinforcements.filter(func(u): return is_instance_valid(u))

	## Newly produced units join a staging pool, never the battle line
	## directly. Feeding units in one at a time is how an army is spent
	## without ever being used.
	for unit in _combat_units():
		if _attack_group.has(unit) or _reinforcements.has(unit) or _scouts.has(unit):
			continue
		_reinforcements.append(unit)
		unit.issue_command(CommandTypes.Type.MOVE, _staging_point(_pending_objective()))

	if _attack_committed:
		_release_reinforcements()
		_attack_start_strength = maxi(_attack_start_strength, _attack_group.size())
		_retarget_if_objective_cleared()
		_review_attack()
		return

	## Gather at the staging point until the force is worth committing,
	## can hurt buildings, and the economy can replace what it loses.
	var value: int = _group_value(_reinforcements)
	if value >= desired_group_value():
		_ready_since = _ready_since if _ready_since > 0.0 else _match_time
	elif value < ATTACK_FLOOR * _tuning()[1]:
		## Dropped below a force worth sending at all; start the clock over.
		_ready_since = 0.0

	var impatient: bool = _ready_since > 0.0 and _match_time - _ready_since > PATIENCE
	if value < desired_group_value() and not impatient:
		return
	if _group_siege_share(_reinforcements) < MIN_SIEGE_SHARE:
		return
	if not economy.can_sustain_offensive():
		return
	_ready_since = 0.0

	_attack_group = _reinforcements.duplicate()
	_reinforcements.clear()
	_current_objective = _choose_target()
	_attack_start_strength = _attack_group.size()
	_attack_committed = true
	for unit in _attack_group:
		unit.issue_command(CommandTypes.Type.ATTACK_MOVE, _current_objective)

## Reinforcements join the fight as a body once they are worth sending,
## rather than arriving individually and dying individually.
func _release_reinforcements() -> void:
	if _group_value(_reinforcements) < REINFORCE_MIN_VALUE:
		return
	for unit in _reinforcements:
		if is_instance_valid(unit):
			unit.issue_command(CommandTypes.Type.ATTACK_MOVE, _current_objective)
			_attack_group.append(unit)
	_reinforcements.clear()

## Where the next attack will go, so staging can be positioned before the
## force is committed.
func _pending_objective() -> Vector3:
	if _current_objective != Vector3.ZERO:
		return _current_objective
	return _choose_target()

## Prefer a soft, valuable target the AI has actually seen over driving
## into whatever is best defended. Production first, because killing
## production is what actually wins - an army can be replaced, a razed
## Vehicle Factory cannot until it is rebuilt.
func _choose_target() -> Vector3:
	for key in ["Vehicle Factory", "Barracks", "Resource Refinery", "Power Plant"]:
		if memory.has_seen_building(key):
			return memory.seen_buildings[key]["position"]
	if memory.has_base_guess:
		return memory.player_base_guess
	## Nothing found yet - probe toward the far side of the map.
	return -base_position

## Phase 15: killing the player's economy is cheaper than killing their
## base, but only when the target is on the way. Returns the best fresh
## economic sighting within OPPORTUNITY_RADIUS of where the army already
## is, ranked harvester -> refinery -> power -> production, or ZERO when
## nothing qualifies. The radius is what stops this from turning an
## assault into a wild goose chase.
const OPPORTUNITY_RANK: Array[String] = [
	"harvester", "Resource Refinery", "Power Plant", "Vehicle Factory", "Barracks",
]

func _army_centre() -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for unit in _attack_group:
		if is_instance_valid(unit):
			sum += unit.global_position
			count += 1
	if count == 0:
		return Vector3.ZERO
	return sum / float(count)

func _opportunity_target(from: Vector3) -> Vector3:
	if from == Vector3.ZERO:
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_rank: int = OPPORTUNITY_RANK.size()
	var best_distance: float = INF
	for record in memory.fresh_economy_targets():
		var distance: float = from.distance_to(record["position"])
		if distance > OPPORTUNITY_RADIUS:
			continue
		var rank: int = OPPORTUNITY_RANK.find(record["kind"])
		if rank < 0:
			continue
		if rank > best_rank or (rank == best_rank and distance >= best_distance):
			continue
		best_rank = rank
		best_distance = distance
		best = record["position"]
	return best

## A committed wave that has arrived and run out of things to shoot picks
## the next structure rather than standing on the rubble of the first.
func _retarget_if_objective_cleared() -> void:
	if _current_objective == Vector3.ZERO or _attack_group.is_empty():
		return
	var arrived: int = 0
	for unit in _attack_group:
		if is_instance_valid(unit) \
			and unit.global_position.distance_to(_current_objective) < 16.0:
			arrived += 1
	if arrived < maxi(2, _attack_group.size() / 2):
		return

	## Something economic within reach beats walking to the next building
	## on the list.
	var opportunity := _opportunity_target(_army_centre())
	if opportunity != Vector3.ZERO \
		and opportunity.distance_to(_current_objective) > 6.0:
		_current_objective = opportunity
		for unit in _attack_group:
			if is_instance_valid(unit):
				unit.issue_command(CommandTypes.Type.ATTACK_MOVE, _current_objective)
		return
	## Anything still standing within reach of where they are?
	for target in get_tree().get_nodes_in_group(_foe_buildings()):
		if not is_instance_valid(target):
			continue
		if target.global_position.distance_to(_current_objective) > 60.0:
			continue
		if target.global_position.distance_to(_current_objective) < 6.0:
			continue
		_current_objective = target.global_position
		for unit in _attack_group:
			if is_instance_valid(unit):
				unit.issue_command(CommandTypes.Type.ATTACK_MOVE, _current_objective)
		return

## Phase 16: the player losing economic infrastructure is a compounding
## advantage, and the AI should treat it as one. A wave that has just
## razed a refinery keeps going rather than turning for home on the next
## casualty.
func _on_building_destroyed(building: Node) -> void:
	if not is_instance_valid(building) or building.stats == null:
		return
	if building.is_player_faction != (not is_player) or building.is_neutral:
		return
	if not AIMemory.ECONOMIC_BUILDINGS.has(building.stats.display_name):
		return
	_confidence = minf(MAX_CONFIDENCE, _confidence + CONFIDENCE_PER_KILL)

func _review_attack() -> void:
	if _attack_group.is_empty():
		_attack_committed = false
		return
	var lost: float = 1.0 - float(_attack_group.size()) / maxf(float(_attack_start_strength), 1.0)
	if lost < RETREAT_LOSS_FRACTION + _confidence:
		return
	## The push has failed. Pull the survivors home rather than feeding
	## them in one at a time.
	for unit in _attack_group:
		if is_instance_valid(unit):
			unit.issue_command(CommandTypes.Type.MOVE, base_position)
			memory.record_loss_at(unit.global_position)
	_attack_group.clear()
	_attack_committed = false
	_current_objective = Vector3.ZERO
