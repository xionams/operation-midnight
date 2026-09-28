extends BuildingBase
class_name CommandHQ

## Win-condition anchor. Destroying either side's HQ ends the match —
## handled centrally in GameState so both HUD and any future systems
## (score, replays) react to a single signal instead of polling HP.

func _on_died() -> void:
	GameState.report_hq_destroyed(get_faction(), self)
	super._on_died()

## Selling the last headquarters loses the match, exactly as losing it to
## enemy fire does.
##
## sell() does not run through _on_died, so a sold HQ used to disappear
## without ever reporting the loss. The match carried on with no defeat
## condition, no build radius and nothing to rebuild from - not a defeat,
## just an unwinnable board left running. Selling a SPARE headquarters is
## still perfectly safe; GameState only ends the match when the last one
## goes.
func sell() -> void:
	if not is_player_faction:
		return
	var faction: GameState.Faction = get_faction()
	super.sell()
	GameState.report_hq_destroyed(faction, self)
