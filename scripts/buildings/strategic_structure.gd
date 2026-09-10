extends BuildingBase
class_name StrategicStructure

## Map-control structures. They start neutral, are captured by Engineer,
## and pay their owner an ongoing benefit - which is what turns a patch
## of map into something worth fighting over rather than scenery.
##
## The benefit is data, not a subclass per structure: `benefit` selects
## which effect the same script applies.

enum Benefit { VISION, REPAIR, SUPPLY }

const REPAIR_RADIUS: float = 10.0
const REPAIR_RATE: float = 0.02
const SUPPLY_PER_MINUTE: int = 75

@export var benefit: Benefit = Benefit.VISION

var _supply_accumulator: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group("strategic_structures")

func _process(delta: float) -> void:
	super._process(delta)
	## A neutral structure pays nobody; the benefit begins at capture.
	if is_neutral:
		return
	match benefit:
		Benefit.REPAIR:
			_tick_repair_field(delta)
		Benefit.SUPPLY:
			_tick_supply(delta)
		_:
			pass

## Vision needs no tick: BuildingStats.vision_range already feeds the fog
## grid the moment ownership changes.

func _tick_repair_field(delta: float) -> void:
	var group: String = "player_units" if is_player_faction else "enemy_units"
	for unit in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(unit) or unit.stats == null:
			continue
		if unit.stats.is_infantry:
			continue
		if unit.global_position.distance_to(global_position) > REPAIR_RADIUS:
			continue
		var health: HealthComponent = unit.get_node_or_null("HealthComponent")
		if health != null and not health.is_dead():
			health.heal(health.max_health * REPAIR_RATE * delta)

func _tick_supply(delta: float) -> void:
	_supply_accumulator += delta * float(SUPPLY_PER_MINUTE) / 60.0
	if _supply_accumulator < 1.0:
		return
	var payout: int = int(_supply_accumulator)
	_supply_accumulator -= float(payout)
	GameState.add_credits_for(is_player_faction, payout)
