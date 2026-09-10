extends Node
class_name GarrisonComponent

## Lets infantry occupy a structure and fight from inside it.
##
## Garrisoned squads are removed from the world rather than simulated
## inside the building: they stop being shootable, and the structure
## fires on their behalf with their weapon. That keeps a garrison cheap
## at army scale and makes the counter obvious - you cannot shoot the
## men, so you must knock the building down.

signal occupancy_changed(count: int)

const CAPACITY: int = 5
const DAMAGE_REDUCTION: float = 0.6
const RANGE_BONUS: float = 1.2
const EVACUATION_DAMAGE: float = 0.4

var occupants: Array = []

var _building: BuildingBase
var _weapon: Weapon
var _attacker: AttackerComponent

func _ready() -> void:
	_building = get_parent() as BuildingBase
	if _building != null and _building.health != null:
		_building.health.died.connect(_evacuate)

func has_room() -> bool:
	return occupants.size() < CAPACITY

func occupancy() -> int:
	return occupants.size()

## The squad is stored, not simulated. Its stats drive the building's
## borrowed weapon so a garrison of riflemen shoots like riflemen.
func enter(unit: Node) -> bool:
	if not has_room() or unit == null or unit.stats == null or not unit.stats.is_infantry:
		return false
	## A neutral structure is open to whoever reaches it first; an owned
	## one only to its owner.
	if _building == null:
		return false
	if not _building.is_neutral and _building.is_player_faction != unit.is_player_faction:
		return false
	## Occupying a neutral building claims it, so the defenders inside are
	## unambiguously somebody's.
	if _building.is_neutral:
		_building.set_faction(unit.is_player_faction)

	occupants.append({
		"stats": unit.stats,
		"health": unit.health.current_health if unit.health else unit.stats.max_health,
	})
	_ensure_weapon(unit.stats)
	SelectionManager.notify_unit_removed(unit)
	unit.queue_free()
	occupancy_changed.emit(occupants.size())
	return true

## Occupants fire through the structure, with the extra reach a raised
## firing position gives them.
func _ensure_weapon(stats: UnitStats) -> void:
	if _weapon != null or stats.weapon_stats == null:
		return
	var borrowed: WeaponStats = stats.weapon_stats.duplicate()
	borrowed.attack_range *= RANGE_BONUS
	_weapon = Weapon.new()
	_weapon.name = "GarrisonWeapon"
	_weapon.stats = borrowed
	_building.add_child(_weapon)

	_attacker = AttackerComponent.new()
	_attacker.name = "AttackerComponent"
	_attacker.weapon = _weapon
	_building.add_child(_attacker)

func _process(_delta: float) -> void:
	if _attacker == null or occupants.is_empty() or _attacker.has_target():
		return
	var group: String = "enemy_units" if _building.is_player_faction else "player_units"
	for candidate in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(candidate):
			continue
		if _building.global_position.distance_to(candidate.global_position) > _weapon.stats.attack_range:
			continue
		if not _weapon.can_damage(candidate):
			continue
		_attacker.set_target(candidate)
		return

## Losing the building costs the squad inside a share of its health, and
## anything already hurt does not make it out.
func _evacuate() -> void:
	for entry in occupants:
		var stats: UnitStats = entry["stats"]
		var remaining: float = entry["health"] * (1.0 - EVACUATION_DAMAGE)
		if remaining <= 0.0 or stats.unit_scene == null:
			continue
		var unit = stats.unit_scene.instantiate()
		unit.stats = stats
		unit.is_player_faction = _building.is_player_faction
		_building.get_parent().add_child(unit)
		unit.global_position = _building.global_position \
			+ Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		if unit.health != null:
			unit.health.current_health = remaining
	occupants.clear()
	occupancy_changed.emit(0)
