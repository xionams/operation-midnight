extends BuildingBase
class_name Barracks

## Infantry production. Cheap and fast compared to the War Factory, which
## is the point: infantry are the answer you can afford early, and the
## Engineer and Spy that come out of here do things no vehicle can.

const GROUP: String = "barracks"

@export var soldier_stats: UnitStats
@export var soldier_scene: PackedScene
@export var engineer_stats: UnitStats
@export var engineer_scene: PackedScene
@export var spy_stats: UnitStats
@export var spy_scene: PackedScene
@export var dog_stats: UnitStats
@export var dog_scene: PackedScene

var queue: ProductionQueue

func _ready() -> void:
	super._ready()
	queue = ProductionQueue.new()
	queue.name = "ProductionQueue"
	queue.spawn_offset = Vector3(stats.body_size.x / 2.0 + 2.5, 0, 0) if stats else Vector3(5, 0, 0)
	add_child(queue)
	if is_player_faction:
		add_to_group(GROUP)

func _on_faction_changing() -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)

func _on_faction_changed() -> void:
	if is_player_faction:
		add_to_group(GROUP)

func sabotage_production() -> int:
	var cleared: int = queue.queue_length()
	queue.clear_without_refund()
	return cleared

func produce_soldier() -> bool:
	return queue.enqueue(soldier_stats, soldier_scene)

func produce_engineer() -> bool:
	return queue.enqueue(engineer_stats, engineer_scene)

func produce_spy() -> bool:
	return queue.enqueue(spy_stats, spy_scene)

func produce_dog() -> bool:
	return queue.enqueue(dog_stats, dog_scene)
