extends Node

## Phase 17/23: deliberate economic damage, and whether the AI recovers.
##
## A commander that dies permanently to one moderate raid is not an
## opponent, it is a fuse. Each scenario damages the AI's economy and
## then checks that income actually returns - not that the AI "looks
## busy", but that credits start arriving again.

const SETTLE: float = 150.0
const RECOVERY_WINDOW: float = 180.0

var _main: Node3D
var _director: AIDirector
var _economy: AIEconomy
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_director = _main.get_node("AIDirector")
	_director.difficulty = AIDirector.Difficulty.NORMAL
	_economy = _director.economy
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

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

## Measures whether money actually arrives over a window, which is the
## only honest definition of "the economy recovered".
func _income_over(seconds: float) -> int:
	var gained: int = 0
	var last: int = GameState.enemy_credits
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame
		var now: int = GameState.enemy_credits
		if now > last:
			gained += now - last
		last = now
	return gained

func _kill(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var hp: HealthComponent = node.get_node_or_null("HealthComponent")
	if hp:
		hp.take_damage(999999.0)

func _run() -> void:
	## Let the AI establish itself on its own income first.
	await _wait(SETTLE)
	print("TEST| settled: %s" % _economy.format_line(SETTLE))
	_check("AI established an economy before damage",
		_economy.refineries().size() >= 1 and _economy.harvesters().size() >= 2,
		"(%d refineries, %d harvesters)" % [
			_economy.refineries().size(), _economy.harvesters().size()])

	# --- Scenario A: lose one harvester ---
	var before: int = _economy.harvesters().size()
	if before > 0:
		_kill(_economy.harvesters()[0])
	await _wait(60.0)
	_check("A: replaces a single lost harvester",
		_economy.harvesters().size() >= before,
		"(%d -> %d)" % [before, _economy.harvesters().size()])

	# --- Scenario C: lose the entire harvest fleet ---
	for harvester in _economy.harvesters():
		_kill(harvester)
	await get_tree().process_frame
	_check("C: harvest fleet destroyed", _economy.harvesters().is_empty())
	await _wait(90.0)
	_check("C: rebuilds harvesters from reserve",
		_economy.harvesters().size() >= 1,
		"(%d)" % _economy.harvesters().size())
	var income: int = await _income_over(60.0)
	_check("C: income resumes after losing the fleet", income > 0, "(+%d)" % income)

	# --- Scenario B: lose a refinery ---
	var refineries_before: int = _economy.refineries().size()
	if refineries_before > 0:
		_kill(_economy.refineries()[0])
	await get_tree().process_frame
	await _wait(RECOVERY_WINDOW)
	_check("B: rebuilds a destroyed refinery",
		_economy.refineries().size() >= mini(refineries_before, 1),
		"(%d -> %d)" % [refineries_before, _economy.refineries().size()])

	# --- Scenario D: lose power ---
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.power_generation > 0:
			_kill(building)
	await get_tree().process_frame
	await _wait(RECOVERY_WINDOW)
	var generation: int = 0
	for building in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(building) and building.stats != null:
			generation += building.stats.power_generation
	_check("D: restores power generation", generation > 0, "(%d)" % generation)

	# --- the economy must not be permanently dead ---
	var final_income: int = await _income_over(60.0)
	_check("Economy is alive after sustained damage", final_income > 0,
		"(+%d over 60s)" % final_income)
	print("TEST| final: %s" % _economy.format_line(0.0))
