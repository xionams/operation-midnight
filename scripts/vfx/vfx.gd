class_name VFX
extends RefCounted

## Lightweight battlefield effects.
##
## Built in code rather than as scene files for the same reason the rest
## of the game is: one place to read, no binary to diff. Everything here
## is CPUParticles3D with small counts and a shared unshaded material -
## chosen for Android, where a few dozen simultaneous GPU particle
## systems cost more than the effect is worth.
##
## Readability beats realism (art direction section 1). A player must be
## able to tell a tank firing from a tank dying at a glance, so the two
## differ in colour and silhouette, not in fidelity.

const FLASH_YELLOW: Color = Color(1.0, 0.85, 0.45)
const FIRE_ORANGE: Color = Color(0.88, 0.48, 0.17)
const SMOKE_GREY: Color = Color(0.32, 0.31, 0.30)
const DUST_TAN: Color = Color(0.60, 0.56, 0.44)
const SPARK_WHITE: Color = Color(1.0, 0.95, 0.80)

static var _dot: GradientTexture2D = null
## Cleared by OM_NO_VFX, so the effect layer can be measured separately
## from models and scenery. Also the switch to reach for if a low-end
## device needs the frame budget back.
static var enabled: bool = OS.get_environment("OM_NO_VFX").is_empty()

## One soft radial dot shared by every effect in the game.
## A soft round dot, white at the centre and fading to nothing at the
## rim. Every particle quad needs it: without a mask a quad renders as
## its own hard-edged rectangle, and a handful of overlapping ones stack
## into a solid white card lying across the battlefield.
static func soft_dot() -> GradientTexture2D:
	if _dot != null:
		return _dot
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	_dot = GradientTexture2D.new()
	_dot.gradient = gradient
	_dot.fill = GradientTexture2D.FILL_RADIAL
	_dot.fill_from = Vector2(0.5, 0.5)
	_dot.fill_to = Vector2(1.0, 0.5)
	_dot.width = 32
	_dot.height = 32
	return _dot

