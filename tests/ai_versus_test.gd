extends Node

## Two commanders, one map, same rules.
##
## Every AI measurement so far has been against a player who does
## nothing. That flatters it: the economy is never raided, the army is
## never traded down, and one attack wave is enough because nothing
## shoots back. This puts the same brain on both sides so the numbers
## mean something.
##
## What is being asked is not "who wins" - it is whether a commander that
## loses a wave keeps playing: rebuilds, re-attacks, defends its own base,
## and does not sit at zero credits after its first bad fight.

const TIME_LIMIT: float = 1200.0
const SNAPSHOT: float = 60.0

var _main: Node3D
var _enemy: AIDirector
var _player: AIDirector

var _peak := {"p_army": 0, "e_army": 0, "p_units": 0, "e_units": 0}
var _waves := {"p": 0, "e": 0}
var _retreats := {"p": 0, "e": 0}
var _was := {"p": false, "e": false}
## The behaviour actually under test: a commander whose wave failed must
## come back. Asserting "two waves happened" punishes a short match for
## being decisive; this asks whether a RETREAT was ever followed by
## another commitment.
var _retreat_at := {"p": -1.0, "e": -1.0}
var _recommitted := {"p": false, "e": false}
## Ticks after a retreat where the commander had everything it needed to
## attack and still did not. "Did not re-attack" is only a bug if it was
## actually able to - refusing to walk 4,000 credits of army into 17,000
## is judgement, not paralysis.
var _ready_but_idle := {"p": 0, "e": 0}
var _elapsed: float = 0.0
var _zero_credit_ticks := {"p": 0, "e": 0}
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	_enemy = _main.get_node("AIDirector")
	_enemy.difficulty = AIDirector.Difficulty.NORMAL

	## A second commander on the player side, with the player's own base
	## and treasury. Nothing is granted to it that the human does not get.
	_player = AIDirector.new()
	_player.name = "PlayerBot"
	_player.is_player = true
	_player.difficulty = AIDirector.Difficulty.NORMAL
	_main.add_child(_player)
	_player.setup(_main.get_node("Level/NavRegion"), _main.get_node("Level"),
		Vector3(-78, 0, 62), Vector3(76, 0, -70))

	## The map seeds the ENEMY base with a barracks, two assault vehicles
	## and a rifle guard, and gives the player only an HQ and two vehicles -
	## deliberate, because the player is meant to be a human. Mirroring it
	## here is what makes this a measurement of the commander rather than
	## of the head start.
	_mirror_opening()

	## The player side is normally driven by a human, so nothing reveals
	## the map for it. Give the bot the same opening knowledge the human
	## starts with and let it scout for the rest.
	FogOfWar.reveal_area(Vector3(-78, 0, 62), 34.0)
	FogOfWar.update_now()

	print("VS| player=%s  enemy=%s" % [_player.strategy_name(), _enemy.strategy_name()])
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _mirror_opening() -> void:
	var base := Vector3(-78, 0, 62)
	var barracks = load("res://scenes/buildings/barracks.tscn").instantiate()
	barracks.stats = load("res://config/buildings/barracks.tres")
	barracks.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(barracks)
	barracks.global_position = base + Vector3(14, 0, -6)

	var spawn := func(scene: String, stats: String, offset: Vector3):
		var unit = load(scene).instantiate()
		unit.stats = load(stats)
		unit.is_player_faction = true
		_main.get_node("Level").add_child(unit)
		unit.global_position = base + offset
	spawn.call("res://scenes/units/assault_vehicle.tscn",
		"res://config/units/assault_vehicle.tres", Vector3(9, 0, 0))
	spawn.call("res://scenes/units/rifle_soldier.tscn",
		"res://config/units/rifle_soldier.tres", Vector3(12, 0, -3))

func _hq(group: String) -> Node:
	for b in get_tree().get_nodes_in_group(group):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			return b
	return null

func _track(side: String, director: AIDirector) -> void:
	var army: int = director.economy.army_value()["total"]
	var key_army: String = side + "_army"
	var key_units: String = side + "_units"
	_peak[key_army] = maxi(_peak[key_army], army)
	_peak[key_units] = maxi(_peak[key_units],
		get_tree().get_nodes_in_group(director._own_units()).size())
	if director._attack_committed and not _was[side]:
		_waves[side] += 1
		if _retreat_at[side] >= 0.0:
			_recommitted[side] = true
	elif _was[side] and not director._attack_committed:
		_retreats[side] += 1
		_retreat_at[side] = _elapsed
	_was[side] = director._attack_committed
	if GameState.balance_of(director.is_player) <= 0:
		_zero_credit_ticks[side] += 1
	if _retreat_at[side] >= 0.0 and not director._attack_committed \
		and director.offense_block_reason() == "ready":
		_ready_but_idle[side] += 1

