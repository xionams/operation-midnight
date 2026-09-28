class_name AINavy
extends Node

## The AI commander's naval arm. A child of AIDirector, called from its
## think tick, and inert on a map without sea.
##
## What it does, in order of need:
##   1. Notices the map has a coast within reach of home.
##   2. Expands to it: a forward post on the shore if the coast lies
##      outside its territory, then a Naval Yard against that shore.
##   3. Keeps a small fleet: patrol boats first, submarines once the
##      opponent has ships worth sinking.
##   4. Lays a sonar buoy once submarines are relevant (it has seen the
##      opponent's, or the opponent has a yard that could build them).
##   5. Defends its coastal infrastructure from ships, and takes the
##      fleet after the opponent's naval assets when it is strong enough.
##
## Ships never join the land army (AIDirector._combat_units skips them):
## a patrol boat ordered to attack-move on an inland base only sails into
## the beach.

const YARD: BuildingStats = preload("res://config/buildings/naval_yard.tres")
const BUOY: BuildingStats = preload("res://config/buildings/sonar_buoy.tres")
const POST: BuildingStats = preload("res://config/buildings/forward_post.tres")
const BOAT: UnitStats = preload("res://config/units/patrol_boat.tres")
const SUB: UnitStats = preload("res://config/units/submarine.tres")

## How far away the sea may be and still be worth fighting for.
const COAST_REACH: float = 130.0
## Not before the land economy stands: a yard in the first minute is a
## commander that starves its own army.
const EARLIEST: float = 120.0
const DEFEND_RADIUS: float = 42.0
const MIN_STRIKE_FLEET: int = 3
const MAX_FLEET: int = 7

var director: Node = null
var is_player: bool = false
var foe_base: Vector3 = Vector3.ZERO

var _coast := Vector3.INF
var _coastal: bool = false
var _post_at: Vector3 = Vector3.ZERO
var _cooldown: float = 0.0
var _strike_target := Vector3.INF
## Public for tests and the debug overlay: what the navy last decided.
var last_decision: String = "idle"

func setup(owner_director: Node, player_side: bool, foe_base_position: Vector3) -> void:
	director = owner_director
	is_player = player_side
	foe_base = foe_base_position

## Resolved on first use, not in setup: the director is set up before the
## map's water is configured, and asking then finds "sea" everywhere.
var _resolved: bool = false

func _resolve_coast() -> void:
	if _resolved:
		return
	_resolved = true
	if not Water.has_water():
		return
	var base: Vector3 = director.base_position
	if Water.is_water(base.x, base.z):
		return
	var nearest: Vector3 = Water.nearest_water(base, COAST_REACH)
	if Water.is_water(nearest.x, nearest.z) \
			and Vector2(nearest.x - base.x, nearest.z - base.z).length() <= COAST_REACH:
		_coast = nearest
		_coastal = true

func is_active() -> bool:
	_resolve_coast()
	return _coastal

func coast_point() -> Vector3:
	return _coast

# ------------------------------------------------------------------ tick

func think(delta_since_last: float, match_time: float) -> void:
	if not is_active():
		return
	_cooldown = maxf(0.0, _cooldown - delta_since_last)
	if match_time < EARLIEST and not _foe_navy_seen():
		last_decision = "land economy first"
		return
	var yard := _yard()
	if yard == null:
		_expand_to_coast()
		return
	_run_sonar(yard)
	_run_fleet_production(yard)
	_run_fleet(yard)

# ------------------------------------------------------------ helpers

func _own_units() -> String:
	return "player_units" if is_player else "enemy_units"

func _own_buildings() -> String:
	return "player_buildings" if is_player else "enemy_buildings"

func _foe_units() -> String:
	return "enemy_units" if is_player else "player_units"

func _foe_buildings() -> String:
	return "enemy_buildings" if is_player else "player_buildings"

static func is_ship(unit: Node) -> bool:
	return unit != null and unit.get("stats") is UnitStats \
		and unit.stats.movement_domain == PlacementDomain.Domain.WATER

func _yard() -> Node:
	return _own_building(YARD.display_name)

func _own_building(display_name: String) -> Node:
	for b in get_tree().get_nodes_in_group(_own_buildings()):
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name:
			return b
	return null

func fleet() -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group(_own_units()):
		if is_instance_valid(u) and is_ship(u):
			out.append(u)
	return out

func _count(stats: UnitStats) -> int:
	return fleet().filter(func(u): return u.stats == stats or u.stats.display_name == stats.display_name).size()

## Opponent ships the commander has actually seen (fog-honest, via memory).
func _foe_navy_seen() -> bool:
	var seen: Dictionary = director.memory.seen_units
	return seen.has(BOAT.display_name) or seen.has(SUB.display_name) \
		or director.memory.has_seen_building(YARD.display_name)

func _foe_subs_relevant() -> bool:
	return director.memory.seen_units.has(SUB.display_name) \
		or director.memory.has_seen_building(YARD.display_name)

