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

	AudioDirector.play_weapon(stats)
	var impact_position: Vector3 = target.global_position
	var travel: float = _spawn_tracer(from_position, impact_position)
	_spawn_muzzle_effects(from_position, impact_position)
	## The round is applied instantly - this is a hitscan weapon and the
	## damage above has already landed. Only the PICTURE of the impact
	## waits for the tracer to arrive, so the streak does not reach its
	## target after the explosion it caused.
	_delay(travel, func(): _spawn_impact_effects(impact_position))
	AudioDirector.play_impact(stats)

## Runs `action` after `seconds`, or immediately if that is negligible.
## Guards on the weapon still existing: a tank that dies mid-flight must
## not take its own impact effect with it, but it must also not call into
## a freed object.
func _delay(seconds: float, action: Callable) -> void:
	if seconds <= 0.01:
		action.call()
		return
	var tree := get_tree()
	if tree == null:
		action.call()
		return
	tree.create_timer(seconds).timeout.connect(func():
		if is_instance_valid(self):
			action.call())

## Presentation only. The scale of the effect follows the weapon's own
## numbers rather than a per-unit switch, so a new weapon gets a sensible
## flash for free and artillery never looks like a rifle.
func _spawn_muzzle_effects(from_position: Vector3, impact_position: Vector3) -> void:
	var direction: Vector3 = (impact_position - from_position).normalized()
	if stats.splash_radius > 0.0:
		VFX.artillery_flash(self, from_position, direction)
	elif stats.damage >= 60.0:
		VFX.cannon_flash(self, from_position, direction)
	else:
		VFX.muzzle_flash(self, from_position, direction)

func _spawn_impact_effects(impact_position: Vector3) -> void:
	if stats.splash_radius > 0.0 or stats.damage >= 60.0:
		VFX.shell_impact(self, impact_position)
	else:
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

## Metres per second the streak appears to travel. Not a ballistics
## figure - the weapon is hitscan - just fast enough to read as a round
## rather than as a beam, and slow enough that the eye catches it.
## Faster and shorter-lived than the first cut. A streak that takes 0.30s
## to cross the field is on screen twice as long as the old instant beam
## was, and at 120 units in contact the concurrent tracer count is what
## the frame budget actually notices: the first version cost ~6 FPS
## against the beam it replaced. At 200 m/s it still reads as a travelling
## round and the population halves.
const TRACER_SPEED: float = 200.0
const TRACER_LENGTH: float = 1.9
const TRACER_MIN_TIME: float = 0.03
const TRACER_MAX_TIME: float = 0.16

## One mesh and one material per colour for the whole game.
##
## The old tracer built a fresh CylinderMesh AND a fresh
## StandardMaterial3D for every shot fired, then tweened that material's
## alpha - so nothing could be shared. At 120 units in contact that is
## hundreds of throwaway resources a second. A streak of fixed length can
## share both, and the node is scaled rather than the mesh rebuilt.
static var _tracer_mesh: CylinderMesh = null
static var _tracer_materials: Dictionary = {}

static func _shared_mesh() -> CylinderMesh:
	if _tracer_mesh == null:
		_tracer_mesh = CylinderMesh.new()
		_tracer_mesh.top_radius = 0.05
		_tracer_mesh.bottom_radius = 0.05
		_tracer_mesh.height = TRACER_LENGTH
		_tracer_mesh.radial_segments = 6
		_tracer_mesh.rings = 0
	return _tracer_mesh

static func _shared_material(color: Color) -> StandardMaterial3D:
	var key: String = str(color)
	if _tracer_materials.has(key):
		return _tracer_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Additive, so rounds brighten what they cross and overlapping fire
	## reads as heavier fire. Alpha blending made them look like grey
	## sticks wherever two crossed.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	_tracer_materials[key] = material
	return material

## Returns how long the streak takes to arrive, so the caller can hold the
## impact effect until it does.
func _spawn_tracer(from_pos: Vector3, to_pos: Vector3) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return 0.0
	if not VFX.enabled:
		return 0.0

	var distance := from_pos.distance_to(to_pos)
	if distance < 0.01:
		return 0.0
	var travel: float = clampf(distance / TRACER_SPEED,
		TRACER_MIN_TIME, TRACER_MAX_TIME)

	var tracer := MeshInstance3D.new()
	tracer.mesh = _shared_mesh()
	tracer.material_override = _shared_material(stats.tracer_color)
	## Heavier weapons throw a fatter round. Scaling the node rather than
	## the mesh is what keeps the mesh shareable.
	var girth: float = 1.0 if stats.damage < 60.0 else 1.8
	tracer.scale = Vector3(girth, 1.0, girth)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	tree.current_scene.add_child(tracer)
	tracer.global_position = from_pos
	tracer.look_at(to_pos, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	## The streak TRAVELS. The previous version drew the whole line from
	## muzzle to target in one frame and faded it, which reads as a laser
	## however short the fade is - there was never a moment where the round
	## was between the two.
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "global_position", to_pos, travel)
	tween.tween_callback(tracer.queue_free)
	return travel
