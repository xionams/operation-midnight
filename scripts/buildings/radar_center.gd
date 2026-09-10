extends BuildingBase
class_name RadarCenter

## Unlocks the upper tech tier and improves the minimap. Radar is the
## first structure whose value is information rather than force, and the
## first thing the player loses to a brown-out.

func is_online() -> bool:
	return not GameState.is_low_power(is_player_faction)

static func player_has_radar(tree: SceneTree) -> bool:
	for building in tree.get_nodes_in_group("player_buildings"):
		if building is RadarCenter and (building as RadarCenter).is_online():
			return true
	return false