func _spend(cost: int, priority: AIEconomy.Priority) -> bool:
	return director.economy.can_afford(cost, priority) \
		and GameState.try_spend_for(is_player, cost)

func _place(stats: BuildingStats, at: Vector3) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = is_player
	director._nav_region.add_child(b)
	b.global_position = Vector3(at.x, PlacementDomain.surface_y(stats, at.x, at.z), at.z)
	EventBus.building_placed.emit(b)
	return b

# ------------------------------------------------------- expansion

## Yard first if a legal berth lies inside territory; otherwise a post on
## the shore to bring the coast into territory.
func _expand_to_coast() -> void:
	if _cooldown > 0.0:
		return
	if not TechTree.is_available(YARD, is_player):
		last_decision = "waiting for yard tech"
		return
	var site := _yard_site(true)
	if site.is_finite():
		if _spend(YARD.cost, AIEconomy.Priority.TECH):
			_place(YARD, site)
			last_decision = "built naval yard"
			_cooldown = 6.0
		return
	if _post_at != Vector3.ZERO and _post_alive():
		last_decision = "waiting for coastal post"
		return
	var post_site := _post_site()
	if post_site.is_finite() and TechTree.is_available(POST, is_player) \
			and _spend(POST.cost, AIEconomy.Priority.ECONOMY):
		var post := _place(POST, post_site)
		## Marked so the ore-expansion logic does not mistake it for its own.
		post.set_meta("coastal", true)
		_post_at = post_site
		last_decision = "built coastal post"
		_cooldown = 6.0

func _post_alive() -> bool:
	for b in get_tree().get_nodes_in_group(_own_buildings()):
		if is_instance_valid(b) and b.has_meta("coastal"):
			return true
	return false

## A berth against the shore nearest home: candidates walk along the
## coast either side of the nearest water point and a little out to sea,
## and the first that passes the same rules a player's placement does
## (on water, against the shore, not overlapping, inside territory) wins.
func _yard_site(require_territory: bool) -> Vector3:
	var base: Vector3 = director.base_position
	var seaward: Vector3 = Vector3(_coast.x - base.x, 0, _coast.z - base.z).normalized()
	var along := Vector3(-seaward.z, 0, seaward.x)
	for out in [6.0, 9.0, 12.0]:
		for step in [0, 1, -1, 2, -2, 3, -3, 4, -4, 6, -6]:
			var p: Vector3 = _coast + seaward * out + along * (float(step) * 8.0)
			if not PlacementDomain.error_for(YARD, p).is_empty():
				continue
			if not director._slot_is_legal(YARD, p):
				continue
			if require_territory and not BuildTerritory.allows(get_tree(), YARD, p, is_player):
				continue
			return p
	return Vector3.INF

## On land, just back from the shore toward home.
func _post_site() -> Vector3:
	var base: Vector3 = director.base_position
	var landward: Vector3 = Vector3(base.x - _coast.x, 0, base.z - _coast.z).normalized()
	## As close to the water as a land footprint allows, so the berth it is
	## for lands well inside the post's reach.
	for back in [7.0, 9.0, 11.0, 14.0, 18.0, 22.0]:
		for side in [0.0, 8.0, -8.0, 16.0, -16.0]:
			var p: Vector3 = _coast + landward * back + Vector3(-landward.z, 0, landward.x) * side
			if PlacementDomain.error_for(POST, p).is_empty() and director._slot_is_legal(POST, p):
				return p
	return Vector3.INF

# ------------------------------------------------------------ sonar

func _run_sonar(yard: Node) -> void:
	if _own_building(BUOY.display_name) != null or not _foe_subs_relevant():
		return
	if not TechTree.is_available(BUOY, is_player):
		return
	var a: float = (yard.get("_visual_root") as Node3D).rotation.y if yard.get("_visual_root") is Node3D else 0.0
	var mouth: Vector3 = yard.global_position + Vector3(cos(a), 0, -sin(a)) * 14.0
	for side in [0.0, 6.0, -6.0, 10.0, -10.0]:
		var p: Vector3 = mouth + Vector3(sin(a), 0, cos(a)) * side
		if PlacementDomain.error_for(BUOY, p).is_empty() and director._slot_is_legal(BUOY, p):
			if _spend(BUOY.cost, AIEconomy.Priority.DEFENCE):
				_place(BUOY, p)
				last_decision = "laid sonar buoy"
			return

# ------------------------------------------------------- production

func desired_fleet_size() -> int:
	var seen: Dictionary = director.memory.seen_units
	var foe: int = 0
	for key in [BOAT.display_name, SUB.display_name]:
		if seen.has(key):
			foe += int(seen[key].get("count", 0))
	## A screen of two until the opponent shows a navy; after that, enough
	## to strike with - sized off what was seen, never below a strike group
	## (the ships it saw may since have been sunk; the yard that built
	## them has not).
	var floor_size: int = MIN_STRIKE_FLEET + 1 if _foe_navy_seen() else 2
	return clampi(maxi(floor_size, foe + 2), 2, MAX_FLEET)

