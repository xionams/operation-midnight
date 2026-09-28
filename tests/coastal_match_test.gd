extends Node

## One complete match on Coastline, won by fighting. The player side is
## scripted, but only through what a player can do: construction orders
## placed where BuildingPlacer.placement_error() allows, production at
## real producers, and orders through SelectionManager. The enemy is the
## normal AI commander, with its navy. Nothing is spawned for free and
## nothing is killed by fiat: victory has to come from the army.
##
##  1 HQ               7 infantry           13 Naval Yard
##  2 power            8 vehicles           14 patrol boats
##  3 refinery         9 expansion          15 submarines + sonar
##  4 harvesting      10 walls and gate     16 fight on land
##  5 income          11 garrison           17 fight at sea
##  6 barracks        12 reach the coast    18 destroy the base, win
##
## Credits are topped up to keep the run short (the economy's pacing is
## ai_match_test's concern). Time runs at 3x.

const LIMIT: float = 2400.0
const T_OUT: float = 150.0

var _main: Node3D
var _placer: BuildingPlacer
var _construction: ConstructionQueue
var _fails: Array = []
var _t: float = 0.0
var _base := Vector3(-78, 0, -20)
var _enemy_base := Vector3(78, 0, -20)

func _ready() -> void:
	GameState.selected_map = load("res://config/maps/coastline.tres")
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_placer = _main.get_node("BuildingPlacer")
	_construction = _main.get_node("ConstructionQueue")
	_main.get_node("AIDirector").difficulty = AIDirector.Difficulty.NORMAL
	Engine.time_scale = 3.0
	await _run()
	Engine.time_scale = 1.0
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-3.0f %-56s %s %s" % [_t, name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _tick() -> void:
	await get_tree().process_frame
	## Already game time: process delta includes Engine.time_scale.
	_t += get_process_delta_time()
	if GameState.credits < 4000:
		GameState.add_credits(4000)
	_census()
	_defend()

## A player defends their base. Without this the first run lost its
## refinery and factory to the AI's first wave at t~400 and the match was
## over for reasons that had nothing to do with what is being tested.
## Only units not on an offensive order are pulled home.
var _defend_timer: float = 0.0
var _on_offensive: Dictionary = {}

func _defend() -> void:
	_defend_timer -= get_process_delta_time()
	if _defend_timer > 0.0:
		return
	_defend_timer = 2.0
	var anchors: Array = [_base]
	for b in _mine("Forward Command Post"):
		anchors.append(b.global_position)
	var threat := Vector3.INF
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(u) or u.stats == null or AINavy.is_ship(u):
			continue
		if not Stealth.visible_to(u, true) or not FogOfWar.is_visible_at(u.global_position):
			continue
		for a in anchors:
			if u.global_position.distance_to(a) < 50.0:
				threat = u.global_position
				break
		if threat.is_finite():
			break
	if not threat.is_finite():
		return
	var defenders: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(u) or u.stats == null or u.stats.is_harvester or AINavy.is_ship(u):
			continue
		if u.get_node_or_null("AttackerComponent") == null or _on_offensive.has(u.get_instance_id()):
			continue
		if u.current_command == CommandTypes.Type.GARRISON:
			continue
		defenders.append(u)
	if not defenders.is_empty():
		_order(defenders, CommandTypes.Type.ATTACK_MOVE, threat)

func _wait(seconds: float) -> void:
	var until: float = _t + seconds
	while _t < until:
		await _tick()

func _mine(display_name: String) -> Array:
	return get_tree().get_nodes_in_group("player_buildings").filter(func(b):
		return is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name)

func _theirs(display_name: String) -> Array:
	return get_tree().get_nodes_in_group("enemy_buildings").filter(func(b):
		return is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name)

func _units(display_name: String) -> Array:
	return get_tree().get_nodes_in_group("player_units").filter(func(u):
		return is_instance_valid(u) and u.stats != null and u.stats.display_name == display_name)

## The first spot near `near` that the real placer accepts.
func _site(stats: BuildingStats, near: Vector3) -> Vector3:
	_placer.active_stats = stats
	for r in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 26.0]:
		for i in 12:
			var a: float = TAU * float(i) / 12.0
			var p: Vector3 = near + Vector3(cos(a), 0, sin(a)) * r
			if _placer.placement_error(p).is_empty():
				_placer.active_stats = null
				return p
			if r == 0.0:
				break
	_placer.active_stats = null
	return Vector3.INF

