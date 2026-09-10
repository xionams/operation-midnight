extends Node
class_name Weapon

## Reusable ranged weapon. Any unit (or later, a defensive building)
## mounts one of these and calls fire_at() — the weapon owns cooldown
## timing, damage application, and the tracer visual. Combat behavior
## lives here and in AttackerComponent, not in individual unit scripts.

@export var stats: WeaponStats

var _cooldown_remaining: float = 0.0

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func can_fire() -> bool:
	return stats != null and _cooldown_remaining <= 0.0

func fire_at(target: Node3D, from_position: Vector3) -> void:
	if not can_fire() or not is_instance_valid(target):
		return
	_cooldown_remaining = stats.attack_cooldown

	var target_health: HealthComponent = target.get_node_or_null("HealthComponent")
	if target_health != null:
		target_health.take_damage(stats.damage)

	_spawn_tracer(from_position, target.global_position)

func _spawn_tracer(from_pos: Vector3, to_pos: Vector3) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var mid := (from_pos + to_pos) * 0.5
	var dist := from_pos.distance_to(to_pos)
	if dist < 0.01:
		return

	var tracer := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = dist
	tracer.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = stats.tracer_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.material_override = material

	tree.current_scene.add_child(tracer)
	tracer.global_position = mid
	tracer.look_at(to_pos, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(tracer.queue_free)
