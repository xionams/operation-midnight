extends EnterBuildingAbility
class_name InfiltrateAbility

## Spy logic: the effect depends on what was infiltrated, so picking the
## right target matters more than simply getting in.
##
##   Refinery     loot credits
##   War Factory / Barracks   sabotage production - queue cleared, no refund
##   Power Plant  knock the plant offline for a while
##   anything else  no useful effect, and the Spy is not spent
##
## Unlike the Engineer the building is not captured; it keeps working for
## its owner, which makes the Spy a raid rather than a land grab.
##
## Only the player has a credit balance in this milestone, so looting an
## enemy Refinery pays the player a flat bounty, while an enemy Spy
## hitting a player Refinery takes a share of the player's balance.

signal infiltrated(building: Node3D, effect: String)

@export var refinery_loot: int = 1000
@export var credit_steal_fraction: float = 0.4
@export var blackout_seconds: float = 20.0

func _apply(building: Node3D) -> bool:
	var target_building := building as BuildingBase
	if target_building == null or _unit == null:
		return false

	var effect: String = ""

	if target_building is Refinery:
		if _unit.is_player_faction:
			GameState.add_credits(refinery_loot)
			effect = "looted %d credits" % refinery_loot
		else:
			var lost: int = GameState.take_credits_fraction(credit_steal_fraction)
			effect = "enemy stole %d credits" % lost
	elif target_building.has_method("sabotage_production"):
		var cleared: int = target_building.sabotage_production()
		effect = "sabotaged %d queued order(s)" % cleared
	elif target_building is PowerPlant:
		target_building.blackout(blackout_seconds)
		effect = "blacked out for %ds" % int(blackout_seconds)
	else:
		return false

	infiltrated.emit(building, effect)
	EventBus.building_infiltrated.emit(building, effect)
	return true
