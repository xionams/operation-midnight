extends Node
class_name EnterBuildingAbility

## Shared behavior for units whose job is to walk into a building and do
## something to it: Engineers capture, Spies infiltrate. The unit is
## consumed on use, which is what makes these units a real decision
## rather than a free action — you spend the unit to get the effect.

signal used(building: Node3D)
signal failed(reason: String)

@export var enter_distance: float = 5.0
@export var consumes_unit: bool = true

var target: Node3D = null

var _unit: UnitBase

func _ready() -> void:
	_unit = get_parent() as UnitBase

## Whether this ability is willing to act on the given node at all.
## Overridden per ability — an Engineer wants enemy buildings, a Spy the
## same, but neither wants its own.
func accepts(candidate: Node) -> bool:
	if not (candidate is BuildingBase) or _unit == null:
		return false
	return (candidate as BuildingBase).is_player_faction != _unit.is_player_faction

func order(building: Node3D) -> void:
	target = building
	if _unit != null:
		_unit.move_to(building.global_position)

func cancel() -> void:
	target = null

func _process(_delta: float) -> void:
	if target == null or _unit == null:
		return
	if not is_instance_valid(target):
		target = null
		return
	if _unit.global_position.distance_to(target.global_position) > enter_distance:
		return

	var building := target
	target = null
	if not _apply(building):
		failed.emit("no effect")
		return
	used.emit(building)
	if consumes_unit:
		_consume()

## Does the actual work. Returns false when the building turned out not
## to be a valid subject after all, so the unit is not wasted.
func _apply(_building: Node3D) -> bool:
	return false

func _consume() -> void:
	SelectionManager.notify_unit_removed(_unit)
	_unit.queue_free()
