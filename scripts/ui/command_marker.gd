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

## "No": a red ring that CONTRACTS with a cross through it. Shrinking is
## the opposite motion to an accepted order's expanding ring, so the two
## cannot be confused even peripherally.
static func spawn_rejected(parent: Node, position: Vector3) -> void:
	var marker := CommandMarker.new()
	marker.name = "RejectedMarker"
	parent.add_child(marker)
	marker.global_position = position + Vector3(0, 0.15, 0)
	var material := _flat_material(Color(1.0, 0.2, 0.15))
	marker.add_child(_ring_mesh(material))
	for angle in [PI * 0.25, -PI * 0.25]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.4, 0.05, 0.22)
		bar.mesh = box
		bar.rotation.y = angle
		bar.material_override = material
		marker.add_child(bar)
	marker.scale = Vector3.ONE * 1.4
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3.ONE * 0.6, LIFETIME * 1.3)
	tween.tween_property(material, "albedo_color:a", 0.0, LIFETIME * 1.3)
	tween.chain().tween_callback(marker.queue_free)

## Target lock: a red ring that rides on the unit or building being
## attacked, so an attack order says WHAT was targeted, not only where.
static func spawn_on_target(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var old := target.get_node_or_null("TargetMarker")
	if old != null:
		old.free()
	var marker := CommandMarker.new()
	marker.name = "TargetMarker"
	target.add_child(marker)
	var size: Vector3 = target.stats.body_size if target.get("stats") != null else Vector3(2, 2, 2)
	var reach: float = maxf(size.x, size.z) * 0.6 + 0.6
	marker.position = Vector3(0, 0.2, 0)
	var material := _flat_material(Color(1.0, 0.22, 0.18))
	marker.add_child(_ring_mesh(material))
	marker.scale = Vector3.ONE * reach * 1.6
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE * reach, 0.18)
	tween.tween_interval(0.5)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(marker.queue_free)

static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	return material

static func _ring_mesh(material: Material) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.25
	ring.mesh = torus
	ring.material_override = material
	return ring

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
		CommandTypes.Type.GARRISON:
			return Color(1.0, 0.85, 0.3)
		CommandTypes.Type.PATROL, CommandTypes.Type.GUARD:
			return Color(0.55, 0.75, 1.0)
	return Color(0.35, 1.0, 0.45)
