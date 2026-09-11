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

## True when this weapon can meaningfully hurt the target at all. Used so
## a unit does not walk across the map to plink uselessly at armour its
## weapon cannot scratch.
## A weapon must be able to hurt a target *usefully* before a unit will
## walk across the map to shoot it. The damage table gives small arms a
## small but non-zero multiplier against armour, which is right for a
## rifleman who is already in a fight - but without this floor an Attack
## Dog would happily chase a Main Battle Tank and die achieving nothing.
const MIN_USEFUL_MULTIPLIER: float = 0.25

func can_damage(target: Node) -> bool:
	if stats == null or not is_instance_valid(target):
		return false
	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	if health == null:
		return false
	return stats.multiplier_for(health.armor_type) >= MIN_USEFUL_MULTIPLIER

func fire_at(target: Node3D, from_position: Vector3) -> void:
	if not can_fire() or not is_instance_valid(target):
		return
	_cooldown_remaining = stats.attack_cooldown

	var attacker := get_parent()
	## Veteran crews hit harder. The multiplier is applied once, here, so
	## every weapon benefits without each unit script knowing about rank.
	var veterancy: VeterancyComponent = attacker.get_node_or_null("VeterancyComponent")
	var bonus: float = veterancy.damage_multiplier() if veterancy else 1.0

	if stats.splash_radius > 0.0:
		_apply_splash(target.global_position, bonus, attacker, veterancy)
	else:
		var target_health: HealthComponent = target.get_node_or_null("HealthComponent")
		if target_health != null:
			var dealt: float = stats.damage_against(target_health.armor_type) * bonus
			target_health.take_damage(dealt, attacker)
			if veterancy:
				veterancy.award_damage(dealt)

	AudioDirector.play("attack")
	_spawn_tracer(from_position, target.global_position)
	_spawn_fire_effects(from_position, target.global_position)

## Presentation only. The scale of the effect follows the weapon's own
## numbers rather than a per-unit switch, so a new weapon gets a sensible
## flash for free and artillery never looks like a rifle.
func _spawn_fire_effects(from_position: Vector3, impact_position: Vector3) -> void:
	var direction: Vector3 = (impact_position - from_position).normalized()
	if stats.splash_radius > 0.0:
		VFX.artillery_flash(self, from_position, direction)
		VFX.shell_impact(self, impact_position)
	elif stats.damage >= 60.0:
		VFX.cannon_flash(self, from_position, direction)
		VFX.shell_impact(self, impact_position)
	else:
		VFX.muzzle_flash(self, from_position, direction)
		VFX.impact(self, impact_position)

## Explosive ordnance damages everything near the impact, friend or foe -
## which is exactly why artillery is dangerous to use inside your own
## lines and excellent against a packed formation.
func _apply_splash(centre: Vector3, bonus: float, attacker: Node, veterancy: VeterancyComponent) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var radius_sq: float = stats.splash_radius * stats.splash_radius
	for group in ["units", "buildings"]:
		for entity in tree.get_nodes_in_group(group):
			if not is_instance_valid(entity):
				continue
			if entity.global_position.distance_squared_to(centre) > radius_sq:
				continue
			var health: HealthComponent = entity.get_node_or_null("HealthComponent")
			if health == null or health.is_dead():
				continue
			var dealt: float = stats.damage_against(health.armor_type) * bonus
			health.take_damage(dealt, attacker)
			if veterancy and entity.get("is_player_faction") != attacker.get("is_player_faction"):
				veterancy.award_damage(dealt)

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
