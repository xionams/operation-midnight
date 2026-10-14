extends Node

## An aircraft that actually flies.
##
## A1 established the constraint by crashing into it: a unit whose
## movement_domain is AIR but which still rides the ground mover aborts
## the engine, because its NavigationAgent3D steers it along the land
## mesh while the settle pass drags it to the terrain. So an aircraft
## gets no agent at all, flies straight, and holds altitude through the
## same settle pass that keeps ships on the water.

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var d = _main.get_node_or_null("AIDirector")
	if d: d.enabled = false
	FogOfWar.enabled = false
	for i in 20:
		await get_tree().physics_frame

	var base: Vector3 = _main.map.player_base
	var start := base + Vector3(14, 0, 14)
	var gunship = _spawn("res://config/units/gunship.tres", start)
	await _frames(20)

	_check("A gunship spawns and survives being alive",
		is_instance_valid(gunship))
	if not is_instance_valid(gunship):
		_finish()
		return
	_check("It is classified as airborne", gunship.is_airborne())
	_check("It is an air target for weapons",
		CombatTarget.domain_of(gunship) == CombatTarget.Domain.AIR)
	_check("It was given no navigation agent", gunship.nav_agent == null)

	## Altitude: held above the GROUND, not above sea level.
	var ground: float = Terrain.height_at(gunship.global_position.x,
		gunship.global_position.z)
	var altitude: float = gunship.global_position.y - ground
	_check("It holds station above the ground",
		absf(altitude - UnitBase.CRUISE_ALTITUDE) < 1.5,
		"%.2fm up" % altitude)

	# --- it flies, in a straight line, over whatever is underneath ---
	var destination := base + Vector3(-34, 0, -26)
	var before: Vector3 = gunship.global_position
	var start_gap: float = Vector2(destination.x - before.x,
		destination.z - before.z).length()
	gunship.move_to(destination)
	_check("Ordered to move, it reports that it is moving", gunship.is_moving())
	await _wait(9.0)
	var travelled: float = Vector2(before.x - gunship.global_position.x,
		before.z - gunship.global_position.z).length()
	_check("It actually travels", travelled > 12.0, "%.1fm" % travelled)
	var remaining: float = Vector2(
		destination.x - gunship.global_position.x,
		destination.z - gunship.global_position.z).length()
	## Progress, not an arbitrary distance: a helicopter with turn_speed
	## 3.2 arcs onto its heading, so how far it has got after nine seconds
	## depends on which way it happened to be pointing.
	_check("It closes on its destination", remaining < start_gap - 15.0,
		"%.1fm of %.1fm to go" % [remaining, start_gap])

	var cruise_ground: float = Terrain.height_at(gunship.global_position.x,
		gunship.global_position.z)
	_check("It is still at altitude mid-flight",
		absf(gunship.global_position.y - cruise_ground - UnitBase.CRUISE_ALTITUDE) < 2.0,
		"%.2fm up" % (gunship.global_position.y - cruise_ground))

	# --- and it stops ---
	await _wait(14.0)
	_check("It arrives and stops", not gunship.is_moving())

	# --- the counter rules hold on a real aircraft ---
	var soldier = _spawn("res://config/units/rifle_soldier.tres",
		gunship.global_position * Vector3(1, 0, 1) + Vector3(2, 0, 2))
	await _frames(10)
	var attacker: AttackerComponent = soldier.get_node_or_null("AttackerComponent")
	if attacker != null:
		soldier.stance = UnitBase.Stance.AGGRESSIVE
		attacker.set_target(gunship, true)
		await _frames(6)
		_check("A rifleman standing underneath it still cannot shoot it",
			not attacker.has_target())

	_finish()

func _finish() -> void:
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

func _spawn(path: String, at: Vector3) -> Node:
	var stats: UnitStats = load(path)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = true
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(at.x, Terrain.height_at(at.x, at.z) + 1.0, at.z)
	return u
