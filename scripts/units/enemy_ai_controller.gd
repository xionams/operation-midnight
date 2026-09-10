extends Node
class_name EnemyAIController

## Minimal "defend a radius" AI. Attached only to enemy combat units
## (never to player units), so player vehicles never need faction
## checks baked into their own scripts. Scans periodically instead of
## every frame to stay cheap at higher unit counts.

@export var defend_radius: float = 22.0
@export var detection_radius: float = 16.0
@export var scan_interval: float = 0.5
@export var leash_multiplier: float = 1.6

var _home_position: Vector3
var _owner_unit: Node3D
var _timer: float = 0.0

func _ready() -> void:
	_owner_unit = get_parent() as Node3D
	if _owner_unit:
		_home_position = _owner_unit.global_position
	_timer = randf() * scan_interval

func _process(delta: float) -> void:
	if _owner_unit == null or not is_instance_valid(_owner_unit):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = scan_interval
	_scan()

func _scan() -> void:
	var attacker: AttackerComponent = _owner_unit.get_node_or_null("AttackerComponent")
	if attacker == null:
		return

	if attacker.has_target():
		if _owner_unit.global_position.distance_to(_home_position) > defend_radius * leash_multiplier:
			attacker.clear_target()
			_owner_unit.call("move_to", _home_position)
		return

	var nearest: Node = null
	var nearest_dist_sq: float = INF
	var candidates: Array = _owner_unit.get_tree().get_nodes_in_group("player_units")
	for unit in candidates:
		if not is_instance_valid(unit):
			continue
		if _home_position.distance_to(unit.global_position) > detection_radius:
			continue
		var dist_sq: float = _owner_unit.global_position.distance_squared_to(unit.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = unit

	if nearest:
		attacker.set_target(nearest)
	elif _owner_unit.global_position.distance_to(_home_position) > 1.0:
		_owner_unit.call("move_to", _home_position)
