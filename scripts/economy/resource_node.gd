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

func _build_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.85, 0.65)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var crystals := Node3D.new()
	crystals.name = "Crystals"
	add_child(crystals)

	for i in range(6):
		var crystal := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		var height: float = rng.randf_range(1.0, 2.4)
		mesh.size = Vector3(0.8, height, 0.8)
		crystal.mesh = mesh
		crystal.material_override = material
		var angle: float = rng.randf_range(0, TAU)
		var radius: float = rng.randf_range(0.2, 1.4)
		crystal.position = Vector3(cos(angle) * radius, height / 2.0, sin(angle) * radius)
		crystal.rotation.y = rng.randf_range(0, TAU)
		crystals.add_child(crystal)

func _update_visual_scale() -> void:
	var crystals := get_node_or_null("Crystals")
	if crystals:
		var fraction: float = clamp(remaining / total_amount, 0.15, 1.0)
		crystals.scale = Vector3(1.0, fraction, 1.0)
