extends Node3D
class_name CommandMarker

## A short-lived mark on the ground where an order landed. Purely
## feedback: RTS controls feel unresponsive when a click produces no
## acknowledgement until the units physically start moving, which on a
## long path can be most of a second.
##
## Colour carries the command type, so the player can see at a glance
## whether they issued a move, an attack or an attack-move.

const LIFETIME: float = 0.55

static func spawn(parent: Node, position: Vector3, type: int) -> void:
	var marker := CommandMarker.new()
	marker.name = "CommandMarker"
	parent.add_child(marker)
	marker.global_position = position + Vector3(0, 0.15, 0)
	marker._build(type)

func _build(type: int) -> void:
	var color := _color_for(type)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.25
	ring.mesh = torus

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Drawn on top of terrain so the marker is never swallowed by the
	## ground it is lying on.
	material.no_depth_test = true
	ring.material_override = material
	add_child(ring)

	## Expands and fades: motion is what makes it read as "accepted" at a
	## glance rather than as another object sitting on the map.
	scale = Vector3.ONE * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 1.35, LIFETIME)
	tween.tween_property(material, "albedo_color:a", 0.0, LIFETIME)
	tween.chain().tween_callback(queue_free)

func _color_for(type: int) -> Color:
	match type:
		CommandTypes.Type.ATTACK:
			return Color(1.0, 0.25, 0.2)
		CommandTypes.Type.ATTACK_MOVE:
			return Color(1.0, 0.65, 0.1)
		CommandTypes.Type.HARVEST:
			return Color(0.2, 0.95, 0.7)
		CommandTypes.Type.RETURN:
			return Color(0.3, 0.8, 1.0)
	return Color(0.35, 1.0, 0.45)
