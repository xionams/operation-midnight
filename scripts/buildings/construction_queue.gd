extends Node
class_name ConstructionQueue

## One active structure order per side, the classic C&C model: the
## building is paid for and timed first, and only when the timer
## completes does it become available to place on the map.
##
## Keeping construction here rather than on a half-built structure means
## the map never contains a building that does not work yet, and the
## player cannot use an unfinished shell to extend their build radius.
##
## Low power halves the rate, which is what gives Power Plants strategic
## weight beyond a number on the HUD.

signal order_started(stats: BuildingStats)
signal order_progress(stats: BuildingStats, fraction: float)
signal order_ready(stats: BuildingStats)
signal order_cancelled()

const LOW_POWER_SPEED: float = 0.5
const CANCEL_REFUND: float = 0.75

@export var is_player: bool = true

var _stats: BuildingStats = null
var _remaining: float = 0.0
var _ready_to_place: bool = false

func current() -> BuildingStats:
	return _stats

func is_busy() -> bool:
	return _stats != null

func is_ready() -> bool:
	return _ready_to_place

func progress() -> float:
	if _stats == null or _stats.build_time <= 0.0:
		return 1.0
	return clampf(1.0 - _remaining / _stats.build_time, 0.0, 1.0)

func remaining_seconds() -> float:
	return maxf(_remaining, 0.0)

## Charges immediately, so the credits are committed the moment the order
## is placed rather than on completion.
func start(stats: BuildingStats) -> bool:
	if stats == null or is_busy():
		return false
	if not TechTree.is_available(stats, is_player):
		return false
	if not GameState.try_spend_for(is_player, stats.cost):
		return false
	_stats = stats
	_remaining = stats.build_time
	_ready_to_place = stats.build_time <= 0.0
	order_started.emit(stats)
	if _ready_to_place:
		order_ready.emit(stats)
	return true

func cancel() -> void:
	if _stats == null:
		return
	GameState.add_credits_for(is_player, int(round(_stats.cost * CANCEL_REFUND)))
	_clear()
	order_cancelled.emit()

## Called once the structure has actually been placed on the map.
func consume() -> void:
	_clear()

func _clear() -> void:
	_stats = null
	_remaining = 0.0
	_ready_to_place = false

func _process(delta: float) -> void:
	if _stats == null or _ready_to_place:
		return
	var rate: float = LOW_POWER_SPEED if GameState.is_low_power(is_player) else 1.0
	_remaining -= delta * rate
	order_progress.emit(_stats, progress())
	if _remaining > 0.0:
		return
	_remaining = 0.0
	_ready_to_place = true
	order_ready.emit(_stats)
