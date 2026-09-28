extends Node

## Nothing on this battlefield may simply blink out of existence.
##
## Units used to vanish on the frame they died: a soldier ceased to
## exist, a ship left nothing at all on the water, and a building swapped
## itself for a pile of rubble between one frame and the next. These
## check that a body outlives its unit - and, just as importantly, that
## the unit itself is gone IMMEDIATELY, so a corpse is never a target, a
## population cost, or something the match-end check can trip over.

const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const TANK := preload("res://config/units/assault_vehicle.tres")
const BOAT := preload("res://config/units/patrol_boat.tres")
const POWER := preload("res://config/buildings/power_plant.tres")
const COAST := preload("res://config/maps/coastline.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-60s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _spawn(stats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _corpses() -> int:
	return get_tree().get_nodes_in_group(DeathThroe.CORPSE_GROUP).size()

func _wrecks() -> int:
	return get_tree().get_nodes_in_group("wreckage").size()

func _ready() -> void:
	GameState.selected_map = COAST
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	await _frames(8)

	var base: Vector3 = COAST.player_base

	# --- a soldier leaves a body ---
	var soldier = _spawn(SOLDIER, true, base + Vector3(8, 0, 6))
	await _frames(6)
	var before_corpses: int = _corpses()
	var upright: float = _body_pitch(soldier)
	soldier.health.take_damage(99999.0)
	await _frames(3)
	_check("A dead soldier stops being a unit at once",
		not is_instance_valid(soldier) or soldier.is_queued_for_deletion())
	_check("...but leaves a body behind", _corpses() > before_corpses,
		"%d -> %d corpses" % [before_corpses, _corpses()])
	await _frames(40)
	var corpse: Node3D = get_tree().get_nodes_in_group(DeathThroe.CORPSE_GROUP)[-1]
	_check("The body has fallen over, not stayed standing",
		absf(corpse.rotation.z) > 1.0,
		"rolled %.2f rad (was %.2f)" % [absf(corpse.rotation.z), upright])
	_check("The body is not a unit, a target or a population cost",
		not corpse.is_in_group("units") and not corpse.is_in_group("player_units"))

	# --- corpses are budgeted ---
	for i in DeathThroe.MAX_CORPSES + 6:
		var extra = _spawn(SOLDIER, true, base + Vector3(10 + (i % 8), 0, 10 + (i / 8)))
		await get_tree().process_frame
		extra.health.take_damage(99999.0)
	await _frames(10)
	_check("Corpses are capped rather than carpeting the map",
		_corpses() <= DeathThroe.MAX_CORPSES,
		"%d of %d" % [_corpses(), DeathThroe.MAX_CORPSES])

	# --- a tank leaves a hull ---
	var tank = _spawn(TANK, true, base + Vector3(-8, 0, 6))
	await _frames(6)
	var before_wrecks: int = _wrecks()
	tank.health.take_damage(99999.0)
	await _frames(6)
	_check("A dead tank leaves a wreck", _wrecks() > before_wrecks,
		"%d -> %d" % [before_wrecks, _wrecks()])

	# --- a ship goes down, and leaves no hulk ---
	var sea: Vector3 = Water.nearest_water(base + Vector3(0, 0, 60), 140.0)
	if Water.is_navigable(sea.x, sea.z):
		var boat = _spawn(BOAT, true, Vector3(sea.x, Water.level, sea.z))
		await _frames(6)
		var hull := DeathThroe.take_model(boat)
		_check("The boat has a hull to sink", hull != null)
		if hull != null:
			## Put it back so the real death path handles it.
			hull.get_parent().remove_child(hull)
			boat.add_child(hull)
			boat.set("_model", hull)
		var wrecks_before: int = _wrecks()
		var top: float = boat.global_position.y
		boat.health.take_damage(99999.0)
		await _frames(4)
		_check("A sinking ship leaves no hulk on the water",
			_wrecks() == wrecks_before, "%d -> %d" % [wrecks_before, _wrecks()])
		await _frames(70)
		var still_floating: bool = false
		for n in _main.get_node("Level").get_children():
			if n is Node3D and n.name.contains("patrol") and n.global_position.y >= top - 0.5:
				still_floating = true
		_check("...and the hull has gone under", not still_floating)

	# --- a building comes down before it becomes rubble ---
	var plant = POWER.scene.instantiate()
	plant.stats = POWER
	plant.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(plant)
	plant.global_position = Vector3(base.x + 16, Terrain.height_at(base.x + 16, base.z), base.z)
	EventBus.building_placed.emit(plant)
	await _frames(8)
	var shell := DeathThroe.take_model(plant)
	_check("The power plant has a shell to collapse", shell != null)
	if shell != null:
		shell.get_parent().remove_child(shell)
		plant.add_child(shell)
		plant.set("_visual_root", shell)
	var tall: float = 1.0
	if shell != null:
		tall = shell.scale.y
	var rubble_before: int = _wrecks()
	plant.health.take_damage(99999.0)
	await _frames(3)
	_check("A destroyed building leaves rubble", _wrecks() > rubble_before,
		"%d -> %d" % [rubble_before, _wrecks()])
	if shell != null and is_instance_valid(shell):
		## Sampled part-way through the fall, not on the frame the rubble
		## appears: three frames in, the collapse has barely started and
		## the margin is too small to mean anything.
		await _frames(24)
		if is_instance_valid(shell):
			_check("...and the shell is visibly coming down meanwhile",
				shell.scale.y < tall * 0.8,
				"%.2f -> %.2f of its height" % [tall, shell.scale.y])
		await _frames(50)
		_check("The collapsed shell clears itself away",
			not is_instance_valid(shell) or shell.is_queued_for_deletion())

	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

func _body_pitch(unit: Node) -> float:
	var model: Node3D = unit.get("_model") as Node3D
	return absf(model.rotation.z) if model != null else 0.0
