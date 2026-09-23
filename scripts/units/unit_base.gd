extends CharacterBody3D
class_name UnitBase

## Shared behavior for every mobile unit: navigation movement, facing,
## the selection ring, health wiring, and the placeholder visual body.
## Concrete units (AssaultVehicle, ScoutVehicle, Harvester) extend this
## and only add what makes them different — combat, harvesting, etc.
## Swapping in a real Blender model later only means setting
## stats.visual_scene; this script never changes.

signal died(unit: UnitBase)

@export var stats: UnitStats
@export var is_player_faction: bool = true

var health: HealthComponent
var nav_agent: NavigationAgent3D
var selection_ring: MeshInstance3D
var health_bar: HealthBar
var veterancy: VeterancyComponent
var turret_aim: TurretAim = null

## Current order, exposed so the HUD and debug overlay can report what a
## unit believes it is doing.
var current_command: int = CommandTypes.Type.STOP
var command_target: Node = null
var command_position: Vector3 = Vector3.ZERO
var stance: int = Stance.DEFENSIVE
## Patrol bounces between the point the order was given and the target.
var patrol_from: Vector3 = Vector3.ZERO
var patrol_to: Vector3 = Vector3.ZERO
var guard_target: Node = null
var garrison_target: Node = null

## How willingly a unit leaves its post to engage.
##   HOLD        never chases; fires only at what comes into range
##   DEFENSIVE   short leash around where it was told to stand
##   AGGRESSIVE  wide acquisition and a long leash
enum Stance { HOLD, DEFENSIVE, AGGRESSIVE }

const STANCE_ACQUIRE_BONUS: Dictionary = {
	Stance.HOLD: 0.0, Stance.DEFENSIVE: 5.0, Stance.AGGRESSIVE: 12.0,
}
const STANCE_LEASH: Dictionary = {
	Stance.HOLD: 0.0, Stance.DEFENSIVE: 12.0, Stance.AGGRESSIVE: 26.0,
}

const ACQUIRE_INTERVAL: float = 0.25
const ACQUIRE_BONUS: float = 5.0
const MAX_CHASE_DISTANCE: float = 12.0
const STUCK_TIME: float = 2.5
const STUCK_EPSILON: float = 0.4

## Captured on the first physics tick, never in _ready: spawners add the
## node to the tree and set its position afterwards, so at _ready time
## every unit still reports the world origin. Reading it there made every
## unit believe home was (0,0,0) and march to the middle of the map.
var _guard_origin: Vector3 = Vector3.ZERO
var _guard_origin_set: bool = false
var _acquire_timer: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_reference: Vector3 = Vector3.ZERO

const UNIT_COLLISION_LAYER: int = 1 << 1 # bit 2
const GROUND_COLLISION_LAYER: int = 1 << 0 # bit 1
const INFANTRY_COLLISION_LAYER: int = 1 << 4 # bit 5 (bit 4 is resource nodes)

## Infantry sit on their own layer that vehicles do not collide with, so
## armour drives straight through them instead of being walled off by a
## man standing in the road. Being driven through is what gets them
## crushed. Both layers stay inside SelectionManager's pick mask, so
## infantry remain clickable.

func get_faction() -> int:
	return GameState.Faction.PLAYER if is_player_faction else GameState.Faction.ENEMY

func _ready() -> void:
	add_to_group("units")
	add_to_group("player_units" if is_player_faction else "enemy_units")

	var infantry: bool = stats != null and stats.is_infantry
	collision_layer = INFANTRY_COLLISION_LAYER if infantry else UNIT_COLLISION_LAYER
	collision_mask = GROUND_COLLISION_LAYER if infantry else (GROUND_COLLISION_LAYER | UNIT_COLLISION_LAYER)

	_build_fog_visibility()
	_build_collision()
	_build_nav_agent()
	_build_health()
	_build_weapon()
	_build_visual()
	_build_selection_ring()
	_build_health_bar()
	_build_veterancy()

## Enemy-owned entities can be hidden by fog. Player-owned ones never are:
## you always see your own army.
func _build_fog_visibility() -> void:
	if is_player_faction:
		return
	var hideable := FogHideable.new()
	hideable.name = "FogHideable"
	add_child(hideable)

