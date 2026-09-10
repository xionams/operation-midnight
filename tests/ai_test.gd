extends Node

## Verifies the enemy plays by the same rules: separate credits, its own
## harvest loop, real construction and production, and attack waves.

var _main: Node3D
var _director: AIDirector
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	_director = _main.get_node("AIDirector")
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _enemy_buildings() -> Array:
	return get_tree().get_nodes_in_group("enemy_buildings")

func _has_enemy(display_name: String) -> bool:
	for b in _enemy_buildings():
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name:
			return true
	return false

func _count_enemy_units() -> int:
	return get_tree().get_nodes_in_group("enemy_units").size()

func _run() -> void:
	# --- the two economies are genuinely separate ---
	var player_before: int = GameState.credits
	var enemy_before: int = GameState.enemy_credits
	_check("Both sides start with credits", player_before > 0 and enemy_before > 0,
		"(player %d, enemy %d)" % [player_before, enemy_before])

	_check("Spending enemy credits leaves the player untouched",
		GameState.try_spend_for(false, 500) and GameState.credits == player_before
		and GameState.enemy_credits == enemy_before - 500,
		"(player %d, enemy %d)" % [GameState.credits, GameState.enemy_credits])

	_check("Spending player credits leaves the enemy untouched",
		GameState.try_spend_for(true, 300) and GameState.enemy_credits == enemy_before - 500
		and GameState.credits == player_before - 300)

	## The bug this guards: an enemy building using the shared production
	## queue must not charge the player.
	var barracks_stats: BuildingStats = load("res://config/buildings/barracks.tres")
	var enemy_barracks = load("res://scenes/buildings/barracks.tscn").instantiate()
	enemy_barracks.stats = barracks_stats
	enemy_barracks.is_player_faction = false
	_main.get_node("Level/NavRegion").add_child(enemy_barracks)
	enemy_barracks.global_position = Vector3(60, 0, -60)
	await get_tree().process_frame

	var p_before: int = GameState.credits
	var e_before: int = GameState.enemy_credits
	enemy_barracks.produce(load("res://config/units/rifle_soldier.tres"))
	_check("Enemy production spends enemy credits, not the player's",
		GameState.credits == p_before and GameState.enemy_credits < e_before,
		"(player %d unchanged, enemy %d -> %d)" % [GameState.credits, e_before, GameState.enemy_credits])

	## And an enemy refinery must pay the enemy.
	var refinery_stats: BuildingStats = load("res://config/buildings/refinery.tres")
	var enemy_refinery = load("res://scenes/buildings/refinery.tscn").instantiate()
	enemy_refinery.stats = refinery_stats
	enemy_refinery.is_player_faction = false
	_main.get_node("Level/NavRegion").add_child(enemy_refinery)
	enemy_refinery.global_position = Vector3(70, 0, -60)
	await get_tree().process_frame

	p_before = GameState.credits
	e_before = GameState.enemy_credits
	enemy_refinery.receive_resources(700.0)
	_check("Enemy harvest income goes to the enemy",
		GameState.credits == p_before and GameState.enemy_credits == e_before + 700,
		"(player %d unchanged, enemy +%d)" % [GameState.credits, GameState.enemy_credits - e_before])

	_check("Enemy refineries are not offered to player harvesters",
		GameState.get_nearest_refinery(Vector3(70, 0, -60), true) == null)
	_check("Enemy harvesters can find their own refinery",
		GameState.get_nearest_refinery(Vector3(70, 0, -60), false) != null)

	# --- the director actually builds and produces ---
	GameState.enemy_credits = 20000
	var buildings_before: int = _enemy_buildings().size()
	var units_before: int = _count_enemy_units()

	var waited: float = 0.0
	while waited < 40.0 and not (_has_enemy("Barracks") and _has_enemy("Power Plant")):
		waited += get_process_delta_time()
		await get_tree().process_frame

	_check("AI builds a Refinery", _has_enemy("Resource Refinery"))
	_check("AI builds a Power Plant", _has_enemy("Power Plant"))
	_check("AI builds a Barracks", _has_enemy("Barracks"))
	_check("AI base grew", _enemy_buildings().size() > buildings_before,
		"(%d -> %d)" % [buildings_before, _enemy_buildings().size()])
	_check("AI paid for what it built", GameState.enemy_credits < 20000,
		"(%d left)" % GameState.enemy_credits)

	## Harvesters are the first thing it should want, but one takes 10s to
	## build - so wait for it rather than checking the instant the
	## buildings appear.
	var harvesters: int = 0
	waited = 0.0
	while waited < 30.0 and harvesters == 0:
		waited += get_process_delta_time()
		await get_tree().process_frame
		harvesters = 0
		for u in get_tree().get_nodes_in_group("enemy_units"):
			if is_instance_valid(u) and u.stats != null and u.stats.is_harvester:
				harvesters += 1
	_check("AI produces harvesters for its economy", harvesters > 0,
		"(%d after %.0fs)" % [harvesters, waited])

	waited = 0.0
	while waited < 45.0 and _count_enemy_units() <= units_before + 2:
		waited += get_process_delta_time()
		await get_tree().process_frame
	_check("AI army grows over time", _count_enemy_units() > units_before,
		"(%d -> %d)" % [units_before, _count_enemy_units()])

	# --- offense: a wave eventually marches on the player ---
	## The AI deliberately stays home until its first scheduled probe, so
	## the player gets an opening. Skip that grace period rather than
	## waiting it out in a test.
	_director._match_time = AIDirector.WAVE_SCHEDULE[0].x + 1.0
	var attacking: int = 0
	waited = 0.0
	while waited < 60.0 and attacking < _director.current_wave_size():
		waited += get_process_delta_time()
		await get_tree().process_frame
		attacking = 0
		for u in get_tree().get_nodes_in_group("enemy_units"):
			if is_instance_valid(u) and u.current_command == CommandTypes.Type.ATTACK_MOVE:
				attacking += 1
	_check("AI forms an attack wave and sends it", attacking >= _director.current_wave_size(),
		"(%d attacking after %.0fs)" % [attacking, waited])

	_check("The player's balance was never touched by the AI",
		GameState.credits == p_before,
		"(%d vs %d)" % [GameState.credits, p_before])