func _run_fleet_production(yard: Node) -> void:
	if yard.queue.queue_length() > 0:
		return
	var ships: int = fleet().size()
	if ships >= desired_fleet_size():
		return
	var boats: int = _count(BOAT)
	var subs: int = _count(SUB)
	var pick: UnitStats = BOAT
	## Submarines hunt ships. Worth it once the opponent has shown some,
	## and never at the expense of a surface screen.
	if boats >= 2 and subs < maxi(1, boats / 2) and _foe_navy_seen():
		pick = SUB
	if not TechTree.is_available(pick, is_player):
		return
	if _spend(pick.cost, AIEconomy.Priority.ARMY):
		yard.produce(pick)
		last_decision = "producing %s" % pick.display_name

# ------------------------------------------------------------ fleet

func _run_fleet(yard: Node) -> void:
	var ships := fleet()
	if ships.is_empty():
		return
	# --- defence of the coast outranks everything ---
	var threat := _coastal_threat(yard)
	if threat.is_finite():
		for s in ships:
			s.issue_command(CommandTypes.Type.ATTACK_MOVE, _sea(threat))
		last_decision = "defending coast"
		return
	# --- strike when strong enough and there is something to hit ---
	var target := _naval_target()
	if ships.size() >= MIN_STRIKE_FLEET and target.is_finite():
		if not _strike_target.is_finite() or _strike_target.distance_to(target) > 8.0:
			_strike_target = target
			for s in ships:
				s.issue_command(CommandTypes.Type.ATTACK_MOVE, _sea(target))
		last_decision = "striking naval target"
		return
	_strike_target = Vector3.INF
	# --- otherwise hold station off the yard, one boat scouting the sea ---
	var a: float = (yard.get("_visual_root") as Node3D).rotation.y if yard.get("_visual_root") is Node3D else 0.0
	var station: Vector3 = yard.global_position + Vector3(cos(a), 0, -sin(a)) * 16.0
	for i in ships.size():
		var s = ships[i]
		var idle: bool = s.nav_agent == null or s.nav_agent.is_navigation_finished()
		if not idle:
			continue
		## With nothing known to strike, one ship sweeps the sea toward the
		## opponent's coast - the only way the navy learns where to go.
		if i == 0 and ships.size() >= 2:
			s.issue_command(CommandTypes.Type.ATTACK_MOVE, _sweep_point())
		elif s.global_position.distance_to(station) > 12.0:
			s.issue_command(CommandTypes.Type.MOVE, _sea(station + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))))
	last_decision = "holding station"

## Alternates between the opponent's stretch of coast and open sea
## between the two bases, so successive sweeps cover the lanes.
var _sweep: int = 0

func _sweep_point() -> Vector3:
	_sweep += 1
	var home: Vector3 = _coast
	var theirs: Vector3 = _sea(foe_base)
	var f: float = [1.0, 0.5, 0.8, 0.3][_sweep % 4]
	var p: Vector3 = home.lerp(theirs, f)
	return _sea(p + Vector3(0, 0, randf_range(4.0, 16.0)))

## A visible opponent ship near any of our structures that touch the sea.
func _coastal_threat(yard: Node) -> Vector3:
	var guarded: Array = [yard.global_position]
	for b in get_tree().get_nodes_in_group(_own_buildings()):
		if is_instance_valid(b) and b.stats != null \
				and Water.distance_to_shore(b.global_position.x, b.global_position.z) < 14.0:
			guarded.append(b.global_position)
	for u in get_tree().get_nodes_in_group(_foe_units()):
		if not is_instance_valid(u) or not is_ship(u):
			continue
		if not Stealth.visible_to(u, is_player):
			continue
		for g in guarded:
			if u.global_position.distance_to(g) <= DEFEND_RADIUS:
				return u.global_position
	return Vector3.INF

## The opponent's naval assets the commander knows about: a yard or buoy
## it has seen (memory), else a ship in sight right now.
func _naval_target() -> Vector3:
	for key in [YARD.display_name, BUOY.display_name]:
		var record = director.memory.seen_buildings.get(key)
		if record != null:
			return record["position"]
	for u in get_tree().get_nodes_in_group(_foe_units()):
		if is_instance_valid(u) and is_ship(u) and Stealth.visible_to(u, is_player) \
				and director._visible_to_ai(u.global_position):
			return u.global_position
	return Vector3.INF

## Any point, pulled onto open water so a ship can actually path to it.
func _sea(point: Vector3) -> Vector3:
	var p: Vector3 = Water.nearest_water(point, 160.0)
	if Water.distance_to_shore(p.x, p.z) < 4.0:
		var out := Vector3(p.x - point.x, 0, p.z - point.z)
		if out.length() > 0.1:
			p += out.normalized() * 6.0
	p.y = Water.level
	return p