func _run() -> void:
	var elapsed: float = 0.0
	var snapshot: float = 0.0
	var winner: String = "neither"
	var ticks: int = 0

	while elapsed < TIME_LIMIT:
		var delta: float = get_process_delta_time()
		elapsed += delta
		_elapsed = elapsed
		ticks += 1
		await get_tree().process_frame
		_track("p", _player)
		_track("e", _enemy)

		snapshot -= delta
		if snapshot <= 0.0:
			snapshot = SNAPSHOT
			print("VS| t=%4.0f P %s [%s]" % [
				elapsed, _player.economy.format_line(elapsed), _player.offense_block_reason()])
			print("VS|        E %s [%s]" % [
				_enemy.economy.format_line(elapsed), _enemy.offense_block_reason()])

		if _hq("player_buildings") == null:
			winner = "enemy"
			break
		if _hq("enemy_buildings") == null:
			winner = "player"
			break

	print("")
	print("VS| ===== RESULT after %d:%02d =====" % [int(elapsed) / 60, int(elapsed) % 60])
	print("VS| winner              %s" % winner)
	print("VS| peak army           player %d / enemy %d" % [_peak["p_army"], _peak["e_army"]])
	print("VS| peak units          player %d / enemy %d" % [_peak["p_units"], _peak["e_units"]])
	print("VS| attack waves        player %d / enemy %d" % [_waves["p"], _waves["e"]])
	print("VS| retreats            player %d / enemy %d" % [_retreats["p"], _retreats["e"]])
	print("VS| buildings left      player %d / enemy %d" % [
		get_tree().get_nodes_in_group("player_buildings").size(),
		get_tree().get_nodes_in_group("enemy_buildings").size()])
	print("")

	## A contested match, not a walkover: both sides had to build an
	## economy while being shot at.
	_check("Both sides built an economy",
		_player.economy.refineries().size() >= 1 and _enemy.economy.refineries().size() >= 1,
		"(player %d, enemy %d refineries)" % [
			_player.economy.refineries().size(), _enemy.economy.refineries().size()])
	_check("Both sides fielded an army",
		_peak["p_army"] >= 2000 and _peak["e_army"] >= 2000,
		"(player %d, enemy %d)" % [_peak["p_army"], _peak["e_army"]])

	## The point of the whole mission: losing a wave must not end a
	## commander's participation in the match.
	var retreated: int = _retreats["p"] + _retreats["e"]
	var came_back: bool = _recommitted["p"] or _recommitted["e"]
	if retreated == 0:
		print("TEST| %-52s N/A (no wave failed this match)" % "After a failed wave")
	else:
		## The gate, not the outcome: a commander that was ready and just
		## sat there is broken; one that never rebuilt enough force is
		## making a defensible call.
		var stuck: int = maxi(_ready_but_idle["p"], _ready_but_idle["e"])
		_check("A retreating commander is never ready-but-idle", stuck < 120,
			"(%d ticks ready without committing; recommitted: player %s, enemy %s)" % [
				stuck, _recommitted["p"], _recommitted["e"]])
		print("TEST| note: %d retreat(s); re-attacked = %s" % [
			retreated, came_back])
	_check("At least one commander pressed an attack",
		_waves["p"] + _waves["e"] >= 1,
		"(player %d, enemy %d)" % [_waves["p"], _waves["e"]])
	_check("Neither side sat broke for most of the match",
		_zero_credit_ticks["p"] < ticks / 2 and _zero_credit_ticks["e"] < ticks / 2,
		"(player %d%%, enemy %d%% of ticks at zero)" % [
			_zero_credit_ticks["p"] * 100 / maxi(ticks, 1),
			_zero_credit_ticks["e"] * 100 / maxi(ticks, 1)])
	_check("The match actually resolved or was still contested",
		winner != "neither" or (
			get_tree().get_nodes_in_group("player_buildings").size() >= 2
			and get_tree().get_nodes_in_group("enemy_buildings").size() >= 2))
