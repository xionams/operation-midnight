extends EnterBuildingAbility
class_name CaptureAbility

## Engineer logic: walk into an enemy structure and it changes hands,
## intact. Capturing a Refinery or War Factory hands over its production
## outright, which is why an unescorted Engineer is worth killing and a
## successful one can swing a match.

func _apply(building: Node3D) -> bool:
	var target_building := building as BuildingBase
	if target_building == null or _unit == null:
		return false
	if target_building.is_player_faction == _unit.is_player_faction:
		return false
	target_building.set_faction(_unit.is_player_faction)
	return true
