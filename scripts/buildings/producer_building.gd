extends BuildingBase
class_name ProducerBuilding

## Any structure that trains units. Production itself lives in the shared
## ProductionQueue; this only owns the queue and answers "can you build
## this?" so the HUD, the AI and the tech gate all use one path instead
## of a bespoke produce_x() per building type.

var queue: ProductionQueue

func _ready() -> void:
	super._ready()
	queue = ProductionQueue.new()
	queue.name = "ProductionQueue"
	queue.spawn_offset = Vector3(stats.body_size.x / 2.0 + 3.0, 0, 0) if stats else Vector3(6, 0, 0)
	add_child(queue)

## True when this building is the one that trains `unit_stats`.
func trains(unit_stats: UnitStats) -> bool:
	return unit_stats != null and stats != null \
		and unit_stats.produced_by == stats.display_name

func produce(unit_stats: UnitStats) -> bool:
	if not trains(unit_stats):
		return false
	return queue.enqueue(unit_stats, unit_stats.unit_scene)

## Spy target: wipe whatever is being built, without refunding it.
func sabotage_production() -> int:
	var cleared: int = queue.queue_length()
	queue.clear_without_refund()
	return cleared
