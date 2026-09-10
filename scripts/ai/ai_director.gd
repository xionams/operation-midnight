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

const BUILD_SPACING: float = 17.0
const DEFEND_RADIUS: float = 46.0
const RETREAT_LOSS_FRACTION: float = 0.65

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

var base_position: Vector3 = Vector3.ZERO
var enabled: bool = true
var strategy: int = Strategy.ECONOMY
var memory: AIMemory

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

func setup(nav_region: Node, level: Node, base: Vector3, _player_base: Vector3) -> void:
	_nav_region = nav_region
	_level = level
	base_position = base
	memory = AIMemory.new()
	memory.name = "AIMemory"
	add_child(memory)
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

func _own(display_name: String) -> Node:
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == display_name:
			return building
	return null

func _count_units(predicate: Callable) -> int:
	var count: int = 0
	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(unit) and unit.stats != null and predicate.call(unit):
			count += 1
	return count

func _harvesters() -> int:
	return _count_units(func(u): return u.stats.is_harvester)

func _combat_units() -> Array:
	var list: Array = []
	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.is_harvester or unit.get_node_or_null("AttackerComponent") == null:
			continue
		list.append(unit)
	return list

# ------------------------------------------------------------- economy

## Harvester count scales with refineries. An AI that builds tanks before
## income simply stops once its opening money is gone.
func _run_economy() -> void:
	var refineries: int = 0
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building is Refinery:
			refineries += 1
	if refineries == 0:
		return
	if _harvesters() >= clampi(refineries * 3, 3, 6):
		return
	var refinery := GameState.get_first_refinery(false)
	if refinery != null and refinery.queue.queue_length() == 0:
		refinery.produce(HARVESTER)

# --------------------------------------------------------- construction

func _build_order() -> Array:
	match strategy:
		Strategy.INFANTRY_PRESSURE:
			return [REFINERY, BARRACKS, POWER_PLANT, BARRACKS, FACTORY, RADAR, TECH]
		Strategy.FAST_VEHICLES:
			return [REFINERY, POWER_PLANT, FACTORY, BARRACKS, RADAR, TECH]
		Strategy.TECH:
			return [REFINERY, POWER_PLANT, BARRACKS, FACTORY, RADAR, TECH, POWER_PLANT]
		_:
			return [REFINERY, POWER_PLANT, BARRACKS, REFINERY, FACTORY, RADAR, TECH]

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
		for building in get_tree().get_nodes_in_group("enemy_buildings"):
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
		if site != Vector3.ZERO and GameState.try_spend_for(false, FORWARD_POST.cost):
			_place_at(FORWARD_POST, site)
			_rebuild_cooldown = _tuning()[3]
			return

	## A base that has been attacked wants a tower covering the approach.
	if wanted == null and not memory.recent_attack_positions.is_empty() \
		and _own("Machine Gun Tower") == null and TechTree.is_available(MG_TOWER, false):
		wanted = MG_TOWER

	if wanted == null or not TechTree.is_available(wanted, false):
		return
	if not GameState.try_spend_for(false, wanted.cost):
		return
	_place(wanted)
	_rebuild_cooldown = _tuning()[3]

## Expand when the ore near home is nearly gone and the commander knows
## of a field somewhere else.
func _should_expand() -> bool:
	if _own("Forward Command Post") != null:
		return false
	if memory.known_resource_fields.size() < 2:
		return false
	var home_remaining: float = 0.0
	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(field) and field.global_position.distance_to(base_position) < 60.0:
			home_remaining += field.remaining
	return home_remaining < 6000.0

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
	building.is_player_faction = false
	_nav_region.add_child(building)
	building.global_position = position
	EventBus.building_placed.emit(building)

func _power_shortfall() -> int:
	var generated: int = 0
	var consumed: int = 0
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
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
	building.is_player_faction = false
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
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
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
		if GameState.enemy_credits - vehicle.cost >= reserve:
			factory.produce(vehicle)
			return

	var barracks := _own("Barracks")
	if barracks != null and barracks.queue.queue_length() == 0:
		var squad := _pick_infantry(composition, responsiveness)
		if GameState.enemy_credits - squad.cost >= reserve:
			barracks.produce(squad)

