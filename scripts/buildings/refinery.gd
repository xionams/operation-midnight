extends BuildingBase
class_name Refinery

## Converts harvested cargo into credits and acts as the harvester
## drop-off point. Also produces Supply Harvesters (the closest
## equivalent to a "vehicle factory" in this milestone) so the HUD's
## Build Harvester button has somewhere to spawn from.

@export var harvester_scene: PackedScene
@export var harvester_cost: int = 1200

func _ready() -> void:
	super._ready()
	if is_player_faction:
		GameState.register_refinery(self)

func _on_died() -> void:
	if is_player_faction:
		GameState.unregister_refinery(self)
	super._on_died()

func receive_resources(amount: float) -> void:
	if amount <= 0.0:
		return
	GameState.add_credits(int(round(amount)))

func produce_harvester() -> Node:
	if harvester_scene == null:
		return null
	if not GameState.try_spend(harvester_cost):
		return null
	var harvester = harvester_scene.instantiate()
	get_parent().add_child(harvester)
	var spawn_offset := Vector3(stats.body_size.x / 2.0 + 3.0, 0, 0) if stats else Vector3(6, 0, 0)
	harvester.global_position = global_position + spawn_offset
	EventBus.unit_spawned.emit(harvester)
	return harvester
