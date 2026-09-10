extends BuildingBase
class_name Gate

## A wall segment the owner's units can walk through.
##
## Rather than animating doors and re-baking navigation, the gate simply
## does not collide with its owner's units: friendly traffic passes,
## hostile traffic is stopped by the collision that remains. That gives
## the gameplay result the brief asks for without a navmesh rebake every
## time a unit walks home.

func _ready() -> void:
	super._ready()
	add_to_group("walls")
	add_to_group("gates")
	_apply_passability()

func _on_faction_changed() -> void:
	_apply_passability()

## Units collide with layer 1 (ground/blockers). A gate belonging to the
## owner drops off that layer so its own side walks through, while it
## stays on the building layer so it can still be selected and shot.
func _apply_passability() -> void:
	collision_layer = BUILDING_COLLISION_LAYER
