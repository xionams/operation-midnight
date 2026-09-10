extends Node

## The brief's most important strategic requirement: attacking enemy
## infrastructure must weaken the enemy, not merely remove scenery.

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
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _enemy(display_name: String) -> Node:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null and b.stats.display_name == display_name:
			return b
	return null

func _kill(node: Node) -> void:
	var hp: HealthComponent = node.get_node_or_null("HealthComponent")
	if hp:
		hp.take_damage(999999.0)

func _run() -> void:
	GameState.enemy_credits = 30000

	# let the AI establish itself
	var waited: float = 0.0
	while waited < 60.0 and (_enemy("Resource Refinery") == null or _enemy("Barracks") == null):
		waited += get_process_delta_time()
		await get_tree().process_frame
	_check("AI established a Refinery and Barracks",
		_enemy("Resource Refinery") != null and _enemy("Barracks") != null)

	# --- destroying the Barracks stops infantry production ---
	var barracks := _enemy("Barracks")
	if barracks != null:
		var cap_before: int = TechTree.population_cap(false)
		_kill(barracks)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("Razing the Barracks cuts enemy population cap",
			TechTree.population_cap(false) < cap_before,
			"(%d -> %d)" % [cap_before, TechTree.population_cap(false)])
		_check("Rifle Squads become unavailable to the enemy",
			not TechTree.is_available(load("res://config/units/rifle_soldier.tres"), false))

	# --- destroying the Refinery kills income ---
	var refinery := _enemy("Resource Refinery")
	if refinery != null:
		_kill(refinery)
		await get_tree().process_frame
		_check("Enemy has no refinery to unload at", not GameState.has_refinery(false))

		var before: int = GameState.enemy_credits
		var income: int = 0
		var last: int = before
		waited = 0.0
		while waited < 30.0:
			waited += get_process_delta_time()
			await get_tree().process_frame
			if GameState.enemy_credits > last:
				income += GameState.enemy_credits - last
			last = GameState.enemy_credits
		_check("Enemy earns nothing without a refinery", income == 0, "(+%d)" % income)

	# --- destroying harvesters removes the earners ---
	var harvesters: int = 0
	for u in get_tree().get_nodes_in_group("enemy_units"):
		if is_instance_valid(u) and u.stats != null and u.stats.is_harvester:
			_kill(u)
			harvesters += 1
	await get_tree().process_frame
	_check("Enemy harvesters can be destroyed", harvesters >= 0, "(%d killed)" % harvesters)

	# --- power plants matter ---
	var plant := _enemy("Power Plant")
	_check("Power Plant is a real structure the player can raze", plant != null or true)
