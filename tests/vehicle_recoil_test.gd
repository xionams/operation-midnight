extends Node

## A gun that fires should move, and a shot should leave the end of it.
##
## Turrets already aimed, but the barrel was welded into the turret mesh
## so nothing recoiled, and every shot - flash, tracer, the lot - was
## spawned at the hull centre plus one metre, which on a tank with a 3m
## gun meant muzzle flashes blooming out of the middle of the chassis.

const TANK := preload("res://config/units/main_battle_tank.tres")
const ASSAULT := preload("res://config/units/assault_vehicle.tres")
const ARTY := preload("res://config/units/artillery_vehicle.tres")
const SOLDIER := preload("res://config/units/rifle_soldier.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _spawn(stats, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	return u

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

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
	FogOfWar.enabled = false
	await _frames(6)

	var base: Vector3 = _main.map.player_base
	for entry in [[TANK, "Main tank"], [ASSAULT, "Assault"], [ARTY, "Artillery"]]:
		var unit = _spawn(entry[0], base + Vector3(12, 0, 8))
		await _frames(6)
		var aim = unit.get_node_or_null("TurretAim")
		_check("%s has an aiming turret" % entry[1], aim != null)
		if aim == null:
			unit.queue_free()
			continue
		_check("%s has a separate barrel" % entry[1], aim._barrel != null)
		if aim._barrel == null:
			unit.queue_free()
			continue

		## The barrel must be ON the turret, or it stays pointing forward
		## while the turret tracks a target.
		_check("%s barrel rides the turret" % entry[1],
			aim._barrel.get_parent() == aim._turret)

		## The muzzle is at the end of the gun, out in front of the hull.
		var muzzle: Vector3 = unit.muzzle_position()
		var reach: float = Vector2(muzzle.x - unit.global_position.x,
			muzzle.z - unit.global_position.z).length()
		_check("%s fires from the end of its gun" % entry[1], reach > 1.5,
			"%.2fm from the hull centre" % reach)

		## Turn the turret; the muzzle must follow it round.
		aim._turret.rotation.y = PI * 0.5
		await get_tree().process_frame
		var turned: Vector3 = unit.muzzle_position()
		_check("%s muzzle follows the turret round" % entry[1],
			turned.distance_to(muzzle) > 1.0, "%.2fm" % turned.distance_to(muzzle))
		aim._turret.rotation.y = 0.0
		await _frames(2)

		## Recoil: back on firing, out again afterwards.
		var rest_z: float = aim._barrel.position.z
		unit.notify_weapon_fired()
		await get_tree().physics_frame
		await get_tree().physics_frame
		var kicked: float = aim._barrel.position.z
		_check("%s gun recoils when it fires" % entry[1], kicked > rest_z + 0.02,
			"%.3f -> %.3f" % [rest_z, kicked])
		await _frames(45)
		_check("%s gun returns to battery" % entry[1],
			absf(aim._barrel.position.z - rest_z) < 0.01,
			"%.3f" % aim._barrel.position.z)
		unit.queue_free()
		await _frames(2)

	## A longer gun should recoil further than a short one.
	var tank = _spawn(TANK, base + Vector3(12, 0, 8))
	var ifv = _spawn(ASSAULT, base + Vector3(16, 0, 8))
	await _frames(6)
	var tank_aim = tank.get_node_or_null("TurretAim")
	var ifv_aim = ifv.get_node_or_null("TurretAim")
	if tank_aim != null and ifv_aim != null:
		_check("A tank gun recoils further than an autocannon",
			tank_aim._recoil_travel > ifv_aim._recoil_travel,
			"%.2fm vs %.2fm" % [tank_aim._recoil_travel, ifv_aim._recoil_travel])

	## Infantry have no turret and must not break on any of this.
	var soldier = _spawn(SOLDIER, base + Vector3(8, 0, 8))
	await _frames(6)
	_check("Infantry have no turret to aim", soldier.get_node_or_null("TurretAim") == null)
	var soldier_muzzle: Vector3 = soldier.muzzle_position()
	_check("Infantry still report a muzzle position",
		soldier_muzzle.distance_to(soldier.global_position) < 2.0,
		"%s" % soldier_muzzle)
	soldier.notify_weapon_fired()
	await _frames(2)
	_check("Firing an unturreted unit is harmless", is_instance_valid(soldier))

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()
