extends Node

## Plays a match, saves it, resumes it, and checks it is the same match.
##
## A phone game gets interrupted constantly, so "save" that loses the
## army, the ore in the ground or the map you had explored is not a save.
## This compares the state either side of a round trip rather than
## trusting that the file was written.

const SETTLE: float = 120.0

var _fails: Array = []
var _before: Dictionary = {}

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _snapshot(scene: Node) -> Dictionary:
	var tree := get_tree()
	var ore: float = 0.0
	for node in tree.get_nodes_in_group("resource_nodes"):
		if is_instance_valid(node):
			ore += node.remaining
	var explored: int = 0
	for byte in FogOfWar.export_explored():
		if byte > 0:
			explored += 1
	var health: float = 0.0
	for group in ["player_units", "enemy_units"]:
		for unit in tree.get_nodes_in_group(group):
			if is_instance_valid(unit) and unit.health != null:
				health += unit.health.current_health
	return {
		"player_units": tree.get_nodes_in_group("player_units").size(),
		"enemy_units": tree.get_nodes_in_group("enemy_units").size(),
		"player_buildings": tree.get_nodes_in_group("player_buildings").size(),
		"enemy_buildings": tree.get_nodes_in_group("enemy_buildings").size(),
		"neutral_buildings": tree.get_nodes_in_group("neutral_buildings").size(),
		"resources": tree.get_nodes_in_group("resource_nodes").size(),
		"ore": ore,
		"credits": GameState.credits,
		"enemy_credits": GameState.enemy_credits,
		"explored": explored,
		"unit_health": health,
	}

func _ready() -> void:
	var scene := get_parent()

	## Second pass: the scene was rebuilt from the save. The commander
	## must be stopped BEFORE any frame runs - given one tick it queues a
	## harvester, and the 1,200 credits that costs look exactly like the
	## save having lost them.
	if not _resumed_state().is_empty():
		var resumed_director = scene.get_node_or_null("AIDirector")
		if resumed_director != null:
			resumed_director.enabled = false
		await get_tree().process_frame
		await _verify(scene)
		return

	await get_tree().process_frame

	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame

	## Let a real match develop so there is something worth saving.
	await _wait(SETTLE)
	_before = _snapshot(scene)
	print("TEST| before: %s" % str(_before))
	_check("A match developed before saving",
		_before["enemy_buildings"] >= 3 and _before["enemy_units"] >= 3,
		"(%d buildings, %d units)" % [_before["enemy_buildings"], _before["enemy_units"]])

	_check("Saving writes a file", SaveGame.save(scene))
	var data := SaveGame.load_data()
	_check("The save reads back", not data.is_empty())
	_check("The save carries the army",
		data.get("units", []).size() == _before["player_units"] + _before["enemy_units"],
		"(%d)" % data.get("units", []).size())

	## Stash what we measured, then resume the way the game would.
	GameState.set_meta("save_test_before", _before)
	GameState.pending_save = data
	GameState.skip_setup = true
	get_tree().paused = false
	get_tree().reload_current_scene()

func _resumed_state() -> Dictionary:
	if GameState.has_meta("save_test_before"):
		return GameState.get_meta("save_test_before")
	return {}

func _verify(scene: Node) -> void:
	var before: Dictionary = _resumed_state()
	GameState.remove_meta("save_test_before")
	## The commander resumes and starts spending the moment the match
	## runs, which is correct but would be measured as the save losing
	## credits. Hold it still for the comparison, then let it go.
	var director = scene.get_node_or_null("AIDirector")
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame

	var after := _snapshot(scene)
	print("TEST| after:  %s" % str(after))

	for key in ["player_units", "enemy_units", "player_buildings",
			"enemy_buildings", "neutral_buildings", "resources"]:
		_check("Resumed with the same %s" % key.replace("_", " "),
			after[key] == before[key], "(%d -> %d)" % [before[key], after[key]])

	_check("Credits survived", after["credits"] == before["credits"],
		"(%d -> %d)" % [before["credits"], after["credits"]])
	_check("Enemy credits survived", after["enemy_credits"] == before["enemy_credits"],
		"(%d -> %d)" % [before["enemy_credits"], after["enemy_credits"]])
	_check("Ore left in the ground survived",
		absf(after["ore"] - before["ore"]) < 50.0,
		"(%.0f -> %.0f)" % [before["ore"], after["ore"]])
	_check("The explored map survived",
		after["explored"] >= before["explored"] * 0.95,
		"(%d -> %d cells)" % [before["explored"], after["explored"]])
	## Damaged units must come back damaged, not healed.
	_check("Unit damage survived",
		absf(after["unit_health"] - before["unit_health"]) < before["unit_health"] * 0.02,
		"(%.0f -> %.0f hp)" % [before["unit_health"], after["unit_health"]])

	## And the resumed match must keep playing.
	if director != null:
		director.enabled = true
	await _wait(25.0)
	_check("The resumed match keeps running",
		get_tree().get_nodes_in_group("enemy_units").size() >= 1)

	SaveGame.delete()
	_check("Deleting the save removes it", not SaveGame.has_save())

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
