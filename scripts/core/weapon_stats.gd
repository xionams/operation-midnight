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

## Damage multipliers per armor class. 1.0 is full damage, 0.0 means this
## weapon cannot hurt that target at all. Tune counters here, never in
## unit scripts: a rifle mauls infantry and barely scratches armour, a
## tank shell does the reverse.
@export var vs_infantry: float = 1.0
@export var vs_light: float = 1.0
@export var vs_heavy: float = 1.0
@export var vs_building: float = 1.0

## Set for anti-infantry weapons that should never be able to target
## something they cannot meaningfully hurt.
@export var can_target_air: bool = false

func multiplier_for(armor: int) -> float:
	match armor:
		Armor.Type.INFANTRY:
			return vs_infantry
		Armor.Type.LIGHT:
			return vs_light
		Armor.Type.HEAVY:
			return vs_heavy
		Armor.Type.BUILDING:
			return vs_building
	return 1.0

func damage_against(armor: int) -> float:
	return damage * multiplier_for(armor)
