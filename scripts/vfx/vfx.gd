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
static func _particle_texture() -> GradientTexture2D:
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
	material.albedo_texture = _particle_texture()
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	return material

## A one-shot burst that frees itself. `spread` is the cone half-angle.
static func _burst(parent: Node, position: Vector3, count: int, color: Color,
		size: float, velocity: float, lifetime: float, gravity: float,
		additive: bool = true, direction: Vector3 = Vector3.UP,
		spread: float = 45.0) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not enabled:
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
	particles.global_position = position
	particles.emitting = true

	var timer := particles.get_tree().create_timer(lifetime + 0.4)
	timer.timeout.connect(func():
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

static func artillery_flash(context: Node, position: Vector3, direction: Vector3) -> void:
	_shake(context, position, 0.10)
	var root := _scene_root(context)
	_burst(root, position, 10, FLASH_YELLOW, 1.0, 8.0, 0.2, 0.0, true,
		direction.normalized(), 20.0)
	_burst(root, position, 10, SMOKE_GREY, 1.4, 2.4, 1.1, 0.6, false, Vector3.UP, 60.0)

# ------------------------------------------------------------- impacts

static func impact(context: Node, position: Vector3) -> void:
	var root := _scene_root(context)
	_burst(root, position, 5, SPARK_WHITE, 0.18, 4.5, 0.22, -6.0, true, Vector3.UP, 70.0)
	_burst(root, position, 4, DUST_TAN, 0.45, 1.6, 0.5, -1.0, false, Vector3.UP, 70.0)

static func shell_impact(context: Node, position: Vector3) -> void:
	var root := _scene_root(context)
	_burst(root, position, 8, FIRE_ORANGE, 0.8, 5.0, 0.3, -2.0, true, Vector3.UP, 60.0)
	_burst(root, position, 10, DUST_TAN, 1.2, 3.0, 0.9, -1.5, false, Vector3.UP, 75.0)

# ---------------------------------------------------------- explosions

static func explosion_small(context: Node, position: Vector3) -> void:
	_shake(context, position, 0.18)
	var root := _scene_root(context)
	_burst(root, position, 12, FIRE_ORANGE, 1.3, 6.0, 0.45, -2.0, true, Vector3.UP, 80.0)
	_burst(root, position, 10, SMOKE_GREY, 1.8, 2.5, 1.4, 0.8, false, Vector3.UP, 60.0)

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

## A destroyed vehicle: fire, then a smoke column that outlives it, so a
## battlefield keeps a record of what happened where.
static func vehicle_wreck(context: Node, position: Vector3) -> void:
	var root := _scene_root(context)
	explosion_small(context, position)
	_burst(root, position + Vector3.UP * 0.4, 12, SMOKE_GREY, 2.4, 1.8, 3.2, 0.9,
		false, Vector3.UP, 25.0)

# ------------------------------------------------------------ ongoing

## Continuous smoke/fire for a damaged structure. Returns the node so the
## caller can free it when the building is repaired.
static func damage_plume(parent: Node, offset: Vector3, severity: int) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var particles := CPUParticles3D.new()
	particles.amount = 6 if severity < 2 else 12
	particles.lifetime = 1.8 if severity < 2 else 2.6
	particles.direction = Vector3.UP
	particles.spread = 18.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.8
	particles.gravity = Vector3(0.3, 0.9, 0.0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4 if severity < 2 else 2.2

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
		fire.scale_amount_min = 0.4
		fire.scale_amount_max = 1.0
		fire.scale_amount_curve = curve
		fire.mesh = mesh
		fire.material_override = _material(FIRE_ORANGE, true)
		particles.add_child(fire)
		fire.position = Vector3(0, -offset.y * 0.35, 0)
	return particles

# ------------------------------------------------------------- utility

static func construction_dust(context: Node, position: Vector3, radius: float) -> void:
	_burst(_scene_root(context), position, 14, DUST_TAN, radius * 0.4,
		radius * 0.7, 1.1, -0.6, false, Vector3.UP, 88.0)

static func capture_effect(context: Node, position: Vector3, color: Color) -> void:
	var root := _scene_root(context)
	_burst(root, position + Vector3.UP, 16, color, 0.9, 4.0, 0.9, -1.2, true,
		Vector3.UP, 80.0)
