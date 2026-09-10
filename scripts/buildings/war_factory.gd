extends BuildingBase
class_name WarFactory

## Produces combat vehicles. This is the building that turns the match
## from "fight with what you started with" into an actual RTS: without
## one, Assault and Scout vehicles only exist as starting units.

const GROUP: String = "war_factories"

@export var assault_stats: UnitStats
@export var assault_scene: PackedScene
@export var scout_stats: UnitStats
@export var scout_scene: PackedScene

var queue: ProductionQueue

func _ready() -> void:
	super._ready()
	queue = ProductionQueue.new()
	queue.name = "ProductionQueue"
	queue.spawn_offset = Vector3(stats.body_size.x / 2.0 + 3.0, 0, 0) if stats else Vector3(7, 0, 0)
	add_child(queue)
	if is_player_faction:
		add_to_group(GROUP)

func produce_assault() -> bool:
	return queue.enqueue(assault_stats, assault_scene)

func produce_scout() -> bool:
	return queue.enqueue(scout_stats, scout_scene)
