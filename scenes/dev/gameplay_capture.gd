extends Node

## Records a fight for video rather than for measurement.
##
## Driven through the real RTS camera - the player's own view, set by
## pan_target and zoom_distance and smoothed by the camera's own follow
## - so what lands on the recording is what someone playing would see,
## not a cinematic rig the game does not have.
##
##     godot --path . scenes/dev/gameplay_capture.tscn \
##           --write-movie out.avi --fixed-fps 30
##
## Movie mode runs on a fixed timestep, so every _wait below is in
## recorded seconds regardless of how slowly the frames actually render.

const TANK := ["res://scenes/units/main_battle_tank.tscn",
	"res://config/units/main_battle_tank.tres"]
const ASSAULT := ["res://scenes/units/assault_vehicle.tscn",
	"res://config/units/assault_vehicle.tres"]
const ARTILLERY := ["res://scenes/units/artillery_vehicle.tscn",
	"res://config/units/artillery_vehicle.tres"]
const RIFLE := ["res://scenes/units/rifle_soldier.tscn",
	"res://config/units/rifle_soldier.tres"]
const AT := ["res://scenes/units/at_squad.tscn",
	"res://config/units/at_squad.tres"]
const DOG := ["res://scenes/units/attack_dog.tscn",
	"res://config/units/attack_dog.tres"]

var _main: Node3D
var _cam: Node3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame

	## The director would rebuild and re-task things mid-shot; the fog
	## would hide the half of the fight the camera is pointed at.
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	## Switching the fog OFF only stops it recomputing - the terrain
	## shader still reads the last visibility texture, so the battlefield
	## stays black wherever nobody has been. Stamp the whole map visible
	## once, THEN freeze it.
	FogOfWar.enabled = false
	FogOfWar.reveal_area(Vector3.ZERO, FogOfWar.get_map_size())
	GameState.add_credits(90000)
	_cam = get_tree().get_first_node_in_group("rts_camera")
	for i in 20:
		await get_tree().physics_frame

	var home: Vector3 = _main.map.player_base
	var field: Vector3 = home + Vector3(34, 0, -26)

	await _beat_establish(home)
	await _beat_armour(field)
	await _beat_infantry(field)
	await _beat_finale(field)

	print("CAPTURE| DONE")
	get_tree().quit()

# ---------------------------------------------------------------- beats

## The base at rest, so the fight that follows has something to be a
## departure from.
func _beat_establish(home: Vector3) -> void:
	_look(home, 30.0, true)
	_spawn(RIFLE, true, home + Vector3(-6, 0, 5))
	_spawn(RIFLE, true, home + Vector3(-4, 0, 7))
	_spawn(DOG, true, home + Vector3(-8, 0, 6))
	var patrol := _spawn(ASSAULT, true, home + Vector3(10, 0, 8))
	if patrol and patrol.has_method("move_to"):
		patrol.move_to(home + Vector3(-10, 0, -6))
	await _wait(1.0)
	_look(home + Vector3(6, 0, -4), 26.0)
	await _wait(4.5)

## Two armoured lines meeting. The shells, the tracers and the first
## wrecks all come from the combat system actually running.
func _beat_armour(field: Vector3) -> void:
	var ours: Array = []
	var theirs: Array = []
	for i in 8:
		ours.append(_spawn(TANK if i % 2 == 0 else ASSAULT, true,
			field + Vector3(-10 + i * 1.1, 0, 8 - i * 0.9)))
		theirs.append(_spawn(TANK if i % 2 else ASSAULT, false,
			field + Vector3(9 - i * 1.0, 0, -7 + i * 0.9)))
	for u in ours + theirs:
		_arm(u)
	_look(field, 28.0, true)
	await _wait(0.6)
	for u in ours:
		if is_instance_valid(u) and u.has_method("move_to"):
			u.move_to(field + Vector3(_rng.randf_range(1, 5), 0,
				_rng.randf_range(-4, 0)))
	for u in theirs:
		if is_instance_valid(u) and u.has_method("move_to"):
			u.move_to(field + Vector3(_rng.randf_range(-5, -1), 0,
				_rng.randf_range(0, 4)))
	_look(field + Vector3(0, 0, 2), 22.0)
	await _wait(5.0)
	## Artillery walking onto the line, which is where the big bangs are.
	for i in 4:
		_shell(field + Vector3(_rng.randf_range(-7, 7), 0,
			_rng.randf_range(-6, 6)), 70.0)
		await _wait(0.9)
	_look(field + Vector3(-3, 0, 1), 18.0)
	await _wait(3.0)

