extends Node

## A fight has to be readable without selecting anything. A vehicle at 20%
## health looked identical to one at full health, and every modelled
## building's damage state was dead code - BuildingBase returned early on
## a null _body, which is the case for every structure that uses a model.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _plume_of(node: Node) -> Node:
	for child in node.get_children():
		if child is CPUParticles3D:
			return child
	return null

func _hurt_to(node: Node, fraction: float) -> void:
	var hp = node.get_node_or_null("HealthComponent")
	hp.current_health = hp.max_health * fraction
	## Damage state is refreshed from the process loop, so let one run.
	await get_tree().physics_frame
	await get_tree().process_frame

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	await get_tree().physics_frame

	var tank: Node = null
	for unit in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(unit) and unit.stats != null \
			and unit.stats.body_size.y >= 1.2:
			tank = unit
			break
	_check("Found a vehicle to damage", tank != null)
	if tank == null:
		return _finish()

	_check("Healthy vehicle shows nothing", _plume_of(tank) == null)

	await _hurt_to(tank, 0.5)
	_check("Vehicle smokes below 60% health", _plume_of(tank) != null)

	await _hurt_to(tank, 0.2)
	var plume := _plume_of(tank)
	_check("Vehicle still marked below 30% health", plume != null)
	var burning: bool = false
	if plume != null:
		for child in plume.get_children():
			if child is CPUParticles3D:
				burning = true
	_check("Heavily damaged vehicle burns as well as smokes", burning)

	## Repair must clear it, or players learn to distrust the effect.
	await _hurt_to(tank, 1.0)
	_check("Repaired vehicle stops smoking", _plume_of(tank) == null)

	## The building path is the one that was dead.
	var building: Node = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b):
			building = b
			break
	_check("Found a structure to damage", building != null)
	if building != null:
		_check("Structure uses a model, not the primitive stand-in",
			building.get("_body") == null)
		await _hurt_to(building, 0.5)
		_check("Modelled structure smokes below 60% health",
			_plume_of(building) != null)
	_finish()

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
