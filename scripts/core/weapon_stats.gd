extends Resource
class_name WeaponStats

## Data-driven stat block for a weapon. Shared by any unit/building
## that mounts an AttackerComponent + Weapon pair.

@export var display_name: String = "Weapon"
@export var damage: float = 10.0
@export var attack_range: float = 10.0
@export var attack_cooldown: float = 1.0
@export var is_hitscan: bool = true
@export var projectile_speed: float = 40.0 ## Used only when is_hitscan == false.
@export var tracer_color: Color = Color.ORANGE
