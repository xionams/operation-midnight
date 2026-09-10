extends BuildingBase
class_name PowerPlant

## Power generator. Generation amount and cost are data-driven via
## BuildingStats; the only behavior of its own is going dark when a Spy
## gets inside, which is what makes it worth guarding.

var _blackout_remaining: float = 0.0
var _offline: bool = false

func is_offline() -> bool:
	return _offline

## Take the plant's generation out of the grid for a while. The building
## survives - it just stops contributing, so the owner feels it as a
## power shortage rather than a loss.
func blackout(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_blackout_remaining = maxf(_blackout_remaining, seconds)
	if _offline:
		return
	_offline = true
	if is_player_faction and stats != null and stats.power_generation > 0:
		GameState.unregister_power_generation(stats.power_generation)

func _process(delta: float) -> void:
	super._process(delta)
	if not _offline:
		return
	_blackout_remaining -= delta
	if _blackout_remaining > 0.0:
		return
	_offline = false
	_blackout_remaining = 0.0
	if is_player_faction and stats != null and stats.power_generation > 0:
		GameState.register_power_generation(stats.power_generation)

## A plant that is dark must not double-unregister when it dies or is
## captured; BuildingBase asks before touching the grid.
func _contributes_power() -> bool:
	return not _offline
