extends Node
class_name ProductionQueue

## Reusable timed unit production for any building that builds units.
## Credits are taken when an order is queued, not when it completes, so
## a player cannot queue more than they can afford; cancelling refunds.
## Attach one to a building and call enqueue().

signal order_queued(stats: UnitStats)
signal order_completed(unit: Node)
signal queue_changed()

const MAX_QUEUED: int = 5

@export var spawn_offset: Vector3 = Vector3(6, 0, 0)

var _orders: Array[UnitStats] = []
var _scenes: Array[PackedScene] = []
var _remaining: float = 0.0

func queue_length() -> int:
	return _orders.size()

func is_full() -> bool:
	return _orders.size() >= MAX_QUEUED

func current_stats() -> UnitStats:
	return _orders[0] if not _orders.is_empty() else null

func progress() -> float:
	if _orders.is_empty():
		return 0.0
	var total: float = _orders[0].build_time
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - _remaining / total, 0.0, 1.0)

func enqueue(stats: UnitStats, scene: PackedScene) -> bool:
	if stats == null or scene == null or is_full():
		return false
	## Charge whoever owns this building, not always the player.
	var owner_is_player: bool = get_parent().is_player_faction
	if not GameState.try_spend_for(owner_is_player, stats.cost):
		return false
	_orders.append(stats)
	_scenes.append(scene)
	if _orders.size() == 1:
		_remaining = stats.build_time
	order_queued.emit(stats)
	queue_changed.emit()
	return true

func cancel_last() -> bool:
	if _orders.is_empty():
		return false
	var index: int = _orders.size() - 1
	GameState.add_credits_for(get_parent().is_player_faction, _orders[index].cost)
	_orders.remove_at(index)
	_scenes.remove_at(index)
	if _orders.is_empty():
		_remaining = 0.0
	elif index == 0:
		_remaining = _orders[0].build_time
	queue_changed.emit()
	return true

## Sabotage: everything queued is lost and nothing is refunded. Distinct
## from cancel_last(), which is the owner changing their mind.
func clear_without_refund() -> int:
	var lost: int = _orders.size()
	_orders.clear()
	_scenes.clear()
	_remaining = 0.0
	if lost > 0:
		queue_changed.emit()
	return lost

func _process(delta: float) -> void:
	if _orders.is_empty():
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	_complete_front()

func _complete_front() -> void:
	var stats: UnitStats = _orders.pop_front()
	var scene: PackedScene = _scenes.pop_front()
	if not _orders.is_empty():
		_remaining = _orders[0].build_time
	else:
		_remaining = 0.0

	var building := get_parent()
	var unit = scene.instantiate()
	unit.stats = stats
	unit.is_player_faction = building.is_player_faction
	building.get_parent().add_child(unit)
	unit.global_position = building.global_position + spawn_offset

	EventBus.unit_spawned.emit(unit)
	order_completed.emit(unit)
	queue_changed.emit()
