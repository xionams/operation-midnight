extends Node

## 40 v 40 mixed-composition engagement. Verifies that a real battle
## resolves: units find targets, damage lands, things die, veterancy is
## earned, and nothing deadlocks in a corner.

const PER_SIDE: int = 40
const BATTLE_TIME: float = 45.0

const PLAYER_MIX: Array[String] = [
	"res://config/units/assault_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
]
const ENEMY_MIX: Array[String] = [
	"res://config/units/assault_vehicle.tres",
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/scout_vehicle.tres",
]

var _main: Node3D
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
	FogOfWar.enabled = false
	var director = _main.get_node_or_null("AIDirector")
	if director:
		director.enabled = false
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

func _spawn(path: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _run() -> void:
	var players: Array = []
	var enemies: Array = []
	for i in PER_SIDE:
		var lane: float = float(i) * 1.8 - 36.0
		players.append(_spawn(PLAYER_MIX[i % PLAYER_MIX.size()], true, Vector3(-26, 0, lane)))
		enemies.append(_spawn(ENEMY_MIX[i % ENEMY_MIX.size()], false, Vector3(26, 0, lane)))
	await get_tree().process_frame

	_check("Both armies deployed",
		players.size() == PER_SIDE and enemies.size() == PER_SIDE)

	## Spread destinations the way SelectionManager does for a real order.
	## Sending forty units to one coordinate guarantees a pile-up and
	## measures the test's own mistake rather than the game's behaviour.
	for i in players.size():
		var lane: float = float(i) * 1.8 - 36.0
		players[i].issue_command(CommandTypes.Type.ATTACK_MOVE, Vector3(20, 0, lane * 0.6))
	for i in enemies.size():
		var lane: float = float(i) * 1.8 - 36.0
		enemies[i].issue_command(CommandTypes.Type.ATTACK_MOVE, Vector3(-20, 0, lane * 0.6))

	var start_units: int = get_tree().get_nodes_in_group("units").size()
	var elapsed: float = 0.0
	var frames: int = 0
	var total: float = 0.0
	var worst: float = 0.0
	while elapsed < BATTLE_TIME:
		await get_tree().process_frame
		var d: float = get_process_delta_time()
		elapsed += d
		frames += 1
		total += d
		worst = maxf(worst, d)

	var alive: int = get_tree().get_nodes_in_group("units").size()
	_check("Units actually died in the battle", alive < start_units,
		"(%d -> %d)" % [start_units, alive])

	## Both sides should have taken losses; a one-sided wipe usually means
	## half the army never engaged.
	var players_alive: int = players.filter(func(u): return is_instance_valid(u)).size()
	var enemies_alive: int = enemies.filter(func(u): return is_instance_valid(u)).size()
	_check("Both sides took casualties",
		players_alive < PER_SIDE and enemies_alive < PER_SIDE,
		"(player %d/%d, enemy %d/%d)" % [players_alive, PER_SIDE, enemies_alive, PER_SIDE])

	var ranked: int = 0
	for u in players + enemies:
		if not is_instance_valid(u):
			continue
		var vet: VeterancyComponent = u.get_node_or_null("VeterancyComponent")
		if vet != null and vet.rank != VeterancyComponent.Rank.REGULAR:
			ranked += 1
	_check("Survivors earned veterancy", ranked > 0, "(%d promoted)" % ranked)

	## Deadlock means "still not moving after time to resolve", so sample
	## positions and re-check rather than reading one frame.
	var snapshot: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.nav_agent != null \
			and not u.nav_agent.is_navigation_finished():
			snapshot[u] = u.global_position
	for i in 240:
		await get_tree().physics_frame
	var idle_stuck: int = 0
	for u in snapshot:
		if not is_instance_valid(u) or u.nav_agent == null:
			continue
		if u.nav_agent.is_navigation_finished():
			continue
		if u.global_position.distance_to(snapshot[u]) < 0.5:
			idle_stuck += 1
	_check("No large-scale deadlock", idle_stuck < 8,
		"(%d of %d travelling units made no progress)" % [idle_stuck, snapshot.size()])

	print("TEST| battle FPS avg %.1f, worst frame %.1f ms" % [
		float(frames) / maxf(total, 0.001), worst * 1000.0])
