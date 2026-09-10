extends Resource
class_name WeaponStats

## Data-driven stat block for a weapon. Shared by any unit, turret or
## building that mounts an AttackerComponent + Weapon pair.
##
## Effectiveness against a target comes from damage_type via the shared
## DamageTypes table, so counters are consistent everywhere and tuned in
## one file rather than per weapon.

@export var display_name: String = "Weapon"
@export var damage: float = 10.0
@export var damage_type: DamageTypes.Type = DamageTypes.Type.SMALL_ARMS
@export var attack_range: float = 10.0

## Artillery cannot fire at things standing on top of it, which is what
## makes it vulnerable to anything that closes the distance.
@export var minimum_range: float = 0.0

@export var attack_cooldown: float = 1.0
@export var is_hitscan: bool = true
@export var projectile_speed: float = 40.0
@export var tracer_color: Color = Color.ORANGE

## Weapons that must halt to shoot. Artillery sets this; nothing else
## should, or the army stops every time it acquires a target.
@export var requires_setup: bool = false

## Damage is dealt in a radius around the impact point rather than to one
## target. 0 means single target.
@export var splash_radius: float = 0.0

@export var can_target_air: bool = false

func multiplier_for(armor: int) -> float:
	return DamageTypes.multiplier(damage_type, armor)

func damage_against(armor: int) -> float:
	return damage * multiplier_for(armor)

func in_range(distance: float) -> bool:
	return distance <= attack_range and distance >= minimum_range
