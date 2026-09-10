extends BuildingBase
class_name CommandHQ

## Win-condition anchor. Destroying either side's HQ ends the match —
## handled centrally in GameState so both HUD and any future systems
## (score, replays) react to a single signal instead of polling HP.

func _on_died() -> void:
	GameState.report_hq_destroyed(get_faction())
	super._on_died()
