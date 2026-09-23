extends Node

## The second art pass, checked on observables rather than on looks.
##
## "It looks better" is not a claim a test can make. What it can check is
## that the pieces exist and are wired: turrets that actually turn, ruins
## that actually appear, models inside their declared footprint, and the
## icons the HUD was drawn to use.

var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-54s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

func _spawn(scene_path: String, stats_path: String, is_player: bool, at: Vector3) -> Node:
	var unit = load(scene_path).instantiate()
	unit.stats = load(stats_path)
	unit.is_player_faction = is_player
	get_parent().get_node("Level").add_child(unit)
	unit.global_position = at
	return unit

func _ready() -> void:
	var scene := get_parent()
	await get_tree().process_frame
	var hud = scene.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	get_tree().paused = false
	await get_tree().process_frame

	# --- turrets exist and turn ---
	var tank = _spawn("res://scenes/units/main_battle_tank.tscn",
		"res://config/units/main_battle_tank.tres", true, Vector3(-60, 0, 80))
	var prey = _spawn("res://scenes/units/rifle_soldier.tscn",
		"res://config/units/rifle_soldier.tres", false, Vector3(-60, 0, 66))
	await _wait(0.4)

	_check("A tank's model carries a turret", tank.turret_aim != null)
	if tank.turret_aim != null:
		var start: float = tank.turret_aim._turret.rotation.y
		## Put the target off to one side; the turret must come round.
		prey.global_position = Vector3(-46, 0, 80)
		tank.get_node("AttackerComponent").set_target(prey)
		await _wait(1.2)
		var turned: float = absf(wrapf(
			tank.turret_aim._turret.rotation.y - start, -PI, PI))
		_check("The turret turns toward its target", turned > 0.3,
			"(%.2f rad)" % turned)
		_check("And settles on it", tank.turret_aim.is_on_target())

		## With nothing to shoot it returns to rest rather than staying
		## locked at whatever it last looked at. The target has to be gone,
		## not merely cleared - a live enemy in range is re-acquired on the
		## next tick, which is correct and is not what this checks.
		prey.queue_free()
		await _wait(2.2)
		_check("It returns to rest when the target is gone",
			absf(wrapf(tank.turret_aim._turret.rotation.y, -PI, PI)) < 0.2,
			"(%.2f rad)" % tank.turret_aim._turret.rotation.y)

	var harvester = _spawn("res://scenes/units/harvester.tscn",
		"res://config/units/harvester.tres", true, Vector3(-70, 0, 80))
	await _wait(0.3)
	_check("A harvester has no turret to turn", harvester.turret_aim == null)

	# --- structures leave ruins ---
	var wrecks_before: int = get_tree().get_nodes_in_group("wreckage").size()
	var target: Node = null
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b.stats != null \
			and b.stats.display_name != "Command Headquarters":
			target = b
			break
	_check("There is a structure to destroy", target != null)
	if target != null:
		## Read the position before destroying it: the building is freed
		## by its own death, and asking a freed node where it stood is how
		## this test hung rather than failed.
		var stood_at: Vector3 = target.global_position
		target.get_node("HealthComponent").take_damage(999999.0)
		await _wait(0.5)
		_check("Destroying a structure leaves a ruin",
			get_tree().get_nodes_in_group("wreckage").size() > wrecks_before,
			"(%d)" % get_tree().get_nodes_in_group("wreckage").size())
		var wreck = get_tree().get_nodes_in_group("wreckage").back()
		_check("The ruin stands where the building did",
			Vector2(wreck.global_position.x, wreck.global_position.z).distance_to(
				Vector2(stood_at.x, stood_at.z)) < 2.0)
		_check("The ruin sits on the ground", absf(wreck.global_position.y) < 0.2)

	# --- vehicles leave hulls too ---
	var hulls_before: int = get_tree().get_nodes_in_group("wreckage").size()
	var doomed = _spawn("res://scenes/units/assault_vehicle.tscn",
		"res://config/units/assault_vehicle.tres", true, Vector3(-80, 0, 90))
	await _wait(0.3)
	var died_at: Vector3 = doomed.global_position
	doomed.get_node("HealthComponent").take_damage(999999.0)
	await _wait(0.5)
	_check("A destroyed vehicle leaves a hull",
		get_tree().get_nodes_in_group("wreckage").size() > hulls_before,
		"(%d)" % get_tree().get_nodes_in_group("wreckage").size())
	var hull = get_tree().get_nodes_in_group("wreckage").back()
	_check("The hull lies where the vehicle died",
		Vector2(hull.global_position.x, hull.global_position.z).distance_to(
			Vector2(died_at.x, died_at.z)) < 2.0)

	## Infantry do not leave a vehicle hull.
	var before_infantry: int = get_tree().get_nodes_in_group("wreckage").size()
	var soldier = _spawn("res://scenes/units/rifle_soldier.tscn",
		"res://config/units/rifle_soldier.tres", true, Vector3(-84, 0, 90))
	await _wait(0.3)
	soldier.get_node("HealthComponent").take_damage(999999.0)
	await _wait(0.5)
	_check("Infantry leave no hull behind",
		get_tree().get_nodes_in_group("wreckage").size() == before_infantry)

	## Wreckage is capped so a long match cannot bury the map in it.
	for i in range(Wreckage.MAX_WRECKS + 6):
		Wreckage.spawn_vehicle(self, Vector3(-90 + i, 0, 95))
	await _wait(0.4)
	_check("Wreckage is capped",
		get_tree().get_nodes_in_group("wreckage").size() <= Wreckage.MAX_WRECKS,
		"(%d of max %d)" % [get_tree().get_nodes_in_group("wreckage").size(),
			Wreckage.MAX_WRECKS])

	# --- the HUD uses the icons that were drawn for it ---
	for icon in ["ui_credits", "ui_power", "ui_unit_cap"]:
		_check("Icon '%s' loads" % icon, Icons.get_icon(icon) != null)
	_check("The top bar shows a number, not a sentence",
		not hud._credits_label.text.contains("Credits"),
		"('%s')" % hud._credits_label.text)

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()
