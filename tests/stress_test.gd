extends Node

## Performance harness. Spawns escalating unit counts, drives them across
## the map so navigation, fog, targeting and combat are all live, and
## reports frame timing at each tier.
##
## Reports the worst sustained frame time as well as the average, because
## an average of 60 hides a stall that a player would feel.

const TIERS: Array[int] = [40, 80, 120]
const SETTLE: float = 2.0
const SAMPLE: float = 6.0

const ROSTER: Array[String] = [
	"res://config/units/rifle_soldier.tres",
	"res://config/units/at_squad.tres",
	"res://config/units/assault_vehicle.tres",
	"res://config/units/scout_vehicle.tres",
	"res://config/units/main_battle_tank.tres",
]

var _main: Node3D
var _spawned: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	## The skirmish setup screen pauses the tree until START is pressed;
	## harnesses start the match themselves.
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	## The AI would otherwise add units mid-measurement and make the
	## numbers unrepeatable.
	var director = _main.get_node_or_null("AIDirector")
	if director:
		director.enabled = false
	await _run()
	print("STRESS| DONE")
	get_tree().quit()

func _spawn(path: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	_spawned.append(u)
	return u

func _run() -> void:
	for tier in TIERS:
		await _fill_to(tier)
		var result := await _measure(tier)
		print("STRESS| %3d units  avg %5.1f FPS  worst frame %5.1f ms  units alive %d" % [
			tier, result[0], result[1], get_tree().get_nodes_in_group("units").size()])

## Two forces facing each other, so combat and targeting are exercised
## rather than only pathfinding.
func _fill_to(target: int) -> void:
	var existing: int = get_tree().get_nodes_in_group("units").size()
	var index: int = existing
	while get_tree().get_nodes_in_group("units").size() < target:
		var player: bool = index % 2 == 0
		var path: String = ROSTER[index % ROSTER.size()]
		var lane: float = float(index / 2) * 2.2 - 30.0
		var pos := Vector3(-40.0 if player else 40.0, 0.0, clampf(lane, -60.0, 60.0))
		var unit := _spawn(path, player, pos)
		unit.issue_command(CommandTypes.Type.ATTACK_MOVE,
			Vector3(40.0 if player else -40.0, 0.0, pos.z))
		index += 1
	for i in int(SETTLE * 60.0):
		await get_tree().process_frame

func _measure(_tier: int) -> Array:
	var frames: int = 0
	var total: float = 0.0
	var worst: float = 0.0
	var elapsed: float = 0.0
	while elapsed < SAMPLE:
		var delta: float = await _next_delta()
		elapsed += delta
		frames += 1
		total += delta
		worst = maxf(worst, delta)
	var average_fps: float = float(frames) / maxf(total, 0.001)
	return [average_fps, worst * 1000.0]

func _next_delta() -> float:
	await get_tree().process_frame
	return get_process_delta_time()