static func _material(color: Color, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	material.albedo_texture = soft_dot()
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	return material

## A one-shot burst that frees itself. `spread` is the cone half-angle.
## The most emitters that may be alive at once.
##
## Every other visual thing in the game already has a ceiling - corpses
## at 40, wrecks at 24, ground marks per layer - but bursts had none, and
## they are the one spawned straight off the trigger. Sixty units in
## contact firing several times a second is the case that matters: each
## shot wants a muzzle flash and an impact, and without a limit a big
## engagement can put hundreds of emitters in the air at once, each one a
## node with its own material and its own transparent overdraw.
##
## Dropped rather than queued when the field is full. A flash that
## arrives late is worse than one that never came: the shot it belonged
## to is long gone.
const MAX_BURSTS: int = 48
const BURST_GROUP: StringName = &"vfx_bursts"

static var _live_bursts: int = 0

static func _burst(parent: Node, position: Vector3, count: int, color: Color,
		size: float, velocity: float, lifetime: float, gravity: float,
		additive: bool = true, direction: Vector3 = Vector3.UP,
		spread: float = 45.0) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not enabled:
		return null
	if _live_bursts >= MAX_BURSTS:
		return null
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.direction = direction
	particles.spread = spread
	particles.initial_velocity_min = velocity * 0.55
	particles.initial_velocity_max = velocity
	particles.gravity = Vector3(0, gravity, 0)
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	particles.damping_min = velocity * 0.4
	particles.damping_max = velocity * 0.8

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = curve

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	particles.mesh = mesh
	particles.material_override = _material(color, additive)

	parent.add_child(particles)
	particles.add_to_group(BURST_GROUP)
	particles.global_position = position
	particles.emitting = true
	_live_bursts += 1

	var timer := particles.get_tree().create_timer(lifetime + 0.4)
	timer.timeout.connect(func():
		_live_bursts = maxi(_live_bursts - 1, 0)
		if is_instance_valid(particles):
			particles.queue_free())
	return particles

static func _scene_root(node: Node) -> Node:
	if node == null or not is_instance_valid(node) or node.get_tree() == null:
		return null
	return node.get_tree().current_scene

# ------------------------------------------------------------- weapons

## Small arms. Deliberately brief and small - twenty rifles firing must
## not white out the screen.
static func muzzle_flash(context: Node, position: Vector3, direction: Vector3) -> void:
	_burst(_scene_root(context), position, 4, FLASH_YELLOW, 0.28, 3.0, 0.08, 0.0,
		true, direction.normalized(), 12.0)

## Tank main gun: a bigger flash plus a dust kick, because the cannon is
## the loudest thing on the field and should look like it.
static func cannon_flash(context: Node, position: Vector3, direction: Vector3) -> void:
	var root := _scene_root(context)
	_burst(root, position, 8, FLASH_YELLOW, 0.75, 7.0, 0.14, 0.0, true,
		direction.normalized(), 16.0)
	_burst(root, position, 6, SMOKE_GREY, 0.9, 2.2, 0.55, 0.4, false,
		direction.normalized(), 40.0)

## A launcher's signature is the back-blast: smoke out of the REAR of
## the tube, away from the target. It is the only muzzle effect on the
## field that throws its smoke backwards, which is what lets an
## anti-armour team be told from a rifleman at a glance.
static func rocket_backblast(context: Node, position: Vector3, direction: Vector3) -> void:
	var root := _scene_root(context)
	var forward: Vector3 = direction.normalized()
	_burst(root, position, 4, FLASH_YELLOW, 0.36, 3.0, 0.1, 0.0, true, forward, 14.0)
	_burst(root, position - forward * 0.4, 9, SMOKE_GREY, 1.1, 3.4, 0.7, 0.35,
		false, -forward, 34.0)

static func artillery_flash(context: Node, position: Vector3, direction: Vector3) -> void:
	_shake(context, position, 0.10)
	var root := _scene_root(context)
	_burst(root, position, 10, FLASH_YELLOW, 1.0, 8.0, 0.2, 0.0, true,
		direction.normalized(), 20.0)
	_burst(root, position, 10, SMOKE_GREY, 1.4, 2.4, 1.1, 0.6, false, Vector3.UP, 60.0)

# ------------------------------------------------------------- impacts

static func impact(context: Node, position: Vector3) -> void:
	if _on_water(position):
		water_splash(context, position, 0.5)
		return
	var root := _scene_root(context)
	_burst(root, position, 5, SPARK_WHITE, 0.18, 4.5, 0.22, -6.0, true, Vector3.UP, 70.0)
	_burst(root, position, 4, DUST_TAN, 0.45, 1.6, 0.5, -1.0, false, Vector3.UP, 70.0)

static func shell_impact(context: Node, position: Vector3) -> void:
	if _on_water(position):
		water_splash(context, position, 1.0)
		return
	var root := _scene_root(context)
	_burst(root, position, 8, FIRE_ORANGE, 0.8, 5.0, 0.3, -2.0, true, Vector3.UP, 60.0)
	_burst(root, position, 10, DUST_TAN, 1.2, 3.0, 0.9, -1.5, false, Vector3.UP, 75.0)
	GroundMarks.scorch(context, position, 0.9)

# ---------------------------------------------------------- explosions

static func explosion_small(context: Node, position: Vector3) -> void:
	_shake(context, position, 0.18)
	var root := _scene_root(context)
	_burst(root, position, 12, FIRE_ORANGE, 1.3, 6.0, 0.45, -2.0, true, Vector3.UP, 80.0)
	_burst(root, position, 10, SMOKE_GREY, 1.8, 2.5, 1.4, 0.8, false, Vector3.UP, 60.0)
	if _on_water(position):
		water_splash(context, position, 1.4)
	else:
		GroundMarks.scorch(context, position, 1.8)

## Shakes whatever camera is watching, if it can see the blast.
static func _shake(context: Node, position: Vector3, strength: float) -> void:
	var tree := context.get_tree() if context != null and is_instance_valid(context) else null
	if tree == null:
		return
	for camera in tree.get_nodes_in_group("rts_camera"):
		if is_instance_valid(camera) and camera.has_method("shake"):
			camera.shake(strength, position)

static func explosion_large(context: Node, position: Vector3) -> void:
	_shake(context, position, 0.55)
	var root := _scene_root(context)
	_burst(root, position + Vector3.UP * 0.5, 20, FLASH_YELLOW, 1.8, 9.0, 0.35, -1.0,
		true, Vector3.UP, 85.0)
	_burst(root, position + Vector3.UP * 0.8, 18, FIRE_ORANGE, 2.6, 5.5, 0.9, -1.5,
		true, Vector3.UP, 80.0)
	_burst(root, position + Vector3.UP, 16, SMOKE_GREY, 3.4, 3.0, 2.2, 1.2,
		false, Vector3.UP, 55.0)
	_burst(root, position, 10, DUST_TAN, 2.0, 4.5, 1.2, -1.0, false, Vector3.UP, 88.0)
	## A structure going up leaves a burn the size of its footprint, which
	## is what makes a razed base still read as a razed base an hour later.
	GroundMarks.scorch(context, position, 4.2)

## A destroyed vehicle: fire, then a smoke column that outlives it, so a
## battlefield keeps a record of what happened where.
static func vehicle_wreck(context: Node, position: Vector3) -> void:
	var root := _scene_root(context)
	explosion_small(context, position)
	_burst(root, position + Vector3.UP * 0.4, 12, SMOKE_GREY, 2.4, 1.8, 3.2, 0.9,
		false, Vector3.UP, 25.0)

# ------------------------------------------------------------ ongoing

## Flame for a structure that is genuinely on its way out.
##
## Smoke alone does not say "this one is nearly gone" - a building at 55%
## and one at 15% both just smoked, differing in shade. Fire is the tell,
## and it has to be additive and bright or it disappears against a
## daylit roof at gameplay zoom.
##
## Particles only, deliberately: a flickering light per burning building
## is what sells fire close up, and also what a mobile renderer cannot
## afford once half a base is alight.
static func structure_fire(parent: Node, offset: Vector3, size: float = 1.0) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not enabled:
		return null
	var fire := CPUParticles3D.new()
	fire.amount = 14
	fire.lifetime = 0.7
	fire.direction = Vector3.UP
	fire.spread = 14.0
	fire.initial_velocity_min = 1.4 * size
	fire.initial_velocity_max = 3.2 * size
	fire.gravity = Vector3(0.0, 1.4, 0.0)
	fire.scale_amount_min = 0.5 * size
	fire.scale_amount_max = 1.5 * size
	## Emit across the roof rather than from one point, so a big
	## structure burns along its length instead of sprouting a candle.
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(size * 1.1, 0.2, size * 1.1)

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	fire.scale_amount_curve = curve

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.35))
	ramp.set_color(1, Color(0.85, 0.22, 0.05))
	fire.color_ramp = ramp

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	fire.mesh = mesh
	fire.material_override = _material(Color(1.0, 0.75, 0.35), true)

	parent.add_child(fire)
	fire.position = offset
	fire.emitting = true
	return fire

