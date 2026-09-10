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
## Capture is not instantaneous: the engineer stands there for a few
## seconds, which gives a defender a window to shoot it off the door.
@export var channel_time: float = 3.0

var target: Node3D = null
var _channel_remaining: float = 0.0

var _unit: UnitBase

func _ready() -> void:
	_unit = get_parent() as UnitBase

## Whether this ability is willing to act on the given node at all.
## Overridden per ability — an Engineer wants enemy buildings, a Spy the
## same, but neither wants its own.
func accepts(candidate: Node) -> bool:
	if not (candidate is BuildingBase) or _unit == null:
		return false
	var building := candidate as BuildingBase
	## Neutral structures are fair game for anyone; owned ones only for
	## the other side.
	if building.is_neutral:
		return true
	return building.is_player_faction != _unit.is_player_faction

func order(building: Node3D) -> void:
	target = building
	_channel_remaining = channel_time
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
		_channel_remaining = channel_time
		return

	## Standing at the door: run the channel down before it takes effect.
	_channel_remaining -= _delta
	if _channel_remaining > 0.0:
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
