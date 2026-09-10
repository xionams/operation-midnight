extends Node
class_name HealthComponent

## Reusable damage/death tracker. Any unit or building adds one of
## these as a child named "HealthComponent" and weapons look it up by
## that name — nothing needs to know the concrete node type it hit.

signal health_changed(current: float, max: float)
signal died

@export var max_health: float = 100.0

var current_health: float
var _dead: bool = false

func _ready() -> void:
	current_health = max_health

func setup(new_max_health: float) -> void:
	max_health = new_max_health
	current_health = new_max_health

func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_dead = true
		died.emit()

func is_dead() -> bool:
	return _dead

func health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health
