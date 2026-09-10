extends UnitBase
class_name AttackDog

## Fast anti-infantry detector. Reveals disguised Spies nearby and tears
## through foot soldiers, but cannot meaningfully hurt a vehicle.

func _ready() -> void:
	super._ready()
	var detector := DetectorAbility.new()
	detector.name = "DetectorAbility"
	add_child(detector)