## Any unit whose stats carry a weapon gets the standard targeting/firing
## pair. Unarmed units (Harvester, Engineer, Spy) simply leave
## weapon_stats null and get nothing.
func _build_weapon() -> void:
	if stats == null or stats.weapon_stats == null:
		return
	var weapon := Weapon.new()
	weapon.name = "Weapon"
	weapon.stats = stats.weapon_stats
	add_child(weapon)

	var attacker := AttackerComponent.new()
	attacker.name = "AttackerComponent"
	attacker.weapon = weapon
	add_child(attacker)

func _build_collision() -> void:
	var size: Vector3 = stats.body_size if stats else Vector3(1.5, 1.0, 2.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y / 2.0, 0)
	add_child(shape)

func _build_nav_agent() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.radius = stats.nav_radius if stats else 1.0
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.8

	## Local avoidance matters at army scale, not in skirmishes: without
	## it two forces meeting head-on interpenetrate and jam, and dozens of
	## units sit still pressed against each other. RVO lets them slide
	## past instead. The unstick nudge stays as a backstop for the cases
	## avoidance cannot resolve, such as being pinned against terrain.
	nav_agent.avoidance_enabled = true
	nav_agent.neighbor_distance = 6.0
	nav_agent.max_neighbors = 8
	nav_agent.avoidance_priority = 0.5 if stats != null and stats.is_infantry else 1.0
	nav_agent.max_speed = stats.move_speed if stats else 5.0
	nav_agent.velocity_computed.connect(_on_avoidance_velocity)
	add_child(nav_agent)