## Continuous smoke/fire for a damaged structure. Returns the node so the
## caller can free it when the building is repaired.
## `size` scales the whole effect. A structure's plume on a tank looks
## like the tank is already dead; a tank's plume on a structure is not
## visible at all. Same shape, different scale.
static func damage_plume(parent: Node, offset: Vector3, severity: int,
		size: float = 1.0) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent):
		return null
	if not enabled:
		return null
	var particles := CPUParticles3D.new()
	particles.amount = 6 if severity < 2 else 12
	particles.lifetime = (1.8 if severity < 2 else 2.6) * size
	particles.direction = Vector3.UP
	particles.spread = 18.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.8
	particles.gravity = Vector3(0.3, 0.9, 0.0)
	particles.initial_velocity_min *= size
	particles.initial_velocity_max *= size
	particles.scale_amount_min = 0.6 * size
	particles.scale_amount_max = (1.4 if severity < 2 else 2.2) * size

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 0.1))
	particles.scale_amount_curve = curve

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	particles.mesh = mesh
	particles.material_override = _material(
		SMOKE_GREY if severity < 2 else Color(0.42, 0.34, 0.30), false)

	parent.add_child(particles)
	particles.position = offset
	particles.emitting = true

	## Heavy damage burns as well as smokes.
	if severity >= 2:
		var fire := CPUParticles3D.new()
		fire.amount = 8
		fire.lifetime = 0.7
		fire.direction = Vector3.UP
		fire.spread = 12.0
		fire.initial_velocity_min = 1.0
		fire.initial_velocity_max = 2.2
		fire.gravity = Vector3.ZERO
		fire.scale_amount_min = 0.4 * size
		fire.scale_amount_max = 1.0 * size
		fire.scale_amount_curve = curve
		fire.mesh = mesh
		fire.material_override = _material(FIRE_ORANGE, true)
		particles.add_child(fire)
		fire.position = Vector3(0, -offset.y * 0.35, 0)
		## ...and throws sparks: the "about to go" cue that smoke alone,
		## which stage 1 also has, cannot give.
		var sparks := CPUParticles3D.new()
		sparks.amount = 5
		sparks.lifetime = 0.5
		sparks.explosiveness = 0.6
		sparks.direction = Vector3.UP
		sparks.spread = 70.0
		sparks.initial_velocity_min = 2.5 * size
		sparks.initial_velocity_max = 5.0 * size
		sparks.gravity = Vector3(0, -9.0, 0)
		sparks.scale_amount_min = 0.08 * size
		sparks.scale_amount_max = 0.18 * size
		sparks.mesh = mesh
		sparks.material_override = _material(SPARK_WHITE, true)
		particles.add_child(sparks)
		sparks.position = Vector3(0, -offset.y * 0.2, 0)
	return particles

