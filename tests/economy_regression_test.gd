extends Node

## Guards the harvest loop for BOTH sides. The AI stalling for 95 seconds
## turned out to be a navmesh problem that applied to player harvesters
## equally - agent_radius baked smaller than the widest unit, and resource
## nodes carving holes around the ore - so this checks income actually
## arrives rather than only that a harvester exists.

const HARVEST_WINDOW: float = 100.0

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	await get_tree().process_frame
	FogOfWar.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-50s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _run() -> void:
	## Both sides get a home field within reach; neither should be stranded.
	var nearest_to_player := _nearest_node_distance(Vector3(-78, 0, 62))
	var nearest_to_enemy := _nearest_node_distance(Vector3(76, 0, -70))
	_check("Player base has ore within reach", nearest_to_player < 45.0,
		"(%.0fm)" % nearest_to_player)
	_check("Enemy base has ore within reach", nearest_to_enemy < 45.0,
		"(%.0fm)" % nearest_to_enemy)

	## A harvester must be able to path onto the ore. Resource nodes are
	## excluded from the navmesh precisely so this is possible.
	var refinery = _main.get_node("Level/NavRegion").get_children().filter(
		func(c): return c is Refinery)
	var player_refinery = load("res://scenes/buildings/refinery.tscn").instantiate()
	player_refinery.stats = load("res://config/buildings/refinery.tres")
	player_refinery.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(player_refinery)
	player_refinery.global_position = Vector3(-64, 0, 46)
	await get_tree().process_frame

	## Measure income, not net balance: the harvester's own purchase price
	## would otherwise mask the first delivery entirely.
	player_refinery.produce(load("res://config/units/harvester.tres"))
	await get_tree().process_frame
	var player_income: int = 0
	var player_last: int = GameState.credits
	var waited: float = 0.0
	while waited < HARVEST_WINDOW and player_income == 0:
		waited += get_process_delta_time()
		await get_tree().process_frame
		if GameState.credits > player_last:
			player_income += GameState.credits - player_last
		player_last = GameState.credits
	_check("Player harvester completes a delivery", player_income > 0,
		"(+%d after %.0fs)" % [player_income, waited])

	## The AI runs the identical loop with its own refinery and credits.
	var enemy_before: int = GameState.enemy_credits
	var enemy_income: int = 0
	var last: int = GameState.enemy_credits
	waited = 0.0
	while waited < HARVEST_WINDOW and enemy_income == 0:
		waited += get_process_delta_time()
		await get_tree().process_frame
		if GameState.enemy_credits > last:
			enemy_income += GameState.enemy_credits - last
		last = GameState.enemy_credits
	_check("Enemy harvester completes a delivery", enemy_income > 0,
		"(+%d after %.0fs)" % [enemy_income, waited])

	## Nothing should be permanently wedged against terrain. Sampled over
	## time and by position, because a single frame cannot tell a stuck
	## unit from one that is turning on the spot or momentarily blocked
	## by a neighbour.
	var start_positions: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(unit) and unit.nav_agent != null \
			and not unit.nav_agent.is_navigation_finished():
			start_positions[unit] = unit.global_position
	for i in 180:
		await get_tree().physics_frame
	var stuck: int = 0
	for unit in start_positions:
		if not is_instance_valid(unit) or unit.nav_agent == null:
			continue
		if unit.nav_agent.is_navigation_finished():
			continue
		if unit.global_position.distance_to(start_positions[unit]) < 0.5:
			stuck += 1
	_check("No unit is wedged mid-path", stuck == 0,
		"(%d of %d travelling units made no progress in 6s)" % [stuck, start_positions.size()])

func _nearest_node_distance(from: Vector3) -> float:
	var best: float = INF
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(node):
			best = minf(best, node.global_position.distance_to(from))
	return best
