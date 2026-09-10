extends Node
class_name DetectorAbility

## Attack Dog logic: strips the disguise off any enemy Spy that comes
## close. This is the counter that stops Spies being an unanswerable
## opening - a defender who keeps dogs at home is safe, one who does not
## loses a Refinery to a unit they never shot at.

signal spy_revealed(spy: Node)

@export var detection_radius: float = 14.0
@export var scan_interval: float = 0.4

var _unit: UnitBase
var _timer: float = 0.0

func _ready() -> void:
	_unit = get_parent() as UnitBase
	_timer = randf() * scan_interval

func _process(delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = scan_interval
	_scan()

func _scan() -> void:
	var enemy_group: String = "enemy_units" if _unit.is_player_faction else "player_units"
	for candidate in _unit.get_tree().get_nodes_in_group(enemy_group):
		if not is_instance_valid(candidate):
			continue
		var disguise: DisguiseAbility = candidate.get_node_or_null("DisguiseAbility")
		if disguise == null or not disguise.is_disguised():
			continue
		if _unit.global_position.distance_to(candidate.global_position) > detection_radius:
			continue
		disguise.reveal()
		spy_revealed.emit(candidate)
