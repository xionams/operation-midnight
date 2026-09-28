extends Node

## Losing your last headquarters loses the match, however it goes.
##
## Selling one did not go through _on_died, so a sold HQ vanished without
## ever reporting the loss: the match carried on with no defeat
## condition, no build radius and nothing to rebuild from. Underneath
## that sat a second defect - the match ended on ANY headquarters going,
## not the last one, so a spare HQ was a liability rather than insurance.

const HQ := preload("res://config/buildings/command_hq.tres")
const POWER := preload("res://config/buildings/power_plant.tres")

var _main: Node3D
var _fails: Array = []
var _ended: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _build(stats, player: bool, pos: Vector3) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _hqs(player: bool) -> int:
	var n: int = 0
	for b in get_tree().get_nodes_in_group("player_buildings" if player else "enemy_buildings"):
		if is_instance_valid(b) and b is CommandHQ and not b.is_queued_for_deletion():
			n += 1
	return n

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	GameState.match_ended.connect(func(won): _ended.append(won))
	GameState.add_credits(40000)
	await _frames(4)

	var base: Vector3 = _main.map.player_base
	_check("Match starts live", GameState.match_state == GameState.MatchState.PLAYING)
	_check("The player starts with one HQ", _hqs(true) == 1, "%d" % _hqs(true))

	# --- selling a SPARE HQ must not lose the match ---
	var spare = _build(HQ, true, base + Vector3(26, 0, 22))
	await _frames(3)
	_check("A second HQ can be built", _hqs(true) == 2, "%d" % _hqs(true))
	spare.sell()
	await _frames(4)
	_check("Selling a spare HQ does NOT end the match",
		GameState.match_state == GameState.MatchState.PLAYING and _ended.is_empty(),
		"state=%d" % GameState.match_state)
	_check("...and the spare is gone", _hqs(true) == 1, "%d" % _hqs(true))

	# --- destroying a SPARE HQ must not lose the match either ---
	var spare2 = _build(HQ, true, base + Vector3(26, 0, -22))
	await _frames(3)
	spare2.get_node("HealthComponent").take_damage(999999.0)
	await _frames(4)
	_check("Destroying a spare HQ does NOT end the match",
		GameState.match_state == GameState.MatchState.PLAYING and _ended.is_empty(),
		"state=%d" % GameState.match_state)

	# --- selling an ordinary building is untouched ---
	var plant = _build(POWER, true, base + Vector3(0, 0, 18))
	await _frames(3)
	var before: int = GameState.credits
	plant.sell()
	await _frames(3)
	_check("Selling a normal building still refunds and ends nothing",
		GameState.credits > before and GameState.match_state == GameState.MatchState.PLAYING,
		"+%d" % (GameState.credits - before))

	# --- save/load must not confuse the HQ count ---
	var save := SaveGame.capture(_main)
	var counted: int = 0
	for entry in save.get("buildings", []):
		if entry.get("player", false) and String(entry.get("name", "")) == HQ.display_name:
			counted += 1
	## The count has to match what is actually on the field, so a sold or
	## destroyed HQ cannot come back on load and quietly restore a defeat
	## condition the player already lost - or vice versa.
	_check("A save records exactly the surviving HQs", counted == _hqs(true),
		"saved %d, live %d" % [counted, _hqs(true)])

	# --- selling the LAST HQ loses, exactly as combat does ---
	var last: Node = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b is CommandHQ:
			last = b
	_check("One HQ left to lose", last != null and _hqs(true) == 1)
	last.sell()
	await _frames(5)
	_check("Selling the LAST HQ ends the match",
		GameState.match_state == GameState.MatchState.DEFEAT,
		"state=%d" % GameState.match_state)
	_check("...and it is reported as a defeat, not a win",
		_ended.size() == 1 and _ended[0] == false, "%s" % str(_ended))

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
