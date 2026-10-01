class_name InfantryAnimator
extends Node

## Procedural limb animation for infantry, posed onto a Skeleton3D.
##
## The poses here are the ones Phase 4 introduced - idle, walk, run,
## crouch, aim, fire, flinch - and they are still computed rather than
## played back: a walk cycle that is a few lines of trig needs no
## animation assets, no state machine and no retargeting, and it can take
## its timing from the ground the unit actually covered.
##
## What changed is what they drive. Each limb used to be its own scene
## node with its own mesh, which cost FOURTEEN draw calls a soldier -
## seven of them paid again in the shadow pass - and at 120 infantry that
## was 1,680 calls for the men alone. One skinned mesh on a thirteen-bone
## armature draws in three, whatever the pose.
##
## Bone poses in Godot are relative to the rest pose, so an untouched
## bone needs no work and zero means "as modelled".

const CARRY_PITCH: float = -0.61
const CARRY_PITCH_CROUCH: float = -0.87
const AIM_PITCH: float = -1.42
const AIM_PITCH_CROUCH: float = -1.30
const AIM_BLEND: float = 7.0

const RUN_SWING: float = 0.62
const CROUCH_SWING: float = 0.34
const RUN_BOB: float = 0.045
const CROUCH_BOB: float = 0.015
const CROUCH_DROP: float = 0.26
const CROUCH_LEAN: float = 0.38
const RUN_LEAN: float = 0.10
const STRIDE_RATE: float = 1.45
const IDLE_BREATH: float = 1.7

const FIRE_TIME: float = 0.18
const HIT_TIME: float = 0.26
const RECOIL: float = 0.09

## Beyond this the small motions stop: a flinch and a muzzle kick are
## sub-pixel at the far end of the camera's range, and skipping them
## there costs nothing anyone can see. The gait keeps running - a frozen
## soldier reads as a bug at any distance.
const DETAIL_RANGE: float = 46.0

## Diagnostic: OM_NO_POSE leaves every skeleton at its rest pose, which
## is how a bind-pose fault is told apart from a posing fault. Resolved
## once - this is read by every soldier on every frame.
static var REST_POSE_ONLY: bool = not OS.get_environment("OM_NO_POSE").is_empty()

var _host: Node3D
var _visual: Node3D
var _skeleton: Skeleton3D
var _stance: InfantryStance
var _attacker: Node = null

## Bone indices, resolved once. -1 means this rig has no such bone, which
## is how the dog shares this script without having arms.
var _b: Dictionary = {}
## Per bone: its rest rotation, and the directions in ITS OWN space that
## correspond to world right and world up.
##
## set_bone_pose_rotation replaces a bone's rotation outright rather than
## adding to it, so handing it a bare Quaternion(RIGHT, angle) throws the
## rest orientation away - which collapsed every soldier into a flattened
## heap while the bind pose itself was perfectly correct. The pose has to
## be composed ONTO the rest, and the axis has to be expressed in the
## bone's frame, because these bones point down their own length rather
## than along any world axis.
var _rest_rot: Dictionary = {}
var _axis_x: Dictionary = {}
var _axis_y: Dictionary = {}
var _rest_pelvis: Vector3 = Vector3.ZERO

var _phase: float = 0.0
var _fire_timer: float = 0.0
var _hit_timer: float = 0.0
var _last_health: float = -1.0
var _armed: bool = false
var _aim: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _speed: float = 0.0

const HUMAN_BONES := ["pelvis", "spine", "head", "upper_arm.L", "lower_arm.L",
	"upper_arm.R", "lower_arm.R", "upper_leg.L", "lower_leg.L",
	"upper_leg.R", "lower_leg.R", "weapon"]
const DOG_BONES := ["spine", "neck", "head", "tail",
	"leg.FL", "leg.FR", "leg.BL", "leg.BR"]

