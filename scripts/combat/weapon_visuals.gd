class_name WeaponVisuals
extends Object

## How each kind of weapon LOOKS when it fires, travels and lands.
##
## Seven classes, because seven things have to be told apart from the
## normal gameplay camera - and the damage table cannot do it. That table
## has five entries and the wrong five: a rifle and a machine gun are
## both SMALL_ARMS, a tank gun and a deck gun are both CANNON. What makes
## them distinguishable on screen is cadence, speed, trail and arc, none
## of which the damage type knows about. So the class is stated on the
## weapon as data rather than guessed from its numbers.
##
## What actually separates them at distance, in order of how well it
## reads: an ARC (only artillery lobs), a TRAIL (only rockets and
## torpedoes leave one), CADENCE (a machine gun sends several rounds per
## shot), then speed, girth and colour.
##
## Damage is NOT routed through here. It has already landed by the time
## any of this is spawned - weapons are hitscan - so a slow shell cannot
## make a unit die late, and a dropped effect cannot make it survive.

enum Class { RIFLE, MACHINE_GUN, CANNON, ANTI_ARMOR, ARTILLERY, NAVAL_GUN, TORPEDO, MELEE }

## Every round currently in flight.
const GROUP: StringName = &"projectiles"

## speed   metres/second the round appears to travel
## rounds  streaks per shot: a burst is what makes an MG read as an MG
## girth   thickness multiplier
## length  streak length multiplier
## arc     metres the shell rises above the straight line at its apex
## trail   leaves a smoke trail (rockets, torpedoes)
## muzzle  which flash to throw
## impact  what to leave where it lands
const PROFILE: Dictionary = {
	Class.RIFLE: {
		"speed": 190.0, "rounds": 1, "girth": 0.7, "length": 0.8, "arc": 0.0,
		"trail": false, "muzzle": "small", "impact": "small", "spacing": 0.0,
	},
	Class.MACHINE_GUN: {
		"speed": 200.0, "rounds": 3, "girth": 0.8, "length": 0.7, "arc": 0.0,
		"trail": false, "muzzle": "small", "impact": "small", "spacing": 0.045,
	},
	Class.CANNON: {
		"speed": 150.0, "rounds": 1, "girth": 2.0, "length": 1.3, "arc": 0.0,
		"trail": false, "muzzle": "cannon", "impact": "shell", "spacing": 0.0,
	},
	Class.ANTI_ARMOR: {
		"speed": 42.0, "rounds": 1, "girth": 1.6, "length": 1.0, "arc": 0.0,
		"trail": true, "muzzle": "rocket", "impact": "shell", "spacing": 0.0,
	},
	Class.ARTILLERY: {
		"speed": 38.0, "rounds": 1, "girth": 1.8, "length": 1.1, "arc": 7.0,
		"trail": true, "muzzle": "artillery", "impact": "explosion", "spacing": 0.0,
	},
	Class.NAVAL_GUN: {
		"speed": 110.0, "rounds": 1, "girth": 1.7, "length": 1.2, "arc": 1.8,
		"trail": false, "muzzle": "cannon", "impact": "shell", "spacing": 0.0,
	},
	Class.TORPEDO: {
		"speed": 26.0, "rounds": 1, "girth": 1.4, "length": 1.6, "arc": 0.0,
		"trail": true, "muzzle": "none", "impact": "water", "spacing": 0.0,
	},
	## Teeth. Nothing leaves the attacker, so there is no flash and no
	## round to draw - only the hit lands.
	Class.MELEE: {
		"speed": 1.0, "rounds": 0, "girth": 0.0, "length": 0.0, "arc": 0.0,
		"trail": false, "muzzle": "none", "impact": "small", "spacing": 0.0,
	},
}

## A round must stay legible without loitering: too fast and it is a
## beam, too slow and the field fills up with them.
const MIN_TRAVEL: float = 0.04
const MAX_TRAVEL: float = 1.6

## One mesh and one material per colour for the whole game. Building a
## fresh mesh and material per shot is what the old tracer did, and at
## 120 units in contact that is hundreds of throwaway resources a second.
static var _mesh: CylinderMesh = null
static var _materials: Dictionary = {}

static func _shared_mesh() -> CylinderMesh:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = 0.05
		_mesh.bottom_radius = 0.05
		_mesh.height = 1.9
		_mesh.radial_segments = 6
		_mesh.rings = 0
	return _mesh

static func _shared_material(color: Color) -> StandardMaterial3D:
	var key: String = str(color)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	_materials[key] = material
	return material

static func profile(stats: WeaponStats) -> Dictionary:
	return PROFILE.get(stats.visual_class, PROFILE[Class.RIFLE])

# ------------------------------------------------------------- muzzle

static func muzzle(context: Node, stats: WeaponStats, from: Vector3, to: Vector3) -> void:
	var direction: Vector3 = (to - from).normalized()
	match profile(stats).get("muzzle", "small"):
		"small":
			VFX.muzzle_flash(context, from, direction)
		"cannon":
			VFX.cannon_flash(context, from, direction)
		"artillery":
			VFX.artillery_flash(context, from, direction)
		"rocket":
			## A launcher's signature is the BACK-blast, not the flash:
			## the smoke goes the other way, which is the only muzzle
			## effect on the field that does.
			VFX.rocket_backblast(context, from, direction)
		_:
			pass

