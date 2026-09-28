class_name InfantryAnimator
extends Node

## Procedural limb animation for infantry (docs/ART_DIRECTION.md 18.7).
##
## Soldiers used to glide: the model was a single welded "Body" mesh, so
## there was nothing to move. They are now built jointed - every limb its
## own node with its origin ON the joint it turns about - and posed here
## from the unit's own state. No armature, no skinning, no AnimationPlayer
## and no baked tracks: a dozen trig calls per soldier per frame, which is
## what an RTS with a hundred of them on screen can afford.
##
## What it reads, and nothing else: how fast the unit is moving, whether
## it is crouched, and when it fired or was hit. That keeps the animation
## a pure function of gameplay state, so it can never drift out of sync
## with what the unit is actually doing.

## Arms come up onto the weapon. The bind pose hangs them straight down
## so the same rig can also carry a toolbox or a launcher; this is the
## rifle carry the animator applies on top.
const CARRY_PITCH: float = -0.61        # ~35 degrees
const CARRY_PITCH_CROUCH: float = -0.87 # tucked in tighter when low

## Stride. Crouching is not just slower - it is a visibly different gait:
## shorter paces, a lower body and a forward lean, so RUN and CROUCH read
## apart at a glance rather than only in the speed readout.
const RUN_SWING: float = 0.62
const CROUCH_SWING: float = 0.34
const RUN_BOB: float = 0.045
const CROUCH_BOB: float = 0.015
const CROUCH_DROP: float = 0.26
const CROUCH_LEAN: float = 0.38
const RUN_LEAN: float = 0.10
## Paces per metre travelled, so the cycle matches the ground rather than
## sliding - the thing that makes a walk cycle read as walking.
const STRIDE_RATE: float = 1.45
const IDLE_BREATH: float = 1.7

const FIRE_TIME: float = 0.18
const HIT_TIME: float = 0.26
const RECOIL: float = 0.09

var _host: Node3D
var _visual: Node3D
var _legs: Array = []          # [node, phase offset]
var _arms: Array = []
var _torso: Node3D
var _head: Node3D
var _weapon: Node3D
var _tail: Node3D
var _stance: InfantryStance

var _rest: Dictionary = {}     # node -> bind-pose transform
var _phase: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _speed: float = 0.0
var _fire_timer: float = 0.0
var _hit_timer: float = 0.0
var _last_health: float = -1.0
var _armed: bool = false

## Attach to a unit whose model carries a jointed rig. Returns null for
## anything without one, so vehicles and buildings cost nothing.
static func attach(host: Node3D, visual: Node) -> InfantryAnimator:
	if visual == null or not (visual is Node3D):
		return null
	if visual.find_child("Torso", true, false) == null:
		return null
	var anim := InfantryAnimator.new()
	anim.name = "InfantryAnimator"
	anim._host = host
	anim._visual = visual as Node3D
	host.add_child(anim)
	anim._bind()
	return anim

func _bind() -> void:
	_torso = _visual.find_child("Torso", true, false) as Node3D
	_head = _visual.find_child("Head", true, false) as Node3D
	_weapon = _visual.find_child("Weapon", true, false) as Node3D
	_tail = _visual.find_child("Tail", true, false) as Node3D
	_armed = _weapon != null

	## Two-legged and four-legged rigs differ only in which legs are in
	## which phase: a dog's diagonal pairs move together.
	for entry in [["Leg_L", 0.0], ["Leg_R", PI],
			["Leg_FL", 0.0], ["Leg_BR", 0.0],
			["Leg_FR", PI], ["Leg_BL", PI]]:
		var leg := _visual.find_child(entry[0], true, false) as Node3D
		if leg != null:
			_legs.append([leg, entry[1]])
	for name in ["Arm_L", "Arm_R"]:
		var arm := _visual.find_child(name, true, false) as Node3D
		if arm != null:
			_arms.append(arm)

	## Hang the upper body off the torso so a lean or a crouch carries the
	## arms, head and weapon with it instead of leaving them behind. The
	## exporter writes a flat list of parts, so the hierarchy is built
	## here rather than in Blender.
	for part in _arms + [_head, _weapon]:
		if part != null and part.get_parent() != _torso and _torso != null:
			part.reparent(_torso, true)

	for node in _all_parts():
		_rest[node] = node.transform
	_stance = InfantryStance.of(_host)
	if _host.get("health") != null and _host.health != null:
		_last_health = _host.health.current_health
		_host.health.health_changed.connect(func(current, _max):
			if current < _last_health:
				_hit_timer = HIT_TIME
			_last_health = current)

func _all_parts() -> Array:
	var parts: Array = []
	for pair in _legs:
		parts.append(pair[0])
	for arm in _arms:
		parts.append(arm)
	for node in [_torso, _head, _weapon, _tail]:
		if node != null:
			parts.append(node)
	return parts

## The weapon fired: kick it back and jolt the arms.
func report_fired() -> void:
	_fire_timer = FIRE_TIME

