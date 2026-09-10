extends Node
class_name AttackerComponent

## Reusable "can attack things" behavior: acquires a target, moves into
## range, faces it, and fires via a Weapon child. Any unit that wants
## combat (tanks, future infantry/artillery/anti-air) attaches one of
## these instead of reimplementing targeting per unit script.

@export var weapon: Weapon
@export var reposition_threshold: float = 1.5

var target: Node3D = null

var _owner_unit: Node3D
var _last_chase_position: Vector3 = Vector3.INF

func _ready() -> void:
	_owner_unit = get_parent() as Node3D

func set_target(new_target: Node) -> void:
	if not is_instance_valid(new_target):
		return
	var health: HealthComponent = new_target.get_node_or_null("HealthComponent")
	if health != null and health.is_dead():
		return
	target = new_target as Node3D
	_last_chase_position = Vector3.INF

func clear_target() -> void:
	target = null

func has_target() -> bool:
	return is_instance_valid(target)

func _physics_process(_delta: float) -> void:
	if weapon == null or weapon.stats == null or _owner_unit == null:
		return
	if not is_instance_valid(target):
		target = null
		return

	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	if health != null and health.is_dead():
		target = null
		return

	var distance: float = _owner_unit.global_position.distance_to(target.global_position)

	if distance > weapon.stats.attack_range:
		if _last_chase_position.distance_to(target.global_position) > reposition_threshold:
			_last_chase_position = target.global_position
			_owner_unit.call("move_to", target.global_position)
	else:
		_owner_unit.call("stop_moving")
		_owner_unit.call("face_towards", target.global_position)
		if weapon.can_fire():
			var muzzle: Vector3 = _owner_unit.global_position + Vector3.UP
			weapon.fire_at(target, muzzle)
