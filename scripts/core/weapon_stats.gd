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
## How this weapon looks firing, travelling and landing. Stated rather
## than derived: the damage table has five types and the wrong five for
## this purpose - a rifle and a machine gun share SMALL_ARMS, a tank gun
## and a deck gun share CANNON - while what tells them apart on screen is
## cadence, trail and arc. See WeaponVisuals.
@export var visual_class: WeaponVisuals.Class = WeaponVisuals.Class.RIFLE

## Weapons that must halt to shoot. Artillery sets this; nothing else
## should, or the army stops every time it acquires a target.
@export var requires_setup: bool = false

## Damage is dealt in a radius around the impact point rather than to one
## target. 0 means single target.
@export var splash_radius: float = 0.0

@export var can_target_air: bool = false

## Armor classes (Armor.Type values) this weapon will never engage,
## whatever the damage table says. An Attack Dog's bite shares the
## small-arms row with rifles, but a dog does not chew through a tank or a
## wall - it lists everything except INFANTRY here. Everything else leaves
## this empty and defers to the table.
@export var excluded_armor: Array[int] = []

## Which battlefield layers this weapon reaches (CombatTarget.Domain
## bits): Land=1, Naval=2, Submerged=4. Guns and rockets reach land and
## surface ships but not a submarine under water; a torpedo reaches only
## ships and submarines.
@export_flags("Land", "Naval", "Submerged") var target_domains: int = 3

func reaches(domain: int) -> bool:
	return (target_domains & domain) != 0

func excludes(armor: int) -> bool:
	return excluded_armor.has(armor)

func multiplier_for(armor: int) -> float:
	return DamageTypes.multiplier(damage_type, armor)

func damage_against(armor: int) -> float:
	return damage * multiplier_for(armor)

func in_range(distance: float) -> bool:
	return distance <= attack_range and distance >= minimum_range
