extends StaticBody3D
class_name ResourceNode

## A finite "Strategic Resources" deposit. Harvesters call harvest()
## to withdraw up to their cargo capacity; the node depletes and
## eventually removes itself. Credits never come from here directly —
## only a harvester physically delivering cargo to a refinery pays out.

signal depleted

@export var total_amount: float = 16000.0

var remaining: float

const RESOURCE_COLLISION_LAYER: int = 1 << 3 # bit 4

func _ready() -> void:
	remaining = total_amount
	add_to_group("resource_nodes")
	collision_layer = RESOURCE_COLLISION_LAYER
	collision_mask = 0
	_build_collision()
	_build_visual()

	## A resource field does not move, so once the player has found it, it
	## stays on their map even when nothing is watching it. That is what
	## makes scouting pay economically.
	var hideable := FogHideable.new()
	hideable.name = "FogHideable"
	hideable.persists_once_explored = true
	add_child(hideable)

func harvest(amount: float) -> float:
	var taken: float = min(amount, remaining)
	remaining -= taken
	_update_visual_scale()
	if remaining <= 0.0:
		depleted.emit()
		queue_free()
	return taken

func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	shape.shape = box
	shape.position = Vector3(0, 1, 0)
	add_child(shape)

const ORE_MODEL: PackedScene = preload("res://assets/models/ore_field.glb")

func _build_visual() -> void:
	var crystals := Node3D.new()
	crystals.name = "Crystals"
	add_child(crystals)
	## Amber ore on a dark apron rather than green crystals: resources are
	## a signal colour in this game's palette, and "crystal" read as
	## fantasy rather than as the industrial mining the fiction wants.
	crystals.add_child(ORE_MODEL.instantiate())

func _update_visual_scale() -> void:
	var crystals := get_node_or_null("Crystals")
	if crystals:
		var fraction: float = clamp(remaining / total_amount, 0.15, 1.0)
		crystals.scale = Vector3(1.0, fraction, 1.0)
