extends Node

## Walks the brief's acceptance sequence end to end, driving the real
## systems the player would drive: construction orders, placement, tech
## unlocks, production, power, combat and victory.
##
## It is deliberately generous with credits and time-compresses the match
## - the point is that the whole loop connects and nothing errors, not
## that the pacing is right, which is judged by playing.

const CHECK_TIMEOUT: float = 40.0

var _main: Node3D
var _placer: BuildingPlacer
var _construction: ConstructionQueue
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	## The skirmish setup screen pauses the tree until START is pressed;
	## harnesses start the match themselves.
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_placer = _main.get_node("BuildingPlacer")
	_construction = _main.get_node("ConstructionQueue")
	FogOfWar.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _has(display_name: String) -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name:
			return b
	return null

## Runs the real order-then-place flow and returns the finished building.
func _build(path: String, at: Vector3) -> Node:
	var stats: BuildingStats = load(path)
	GameState.add_credits(stats.cost + 500)
	if not _construction.start(stats):
		return null
	var waited: float = 0.0
	while waited < CHECK_TIMEOUT and not _construction.is_ready():
		waited += get_process_delta_time()
		await get_tree().process_frame
	if not _construction.is_ready():
		return null
	_construction.consume()
	var building = stats.scene.instantiate()
	building.stats = stats
	building.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(building)
	building.global_position = at
	EventBus.building_placed.emit(building)
	await get_tree().process_frame
	return building

func _produce(path: String) -> Node:
	var stats: UnitStats = load(path)
	GameState.add_credits(stats.cost + 500)
	var producer := BuildCatalog.producer_for(stats, true)
	if producer == null:
		print("TEST|   (no producer for %s)" % stats.display_name)
		return null
	## Report WHY a production request was refused. This check failed
	## about one run in eight and was written off as timing; the reason
	## is worth printing rather than guessing at again.
	if not TechTree.has_population_for(stats, true):
		print("TEST|   (population %d/%d, %s needs %d)" % [
			TechTree.population_used(true), TechTree.population_cap(true),
			stats.display_name, stats.population])
	if not producer.produce(stats):
		print("TEST|   (%s refused by %s)" % [stats.display_name, producer.name])
		return null
	## Watch for THIS unit arriving, not for the headcount to change.
	## Counting was wrong in a way that only showed up once the AI got
	## more aggressive: if a player unit died in the same frame the new
	## one spawned, the total was unchanged and the test concluded
	## nothing had been built. The tank was there the whole time.
	var existing: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("player_units"):
		existing[unit.get_instance_id()] = true

	var waited: float = 0.0
	while waited < CHECK_TIMEOUT:
		for unit in get_tree().get_nodes_in_group("player_units"):
			if existing.has(unit.get_instance_id()):
				continue
			if unit.stats == stats:
				return unit
		waited += get_process_delta_time()
		await get_tree().process_frame
	print("TEST|   (%s never arrived in %.0fs)" % [stats.display_name, CHECK_TIMEOUT])
	return null

