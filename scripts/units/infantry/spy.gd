extends UnitBase
class_name Spy

## Unarmed infiltrator. Disguised until a detector reveals it, so it
## walks past defenders rather than fighting them, and what it does
## inside depends on which building it picked.

func _ready() -> void:
	super._ready()
	var disguise := DisguiseAbility.new()
	disguise.name = "DisguiseAbility"
	add_child(disguise)
	var infiltrate := InfiltrateAbility.new()
	infiltrate.name = "InfiltrateAbility"
	add_child(infiltrate)
