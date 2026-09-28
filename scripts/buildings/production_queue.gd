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
const CANCEL_REFUND: float = 0.75
const LOW_POWER_SPEED: float = 0.5

@export var spawn_offset: Vector3 = Vector3(6, 0, 0)

var _orders: Array[UnitStats] = []
var _scenes: Array[PackedScene] = []
var _remaining: float = 0.0

func queue_length() -> int:
	return _orders.size()

## Orders already paid for still occupy population, or a player could
## queue an unlimited army and watch it all arrive past the cap at once.
## Read-only view of what is queued, for economic accounting.
func orders() -> Array:
	return _orders.duplicate()

func queued_population() -> int:
	var total: int = 0
	for stats in _orders:
		total += stats.population
	return total

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

## Why `stats` cannot be queued here right now, or "" if it can. The
## sidebar reports this instead of a tile that silently does nothing.
func enqueue_error(stats: UnitStats) -> String:
	if stats == null:
		return "Nothing to build"
	var owner_is_player: bool = get_parent().is_player_faction
	if is_full():
		return "%s queue is full (%d)" % [get_parent().stats.display_name, MAX_QUEUED]
	if not TechTree.is_available(stats, owner_is_player):
		return "%s is not available yet" % stats.display_name
	if not TechTree.has_population_for(stats, owner_is_player):
		return "Unit cap reached (%d/%d) - build more structures" % [
			TechTree.population_used(owner_is_player), TechTree.population_cap(owner_is_player)]
	if GameState.balance_of(owner_is_player) < stats.cost:
		return "Insufficient funds for %s" % stats.display_name
	return ""

func enqueue(stats: UnitStats, scene: PackedScene) -> bool:
	if stats == null or scene == null or is_full():
		return false
	## Charge whoever owns this building, not always the player.
	var owner_is_player: bool = get_parent().is_player_faction
	if not TechTree.is_available(stats, owner_is_player):
		return false
	if not TechTree.has_population_for(stats, owner_is_player):
		return false
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
	## Fixed partial refund; tracking how far along an order was is
	## complexity the slice does not need.
	GameState.add_credits_for(get_parent().is_player_faction, int(round(_orders[index].cost * CANCEL_REFUND)))
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
	var rate: float = LOW_POWER_SPEED if GameState.is_low_power(get_parent().is_player_faction) else 1.0
	rate *= _throughput()
	_remaining -= delta * rate
	if _remaining > 0.0:
		return
	_complete_front()

## Extra production buildings of the same kind speed each other up, so a
## second Barracks is a real economic choice against spending the same
## money on units now.
func _throughput() -> float:
	var owner_building := get_parent()
	if owner_building.stats == null:
		return 1.0
	var group: String = "player_buildings" if owner_building.is_player_faction else "enemy_buildings"
	var same: int = 0
	for building in get_tree().get_nodes_in_group(group):
		if is_instance_valid(building) and building.stats != null \
			and building.stats.display_name == owner_building.stats.display_name:
			same += 1
	return 1.0 + 0.35 * float(maxi(0, same - 1))

## Land units roll out of the door (spawn_offset). A ship is launched
## onto open water beside the yard: the first spot round the building that
## is water with room to float, so it never appears on the beach.
func _spawn_point(building: Node3D, stats: UnitStats) -> Vector3:
	var default: Vector3 = building.global_position + spawn_offset
	if stats == null or stats.movement_domain != PlacementDomain.Domain.WATER:
		return default
	var half: Vector2 = building.stats.footprint * 0.5 if building.get("stats") != null else Vector2(5, 5)
	var reach: float = maxf(half.x, half.y) + 4.0
	var best: Vector3 = Water.nearest_water(default)
	var best_room: float = -1.0
	## Out of the berth mouth when the model has been turned to the sea
	## (BuildingBase._face_open_water): the ship visibly leaves the yard.
	var visual = building.get("_visual_root")
	if visual is Node3D:
		var a: float = (visual as Node3D).rotation.y
		var mouth: Vector3 = building.global_position + Vector3(cos(a), 0.0, -sin(a)) * reach
		if Water.is_water(mouth.x, mouth.z) and Water.distance_to_shore(mouth.x, mouth.z) > 2.0:
			mouth.y = Water.level
			return mouth
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		var p: Vector3 = building.global_position + Vector3(cos(a), 0.0, sin(a)) * reach
		if not Water.is_water(p.x, p.z):
			continue
		var room: float = Water.distance_to_shore(p.x, p.z)
		if room > best_room:
			best_room = room
			best = p
	best.y = Water.level
	return best

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
	unit.global_position = _spawn_point(building, stats)

	## Newly produced units walk to the building's rally point if one is
	## set, so a factory can feed a staging area without micromanagement.
	var rally = building.get("rally_point")
	if rally != null and rally != Vector3.ZERO and unit.has_method("issue_command"):
		## Scatter arrivals slightly, or every unit walks to one coordinate
		## and forms a pile at the rally point.
		var spread := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		unit.issue_command(CommandTypes.Type.MOVE, rally + spread)

	EventBus.unit_spawned.emit(unit)
	order_completed.emit(unit)
	queue_changed.emit()
