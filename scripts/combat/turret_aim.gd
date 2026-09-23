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

var _turret: Node3D = null
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
	host.add_child(aim)
	return aim

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
