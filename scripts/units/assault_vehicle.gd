extends UnitBase
class_name AssaultVehicle

## Basic armored combat unit. All targeting/firing behavior lives in
## AttackerComponent + Weapon; this script only wires them together so
## future unit types (artillery, anti-air, ...) can reuse the exact
## same components with different WeaponStats.

func _ready() -> void:
	super._ready()

	var weapon := Weapon.new()
	weapon.name = "Weapon"
	weapon.stats = stats.weapon_stats if stats else null
	add_child(weapon)

	var attacker := AttackerComponent.new()
	attacker.name = "AttackerComponent"
	attacker.weapon = weapon
	add_child(attacker)