func _pick_infantry(composition: Dictionary, responsiveness: float) -> UnitStats:
	var armour_share: float = composition.get("armor", 0.0) + composition.get("vehicle", 0.0)
	if armour_share * responsiveness > 0.3 and TechTree.is_available(AT_SQUAD, false):
		return AT_SQUAD
	return RIFLE

func _pick_vehicle(composition: Dictionary, responsiveness: float) -> UnitStats:
	## A turtling player calls for something that outranges a turret.
	if memory.has_seen_building("Machine Gun Tower") or memory.has_seen_building("Anti-Armor Turret"):
		if TechTree.is_available(ARTILLERY, false) and randf() < 0.5 * responsiveness + 0.2:
			return ARTILLERY
	if composition.get("infantry", 0.0) > 0.5 and TechTree.is_available(ASSAULT, false):
		return ASSAULT
	if TechTree.is_available(TANK, false) and randf() < 0.45:
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
		for unit in get_tree().get_nodes_in_group("enemy_units"):
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
	for unit in get_tree().get_nodes_in_group("player_units"):
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

func _visible_to_ai(point: Vector3) -> bool:
	var eyes: Array = get_tree().get_nodes_in_group("enemy_units")
	eyes.append_array(get_tree().get_nodes_in_group("enemy_buildings"))
	for eye in eyes:
		if not is_instance_valid(eye) or eye.stats == null:
			continue
		if eye.global_position.distance_to(point) <= eye.stats.vision_range:
			return true
	return false

# ------------------------------------------------------------- offense

func desired_group_size() -> int:
	var base_size: float = 6.0
	if _match_time > 600.0:
		base_size = 14.0
	elif _match_time > 360.0:
		base_size = 10.0
	elif _match_time > 180.0:
		base_size = 7.0
	return maxi(3, int(base_size * _tuning()[1]))

## Gathers a group, commits it at a chosen target, and pulls the
## survivors out when it is clearly losing. Attacking piecemeal feeds the
## defender; never retreating makes every battle a suicide.
func _run_offense() -> void:
	_attack_group = _attack_group.filter(func(u): return is_instance_valid(u))

	## Absorb anything idle, whether or not a push is already under way.
	## Without this the AI commits one wave and then never attacks again
	## until that wave is destroyed, quietly stockpiling an army at home
	## while the player is left alone.
	var reinforcements: Array = []
	for unit in _combat_units():
		if _attack_group.has(unit) or _scouts.has(unit):
			continue
		_attack_group.append(unit)
		reinforcements.append(unit)

	if _attack_committed:
		var target := _current_objective
		for unit in reinforcements:
			unit.issue_command(CommandTypes.Type.ATTACK_MOVE, target)
		## Peak strength, so a group that has been topped up is judged
		## against how strong it ever was rather than its opening size.
		_attack_start_strength = maxi(_attack_start_strength, _attack_group.size())
		_review_attack()
		return

	if _attack_group.size() < desired_group_size():
		return

	_current_objective = _choose_target()
	_attack_start_strength = _attack_group.size()
	_attack_committed = true
	for unit in _attack_group:
		unit.issue_command(CommandTypes.Type.ATTACK_MOVE, _current_objective)

## Prefer a soft, valuable target the AI has actually seen over driving
## into whatever is best defended.
func _choose_target() -> Vector3:
	for key in ["Resource Refinery", "Vehicle Factory", "Barracks", "Power Plant"]:
		if memory.has_seen_building(key):
			return memory.seen_buildings[key]["position"]
	if memory.has_base_guess:
		return memory.player_base_guess
	## Nothing found yet - probe toward the far side of the map.
	return -base_position

func _review_attack() -> void:
	if _attack_group.is_empty():
		_attack_committed = false
		return
	var lost: float = 1.0 - float(_attack_group.size()) / maxf(float(_attack_start_strength), 1.0)
	if lost < RETREAT_LOSS_FRACTION:
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
