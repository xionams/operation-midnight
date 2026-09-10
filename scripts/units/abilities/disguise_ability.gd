extends Node
class_name DisguiseAbility

## Spy logic: while disguised the unit is ignored by enemy targeting, so
## it can walk past defenders instead of fighting through them. The
## disguise is not permanent cover - it drops when the Spy is revealed by
## a detector, which is what gives Attack Dogs their job.

signal disguise_changed(disguised: bool)

@export var disguised: bool = true

var _unit: UnitBase

func _ready() -> void:
	_unit = get_parent() as UnitBase
	_apply_visual()

func is_disguised() -> bool:
	return disguised and is_instance_valid(_unit)

func reveal() -> void:
	if not disguised:
		return
	disguised = false
	_apply_visual()
	disguise_changed.emit(false)

## Disguised units wear the enemy's indicator colour, so on screen they
## read as one of theirs until something reveals them.
func _apply_visual() -> void:
	if _unit == null:
		return
	var shown_as_player: bool = (not _unit.is_player_faction) if disguised else _unit.is_player_faction
	for child in _unit.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_child := child as MeshInstance3D
		if mesh_child == _unit.selection_ring:
			continue
		var material := mesh_child.material_override as StandardMaterial3D
		if material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			material.albedo_color = Color(0.2, 0.45, 1.0) if shown_as_player else Color(0.9, 0.15, 0.15)

## True when `viewer` should be able to see through this disguise.
static func visible_to(target: Node, viewer_is_player: bool) -> bool:
	var disguise: DisguiseAbility = target.get_node_or_null("DisguiseAbility")
	if disguise == null or not disguise.is_disguised():
		return true
	var unit := target as UnitBase
	if unit == null:
		return true
	return unit.is_player_faction == viewer_is_player
