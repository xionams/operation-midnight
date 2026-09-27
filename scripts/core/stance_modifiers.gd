extends Resource
class_name StanceModifiers

## One posture's effect on a unit, as data. InfantryStance picks which of
## these is active; the systems that care (movement in UnitBase, damage /
## range / rate of fire in Weapon) ask for the active one and multiply.
## Nothing else in the game needs to know which posture a unit is in, so
## adding a modifier later means one field here and one multiply at the
## place that stat is used - not a new `if crouched:` somewhere.
##
## All values are multipliers on the unit's own stats; 1.0 is neutral.

@export var display_name: String = "Stance"
@export var move_speed_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var range_multiplier: float = 1.0
## Above 1.0 fires faster (the cooldown is divided by it).
@export var fire_rate_multiplier: float = 1.0

## Reserved for later phases. Carried now so balance files can already be
## authored against them; nothing reads them yet.
@export var accuracy_multiplier: float = 1.0
@export var suppression_resistance: float = 0.0