## Attaches to anything whose model carries a skeleton. Vehicles have
## none and get nothing.
static func attach(host: Node3D, visual: Node) -> InfantryAnimator:
	if visual == null or not (visual is Node3D):
		return null
	var skeleton := _find_skeleton(visual)
	if skeleton == null:
		return null
	var anim := InfantryAnimator.new()
	anim.name = "InfantryAnimator"
	anim._host = host
	anim._visual = visual as Node3D
	anim._skeleton = skeleton
	host.add_child(anim)
	anim._bind()
	return anim

static func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _bind() -> void:
	for name in HUMAN_BONES + DOG_BONES:
		var index: int = _skeleton.find_bone(name)
		_b[name] = index
		if index < 0:
			continue
		## Two different rest transforms, for two different jobs.
		##
		## The rotation to compose onto is the LOCAL rest, because a bone
		## pose is expressed relative to its parent. The axis to turn
		## about has to come from the GLOBAL rest: get_bone_rest is
		## parent-relative, so inverting it yields the parent's idea of
		## "right", and three joints down a chain that points somewhere
		## else entirely - it swung the arms out sideways instead of
		## forward.
		_rest_rot[name] = _skeleton.get_bone_rest(index).basis \
			.orthonormalized().get_rotation_quaternion()
		var world: Basis = _skeleton.get_bone_global_rest(index).basis.orthonormalized()
		_axis_x[name] = (world.inverse() * Vector3.RIGHT).normalized()
		_axis_y[name] = (world.inverse() * Vector3.UP).normalized()
	_armed = _b.get("weapon", -1) >= 0
	if _b.get("pelvis", -1) >= 0:
		_rest_pelvis = _skeleton.get_bone_rest(_b["pelvis"]).origin
	_stance = InfantryStance.of(_host)
	if _host.get("health") != null and _host.health != null:
		_last_health = _host.health.current_health
		_host.health.health_changed.connect(func(current, _max):
			if current < _last_health:
				_hit_timer = HIT_TIME
			_last_health = current)

func is_quadruped() -> bool:
	return _b.get("leg.FL", -1) >= 0

## The weapon fired: kick it back and jolt the arms.
func report_fired() -> void:
	_fire_timer = FIRE_TIME

func _pose_bone(bone: String, angle_x: float, angle_y: float = 0.0) -> void:
	var index: int = _b.get(bone, -1)
	if index < 0:
		return
	var turn := Quaternion(_axis_x[bone], angle_x)
	if not is_zero_approx(angle_y):
		turn *= Quaternion(_axis_y[bone], angle_y)
	_skeleton.set_bone_pose_rotation(index, _rest_rot[bone] * turn)

func _process(delta: float) -> void:
	if not is_instance_valid(_host) or _skeleton == null:
		return
	if REST_POSE_ONLY:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)

	## Speed from ground actually covered, not from `velocity`: the body
	## sets velocity inside _physics_process and through the avoidance
	## callback, so a _process frame can read a stale or zeroed value.
	var here: Vector3 = _host.global_position
	if _last_pos == Vector3.INF:
		_last_pos = here
	var moved: float = Vector2(here.x - _last_pos.x, here.z - _last_pos.z).length()
	_last_pos = here
	_speed = lerpf(_speed, moved / maxf(delta, 0.0001), clampf(delta * 12.0, 0.0, 1.0))

	var crouched: bool = _stance != null and _stance.is_crouched()
	var moving: bool = _speed > 0.15
	if moving:
		_phase += _speed * STRIDE_RATE * delta * TAU * 0.5
	else:
		_phase += IDLE_BREATH * delta

	if _attacker == null or not is_instance_valid(_attacker):
		_attacker = _host.get_node_or_null("AttackerComponent")
	var engaged: bool = _fire_timer > 0.0 or (_attacker != null
		and is_instance_valid(_attacker) and is_instance_valid(_attacker.target))
	_aim = move_toward(_aim, 1.0 if engaged else 0.0, delta * AIM_BLEND)

	if is_quadruped():
		_pose_dog(moving)
		return
	_pose_human(crouched, moving, _near_enough())

## Is the camera close enough for the small motions to be worth posing?
func _near_enough() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	return camera.global_position.distance_squared_to(_host.global_position) \
		< DETAIL_RANGE * DETAIL_RANGE

