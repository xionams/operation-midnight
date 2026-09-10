extends ProducerBuilding
class_name Barracks

## Infantry production. Everything it can train is declared by the units
## themselves (produced_by), so adding a squad type needs no change here.

const GROUP: String = "barracks"

func _ready() -> void:
	super._ready()
	if is_player_faction:
		add_to_group(GROUP)

func _on_faction_changing() -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)

func _on_faction_changed() -> void:
	if is_player_faction:
		add_to_group(GROUP)
