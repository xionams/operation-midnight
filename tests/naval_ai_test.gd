extends Node

## The naval AI, proved in a real match on Coastline: the enemy commander
## runs normally (land AND sea), the player side is scripted to provide
## the naval situations the navy must answer.
##
##   1. It notices the map is naval and that the coast is within reach.
##   2. It expands to the coast and raises a Naval Yard legally (on water,
##      against the shore, inside its own territory).
##   3. It builds a fleet, and keeps ships out of its land army.
##   4. A player ship off its coast is engaged: coastal defence.
##   5. Once the player's submarines are relevant it lays a sonar buoy
##      and adds submarines.
##   6. With a strike fleet and a known player yard, it attacks it.
##
## Time runs at 4x; credits are topped up so the test measures decisions,
## not the economy (ai_match_test covers that).

const LIMIT: float = 900.0

var _main: Node3D
var _director: AIDirector
var _navy: AINavy
var _fails: Array = []
var _t: float = 0.0

func _ready() -> void:
	GameState.selected_map = load("res://config/maps/coastline.tres")
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_director = _main.get_node("AIDirector")
	_director.difficulty = AIDirector.Difficulty.NORMAL
	_navy = _director.navy
	Engine.time_scale = 4.0
	await _run()
	Engine.time_scale = 1.0
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-60s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _enemy(display_name: String) -> Array:
	return get_tree().get_nodes_in_group("enemy_buildings").filter(func(b):
		return is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name)

func _ships() -> Array:
	return _navy.fleet()

## Advance game time until `cond` holds or `limit` game-seconds pass.
func _until(cond: Callable, limit: float) -> bool:
	var start: float = _t
	var next_log: float = _t + 60.0
	while _t - start < limit and _t < LIMIT:
		if cond.call():
			return true
		if _t > next_log:
			next_log = _t + 60.0
			print("TEST|   t=%.0f navy: %s, %d ships (ai clock %.0f, yard tech %s, credits %d)" % [
				_t, _navy.last_decision, _ships().size(), _director._match_time,
				str(TechTree.missing_prerequisites(AINavy.YARD, false)), GameState.enemy_credits])
		GameState.enemy_credits = maxi(GameState.enemy_credits, 6000)
		## The player side is scripted and passive; left alone the AI's
		## land army wins the match before the navy has had its say.
		for b in get_tree().get_nodes_in_group("player_buildings"):
			if is_instance_valid(b) and b.stats != null and b.stats.display_name == "Command Headquarters":
				b.health.heal_to_full()
		await get_tree().process_frame
		## Already game time: process delta includes Engine.time_scale.
		_t += get_process_delta_time()
		if GameState.match_state != GameState.MatchState.PLAYING:
			return cond.call()
	return cond.call()

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Water.level, pos.z)
	return u

func _run() -> void:
	# 1 ------------------------------------------------------------
	_check("The navy recognises Coastline as a naval map", _navy.is_active(),
		"(coast at %s)" % str(_navy.coast_point()))
	_check("...and the coast point is on water", _navy.is_active()
		and Water.is_water(_navy.coast_point().x, _navy.coast_point().z))

	# 2 ------------------------------------------------------------
	var built: bool = await _until(func(): return not _enemy("Naval Yard").is_empty(), 600.0)
	_check("The AI raises a Naval Yard", built, "(t=%.0fs, last: %s)" % [_t, _navy.last_decision])
	if not built:
		return
	var yard: Node = _enemy("Naval Yard")[0]
	var p: Vector3 = yard.global_position
	_check("...legally: on water and against the shore",
		PlacementDomain.error_for(yard.stats, p).is_empty(), PlacementDomain.error_for(yard.stats, p))
	_check("...inside its own territory",
		BuildTerritory.allows(get_tree(), yard.stats, p, false))
	var coastal_post: bool = get_tree().get_nodes_in_group("enemy_buildings").any(
		func(b): return is_instance_valid(b) and b.has_meta("coastal"))
	print("TEST|   (expanded via a coastal post first: %s)" % coastal_post)

	# 3 ------------------------------------------------------------
	var fleet: bool = await _until(func(): return _ships().size() >= 2, 200.0)
	_check("It builds a fleet", fleet, "(%d ships)" % _ships().size())
	var mixed: bool = false
	for u in _director._combat_units():
		if AINavy.is_ship(u):
			mixed = true
	_check("Ships never join the land army", not mixed)
	var afloat: bool = _ships().all(func(s): return Water.is_water(s.global_position.x, s.global_position.z))
	_check("Every ship is on water", afloat)

	# 4 ------------------------------------------------------------
	var raider := _spawn(load("res://config/units/patrol_boat.tres"), true,
		p + Vector3(0, 0, 18) if Water.is_water(p.x, p.z + 18) else Water.nearest_water(p + Vector3(0, 0, 18)))
	raider.get_node("AttackerComponent").set_physics_process(false)
	var start_hp: float = raider.health.current_health
	var answered: bool = await _until(func():
		return not is_instance_valid(raider) or raider.health.current_health < start_hp, 90.0)
	_check("A player ship off its coast is engaged (coastal defence)", answered,
		"(last: %s)" % _navy.last_decision)

	# 5 ------------------------------------------------------------
	## A player yard down the coast, where the AI will find it: this is
	## what makes the player's submarines "relevant".
	var player_yard_stats: BuildingStats = load("res://config/buildings/naval_yard.tres")
	var player_yard = player_yard_stats.scene.instantiate()
	player_yard.stats = player_yard_stats
	player_yard.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(player_yard)
	var yard_at := Vector3(10, Water.level, 34)
	player_yard.global_position = yard_at
	EventBus.building_placed.emit(player_yard)
	var seen: bool = await _until(func(): return _director.memory.has_seen_building("Naval Yard"), 300.0)
	_check("Its fleet scouts the sea and finds the player's yard", seen,
		"(last: %s)" % _navy.last_decision)
	var buoy: bool = await _until(func(): return not _enemy("Sonar Buoy").is_empty(), 120.0)
	_check("Submarines now matter: it lays a sonar buoy", buoy)
	if buoy:
		var ai_buoy: Node = _enemy("Sonar Buoy")[0]
		var lurker := _spawn(load("res://config/units/submarine.tres"), true,
			Water.nearest_water(ai_buoy.global_position + Vector3(6, 0, 6)))
		lurker.get_node("AttackerComponent").set_physics_process(false)
		await _until(func(): return false, 2.0)
		_check("Its sonar exposes a submerged player submarine",
			Stealth.is_submerged(lurker) and Stealth.visible_to(lurker, false))
		var lurker_hp: float = lurker.health.current_health
		var hunted: bool = await _until(func():
			return not is_instance_valid(lurker) or lurker.health.current_health < lurker_hp, 90.0)
		_check("...and its ships engage the detected submarine", hunted,
			"(last: %s)" % _navy.last_decision)
	var sub: bool = await _until(func():
		return _ships().any(func(s): return s.stats.display_name == "Attack Submarine"), 200.0)
	_check("...and adds submarines to the fleet", sub, "(%d ships)" % _ships().size())

	# 6 ------------------------------------------------------------
	var yard_hp: float = player_yard.health.current_health
	var struck: bool = await _until(func():
		return not is_instance_valid(player_yard) or player_yard.health.current_health < yard_hp, 240.0)
	_check("With a strike fleet it attacks the player's naval yard", struck,
		"(last: %s, %d ships)" % [_navy.last_decision, _ships().size()])
	print("TEST|   (game time used: %.0fs)" % _t)