func _process(delta: float) -> void:
	if not is_instance_valid(_host) or _torso == null:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)

	## Speed from GROUND ACTUALLY COVERED, not from `velocity`. The body
	## sets velocity inside _physics_process and through the avoidance
	## callback, so a _process frame can read a stale or zeroed value -
	## measured, a soldier that had just walked 3.6m reported 0.00 m/s.
	## Displacement is also the honest input for a walk cycle: it is what
	## decides whether the feet keep pace with the ground.
	var here: Vector3 = _host.global_position
	if _last_pos == Vector3.INF:
		_last_pos = here
	var moved: float = Vector2(here.x - _last_pos.x, here.z - _last_pos.z).length()
	_last_pos = here
	## Smoothed, so a single stalled frame does not drop the unit into
	## its idle pose and back.
	_speed = lerpf(_speed, moved / maxf(delta, 0.0001), clampf(delta * 12.0, 0.0, 1.0))
	var speed: float = _speed
	var crouched: bool = _stance != null and _stance.is_crouched()
	var moving: bool = speed > 0.15

	## The cycle advances with DISTANCE, not time, so the feet keep pace
	## with the ground however fast or slow the unit is going.
	if moving:
		_phase += speed * STRIDE_RATE * delta * TAU * 0.5
	else:
		_phase += IDLE_BREATH * delta

	var swing: float = (CROUCH_SWING if crouched else RUN_SWING)
	var bob: float = (CROUCH_BOB if crouched else RUN_BOB)
	var lean: float = (CROUCH_LEAN if crouched else RUN_LEAN)
	if not moving:
		swing = 0.0
		bob *= 0.25

	_pose_legs(swing, crouched, moving)
	_pose_torso(bob, lean, crouched, moving)
	_pose_arms(swing, crouched, moving)
	_pose_head()
	_pose_weapon()
	_pose_tail(moving)

func _pose_legs(swing: float, crouched: bool, moving: bool) -> void:
	## Crouched legs stay bent even at rest - that bend is most of what
	## makes a crouch read from the side.
	var bend: float = 0.45 if crouched else 0.0
	for pair in _legs:
		var leg: Node3D = pair[0]
		if not is_instance_valid(leg):
			continue
		var offset: float = pair[1]
		var angle: float = sin(_phase + offset) * swing - bend
		if not moving:
			angle = -bend
		leg.transform = _rest[leg]
		leg.rotate_x(angle)

func _pose_torso(bob: float, lean: float, crouched: bool, moving: bool) -> void:
	var rest: Transform3D = _rest[_torso]
	## Two bobs per stride: the body rises on each footfall, not each pace.
	var rise: float = absf(sin(_phase)) * bob
	var drop: float = CROUCH_DROP if crouched else 0.0
	if not moving:
		rise = sin(_phase) * bob
	var pitch: float = lean
	## A hit throws the torso back for a moment; a shot rocks it slightly.
	if _hit_timer > 0.0:
		pitch -= (_hit_timer / HIT_TIME) * 0.45
	if _fire_timer > 0.0:
		pitch -= (_fire_timer / FIRE_TIME) * 0.09
	_torso.transform = rest
	_torso.position += Vector3(0.0, rise - drop, 0.0)
	_torso.rotate_x(pitch)

func _pose_arms(swing: float, crouched: bool, moving: bool) -> void:
	var carry: float = CARRY_PITCH_CROUCH if crouched else CARRY_PITCH
	if not _armed:
		## Empty hands swing freely; a carried weapon does not.
		carry = 0.0
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		if not is_instance_valid(arm):
			continue
		## Arms counter-swing against the legs, and only a little when
		## they are holding something up.
		var free: float = 0.35 if _armed else 1.0
		var angle: float = carry
		if moving:
			angle += -sin(_phase + (PI if i == 1 else 0.0)) * swing * free
		if _fire_timer > 0.0:
			angle += (_fire_timer / FIRE_TIME) * 0.22
		arm.transform = _rest[arm]
		arm.rotate_x(angle)

func _pose_head() -> void:
	if _head == null or not is_instance_valid(_head):
		return
	_head.transform = _rest[_head]
	## The head stays level while the torso leans, the way a person's
	## does - it is a small thing that stops a crouch looking like a bow.
	var counter: float = -_torso.rotation.x * 0.6
	if _hit_timer > 0.0:
		counter -= (_hit_timer / HIT_TIME) * 0.3
	_head.rotate_x(counter)

func _pose_weapon() -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		return
	_weapon.transform = _rest[_weapon]
	if _fire_timer <= 0.0:
		return
	## Recoil runs back along the barrel (+Z is behind a -Z-forward unit)
	## and lifts the muzzle, then settles.
	var t: float = _fire_timer / FIRE_TIME
	_weapon.position += Vector3(0.0, 0.0, RECOIL * t)
	_weapon.rotate_x(0.35 * t)

func _pose_tail(moving: bool) -> void:
	if _tail == null or not is_instance_valid(_tail):
		return
	_tail.transform = _rest[_tail]
	_tail.rotate_y(sin(_phase * (2.0 if moving else 1.0)) * 0.35)
