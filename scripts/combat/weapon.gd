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

## Reach after the wielder's posture. Everything that asks "am I in range"
## goes through here rather than reading stats.attack_range directly.
func attack_range() -> float:
	if stats == null:
		return 0.0
	return stats.attack_range * InfantryStance.modifiers_of(get_parent()).range_multiplier

## True when this weapon can meaningfully hurt the target at all. Used so
## a unit does not walk across the map to plink uselessly at armour its
## weapon cannot scratch.
## A weapon must be able to hurt a target *usefully* before a unit will
## walk across the map to shoot it. The damage table gives small arms a
## small but non-zero multiplier against armour, which is right for a
## rifleman who is already in a fight - but without this floor an Attack
## Dog would happily chase a Main Battle Tank and die achieving nothing.
const MIN_USEFUL_MULTIPLIER: float = 0.25

##
## This is the bar for choosing a target by ITSELF (idle defence,
## attack-move, towers). A direct order from the player is judged by
## can_attack instead: a rifleman told to shoot a tank should shoot it,
## however little it achieves - that is the player's call to make.
func can_damage(target: Node) -> bool:
	if not can_attack(target):
		return false
	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	return stats.multiplier_for(health.armor_type) >= MIN_USEFUL_MULTIPLIER

## True when this weapon can hurt the target at all and is not the kind
## of weapon that refuses that armor outright (see WeaponStats.excluded_armor).
func can_attack(target: Node) -> bool:
	if stats == null or not is_instance_valid(target):
		return false
	var health: HealthComponent = target.get_node_or_null("HealthComponent")
	if health == null:
		return false
	if stats.excludes(health.armor_type):
		return false
	if not stats.reaches(CombatTarget.domain_of(target)):
		return false
	return stats.multiplier_for(health.armor_type) > 0.0

func fire_at(target: Node3D, from_position: Vector3) -> void:
	if not can_fire() or not is_instance_valid(target):
		return
	var attacker := get_parent()
	## A submarine has to come up to shoot, which is what lets it be
	## answered (see Stealth).
	var stealth: Stealth = attacker.get_node_or_null("Stealth")
	if stealth != null:
		stealth.surface()
	## Posture (RUN / CROUCH) scales rate of fire and damage here, once,
	## the same way rank does - see InfantryStance.
	var posture: StanceModifiers = InfantryStance.modifiers_of(attacker)
	_cooldown_remaining = stats.attack_cooldown / maxf(posture.fire_rate_multiplier, 0.01)

	## Veteran crews hit harder. The multiplier is applied once, here, so
	## every weapon benefits without each unit script knowing about rank.
	var veterancy: VeterancyComponent = attacker.get_node_or_null("VeterancyComponent")
	var bonus: float = veterancy.damage_multiplier() if veterancy else 1.0
	bonus *= posture.damage_multiplier

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
	## Presentation only, and all of it after the damage above. See
	## WeaponVisuals for why the LOOK of a weapon is stated on it rather
	## than derived from its damage numbers.
	var travel: float = WeaponVisuals.projectile(self, stats, from_position, impact_position)
	WeaponVisuals.muzzle(self, stats, from_position, impact_position)
	## The round is applied instantly - this is a hitscan weapon and the
	## damage above has already landed. Only the PICTURE of the impact
	## waits for the tracer to arrive, so the streak does not reach its
	## target after the explosion it caused.
	_delay(travel, func(): WeaponVisuals.impact(self, stats, impact_position))
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
