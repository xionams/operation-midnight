extends Node

## The enemy commander uses Engineers and Spies.
##
## It already produced both and then ignored them: nothing in
## ai_director.gd referenced either unit, so they walked around as
## expensive rifle squads that could not shoot. Both ride
## EnterBuildingAbility, so using them is a targeting decision, and
## targets come from AIMemory - which is what lets the commander be
## baited by a structure that is no longer there.

var _main: Node3D
var _director: AIDirector
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _spawn(path: String, player: bool, at: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z), at.z)
	return u

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_director = _main.get_node("AIDirector")
	_director.difficulty = AIDirector.Difficulty.NORMAL
	GameState.add_credits(60000)
	for i in 30:
		await get_tree().physics_frame

	var enemy_base: Vector3 = _main.map.enemy_base

	# --- a Spy goes for the thing worth sabotaging ---
	var player_base: Vector3 = _main.map.player_base
	var site := Vector3(player_base.x + 14, 0, player_base.z + 10)
	site.y = Terrain.height_at(site.x, site.z)
	var refinery = _main._spawn_building(
		load("res://scenes/buildings/refinery.tscn"),
		load("res://config/buildings/refinery.tres"), true, site)
	await _frames(12)
	_check("The player has a refinery to target", refinery != null)
	if refinery == null:
		_finish()
		return

	## The commander only knows what it has SEEN, so put the sighting in
	## memory the same way an observation would.
	_director.memory.seen_economy.append({
		"position": refinery.global_position,
		"kind": "Resource Refinery",
		"value": 2000,
		"last_seen": _director.memory._now,
	})

	var spy = _spawn("res://config/units/spy.tres", false,
		enemy_base + Vector3(6, 0, 6))
	await _frames(10)
	var ability = _enter_ability(spy)
	_check("The Spy carries an enter-building ability", ability != null)

	_director._run_infiltration()
	await _frames(4)
	_check("The commander sends the Spy at the remembered refinery",
		ability != null and ability.target == refinery,
		"target=%s" % (ability.target.name if ability != null and ability.target != null else "none"))

	# --- an Engineer takes free ground ---
	var hall = preload("res://scenes/buildings/civilian_structure.tscn").instantiate()
	hall.is_neutral = true
	_main.get_node("Level").add_child(hall)
	hall.global_position = Vector3(enemy_base.x + 20, 0, enemy_base.z + 20)
	hall.global_position.y = Terrain.height_at(hall.global_position.x, hall.global_position.z)
	await _frames(10)

	var engineer = _spawn("res://config/units/engineer.tres", false,
		enemy_base + Vector3(-6, 0, 6))
	await _frames(10)
	var eng_ability = _enter_ability(engineer)
	_check("The Engineer carries an enter-building ability", eng_ability != null)
	_director._run_infiltration()
	await _frames(4)
	_check("The commander sends the Engineer at a neutral structure",
		eng_ability != null and eng_ability.target != null,
		"target=%s" % (eng_ability.target.name if eng_ability != null and eng_ability.target != null else "none"))

	# --- a sighting that no longer matches anything yields no target ---
	_director.memory.seen_economy.clear()
	_director.memory.seen_economy.append({
		"position": Vector3(-500, 0, -500),
		"kind": "Resource Refinery", "value": 2000,
		"last_seen": _director.memory._now,
	})
	var ghost_spy = _spawn("res://config/units/spy.tres", false,
		enemy_base + Vector3(10, 0, -6))
	await _frames(10)
	var ghost_ability = _enter_ability(ghost_spy)
	_director._run_infiltration()
	await _frames(4)
	_check("A sighting matching no structure sends nobody",
		ghost_ability != null and ghost_ability.target == null)

	# --- EASY does not play this game at all ---
	_director.difficulty = AIDirector.Difficulty.EASY
	for u in [spy, engineer]:
		var a = _enter_ability(u)
		if a != null:
			a.cancel()
	await _frames(4)
	_director._run_infiltration()
	await _frames(4)
	_check("EASY leaves specialists alone",
		_enter_ability(spy).target == null)

	# --- production is gated behind a real economy ---
	_director.difficulty = AIDirector.Difficulty.NORMAL
	for u in [spy, engineer, ghost_spy]:
		if is_instance_valid(u):
			u.queue_free()
	await _frames(10)
	_director.memory.seen_economy.clear()
	_director.memory.seen_economy.append({
		"position": refinery.global_position, "kind": "Resource Refinery",
		"value": 2000, "last_seen": _director.memory._now,
	})
	var barracks = _director._own("Barracks")
	_check("The commander has a barracks to produce from", barracks != null)
	if barracks != null:
		## The barracks is already running the commander's normal
		## infantry, so "did it buy a specialist" is a question about
		## WHAT is queued, not how much.
		GameState.add_credits_for(_director.is_player,
			400 - GameState.balance_of(_director.is_player))
		barracks.queue.clear_without_refund()
		_director._run_infiltration()
		await _frames(4)
		_check("Broke, it does not buy a specialist",
			not _specialist_queued(barracks),
			"queued %s" % _queue_names(barracks))

		GameState.add_credits_for(_director.is_player,
			40000 - GameState.balance_of(_director.is_player))
		barracks.queue.clear_without_refund()
		_director._run_infiltration()
		await _frames(4)
		var refineries: int = _director._refinery_count()
		_check("Rich but short of refineries, still no specialist",
			refineries >= AIDirector.SPECIALIST_MIN_REFINERIES
				or not _specialist_queued(barracks),
			"%d refineries, queued %s" % [refineries, _queue_names(barracks)])

	_finish()

func _queue_names(barracks: Node) -> String:
	var names: Array = []
	for stats in barracks.queue.orders():
		names.append(stats.display_name)
	return str(names)

func _specialist_queued(barracks: Node) -> bool:
	for stats in barracks.queue.orders():
		if stats.display_name in ["Engineer", "Spy"]:
			return true
	return false

func _enter_ability(unit: Node) -> Node:
	for child in unit.get_children():
		if child is EnterBuildingAbility:
			return child
	return null

func _nearest_player_building(display: String) -> Node3D:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display:
			return b
	return null

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
