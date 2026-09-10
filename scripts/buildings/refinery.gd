extends BuildingBase
class_name Refinery

## Converts harvested cargo into credits and acts as the harvester
## drop-off point. Also produces Supply Harvesters (the closest
## equivalent to a "vehicle factory" in this milestone) so the HUD's
## Build Harvester button has somewhere to spawn from.

@export var harvester_scene: PackedScene
@export var harvester_stats: UnitStats

var queue: ProductionQueue

func _ready() -> void:
	super._ready()
	queue = ProductionQueue.new()
	queue.name = "ProductionQueue"
	queue.spawn_offset = Vector3(stats.body_size.x / 2.0 + 3.0, 0, 0) if stats else Vector3(6, 0, 0)
	add_child(queue)
	if is_player_faction:
		GameState.register_refinery(self)

func _on_died() -> void:
	if is_player_faction:
		GameState.unregister_refinery(self)
	super._on_died()

func _on_faction_changing() -> void:
	if is_player_faction:
		GameState.unregister_refinery(self)

func _on_faction_changed() -> void:
	if is_player_faction:
		GameState.register_refinery(self)

## Spy target: wipe whatever is being built, without refunding it.
func sabotage_production() -> int:
	var cleared: int = queue.queue_length()
	queue.clear_without_refund()
	return cleared

func receive_resources(amount: float) -> void:
	if amount <= 0.0:
		return
	GameState.add_credits(int(round(amount)))

func produce_harvester() -> bool:
	return queue.enqueue(harvester_stats, harvester_scene)
