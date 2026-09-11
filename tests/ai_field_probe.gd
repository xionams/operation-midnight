extends Node

## Phase 19/20: where the money actually comes from, and whether the AI
## converts map control into income. Prints each field's remaining ore
## and the AI's structure list, so "the economy stalls at four minutes"
## can be attributed rather than guessed at.

const RUN_TIME: float = 420.0
const INTERVAL: float = 60.0

var _director: AIDirector
var _economy: AIEconomy

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	_director = main.get_node("AIDirector")
	_director.difficulty = AIDirector.Difficulty.NORMAL
	_economy = _director.economy
	await _run()
	get_tree().quit()

func _hq() -> Node:
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name == "Command Headquarters":
			return b
	return null

func _report(t: float) -> void:
	var base: Vector3 = _director.base_position
	var parts: Array = []
	for field in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(field):
			parts.append("%.0fm:%.0f" % [
				field.global_position.distance_to(base), field.remaining])
	var names: Dictionary = {}
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null:
			names[b.stats.display_name] = names.get(b.stats.display_name, 0) + 1
	print("FIELD| t=%4.0f fields[%s]" % [t, ", ".join(parts)])
	print("BASE | t=%4.0f %s" % [t, str(names)])
	print(_economy.format_line(t))

func _run() -> void:
	var elapsed: float = 0.0
	var next: float = 0.0
	while elapsed < RUN_TIME:
		elapsed += get_process_delta_time()
		## Keep the passive player alive so the economy can be observed
		## past the point where the AI would otherwise win.
		var hq := _hq()
		if hq and hq.health and hq.health.current_health < hq.health.max_health:
			hq.health.current_health = hq.health.max_health
		await get_tree().process_frame
		if elapsed >= next:
			next += INTERVAL
			_report(elapsed)
	print("PROBE| done")
