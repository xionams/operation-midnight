extends Node
class_name HealthComponent

## Reusable damage/death tracker. Any unit or building adds one of
## these as a child named "HealthComponent" and weapons look it up by
## that name — nothing needs to know the concrete node type it hit.
##
## Damage arrives already scaled by the attacker's weapon against this
## component's armor_type, so the multiplier table lives in one place
## (WeaponStats) rather than being reimplemented per weapon.

signal health_changed(current: float, max: float)
signal died
signal killed_by(attacker: Node)

@export var max_health: float = 100.0
@export var armor_type: Armor.Type = Armor.Type.HEAVY

var current_health: float
var _dead: bool = false

func _ready() -> void:
	current_health = max_health

func setup(new_max_health: float, new_armor: Armor.Type = Armor.Type.HEAVY) -> void:
	max_health = new_max_health
	current_health = new_max_health
	armor_type = new_armor

func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead or amount <= 0.0:
		return
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_dead = true
		if attacker != null and is_instance_valid(attacker):
			killed_by.emit(attacker)
		died.emit()

## Full-health reset used when a building changes hands, so a captured
## structure does not immediately die from the damage that softened it.
func heal_to_full() -> void:
	if _dead:
		return
	current_health = max_health
	health_changed.emit(current_health, max_health)

func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func is_dead() -> bool:
	return _dead

func health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health