func _pose_human(crouched: bool, moving: bool, detailed: bool) -> void:
	var swing: float = (CROUCH_SWING if crouched else RUN_SWING) if moving else 0.0
	var bob: float = CROUCH_BOB if crouched else RUN_BOB
	var lean: float = CROUCH_LEAN if crouched else RUN_LEAN
	if not moving:
		bob *= 0.25

	## Legs. Crouched legs stay bent even at rest; that bend is most of
	## what makes a crouch read from the side.
	var bend: float = 0.45 if crouched else 0.0
	_pose_bone("upper_leg.L", sin(_phase) * swing - bend)
	_pose_bone("upper_leg.R", sin(_phase + PI) * swing - bend)
	_pose_bone("lower_leg.L", bend * 1.3)
	_pose_bone("lower_leg.R", bend * 1.3)

	## Pelvis carries the bob and the crouch drop.
	var rise: float = (absf(sin(_phase)) if moving else sin(_phase)) * bob
	var pelvis: int = _b.get("pelvis", -1)
	if pelvis >= 0:
		_skeleton.set_bone_pose_position(pelvis,
			_rest_pelvis + Vector3(0.0, rise - (CROUCH_DROP if crouched else 0.0), 0.0))

	## Spine leans, squares up when aiming, and takes the flinch.
	var pitch: float = lerpf(lean, lean * 0.45, _aim)
	if detailed:
		if _hit_timer > 0.0:
			pitch -= (_hit_timer / HIT_TIME) * 0.45
		if _fire_timer > 0.0:
			pitch -= (_fire_timer / FIRE_TIME) * 0.09
	_pose_bone("spine", pitch)
	## The head stays level while the torso leans, the way a person's
	## does - it stops a crouch looking like a bow.
	_pose_bone("head", -pitch * 0.6)

	## Arms. A carried weapon barely swings; one held on target swings
	## less still, and that stillness is most of what reads as aiming.
	var carry: float = CARRY_PITCH_CROUCH if crouched else CARRY_PITCH
	var aimed: float = AIM_PITCH_CROUCH if crouched else AIM_PITCH
	if not _armed:
		carry = 0.0
		aimed = 0.0
	var base: float = lerpf(carry, aimed, _aim)
	var free: float = (0.35 if _armed else 1.0) * (1.0 - _aim * 0.8)
	var kick: float = (_fire_timer / FIRE_TIME) * 0.22 if (detailed and _fire_timer > 0.0) else 0.0
	_pose_bone("upper_arm.L", base - sin(_phase) * swing * free + kick)
	_pose_bone("upper_arm.R", base - sin(_phase + PI) * swing * free + kick)
	## A slight elbow keeps the arms from reading as planks.
	_pose_bone("lower_arm.L", -0.25 * (1.0 - _aim * 0.5))
	_pose_bone("lower_arm.R", -0.25 * (1.0 - _aim * 0.5))

	## Recoil runs back along the barrel and lifts the muzzle.
	var weapon: int = _b.get("weapon", -1)
	if weapon >= 0:
		if detailed and _fire_timer > 0.0:
			var t: float = _fire_timer / FIRE_TIME
			_pose_bone("weapon", 0.35 * t)
		else:
			_pose_bone("weapon", 0.0)

func _pose_dog(moving: bool) -> void:
	var swing: float = 0.55 if moving else 0.0
	## Diagonal pairs together, which is what a trot looks like.
	_pose_bone("leg.FL", sin(_phase) * swing)
	_pose_bone("leg.BR", sin(_phase) * swing)
	_pose_bone("leg.FR", sin(_phase + PI) * swing)
	_pose_bone("leg.BL", sin(_phase + PI) * swing)
	_pose_bone("spine", sin(_phase * 2.0) * 0.04)
	_pose_bone("head", -sin(_phase * 2.0) * 0.05 - (0.25 if _hit_timer > 0.0 else 0.0))
	_pose_bone("tail", 0.0, sin(_phase * (2.0 if moving else 1.0)) * 0.35)
