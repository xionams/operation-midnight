extends OccupantHold
class_name GarrisonComponent

## Lets infantry occupy a structure and fight from inside it.
##
## Built on OccupantHold, which owns capacity, boarding, leaving and the
## collapse. This adds only what is specific to a building:
##   - a neutral structure is open to whoever reaches it first, and
##     occupying it claims it; once the last occupant walks out it goes
##     back to being neutral, so the other side can take it next
##   - the structure fires on its occupants' behalf with their weapon,
##     from a raised position that adds reach
##
## Capacity comes from BuildingStats.garrison_capacity, so a house, a
## block and a warehouse differ by data, not by script.
##
## Reserved for later phases (carried as data now, not yet applied):
## occupant_damage_multiplier and occupant_protection. Per-slot firing
## positions would hang off the same occupants array.

const DEFAULT_CAPACITY: int = 4
const RANGE_BONUS: float = 1.2

@export var occupant_damage_multiplier: float = 1.0
@export var occupant_protection: float = 0.0

var _building: BuildingBase
var _weapon: Weapon
var _attacker: AttackerComponent
## A civilian structure reverts when abandoned; a building someone built
## or captured with an Engineer stays theirs.
var _started_neutral: bool = false

func _ready() -> void:
	super._ready()
	_building = get_parent() as BuildingBase
	if _building == null:
		return
	_started_neutral = _building.is_neutral
	if _building.stats != null:
		capacity = _building.stats.garrison_capacity if _building.stats.garrison_capacity > 0 \
			else DEFAULT_CAPACITY
	if _building.health != null:
		_building.health.died.connect(eject_on_destruction)

## A neutral structure is open to whoever reaches it first; an owned one
## only to its owner.
func _accepts_side(unit: UnitBase) -> bool:
	if _building == null:
		return false
	return _building.is_neutral or _building.is_player_faction == unit.is_player_faction

## Occupying a neutral building claims it, so the defenders inside are
## unambiguously somebody's.
func _on_entering(unit: UnitBase) -> void:
	if _building.is_neutral:
		_building.set_faction(unit.is_player_faction)

func _on_entered(unit: UnitBase) -> void:
	_ensure_weapon(unit.stats)

## When the last man leaves, the building stops shooting and a civilian
## structure is up for grabs again.
func _on_emptied() -> void:
	if _attacker != null:
		_attacker.queue_free()
		_attacker = null
	if _weapon != null:
		_weapon.queue_free()
		_weapon = null
	if _started_neutral and _building != null and _building.health != null \
		and not _building.health.is_dead():
		_building.release_to_neutral()

## Occupants fire through the structure, with the extra reach a raised
## firing position gives them.
func _ensure_weapon(stats: UnitStats) -> void:
	if _weapon != null or stats == null or stats.weapon_stats == null:
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
		if _building.global_position.distance_to(candidate.global_position) > _weapon.attack_range():
			continue
		if not _weapon.can_damage(candidate):
			continue
		_attacker.set_target(candidate)
		return