## Infantry going in over the ground the armour just fought on, so the
## skinned rig is on camera at the zoom a player actually uses.
func _beat_infantry(field: Vector3) -> void:
	var squad: Array = []
	for i in 7:
		squad.append(_spawn(RIFLE if i % 3 else AT, true,
			field + Vector3(-11 + i * 1.5, 0, 9)))
	for i in 5:
		_arm(_spawn(RIFLE, false, field + Vector3(1 + i * 1.4, 0, -5)))
	for u in squad:
		_arm(u)
		if is_instance_valid(u) and u.has_method("move_to"):
			u.move_to(field + Vector3(1 + _rng.randf_range(-2, 2), 0,
				-3 + _rng.randf_range(-2, 2)))
	_look(field + Vector3(-5, 0, 4), 17.0, false)
	await _wait(4.0)
	_look(field + Vector3(0, 0, 0), 15.5)
	await _wait(4.0)
	for i in 3:
		_shell(field + Vector3(_rng.randf_range(-4, 5), 0,
			_rng.randf_range(-4, 3)), 45.0)
		await _wait(1.1)

## An enemy outpost comes down: the largest explosion the game has, plus
## the fires and the wreck field left behind.
func _beat_finale(field: Vector3) -> void:
	var outpost = _main._spawn_building(
		load("res://scenes/buildings/barracks.tscn"),
		load("res://config/buildings/barracks.tres"), false,
		field + Vector3(9, 0, -12))
	await _wait(0.4)
	_look(field + Vector3(8, 0, -10), 20.0)
	await _wait(2.2)
	## Hurt it first so it is visibly burning before it goes.
	var hp = outpost.get_node_or_null("HealthComponent") if outpost else null
	if hp != null:
		hp.take_damage(hp.max_health * 0.72)
	await _wait(2.6)
	_shell(field + Vector3(8, 0, -11), 30.0)
	await _wait(0.5)
	if hp != null:
		hp.take_damage(hp.max_health)
	await _wait(2.0)
	_look(field + Vector3(2, 0, -4), 27.0)
	await _wait(4.0)

# -------------------------------------------------------------- helpers

## Where the player's camera is going. The camera smooths its own way
## there, so this reads as a pan rather than a cut.
func _look(at: Vector3, zoom: float, immediate: bool = false) -> void:
	if _cam == null:
		return
	_cam.pan_target = at
	_cam.zoom_distance = zoom
	if immediate and _cam.has_method("snap"):
		_cam.snap()

## A shell landing: the blast, the shake, and real damage to whatever is
## standing near it, so the wrecks that follow are earned.
func _shell(at: Vector3, damage: float) -> void:
	var ground := Vector3(at.x, Terrain.height_at(at.x, at.z), at.z)
	VFX.explosion_large(_main, ground)
	if _cam != null and _cam.has_method("shake"):
		_cam.shake(0.9, ground)
	for group in ["player_units", "enemy_units"]:
		for u in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(u):
				continue
			var d: float = u.global_position.distance_to(ground)
			if d > 7.0:
				continue
			var hp = u.get_node_or_null("HealthComponent")
			if hp != null:
				hp.take_damage(damage * (1.0 - d / 7.0))

func _arm(unit) -> void:
	if is_instance_valid(unit):
		unit.stance = UnitBase.Stance.AGGRESSIVE

func _spawn(entry: Array, is_player: bool, at: Vector3) -> Node:
	return _main._spawn_unit(load(entry[0]), load(entry[1]), is_player, at)

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame
