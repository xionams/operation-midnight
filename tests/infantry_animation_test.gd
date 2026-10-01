extends Node

## Infantry must move their limbs, and RUN must not look like CROUCH.
##
## The poses are procedural and now drive a Skeleton3D: a soldier is one
## skinned mesh on a thirteen-bone armature rather than a dozen separate
## MeshInstance3D limbs, which took him from fourteen draw calls to two.
## These checks are about MEASURED motion - how far a leg actually
## swings, how much lower a crouched body sits - so they survived the
## change of what the motion drives.

const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const DOG := preload("res://config/units/attack_dog.tres")
const TANK := preload("res://config/units/assault_vehicle.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-58s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _spawn(stats, pos: Vector3, player: bool = true) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	## Faction BEFORE the node enters the tree: _ready reads it to pick
	## groups and collision layers, so flipping it afterwards leaves a
	## unit that is nominally hostile but registered as friendly.
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	return u

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## How far a BONE has turned FROM ITS REST POSE, and how high it rides,
## while the unit walks.
##
## Measured off the skeleton rather than a scene node: there are no limb
## nodes any more, and the bone pose is what the skin follows. The angle
## is taken as a delta from rest - a raw euler on a bone whose rest
## orientation already points down a limb wraps past PI and reports a
## motionless leg as swinging a full turn.
func _tilt_from_rest(skeleton: Skeleton3D, index: int) -> float:
	var rest: Basis = skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var now: Basis = skeleton.get_bone_global_pose(index).basis.orthonormalized()
	return (now * rest.inverse()).get_euler().x

func _swing_of(unit: Node, bone_name: String, seconds: float) -> Dictionary:
	var anim = unit.get_node_or_null("InfantryAnimator")
	var skeleton: Skeleton3D = anim._skeleton
	var index: int = skeleton.find_bone(bone_name)
	var lo: float = INF
	var hi: float = -INF
	var low_y: float = INF
	var high_y: float = -INF
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame
		if not is_instance_valid(skeleton) or index < 0:
			break
		var pitch: float = _tilt_from_rest(skeleton, index)
		lo = minf(lo, pitch)
		hi = maxf(hi, pitch)
		var y: float = skeleton.get_bone_global_pose(index).origin.y
		low_y = minf(low_y, y)
		high_y = maxf(high_y, y)
	return {"swing": hi - lo, "low": lo, "high": hi, "y": low_y, "y_high": high_y}

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	FogOfWar.enabled = false
	await _frames(6)

	var base: Vector3 = _main.map.player_base

	# --- the rig arrived intact ---
	var soldier = _spawn(SOLDIER, base + Vector3(10, 0, 10))
	await _frames(6)
	var anim = soldier.get_node_or_null("InfantryAnimator")
	_check("A soldier gets an animator", anim != null)
	if anim == null:
		print("TEST| ---- %d failure(s) ----" % _fails.size())
		print("TEST| DONE")
		get_tree().quit()
		return
	var skeleton: Skeleton3D = anim._skeleton
	_check("The soldier is skinned to a skeleton", skeleton != null)
	var missing: Array = []
	for bone in ["pelvis", "spine", "head", "upper_arm.L", "lower_arm.R",
			"upper_leg.L", "lower_leg.R", "weapon"]:
		if skeleton.find_bone(bone) < 0:
			missing.append(bone)
	_check("The skeleton carries the bones the poses need",
		missing.is_empty(), "missing %s" % str(missing))

	## The whole man is ONE drawn body. This is the point of the rig: a
	## limb per scene node cost fourteen draw calls a soldier.
	var meshes: int = _count_meshes(anim._visual)
	_check("A soldier is one skinned mesh, not a pile of limbs", meshes == 1,
		"%d MeshInstance3D" % meshes)

	# --- walking actually swings the legs ---
	var from: Vector3 = soldier.global_position
	soldier.move_to(base + Vector3(10, 0, 44))
	await _frames(20)
	for i in 30:
		await get_tree().process_frame
	_check("The soldier actually walks when ordered",
		from.distance_to(soldier.global_position) > 3.0,
		"moved %.2fm" % from.distance_to(soldier.global_position))
	var run := await _swing_of(soldier, "upper_leg.L", 2.5)
	_check("Walking swings the legs", run["swing"] > 0.25,
		"%.2f rad" % run["swing"])
	var run_torso := await _swing_of(soldier, "pelvis", 1.5)
	_check("The body bobs while walking", run_torso["y_high"] - run_torso["y"] > 0.005,
		"%.3f m" % (run_torso["y_high"] - run_torso["y"]))
	## The lean is carried by the spine; the pelvis only takes the bob
	## and the crouch drop.
	var run_spine := await _swing_of(soldier, "spine", 1.0)
	var run_lean: float = absf(run_spine["high"])
	var run_height: float = run_torso["y_high"]

	# --- crouching looks different, not merely slower ---
	var stance = InfantryStance.of(soldier)
	_check("The soldier carries a posture", stance != null)
	stance.set_mode(InfantryStance.Mode.CROUCH)
	soldier.move_to(base + Vector3(10, 0, 70))
	await _frames(20)
	var crouch := await _swing_of(soldier, "upper_leg.L", 2.5)
	var crouch_torso := await _swing_of(soldier, "pelvis", 1.5)
	var crouch_spine := await _swing_of(soldier, "spine", 1.0)
	_check("CROUCH takes shorter paces than RUN",
		crouch["swing"] < run["swing"] * 0.8,
		"crouch %.2f vs run %.2f rad" % [crouch["swing"], run["swing"]])
	_check("CROUCH carries the body visibly lower",
		crouch_torso["y_high"] < run_height - 0.1,
		"crouch %.2fm vs run %.2fm" % [crouch_torso["y_high"], run_height])
	_check("CROUCH leans further forward",
		absf(crouch_spine["high"]) > run_lean + 0.1,
		"crouch %.2f vs run %.2f rad" % [absf(crouch_spine["high"]), run_lean])

	stance.set_mode(InfantryStance.Mode.RUN)
	await _frames(10)

	# --- firing recoils the weapon ---
	var weapon_bone: int = skeleton.find_bone("weapon")
	soldier.stop_moving()
	await _frames(12)
	var rest_pitch: float = skeleton.get_bone_pose_rotation(weapon_bone).get_euler().x
	soldier.notify_weapon_fired()
	await get_tree().process_frame
	await get_tree().process_frame
	var fired_pitch: float = skeleton.get_bone_pose_rotation(weapon_bone).get_euler().x
	_check("Firing kicks the weapon bone", absf(fired_pitch - rest_pitch) > 0.05,
		"%.3f -> %.3f rad" % [rest_pitch, fired_pitch])
	await _frames(40)
	_check("The weapon settles back afterwards",
		absf(skeleton.get_bone_pose_rotation(weapon_bone).get_euler().x - rest_pitch) < 0.02)

	# --- taking a hit flinches ---
	await _frames(6)
	var spine_bone: int = skeleton.find_bone("spine")
	var calm: float = skeleton.get_bone_pose_rotation(spine_bone).get_euler().x
	soldier.health.take_damage(12.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var flinched: float = skeleton.get_bone_pose_rotation(spine_bone).get_euler().x
	_check("Being hit flinches the body", absf(flinched - calm) > 0.05,
		"%.2f -> %.2f rad" % [calm, flinched])

	# --- a soldier in contact raises his weapon ---
	soldier.stop_moving()
	stance.set_mode(InfantryStance.Mode.RUN)
	await _frames(30)
	var arm_bone: int = skeleton.find_bone("upper_arm.R")
	var carried: float = skeleton.get_bone_pose_rotation(arm_bone).get_euler().x
	_check("At rest the weapon is carried, not aimed", anim._aim < 0.1,
		"aim %.2f" % anim._aim)

	## Put an enemy in front of him and let him engage.
	## Placed relative to where the soldier ACTUALLY is - he has walked a
	## long way through the tests above, so a position derived from the
	## base would be well outside his 10m rifle range.
	var mark = _spawn(SOLDIER, soldier.global_position + Vector3(4, 0, 0), false)
	## Aggressive, so he acquires rather than waiting to be shot at:
	## DEFENSIVE (the default) holds its fire until something starts on
	## it, which is not the case being tested here.
	soldier.stance = UnitBase.Stance.AGGRESSIVE
	for i in 70:
		await get_tree().process_frame
	_check("Facing an enemy he brings the weapon up", anim._aim > 0.8,
		"aim %.2f" % anim._aim)
	var aimed: float = skeleton.get_bone_pose_rotation(arm_bone).get_euler().x
	_check("...which is a visibly different arm pose",
		absf(aimed - carried) > 0.4, "carry %.2f -> aim %.2f rad" % [carried, aimed])

	mark.health.take_damage(99999.0)
	await _frames(70)
	_check("With nothing to shoot he lowers it again", anim._aim < 0.2,
		"aim %.2f" % anim._aim)

	# --- the dog runs on four legs ---
	var dog = _spawn(DOG, base + Vector3(-10, 0, 10))
	await _frames(6)
	var dog_anim = dog.get_node_or_null("InfantryAnimator")
	_check("The dog is rigged too", dog_anim != null)
	if dog_anim != null:
		_check("The dog is rigged as a quadruped", dog_anim.is_quadruped())
		var dog_legs := 0
		for leg in ["leg.FL", "leg.FR", "leg.BL", "leg.BR"]:
			if dog_anim._skeleton.find_bone(leg) >= 0:
				dog_legs += 1
		_check("The dog has four legs on the rig", dog_legs == 4, "%d" % dog_legs)
		dog.move_to(base + Vector3(-10, 0, 40))
		await _frames(10)
		var gait := await _swing_of(dog, "leg.FL", 2.0)
		_check("The dog's legs actually run", gait["swing"] > 0.2,
			"%.2f rad" % gait["swing"])

	# --- vehicles pay nothing for any of this ---
	var tank = _spawn(TANK, base + Vector3(18, 0, 10))
	await _frames(6)
	_check("A vehicle gets no infantry animator",
		tank.get_node_or_null("InfantryAnimator") == null)

	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

## MeshInstance3D nodes under the model. One soldier should be one.
func _count_meshes(root: Node) -> int:
	var n := 0
	if root is MeshInstance3D:
		n += 1
	for c in root.get_children():
		n += _count_meshes(c)
	return n
