class_name TurretAim
extends Node

## Turns a model's `Turret` node toward whatever its owner is shooting.
##
## The greyboxes were built with the turret as a separate node pivoting
## on Y precisely so this could exist later, and until now nothing read
## it: tanks fired from a barrel welded facing forward, which is the kind
## of detail that reads as "unfinished" long before anyone can say why.
##
## Rotation only, on one axis, at a fixed rate. No animation system, no
## per-unit configuration - a turret either exists in the model or it
## does not.

## Radians per second. Slow enough to see, fast enough that a tank is not
## still turning when the shot lands.
const TRAVERSE: float = 3.4

## Recoil. The gun snaps back over RECOIL_KICK seconds and is pushed out
## again more slowly by its recuperator, which is what the eye reads as
## weight - a symmetric bounce reads as a spring.
const RECOIL_KICK: float = 0.05
const RECOIL_RETURN: float = 0.34

var _turret: Node3D = null
var _barrel: Node3D = null
var _barrel_rest: Transform3D = Transform3D.IDENTITY
## How far this particular gun recoils, from its own length: a howitzer
## should not kick the same distance as an autocannon.
var _recoil_travel: float = 0.0
var _recoil_t: float = 0.0
## The muzzle in barrel-local space, so flashes and shots start at the
## end of the gun rather than somewhere inside the hull.
var _muzzle_local: Vector3 = Vector3.ZERO
var _attacker: AttackerComponent = null
var _host: Node3D = null
## Where the turret points with nothing to shoot, relative to the hull.
var _rest: float = 0.0

## Attaches to a host if its model actually has a turret. Returns null
## when there is nothing to aim, so callers need no special case.
static func attach(host: Node3D, visual: Node) -> TurretAim:
	if host == null or visual == null:
		return null
	var turret := visual.find_child("Turret", true, false) as Node3D
	if turret == null:
		return null
	var aim := TurretAim.new()
	aim.name = "TurretAim"
	aim._turret = turret
	aim._host = host
	aim._rest = turret.rotation.y
	## The gun is exported as a sibling of the turret (the exporter
	## writes a flat list), so it is hung onto the turret here - a barrel
	## that did not follow its own turret would be worse than none.
	var barrel := visual.find_child("Barrel", true, false) as Node3D
	if barrel != null:
		barrel.reparent(turret, true)
		aim._barrel = barrel
		aim._barrel_rest = barrel.transform
		aim._measure_gun()
	host.add_child(aim)
	return aim

## Read the gun's own reach out of its geometry, so the muzzle point and
## the recoil distance come from the model rather than a table that has
## to be kept in step with it.
func _measure_gun() -> void:
	var reach: float = 0.0
	for node in _mesh_nodes(_barrel):
		var box: AABB = node.get_aabb()
		var local_end: Vector3 = node.transform * Vector3(0.0, box.position.y + box.size.y * 0.5,
			box.position.z)
		reach = minf(reach, local_end.z)
	_muzzle_local = Vector3(0.0, 0.0, reach)
	## A short autocannon barely moves; a long gun visibly does.
	_recoil_travel = clampf(absf(reach) * 0.11, 0.05, 0.42)

func _mesh_nodes(root: Node) -> Array:
	var found: Array = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(_mesh_nodes(child))
	return found

## Where the shot leaves the gun, in world space. Falls back to a point
## above the hull for anything with no modelled barrel.
func muzzle_point() -> Vector3:
	if _barrel != null and is_instance_valid(_barrel):
		return _barrel.global_transform * _muzzle_local
	return _host.global_position + Vector3.UP

## The gun just fired: kick it back.
func report_fired() -> void:
	_recoil_t = 1.0

func _ready() -> void:
	_attacker = _host.get_node_or_null("AttackerComponent")

func _physics_process(delta: float) -> void:
	if _turret == null or not is_instance_valid(_turret):
		return

	var wanted: float = _rest
	if _attacker != null and is_instance_valid(_attacker.target):
		var to_target: Vector3 = _attacker.target.global_position - _host.global_position
		if to_target.length_squared() > 0.01:
			## The turret is a child of the hull, so it aims in the
			## hull's frame - otherwise a vehicle turning would drag its
			## aim around with it.
			wanted = atan2(-to_target.x, -to_target.z) - _host.global_rotation.y

	_turret.rotation.y = _step_toward(_turret.rotation.y, wanted, TRAVERSE * delta)
	_tick_recoil(delta)

func _tick_recoil(delta: float) -> void:
	if _barrel == null or not is_instance_valid(_barrel):
		return
	if _recoil_t <= 0.0:
		if _barrel.transform != _barrel_rest:
			_barrel.transform = _barrel_rest
		return
	## Back fast, out slowly.
	_recoil_t = maxf(0.0, _recoil_t - delta / RECOIL_RETURN)
	var eased: float = _recoil_t * _recoil_t
	_barrel.transform = _barrel_rest
	_barrel.position += Vector3(0.0, 0.0, _recoil_travel * eased)

## Shortest way round, so a turret never takes the long way to a target
## that is a few degrees the other side of straight behind.
func _step_toward(from: float, to: float, amount: float) -> float:
	var difference: float = wrapf(to - from, -PI, PI)
	if absf(difference) <= amount:
		return to
	return from + signf(difference) * amount

## True when the turret is pointing close enough to fire convincingly.
func is_on_target() -> bool:
	if _turret == null or _attacker == null or not is_instance_valid(_attacker.target):
		return false
	var to_target: Vector3 = _attacker.target.global_position - _host.global_position
	var wanted: float = atan2(-to_target.x, -to_target.z) - _host.global_rotation.y
	return absf(wrapf(wanted - _turret.rotation.y, -PI, PI)) < 0.25
