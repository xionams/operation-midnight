extends ProducerBuilding
class_name WarFactory

## Vehicle production. This is the building that turns the match from
## "fight with what you started with" into an actual RTS.

const GROUP: String = "war_factories"

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
