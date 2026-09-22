extends Node

## Boots a real match on one map and checks the economy actually runs.
##
## The data test says the numbers are sane. This says the battlefield
## works: harvesters can reach the ore and get back, the AI can place
## buildings on the ground it has, and credits actually arrive. A field
## the navmesh cannot deliver to looks perfectly fine in a .tres.
##
## One map per process, chosen by a user argument:
##     godot --headless res://tests/map_playability_test.tscn -- 1
##
## The harness follows the same shape as every other test here - a scene
## whose root IS main.tscn - and switches map the way the game does, by
## storing the choice and reloading. Instantiating main.tscn by hand
## instead looked simpler and quietly broke the AI on every map,
## including the one the rest of the suite runs on.

const MAPS: Array[String] = [
	"res://config/maps/ridgeline.tres",
	"res://config/maps/dry_basin.tres",
	"res://config/maps/cold_corridor.tres",
]
const SETTLE: float = 150.0

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-52s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _target() -> Resource:
	var index: int = 0
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			index = arg.to_int()
	return load(MAPS[clampi(index, 0, MAPS.size() - 1)])

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var wanted := _target()

	## Not the map the scene built with: store the choice and reload, the
	## same path the START button takes.
	if scene.map != wanted:
		GameState.selected_map = wanted
		GameState.skip_setup = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return

	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	get_tree().paused = false

	var name: String = wanted.display_name
	var elapsed: float = 0.0
	while elapsed < SETTLE:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	var director = scene.get_node_or_null("AIDirector")
	_check("%s: a commander is running" % name, director != null)
	if director != null:
		var economy = director.economy
		_check("%s: AI built a refinery" % name, economy.refineries().size() >= 1,
			"(%d)" % economy.refineries().size())
		_check("%s: AI is running harvesters" % name, economy.harvesters().size() >= 2,
			"(%d)" % economy.harvesters().size())
		_check("%s: ore actually reaches a refinery" % name,
			economy.income_per_minute > 0.0,
			"(%d cr/min, trip %.1fs)" % [int(economy.income_per_minute),
				economy.average_round_trip()])
		_check("%s: harvesters have somewhere to go" % name,
			economy.active_harvesters() >= 1, "(%d active)" % economy.active_harvesters())

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
