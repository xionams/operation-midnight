extends BuildingBase
class_name Wall

## A wall segment. Cheap, tough for its price, and its whole job is
## occupying navigation space so attackers must go around or spend time
## breaking through. It uses the standard building health and ownership
## path, so it can be shot, sold and repaired like anything else.

func _ready() -> void:
	super._ready()
	add_to_group("walls")