func _run() -> void:
	var base := Vector3(-78, 0, 62)

	# 1-3 opening state
	_check("Match starts with a Command HQ", _has("Command Headquarters") != null)
	_check("Population cap comes from the HQ", TechTree.population_cap(true) == 20,
		"(%d)" % TechTree.population_cap(true))
	_check("Advanced tech is locked at the start",
		not TechTree.is_available(load("res://config/buildings/tech_center.tres"), true))

	# 4-5 power
	var power_before: int = GameState.power_generated
	var plant = await _build("res://config/buildings/power_plant.tres", base + Vector3(16, 0, -6))
	_check("Power Plant built through the construction queue", plant != null)
	_check("Power generation rose", GameState.power_generated > power_before,
		"(%d -> %d)" % [power_before, GameState.power_generated])

	# 6-8 economy
	var refinery = await _build("res://config/buildings/refinery.tres", base + Vector3(-14, 0, -10))
	_check("Refinery built", refinery != null)
	await get_tree().process_frame
	var harvesters: int = 0
	for u in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u.stats != null and u.stats.is_harvester:
			harvesters += 1
	_check("First Refinery ships a free Harvester", harvesters >= 1, "(%d)" % harvesters)

	var income: int = 0
	var last: int = GameState.credits
	var waited: float = 0.0
	while waited < 90.0 and income == 0:
		waited += get_process_delta_time()
		await get_tree().process_frame
		if GameState.credits > last:
			income += GameState.credits - last
		last = GameState.credits
	_check("Harvester physically earns credits", income > 0, "(+%d after %.0fs)" % [income, waited])

	# 9 walls
	var wall_stats: BuildingStats = load("res://config/buildings/wall.tres")
	GameState.add_credits(2000)
	var walls_before: int = get_tree().get_nodes_in_group("walls").size()
	for i in 5:
		var w = wall_stats.scene.instantiate()
		w.stats = wall_stats
		w.is_player_faction = true
		_main.get_node("Level/NavRegion").add_child(w)
		w.global_position = base + Vector3(-20 + i * 2.0, 0, 12)
	await get_tree().process_frame
	_check("Walls can be built", get_tree().get_nodes_in_group("walls").size() == walls_before + 5)

	# 10-11 infantry
	var barracks = await _build("res://config/buildings/barracks.tres", base + Vector3(6, 0, 14))
	_check("Barracks built", barracks != null)
	_check("Barracks raises the unit cap", TechTree.population_cap(true) >= 30,
		"(%d)" % TechTree.population_cap(true))
	var soldier = await _produce("res://config/units/rifle_soldier.tres")
	_check("Rifle Squad produced", soldier != null)

	# 12-13 vehicles
	var factory = await _build("res://config/buildings/war_factory.tres", base + Vector3(26, 0, 10))
	_check("Vehicle Factory built", factory != null)
	var tank = await _produce("res://config/units/assault_vehicle.tres")
	_check("Assault Vehicle produced", tank != null)

	# 14 rally points
	if factory != null:
		factory.rally_point = base + Vector3(30, 0, 20)
		_check("Rally point can be set on a production building",
			factory.rally_point != Vector3.ZERO)

	# 15 defences
	var tower = await _build("res://config/buildings/mg_tower.tres", base + Vector3(-6, 0, 18))
	_check("Machine Gun Tower built", tower != null)
	_check("Tower mounts a real weapon", tower != null and tower.get_node_or_null("Weapon") != null)

	# 16-17 low power
	_check("Grid is healthy so far", not GameState.is_low_power(true),
		"(%d/%d)" % [GameState.power_consumed, GameState.power_generated])
	GameState.register_power_consumption(500)
	await get_tree().process_frame
	_check("Overdrawing the grid triggers LOW POWER", GameState.is_low_power(true))
	_check("Defences go offline in LOW POWER", tower == null or tower.is_offline())
	GameState.register_power_generation(600)
	await get_tree().process_frame
	_check("Restoring generation clears LOW POWER", not GameState.is_low_power(true))
	_check("Defences come back online", tower == null or not tower.is_offline())

	# 21-23 tech tier
	var radar = await _build("res://config/buildings/radar_center.tres", base + Vector3(-24, 0, 4))
	_check("Radar Center built once its prerequisites exist", radar != null)
	_check("Anti-Armor Turret unlocked by Radar",
		TechTree.is_available(load("res://config/buildings/at_turret.tres"), true))
	var tech = await _build("res://config/buildings/tech_center.tres", base + Vector3(34, 0, -4))
	_check("Technology Center built", tech != null)
	_check("Main Battle Tank unlocked by Technology Center",
		TechTree.is_available(load("res://config/units/main_battle_tank.tres"), true))
	var mbt = await _produce("res://config/units/main_battle_tank.tres")
	_check("Main Battle Tank produced", mbt != null)

	# 24-25 army handling
	SelectionManager.clear_selection()
	for u in get_tree().get_nodes_in_group("player_units"):
		SelectionManager._select_unit(u)
	_check("A multi-unit army can be selected",
		SelectionManager.selected_units.size() >= 4,
		"(%d)" % SelectionManager.selected_units.size())
	SelectionManager.assign_control_group(1)
	_check("Army can be stored in a control group",
		SelectionManager.control_group_size(1) == SelectionManager.selected_units.size())

	# 26 attack-move
	SelectionManager._issue_to_selection(CommandTypes.Type.ATTACK_MOVE, Vector3(40, 0, -40), null)
	var attacking: int = 0
	for u in SelectionManager.selected_units:
		if is_instance_valid(u) and u.current_command == CommandTypes.Type.ATTACK_MOVE:
			attacking += 1
	_check("Army accepts an attack-move order", attacking >= 4, "(%d)" % attacking)

	# 28-31 destroying the enemy
	var enemy_buildings: int = get_tree().get_nodes_in_group("enemy_buildings").size()
	_check("Enemy has infrastructure to destroy", enemy_buildings >= 2, "(%d)" % enemy_buildings)

	var enemy_hq: Node = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			enemy_hq = b
	_check("Enemy Command HQ exists", enemy_hq != null)
	if enemy_hq != null:
		enemy_hq.get_node("HealthComponent").take_damage(999999.0)
		await get_tree().process_frame
		await get_tree().process_frame
	_check("Destroying the enemy HQ wins the match",
		GameState.match_state == GameState.MatchState.VICTORY,
		"(state %d)" % GameState.match_state)