# ---------------------------------------------------------------- water

const FOAM_WHITE: Color = Color(0.88, 0.93, 0.95)
const SPRAY_BLUE: Color = Color(0.62, 0.78, 0.84)

static func _on_water(position: Vector3) -> bool:
	return Water.has_water() and Water.is_water(position.x, position.z) \
		and position.y < Water.level + 2.0

## A shell into the sea: a white column and a ring of spray instead of
## dust and a scorch mark the seabed would never show.
static func water_splash(context: Node, position: Vector3, size: float = 1.0) -> void:
	var root := _scene_root(context)
	var at := Vector3(position.x, Water.level + 0.05, position.z)
	_burst(root, at, int(8 * size) + 4, FOAM_WHITE, 0.7 * size, 7.5 * size, 0.8, -9.0,
		false, Vector3.UP, 12.0)
	_burst(root, at, int(10 * size) + 4, SPRAY_BLUE, 0.9 * size, 3.5 * size, 0.7, -4.0,
		false, Vector3.UP, 80.0)

## The foam trail behind a moving hull. One small emitter per ship,
## emitting only while under way (ModelAnimator toggles it), in world
## space so the trail stays where the ship has been.
static func wake(parent: Node3D, stern: Vector3, width: float) -> CPUParticles3D:
	if parent == null or not enabled:
		return null
	var p := CPUParticles3D.new()
	p.name = "Wake"
	p.local_coords = false
	p.emitting = false
	p.amount = 20
	p.lifetime = 2.0
	p.direction = Vector3(0, 0, 1)
	p.spread = 35.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.4, 0.0, 0.2)
	p.scale_amount_min = width * 0.5
	p.scale_amount_max = width * 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	curve.max_value = 2.0
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.75))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	p.mesh = mesh
	p.material_override = _material(FOAM_WHITE, false)
	parent.add_child(p)
	p.position = stern
	return p

## Bubbles over a submerged submarine: the owner's cue that it is down
## (the enemy never sees them - they hide with the hull).
static func bubbles(parent: Node3D, length: float) -> CPUParticles3D:
	if parent == null or not enabled:
		return null
	var p := CPUParticles3D.new()
	p.name = "Bubbles"
	p.emitting = false
	p.amount = 10
	p.lifetime = 1.1
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.1, length * 0.4)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	p.mesh = mesh
	p.material_override = _material(FOAM_WHITE, false)
	parent.add_child(p)
	p.position = Vector3(0, 0.4, 0)
	return p

# ----------------------------------------------------------- damage tint

static var _tints: Array = []

## Darkens a MODEL as it takes damage: 0 clean, 1 worn, 2 burnt. An
## overlay rather than a new material, so every model keeps sharing its
## five materials, and the tint costs one extra pass only on what is
## actually damaged.
static func damage_tint(root: Node, stage: int) -> void:
	if root == null or not is_instance_valid(root):
		return
	if _tints.is_empty():
		for c in [Color(0.70, 0.68, 0.66), Color(0.42, 0.37, 0.34)]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.albedo_color = c
			m.disable_receive_shadows = true
			_tints.append(m)
	var overlay: Material = null if stage <= 0 else _tints[mini(stage, 2) - 1]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = overlay

# ------------------------------------------------------------- utility

static func construction_dust(context: Node, position: Vector3, radius: float) -> void:
	_burst(_scene_root(context), position, 14, DUST_TAN, radius * 0.4,
		radius * 0.7, 1.1, -0.6, false, Vector3.UP, 88.0)

static func capture_effect(context: Node, position: Vector3, color: Color) -> void:
	var root := _scene_root(context)
	_burst(root, position + Vector3.UP, 16, color, 0.9, 4.0, 0.9, -1.2, true,
		Vector3.UP, 80.0)
