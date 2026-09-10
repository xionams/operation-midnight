extends ProducerBuilding
class_name Refinery

## Converts harvested cargo into credits and acts as the harvester
## drop-off point. It also trains Harvesters, so a player who loses their
## whole harvest fleet can rebuild it from the refinery itself rather
## than being economically dead.

func _ready() -> void:
	super._ready()
	GameState.register_refinery(self, is_player_faction)

func _on_died() -> void:
	GameState.unregister_refinery(self, is_player_faction)
	super._on_died()

func _on_faction_changing() -> void:
	## Leaves whichever side's list it is currently on, before the flip.
	GameState.unregister_refinery(self, is_player_faction)

func _on_faction_changed() -> void:
	GameState.register_refinery(self, is_player_faction)

func receive_resources(amount: float) -> void:
	if amount <= 0.0:
		return
	GameState.add_credits_for(is_player_faction, int(round(amount)))