## Order, wait for construction, place legally. Returns the building.
func _build(id: String, near: Vector3) -> Node:
	var stats: BuildingStats = load("res://config/buildings/%s.tres" % id)
	## A player keeps the grid ahead of demand: low power halves production
	## and construction, and the first run of this match starved on one plant.
	if id != "power_plant" and stats.power_consumption > 0 \
			and GameState.power_consumed + stats.power_consumption > GameState.power_generated:
		await _build("power_plant", _base + Vector3(30, 0, -20 + _plants * 9))
		_plants += 1
	if _construction.is_busy():
		print("TEST|   (queue still holding %s)" % _construction.current().display_name)
		return null
	if not _construction.start(stats):
		print("TEST|   (construction refused %s: missing %s)" % [
			stats.display_name, str(TechTree.missing_prerequisites(stats, true))])
		return null
	var waited: float = 0.0
	while not _construction.is_ready() and waited < T_OUT:
		var before: float = _t
		await _tick()
		waited += _t - before
	if not _construction.is_ready():
		print("TEST|   (%s still under construction after %.0fs; cancelled)" % [stats.display_name, T_OUT])
		_construction.cancel()
		return null
	var at := _site(stats, near)
	if not at.is_finite():
		print("TEST|   (no legal site for %s near %s; cancelled)" % [stats.display_name, near])
		_construction.cancel()
		return null
	_construction.consume()
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(at.x, PlacementDomain.surface_y(stats, at.x, at.z), at.z)
	EventBus.building_placed.emit(b)
	await _tick()
	return b

func _produce(id: String, count: int = 1) -> Array:
	var stats: UnitStats = load("res://config/units/%s.tres" % id)
	var producer := BuildCatalog.producer_for(stats, true)
	var made: Array = []
	if producer == null:
		print("TEST|   (no producer for %s)" % stats.display_name)
		return made
	var existing: Dictionary = {}
	for u in get_tree().get_nodes_in_group("player_units"):
		existing[u.get_instance_id()] = true
	## Production charges on enqueue; top up per order so every one queued
	## is actually paid for (queueing five tanks on 4,000 credits bought two).
	var queued: int = 0
	for i in count:
		if GameState.credits < stats.cost:
			GameState.add_credits(stats.cost)
		if producer.produce(stats):
			queued += 1
	if queued < count:
		print("TEST|   (%s: only %d of %d orders accepted)" % [stats.display_name, queued, count])
	var waited: float = 0.0
	while made.size() < count and waited < T_OUT + stats.build_time * count:
		var before: float = _t
		await _tick()
		waited += _t - before
		for u in get_tree().get_nodes_in_group("player_units"):
			if not existing.has(u.get_instance_id()) and u.stats == stats:
				existing[u.get_instance_id()] = true
				made.append(u)
	return made

func _order(units: Array, type: int, at: Vector3, target: Node = null) -> void:
	SelectionManager.clear_selection()
	for u in units:
		if is_instance_valid(u):
			SelectionManager._select_unit(u)
	SelectionManager._issue_to_selection(type, at, target)
	SelectionManager.clear_selection()

func _alive(units: Array) -> Array:
	return units.filter(func(u): return is_instance_valid(u) and u.is_inside_tree())