## RVO hands back a velocity that avoids neighbours; the body moves with
## that rather than the raw desired direction.
func _on_avoidance_velocity(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()
	_crush_what_we_drove_over()

func _build_health() -> void:
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = stats.max_health if stats else 100.0
	health.armor_type = stats.armor_type if stats else Armor.Type.HEAVY
	add_child(health)
	health.died.connect(_on_died)

func _build_visual() -> void:
	## OM_NO_MODELS falls back to the primitive stand-ins. Kept because it
	## is how the art pass's performance cost was isolated: models, scenery
	## and VFX can each be switched off independently and measured.
	if stats and stats.visual_scene and OS.get_environment("OM_NO_MODELS").is_empty():
		var visual := stats.visual_scene.instantiate()
		add_child(visual)
		## The model carries its own faction markings in a named material
		## slot, so it needs painting rather than a separate indicator box.
		FactionPaint.apply(visual, FactionPaint.color_for(is_player_faction))
		## Models built with a Turret node aim it; everything else
		## simply has no turret to turn.
		turret_aim = TurretAim.attach(self, visual)
		return

	var size: Vector3 = stats.body_size if stats else Vector3(1.5, 1.0, 2.2)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	body.mesh = mesh
	body.position = Vector3(0, size.y / 2.0, 0)

	var material := StandardMaterial3D.new()
	material.albedo_color = stats.body_color if stats else Color.GRAY
	body.material_override = material
	add_child(body)

	var indicator := MeshInstance3D.new()
	var indicator_mesh := BoxMesh.new()
	indicator_mesh.size = Vector3(size.x * 0.3, 0.15, size.z * 0.3)
	indicator.mesh = indicator_mesh
	indicator.position = Vector3(0, size.y + 0.1, size.z * 0.25)
	var indicator_material := StandardMaterial3D.new()
	indicator_material.albedo_color = Color(0.2, 0.45, 1.0) if is_player_faction else Color(0.9, 0.15, 0.15)
	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator.material_override = indicator_material
	add_child(indicator)

func _build_selection_ring() -> void:
	selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	var radius: float = max(stats.body_size.x, stats.body_size.z) * 0.7 if stats else 1.2
	ring.inner_radius = radius
	ring.outer_radius = radius + 0.15
	selection_ring.mesh = ring
	selection_ring.position = Vector3(0, 0.05, 0)
	var material := StandardMaterial3D.new()
	## Harvesters read amber so a player scanning a selection can tell at
	## a glance whether they just grabbed their economy along with their
	## army - which is the mistake this ring exists to prevent.
	material.albedo_color = Color(0.88, 0.65, 0.24) if (stats and stats.is_harvester) \
		else Color(0.23, 0.87, 0.35)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Never swallowed by the ground it is lying on.
	material.no_depth_test = true
	selection_ring.material_override = material
	selection_ring.visible = false
	add_child(selection_ring)

## Only things that fight can earn rank; a harvester promoting itself for
## being shot at would be noise.
func _build_veterancy() -> void:
	if stats == null or stats.weapon_stats == null:
		return
	veterancy = VeterancyComponent.new()
	veterancy.name = "VeterancyComponent"
	add_child(veterancy)

func _build_health_bar() -> void:
	var size: Vector3 = stats.body_size if stats else Vector3(1.5, 1.0, 2.2)
	health_bar = HealthBar.attach(self, health, size.y, maxf(size.x, 1.4))

func set_selected(selected: bool) -> void:
	if selection_ring:
		var was: bool = selection_ring.visible
		selection_ring.visible = selected
		## A ring that simply appears is easy to miss in a crowd. A short
		## pop is the acknowledgement - it only plays on the transition,
		## so re-selecting the same units does not restart it.
		if selected and not was:
			selection_ring.scale = Vector3(1.45, 1.0, 1.45)
			var tween := create_tween()
			tween.tween_property(selection_ring, "scale", Vector3.ONE, 0.16) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if health_bar:
		health_bar.set_selected(selected)

func move_to(target_position: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_position

func stop_moving() -> void:
	if nav_agent:
		nav_agent.target_position = global_position
	velocity = Vector3.ZERO

func face_towards(target_position: Vector3) -> void:
	var direction: Vector3 = target_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var desired_rotation: float = atan2(direction.x, direction.z)
	var turn_speed: float = stats.turn_speed if stats else 6.0
	rotation.y = lerp_angle(rotation.y, desired_rotation, clamp(turn_speed * get_physics_process_delta_time(), 0.0, 1.0))

func attack_target(target: Node) -> void:
	issue_command(CommandTypes.Type.ATTACK, Vector3.ZERO, target)

## Single entry point for every order. The player's input layer resolves
## intent to a CommandType and calls this; units never read input, and
## specialised units (Harvester) override _handle_command rather than
## growing their own input handling.
func issue_command(type: int, position: Vector3 = Vector3.ZERO, target: Node = null) -> void:
	current_command = type
	command_target = target
	command_position = position
	_guard_origin = global_position
	_guard_origin_set = true
	_acquire_timer = 0.0
	_handle_command(type, position, target)

func _handle_command(type: int, position: Vector3, target: Node) -> void:
	var attacker: AttackerComponent = get_node_or_null("AttackerComponent")
	match type:
		CommandTypes.Type.MOVE:
			if attacker:
				attacker.clear_target()
			move_to(position)
		CommandTypes.Type.ATTACK:
			if attacker:
				attacker.set_target(target)
			elif target is Node3D:
				move_to((target as Node3D).global_position)
		CommandTypes.Type.ATTACK_MOVE:
			if attacker:
				attacker.clear_target()
			move_to(position)
		CommandTypes.Type.STOP:
			if attacker:
				attacker.clear_target()
			stop_moving()
		CommandTypes.Type.GUARD:
			if attacker:
				attacker.clear_target()
			guard_target = target
			stop_moving()
		CommandTypes.Type.GARRISON:
			## Only infantry can occupy; everyone else just walks there.
			if stats != null and stats.is_infantry and target != null:
				garrison_target = target
				move_to(position)
			else:
				move_to(position)
		CommandTypes.Type.PATROL:
			if attacker:
				attacker.clear_target()
			patrol_from = global_position
			patrol_to = position
			move_to(patrol_to)
		_:
			## Orders that mean something only to a specialist - HARVEST,
			## RETURN, CAPTURE - still have to do something sensible for
			## everyone else, or a mixed selection silently ignores the
			## click. Walking there is the honest interpretation.
			if attacker:
				attacker.clear_target()
			move_to(position)

## Attack-move and idle defence share one scan. Runs on a timer rather
## than every frame - target acquisition at 4Hz is indistinguishable in
## play and keeps the cost flat as army sizes grow.
func _tick_combat_behavior(delta: float) -> void:
	if not _guard_origin_set:
		_guard_origin = global_position
		_guard_origin_set = true

	var attacker: AttackerComponent = get_node_or_null("AttackerComponent")
	if attacker == null or attacker.weapon == null or attacker.weapon.stats == null:
		return

	if attacker.has_target() or attacker.is_searching():
		return

	## An attack-mover with nothing to shoot resumes its advance.
	if current_command == CommandTypes.Type.ATTACK_MOVE and nav_agent != null \
		and nav_agent.is_navigation_finished() == false:
		pass
	elif current_command == CommandTypes.Type.ATTACK_MOVE:
		move_to(command_position)

	_tick_patrol()
	_tick_guard()
	_tick_garrison()

	_acquire_timer -= delta
	if _acquire_timer > 0.0:
		return
	_acquire_timer = ACQUIRE_INTERVAL

	var acquisition: float = attacker.weapon.stats.attack_range \
		+ STANCE_ACQUIRE_BONUS.get(stance, ACQUIRE_BONUS)
	var found := _nearest_hostile(acquisition, attacker)
	if found == null:
		if _should_return_home():
			move_to(_guard_origin)
		return

	attacker.set_target(found)
	if current_command == CommandTypes.Type.ATTACK_MOVE:
		stop_moving()

## The leash exists to stop a unit chasing a target across the map, not
## to override travel. A unit that is still navigating is going somewhere
## on purpose - including via a direct move_to() from the harvest loop or
## the AI - and must be left alone, or every ordered move gets cancelled
## the moment it passes the leash radius.
func _should_return_home() -> bool:
	if current_command == CommandTypes.Type.ATTACK_MOVE \
		or current_command == CommandTypes.Type.MOVE:
		## An advancing unit has no post to return to; where it stands now
		## becomes home if it is ever told to hold.
		_guard_origin = global_position
		return false
	if nav_agent != null and not nav_agent.is_navigation_finished():
		return false
	var leash: float = STANCE_LEASH.get(stance, MAX_CHASE_DISTANCE)
	if leash <= 0.0:
		return global_position.distance_to(_guard_origin) > 1.0
	return global_position.distance_to(_guard_origin) > leash

## Walk in once close enough. Entering removes the unit from the world,
## so this is the last thing it does.
func _tick_garrison() -> void:
	if current_command != CommandTypes.Type.GARRISON or not is_instance_valid(garrison_target):
		return
	if global_position.distance_to(garrison_target.global_position) > 6.0:
		return
	var garrison = garrison_target.get_node_or_null("GarrisonComponent")
	garrison_target = null
	if garrison != null:
		garrison.enter(self)

## Patrol turns around at each end, so a unit sweeps a line indefinitely
## and re-engages anything that wanders into it.
func _tick_patrol() -> void:
	if current_command != CommandTypes.Type.PATROL:
		return
	if nav_agent == null or not nav_agent.is_navigation_finished():
		return
	var swap := patrol_from
	patrol_from = patrol_to
	patrol_to = swap
	_guard_origin = global_position
	move_to(patrol_to)

## Guarding follows whatever it was told to protect, so an escort keeps
## up with the harvester it is covering instead of standing where the
## order was given.
func _tick_guard() -> void:
	if current_command != CommandTypes.Type.GUARD or not is_instance_valid(guard_target):
		return
	var post: Vector3 = guard_target.global_position
	_guard_origin = post
	if global_position.distance_to(post) > 8.0 \
		and (nav_agent == null or nav_agent.is_navigation_finished()):
		move_to(post)

## Acquisition considers units FIRST, then structures.
##
## Structures were previously not considered at all, which meant an
## attack-move could never engage a base: an army would arrive at the
## enemy HQ and stand there indefinitely because nothing ever became a
## target. It is why sieges never resolved for either side.
##
## Units still take precedence at equal opportunity - something shooting
## back is the more urgent problem - so this does not turn troops into
## building-obsessed sappers that ignore the defenders.
func _nearest_hostile(radius: float, attacker: AttackerComponent) -> Node:
	var unit_group: String = "enemy_units" if is_player_faction else "player_units"
	var found := _nearest_in_group(unit_group, radius, attacker)
	if found != null:
		return found

	var building_group: String = "enemy_buildings" if is_player_faction else "player_buildings"
	return _nearest_in_group(building_group, radius, attacker)

## Advancing orders ignore the leash; holding orders honour it.
func _leash_applies() -> bool:
	return current_command != CommandTypes.Type.ATTACK_MOVE \
		and current_command != CommandTypes.Type.MOVE \
		and current_command != CommandTypes.Type.PATROL

func _nearest_in_group(group: String, radius: float, attacker: AttackerComponent) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for candidate in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(candidate):
			continue
		if is_player_faction and FogHideable.is_hidden(candidate):
			continue
		if not DisguiseAbility.visible_to(candidate, is_player_faction):
			continue
		if not attacker.weapon.can_damage(candidate):
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist > radius or dist >= best_dist:
			continue
		## The leash keeps a unit holding a position from wandering off
		## after a target. It must NOT restrict a unit that was ordered to
		## advance: _guard_origin is where the order was given, so once an
		## attack-move had travelled further than the leash it rejected
		## every target in front of it and the assault simply stopped.
		if _leash_applies():
			var leash: float = STANCE_LEASH.get(stance, MAX_CHASE_DISTANCE)
			if leash > 0.0 and candidate.global_position.distance_to(_guard_origin) > leash + radius:
				continue
		best_dist = dist
		best = candidate
	return best

## Units carrying an EnterBuildingAbility (Engineer, Spy) answer a click
## on a building with their ability instead of an attack. Returns true
## when the order was consumed, so callers can fall back to attacking.
func special_order(target: Node) -> bool:
	for child in get_children():
		if child is EnterBuildingAbility and (child as EnterBuildingAbility).accepts(target):
			(child as EnterBuildingAbility).order(target as Node3D)
			return true
	return false

func has_special_ability() -> bool:
	for child in get_children():
		if child is EnterBuildingAbility:
			return true
	return false

func _physics_process(delta: float) -> void:
	if nav_agent == null or nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		if nav_agent != null:
			nav_agent.set_velocity(Vector3.ZERO)
		_tick_combat_behavior(delta)
		return

	var next_position: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0

	if direction.length() > 0.05:
		var desired_rotation: float = atan2(direction.x, direction.z)
		var turn_speed: float = stats.turn_speed if stats else 6.0
		rotation.y = lerp_angle(rotation.y, desired_rotation, clamp(turn_speed * delta, 0.0, 1.0))
		var speed: float = stats.move_speed if stats else 5.0
		velocity = direction.normalized() * speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()
	_crush_what_we_drove_over()
	_tick_combat_behavior(delta)
	_tick_unstick(delta)

## A unit that is navigating but has not actually moved for a while is
## jammed - against terrain, a building, or another unit. Re-issuing the
## destination makes the agent re-path from where it actually is, which
## frees it without teleporting anything or special-casing the terrain
## that trapped it.
func _tick_unstick(delta: float) -> void:
	if nav_agent == null or nav_agent.is_navigation_finished():
		_stuck_timer = 0.0
		return
	if global_position.distance_to(_stuck_reference) > STUCK_EPSILON:
		_stuck_reference = global_position
		_stuck_timer = 0.0
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_TIME:
		return
	_stuck_timer = 0.0
	var destination: Vector3 = nav_agent.target_position
	## Nudge sideways before re-pathing, so a unit pressed flat against a
	## wall has somewhere to go rather than immediately re-jamming.
	global_position += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	nav_agent.target_position = destination

## Armour flattens enemy infantry it drives over. Vehicles pass through
## the infantry layer, so contact cannot be read from slide collisions -
## proximity while actually moving is what counts. Only runs for vehicles
## that are moving, over the handful of enemy infantry on the field.
func _crush_what_we_drove_over() -> void:
	if stats == null or not stats.can_crush:
		return
	if velocity.length_squared() < 1.0:
		return

	var reach: float = maxf(stats.body_size.x, stats.body_size.z) * 0.5
	var enemy_group: String = "enemy_units" if is_player_faction else "player_units"
	for other in get_tree().get_nodes_in_group(enemy_group):
		if not (other is UnitBase):
			continue
		var victim := other as UnitBase
		if victim.stats == null or not victim.stats.can_be_crushed:
			continue
		var gap: float = victim.global_position.distance_to(global_position)
		if gap > reach + maxf(victim.stats.body_size.x, victim.stats.body_size.z) * 0.5:
			continue
		var victim_health: HealthComponent = victim.get_node_or_null("HealthComponent")
		if victim_health != null and not victim_health.is_dead():
			victim_health.take_damage(victim_health.max_health * 10.0, self)

func _on_died() -> void:
	## Infantry fall; vehicles burn. The difference is what tells a player
	## at a glance how much they just lost.
	if stats != null and not stats.is_infantry:
		VFX.vehicle_wreck(self, global_position)
		AudioDirector.play("explosion_small")
	else:
		VFX.impact(self, global_position + Vector3.UP * 0.6)
	MatchStats.record_unit_death(is_player_faction)
	died.emit(self)
	SelectionManager.notify_unit_removed(self)
	queue_free()
