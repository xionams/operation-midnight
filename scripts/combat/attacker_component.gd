extends Node
class_name AttackerComponent

## Reusable "can attack things" behavior: acquires a target, moves into
## range, faces it, and fires via a Weapon child. Any unit that wants
## combat (tanks, future infantry/artillery/anti-air) attaches one of
## these instead of reimplementing targeting per unit script.

@export var weapon: Weapon
@export var reposition_threshold: float = 1.5

const SEARCH_TIMEOUT: float = 4.0

var target: Node3D = null

var _owner_unit: Node3D
var _last_chase_position: Vector3 = Vector3.INF
var _searching_last_known: bool = false
var _last_known_position: Vector3 = Vector3.ZERO
var _search_remaining: float = 0.0

## Advance on the target's last known position; if it is not there when we
## arrive, or we run out of patience, stop looking rather than hunting it
## across the map through fog.
func _tick_last_known_search(delta: float) -> void:
	_search_remaining -= delta
	var arrived: bool = _owner_unit.global_position.distance_to(_last_known_position) < 3.0
	if _search_remaining > 0.0 and not arrived:
		return
	_searching_last_known = false
	if _owner_unit.has_method("stop_moving"):
		_owner_unit.call("stop_moving")

func is_searching() -> bool:
	return _searching_last_known

func _ready() -> void:
	_owner_unit = get_parent() as Node3D

func set_target(new_target: Node) -> void:
	if not is_instance_valid(new_target):
		return
	var health: HealthComponent = new_target.get_node_or_null("HealthComponent")
	if health != null and health.is_dead():
		return
	## Refuse targets this weapon cannot meaningfully hurt, so a dog does
	## not chase a tank forever doing nothing.
	if weapon != null and weapon.stats != null and not weapon.can_damage(new_target):
		return
	## Cannot order an attack on something the player cannot see.
	if _owner_unit != null and _owner_unit.is_player_faction and FogHideable.is_hidden(new_target):
		return
	target = new_target as Node3D
	_last_chase_position = Vector3.INF
	_searching_last_known = false

func clear_target() -> void:
	target = null
	_searching_last_known = false

func has_target() -> bool:
	return is_instance_valid(target)

func _physics_process(delta: float) -> void:
	if weapon == null or weapon.stats == null or _owner_unit == null:
		return

	if _searching_last_known:
		_tick_last_known_search(delta)
		return

	if not is_instance_valid(target):
		target = null
		return

	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	if health != null and health.is_dead():
		target = null
		return

	## The target walked into fog. The player does not get to track it -
	## the unit advances on where it last saw the target and gives up if
	## nothing is there.
	if _owner_unit.is_player_faction and FogHideable.is_hidden(target):
		## Capture where it was before dropping it - that position is the
		## entire point of the behaviour.
		var vanished_at: Vector3 = target.global_position
		target = null
		if not _owner_unit.has_method("move_to"):
			return
		_last_known_position = vanished_at
		_searching_last_known = true
		_search_remaining = SEARCH_TIMEOUT
		_owner_unit.call("move_to", _last_known_position)
		return

	var distance: float = _owner_unit.global_position.distance_to(target.global_position)

	## Defensive structures mount this same component but cannot move, so
	## every movement call is optional. A turret simply drops a target
	## that walks out of range instead of trying to chase it.
	var mobile: bool = _owner_unit.has_method("move_to")

	if distance > weapon.stats.attack_range:
		if not mobile:
			target = null
			return
		if _last_chase_position.distance_to(target.global_position) > reposition_threshold:
			_last_chase_position = target.global_position
			_owner_unit.call("move_to", target.global_position)
	else:
		if mobile:
			_owner_unit.call("stop_moving")
			_owner_unit.call("face_towards", target.global_position)
		if weapon.can_fire():
			var muzzle: Vector3 = _owner_unit.global_position + Vector3.UP
			weapon.fire_at(target, muzzle)