func _run() -> void:
	# 1 -----------------------------------------------------------------
	_check("1  The match starts with our Command HQ", not _mine("Command Headquarters").is_empty())
	# 2 -----------------------------------------------------------------
	var plant = await _build("power_plant", _base + Vector3(16, 0, -10))
	_check("2  Power Plant built and placed legally", plant != null,
		"(%d/%d power)" % [GameState.power_consumed, GameState.power_generated])
	# 3-5 ---------------------------------------------------------------
	var refinery = await _build("refinery", _base + Vector3(18, 0, 8))
	_check("3  Refinery built", refinery != null)
	await _wait(2.0)
	var harvesters: Array = get_tree().get_nodes_in_group("player_units").filter(func(u):
		return is_instance_valid(u) and u.stats != null and u.stats.is_harvester)
	_check("4  It ships a Harvester", not harvesters.is_empty())
	var harvested_before: int = MatchStats.resources_harvested
	var earned: bool = false
	var until: float = _t + 120.0
	while _t < until and not earned:
		await _tick()
		earned = MatchStats.resources_harvested > harvested_before
	_check("5  The harvester earns credits by harvesting", earned,
		"(+%d)" % (MatchStats.resources_harvested - harvested_before))
	# 6-7 ---------------------------------------------------------------
	var barracks = await _build("barracks", _base + Vector3(-16, 0, -10))
	_check("6  Barracks built", barracks != null)
	var riflemen: Array = await _produce("rifle_soldier", 5)
	var at: Array = await _produce("at_squad", 2)
	_check("7  Infantry produced", riflemen.size() + at.size() >= 6, "(%d)" % (riflemen.size() + at.size()))
	# 8 -----------------------------------------------------------------
	var factory = await _build("war_factory", _base + Vector3(-18, 0, 12))
	_check("8a Vehicle Factory built", factory != null)
	var radar = await _build("radar_center", _base + Vector3(0, 0, -26))
	var tech = await _build("tech_center", _base + Vector3(24, 0, -26))
	_check("8b Tech tier: Radar and Technology Center built", radar != null and tech != null)
	var tanks: Array = await _produce("main_battle_tank", 5)
	var assault: Array = await _produce("assault_vehicle", 2)
	_check("8c Vehicles produced (MBTs, assault vehicles)", tanks.size() >= 4 and assault.size() >= 1,
		"(%d MBT, %d assault)" % [tanks.size(), assault.size()])
	# 9 -----------------------------------------------------------------
	var territory_before: bool = BuildTerritory.contains(get_tree(), Vector3(-40, 0, 6), true)
	## Toward the shore, still inside the refinery's reach (placement rule).
	var post = await _build("forward_post", Vector3(-58, 0, 4))
	_check("9  Expansion: a Forward Post pushes territory toward the coast",
		post != null and not territory_before and BuildTerritory.contains(get_tree(), Vector3(-40, 0, 6), true))
	# 10 ----------------------------------------------------------------
	var wall_stats: BuildingStats = load("res://config/buildings/wall.tres")
	var gate_stats: BuildingStats = load("res://config/buildings/gate.tres")
	var line: Array = []
	for i in 9:
		var s: BuildingStats = gate_stats if i == 4 else wall_stats
		var p := Vector3(-100 + i * 2.0, 0, 0)
		_placer.active_stats = s
		var err: String = _placer.placement_error(p)
		_placer.active_stats = null
		if not err.is_empty() or not GameState.try_spend_for(true, s.cost):
			continue
		var w = s.scene.instantiate()
		w.stats = s
		w.is_player_faction = true
		_main.get_node("Level/NavRegion").add_child(w)
		w.global_position = Vector3(p.x, Terrain.height_at(p.x, p.z), p.z)
		EventBus.building_placed.emit(w)
		line.append(w)
	await _tick()
	var connected: int = line.filter(func(w): return is_instance_valid(w) and w.connections != 0).size()
	_check("10 A connected wall line with a gate", line.size() == 9 and connected == 9,
		"(%d placed, %d connected)" % [line.size(), connected])
	# 11 ----------------------------------------------------------------
	var shelter: Node = null
	var best: float = INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.get("is_neutral") == true and b.get_node_or_null("GarrisonComponent") != null:
			var d: float = b.global_position.distance_to(_base)
			if d < best:
				best = d
				shelter = b
	riflemen = _alive(riflemen)
	if shelter != null and riflemen.size() >= 2:
		_order([riflemen[0], riflemen[1]], CommandTypes.Type.GARRISON, shelter.global_position, shelter)
		var hold = shelter.get_node("GarrisonComponent")
		var until_g: float = _t + 90.0
		while _t < until_g and hold.occupancy() == 0:
			await _tick()
		_check("11 Infantry garrison a civilian building and claim it",
			hold.occupancy() >= 1 and shelter.is_player_faction, "(%d inside; %s at %s, soldier %s, cmd %s)" % [
				hold.occupancy(), shelter.stats.display_name, str(shelter.global_position),
				str(riflemen[0].global_position) if is_instance_valid(riflemen[0]) and riflemen[0].is_inside_tree() else "gone",
				CommandTypes.type_name(riflemen[0].current_command) if is_instance_valid(riflemen[0]) else "-"])
	else:
		_check("11 A garrisonable building exists", false)
	# 12-13 -------------------------------------------------------------
	var coast: Vector3 = Water.nearest_water(post.global_position if is_instance_valid(post) else Vector3(-58, 0, 4))
	_check("12 The coast is inside our territory", BuildTerritory.contains(get_tree(), coast, true))
	var yard = await _build("naval_yard", coast + Vector3(0, 0, 6))
	_check("13 Naval Yard built on the shore", yard != null)
	if yard == null:
		return
	# 14-15 -------------------------------------------------------------
	var boats: Array = await _produce("patrol_boat", 4)
	_check("14 Patrol boats launched from the yard, afloat", boats.size() >= 3
		and _alive(boats).all(func(b): return Water.is_water(b.global_position.x, b.global_position.z)),
		"(%d)" % boats.size())
	var subs: Array = await _produce("submarine", 2)
	var buoy = await _build("sonar_buoy", (yard.global_position if is_instance_valid(yard) else coast) + Vector3(14, 0, 8))
	_check("15 Submarines and a sonar buoy", subs.size() >= 1 and buoy != null, "(%d subs)" % subs.size())
	await _wait(1.0)
	subs = _alive(subs)
	if not subs.is_empty():
		var sub: Node = subs[0]
		_check("15b Our submarine runs submerged and hidden from the enemy",
			Stealth.is_submerged(sub) and not Stealth.visible_to(sub, false))
	# 16-17 -------------------------------------------------------------
	var land_army: Array = _alive(tanks + assault + at + riflemen.slice(2))
	var fleet: Array = _alive(boats + subs)
	var enemy_coast: Vector3 = Water.nearest_water(_enemy_base, 120.0) + Vector3(0, 0, 10)
	for u in land_army + fleet:
		_on_offensive[u.get_instance_id()] = true
	_order(fleet, CommandTypes.Type.ATTACK_MOVE, enemy_coast)
	_order(land_army, CommandTypes.Type.ATTACK_MOVE, _enemy_base)
	# keep the pressure on: reinforce and re-issue until the base falls
	var wave: int = 0
	while _t < LIMIT and GameState.match_state == GameState.MatchState.PLAYING:
		var until_wave: float = _t + 20.0
		while _t < until_wave and GameState.match_state == GameState.MatchState.PLAYING:
			await _tick()
		wave += 1
		land_army = _alive(land_army)
		fleet = _alive(fleet)
		if land_army.size() < 6:
			land_army.append_array(await _produce("main_battle_tank", 3))
			land_army.append_array(await _produce("artillery_vehicle", 1))
		if fleet.size() < 3:
			fleet.append_array(await _produce("patrol_boat", 2))
		## Units die while production is awaited; touching a freed one
		## segfaults a release build rather than raising an error.
		land_army = _alive(land_army)
		fleet = _alive(fleet)
		for u in land_army + fleet:
			_on_offensive[u.get_instance_id()] = true
		_order(land_army, CommandTypes.Type.ATTACK_MOVE, _nearest_enemy_building(_enemy_base))
		_order(fleet, CommandTypes.Type.ATTACK_MOVE, _sea_target(enemy_coast))
		if wave % 3 == 0:
			print("TEST|   t=%.0f army=%d fleet=%d enemy buildings=%d land kills=%d sea kills=%d" % [
				_t, land_army.size(), fleet.size(),
				get_tree().get_nodes_in_group("enemy_buildings").size(), land_kills, sea_kills])
	_check("16 Our army fought and killed enemy land units", land_kills > 0, "(%d)" % land_kills)
	_check("17a The AI played the naval game (built a yard and ships)",
		_ai_built_navy and _ai_ships_seen > 0, "(%d AI ships seen)" % _ai_ships_seen)
	_check("17b Our fleet fought at sea: enemy ships sunk or naval assets razed",
		sea_kills > 0 or _ai_naval_buildings_razed > 0,
		"(%d sunk, %d naval buildings razed)" % [sea_kills, _ai_naval_buildings_razed])
	# 18 ----------------------------------------------------------------
	_check("18 The enemy base is destroyed and the match is won",
		GameState.match_state == GameState.MatchState.VICTORY,
		"(state %d at t=%.0f, %d enemy buildings left)" % [
			GameState.match_state, _t, get_tree().get_nodes_in_group("enemy_buildings").size()])