# --------------------------------------------------------- projectile

## Spawns the visible round(s) and returns how long the last one takes to
## arrive, so the caller can hold the impact picture until it lands.
static func projectile(context: Node, stats: WeaponStats, from: Vector3, to: Vector3) -> float:
	if not VFX.enabled:
		return 0.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return 0.0
	var distance: float = from.distance_to(to)
	if distance < 0.01:
		return 0.0

	var p: Dictionary = profile(stats)
	var travel: float = clampf(distance / float(p["speed"]), MIN_TRAVEL, MAX_TRAVEL)
	var rounds: int = int(p["rounds"])
	if rounds <= 0:
		return 0.0
	var spacing: float = float(p["spacing"])
	## A burst leaves the muzzle as several rounds in quick succession,
	## not all at once - that stagger is what the eye reads as automatic
	## fire rather than as one fat round.
	##
	## The stagger is a leading interval on each round's OWN tween, not a
	## SceneTreeTimer per round. Timer callbacks were tried and silently
	## never fired, so a machine gun put exactly one round in the air; a
	## tween is owned by the node it animates and cannot go missing.
	for i in rounds:
		_round(tree, stats, p, from, to, travel, spacing * float(i))
	return travel + spacing * float(maxi(rounds - 1, 0))

static func _round(tree: SceneTree, stats: WeaponStats, p: Dictionary,
		from: Vector3, to: Vector3, travel: float, delay: float = 0.0) -> void:
	var shot := MeshInstance3D.new()
	## Grouped, not named, so rounds in flight can be counted - by a test,
	## or by anyone chasing a frame-rate drop in a heavy firefight. A name
	## does not survive: Godot discards a colliding one and substitutes
	## @MeshInstance3D@1631, so every round after the first in a burst
	## became invisible to any search that went looking by name.
	shot.add_to_group(GROUP)
	shot.mesh = _shared_mesh()
	shot.material_override = _shared_material(stats.tracer_color)
	shot.scale = Vector3(float(p["girth"]), float(p["length"]), float(p["girth"]))
	shot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.current_scene.add_child(shot)
	shot.global_position = from
	shot.look_at(to, Vector3.UP)
	shot.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	if bool(p["trail"]):
		_attach_trail(shot, stats)

	var arc: float = float(p["arc"])
	var tween := shot.create_tween()
	if delay > 0.0:
		## Held at the muzzle and out of sight until its turn.
		shot.visible = false
		tween.tween_interval(delay)
		tween.tween_callback(func():
			if is_instance_valid(shot):
				shot.visible = true)
	if arc <= 0.01:
		tween.tween_property(shot, "global_position", to, travel)
	else:
		## A lobbed shell. The arc is the single clearest tell that a
		## shot came from artillery rather than a tank, and it is worth
		## more than any amount of colour.
		tween.tween_method(func(t: float):
			if not is_instance_valid(shot):
				return
			var flat: Vector3 = from.lerp(to, t)
			var lift: float = arc * 4.0 * t * (1.0 - t)
			var next: Vector3 = flat + Vector3.UP * lift
			## Point the shell along its own path, so it noses over at
			## the top the way a shell does.
			if next.distance_to(shot.global_position) > 0.01:
				shot.look_at(next, Vector3.UP)
				shot.rotate_object_local(Vector3.RIGHT, PI / 2.0)
			shot.global_position = next,
			0.0, 1.0, travel)
	tween.tween_callback(shot.queue_free)

## Smoke behind a rocket or a torpedo. Only ever on the slow ordnance -
## anti-armour, artillery and torpedoes all reload in 2 seconds or more,
## so the number in the air at once stays small even in a big fight.
static func _attach_trail(shot: Node3D, stats: WeaponStats) -> void:
	var wet: bool = stats.visual_class == Class.TORPEDO
	var trail := CPUParticles3D.new()
	trail.amount = 14 if wet else 18
	trail.lifetime = 0.75 if wet else 0.55
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 6.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5 if wet else 1.2
	trail.gravity = Vector3(0, 0.0 if wet else 0.7, 0)
	trail.scale_amount_min = 0.22
	trail.scale_amount_max = 0.5 if wet else 0.8
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	trail.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.85, 0.92, 1.0, 0.5) if wet \
		else Color(0.75, 0.75, 0.78, 0.55)
	material.disable_receive_shadows = true
	trail.material_override = material
	shot.add_child(trail)
	trail.emitting = true

# ------------------------------------------------------------- impact

static func impact(context: Node, stats: WeaponStats, at: Vector3) -> void:
	match profile(stats).get("impact", "small"):
		"shell":
			VFX.shell_impact(context, at)
		"explosion":
			VFX.explosion_small(context, at)
		"water":
			## A torpedo always ends in the water, so it always throws a
			## column - it is the only impact on the field that does.
			VFX.water_splash(context, at, 2.2)
		_:
			VFX.impact(context, at)