var _ai_built_navy: bool = false
var _plants: int = 0
var land_kills: int = 0
var sea_kills: int = 0
## instance id -> [weakref, is_ship]
var _tracked: Dictionary = {}

## Enemy units that were alive and are gone were killed (the AI does not
## garrison or sell units). Split by domain: land fight vs sea fight.
var _ai_ships_seen: int = 0
var _ai_naval_buildings_razed: int = 0
var _naval_buildings: Dictionary = {}

func _census() -> void:
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and u.stats != null and not _tracked.has(u.get_instance_id()):
			_tracked[u.get_instance_id()] = [weakref(u), AINavy.is_ship(u)]
			if AINavy.is_ship(u):
				_ai_ships_seen += 1
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null \
				and b.stats.placement_domain == PlacementDomain.Domain.WATER \
				and not _naval_buildings.has(b.get_instance_id()):
			_naval_buildings[b.get_instance_id()] = weakref(b)
			_ai_built_navy = true
	for id in _naval_buildings.keys():
		if _naval_buildings[id].get_ref() == null:
			_ai_naval_buildings_razed += 1
			_naval_buildings.erase(id)
	for id in _tracked.keys():
		var entry: Array = _tracked[id]
		if entry[0].get_ref() == null:
			if entry[1]:
				sea_kills += 1
			else:
				land_kills += 1
			_tracked.erase(id)

func _nearest_enemy_building(from: Vector3) -> Vector3:
	var best := _enemy_base
	var best_d: float = INF
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if not is_instance_valid(b) or b.stats == null or b.stats.placement_domain == PlacementDomain.Domain.WATER:
			continue
		var d: float = b.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = b.global_position
	return best

## The enemy's naval assets if any exist, else its stretch of coast.
func _sea_target(fallback: Vector3) -> Vector3:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null and b.stats.placement_domain == PlacementDomain.Domain.WATER:
			_ai_built_navy = true
			return b.global_position
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and AINavy.is_ship(u):
			_ai_built_navy = true
			return u.global_position
	return fallback
