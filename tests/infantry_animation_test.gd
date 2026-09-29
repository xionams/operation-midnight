extends Node

## Infantry must move their limbs, and RUN must not look like CROUCH.
##
## Soldiers glided: the model was one welded "Body" mesh with nothing to
## animate. They are now jointed rigs posed procedurally, so these checks
## are about MEASURED motion - how far a leg actually swings, how much
## lower a crouched body sits - rather than whether an animation asset
## happens to exist.

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

## Range a part's local pitch covers while the unit walks a while.
func _swing_of(unit: Node, part_name: String, seconds: float) -> Dictionary:
	var anim = unit.get_node_or_null("InfantryAnimator")
	var part: Node3D = anim._visual.find_child(part_name, true, false)
	var lo: float = INF
	var hi: float = -INF
	var low_y: float = INF
	var high_y: float = -INF
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame
		if not is_instance_valid(part):
			break
		lo = minf(lo, part.rotation.x)
		hi = maxf(hi, part.rotation.x)
		var y: float = part.global_position.y - unit.global_position.y
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
	var missing: Array = []
	for part in ["Torso", "Leg_L", "Leg_R", "Arm_L", "Arm_R", "Head", "Weapon"]:
		if anim._visual.find_child(part, true, false) == null:
			missing.append(part)
	_check("The soldier model is jointed, not one welded body",
		missing.is_empty(), "missing %s" % str(missing))

	## The upper body hangs off the torso, so a lean carries it along.
	var head: Node3D = anim._visual.find_child("Head", true, false)
	var torso: Node3D = anim._visual.find_child("Torso", true, false)
	_check("Head and weapon follow the torso", head.get_parent() == torso)

	# --- walking actually swings the legs ---
	var from: Vector3 = soldier.global_position
	soldier.move_to(base + Vector3(10, 0, 44))
	await _frames(20)
	for i in 30:
		await get_tree().process_frame
	_check("The soldier actually walks when ordered",
		from.distance_to(soldier.global_position) > 3.0,
		"moved %.2fm" % from.distance_to(soldier.global_position))
	var run := await _swing_of(soldier, "Leg_L", 2.5)
	_check("Walking swings the legs", run["swing"] > 0.25,
		"%.2f rad" % run["swing"])
	var run_torso := await _swing_of(soldier, "Torso", 1.5)
	_check("The body bobs while walking", run_torso["y_high"] - run_torso["y"] > 0.005,
		"%.3f m" % (run_torso["y_high"] - run_torso["y"]))
	var run_lean: float = run_torso["high"]
	var run_height: float = run_torso["y_high"]

	# --- crouching looks different, not merely slower ---
	var stance = InfantryStance.of(soldier)
	_check("The soldier carries a posture", stance != null)
	stance.set_mode(InfantryStance.Mode.CROUCH)
	soldier.move_to(base + Vector3(10, 0, 70))
	await _frames(20)
	var crouch := await _swing_of(soldier, "Leg_L", 2.5)
	var crouch_torso := await _swing_of(soldier, "Torso", 1.5)
	_check("CROUCH takes shorter paces than RUN",
		crouch["swing"] < run["swing"] * 0.8,
		"crouch %.2f vs run %.2f rad" % [crouch["swing"], run["swing"]])
	_check("CROUCH carries the body visibly lower",
		crouch_torso["y_high"] < run_height - 0.1,
		"crouch %.2fm vs run %.2fm" % [crouch_torso["y_high"], run_height])
	_check("CROUCH leans further forward",
		crouch_torso["high"] > run_lean + 0.1,
		"crouch %.2f vs run %.2f rad" % [crouch_torso["high"], run_lean])

	stance.set_mode(InfantryStance.Mode.RUN)
	await _frames(10)

	# --- firing recoils the weapon ---
	var weapon: Node3D = anim._visual.find_child("Weapon", true, false)
	soldier.stop_moving()
	await _frames(12)
	var rest_z: float = weapon.position.z
	soldier.notify_weapon_fired()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Firing kicks the weapon back", weapon.position.z > rest_z + 0.01,
		"%.3f -> %.3f" % [rest_z, weapon.position.z])
	var fired_pitch: float = weapon.rotation.x
	_check("Firing lifts the muzzle", fired_pitch > 0.05, "%.2f rad" % fired_pitch)
	await _frames(30)
	_check("The weapon settles back afterwards",
		absf(weapon.position.z - rest_z) < 0.01, "%.3f" % weapon.position.z)

	# --- taking a hit flinches ---
	await _frames(6)
	var calm: float = torso.rotation.x
	soldier.health.take_damage(12.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Being hit flinches the body", torso.rotation.x < calm - 0.05,
		"%.2f -> %.2f rad" % [calm, torso.rotation.x])

	# --- a soldier in contact raises his weapon ---
	soldier.stop_moving()
	stance.set_mode(InfantryStance.Mode.RUN)
	await _frames(30)
	var arm: Node3D = anim._visual.find_child("Arm_R", true, false)
	var carried: float = arm.rotation.x
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
	var aimed: float = arm.rotation.x
	_check("...which is a visibly different arm pose", aimed < carried - 0.4,
		"carry %.2f -> aim %.2f rad" % [carried, aimed])
	_check("...and the weapon comes up towards level",
		absf(aimed) > 1.1, "%.2f rad" % absf(aimed))

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
		_check("The dog has four legs on the rig", dog_anim._legs.size() == 4,
			"%d" % dog_anim._legs.size())
		dog.move_to(base + Vector3(-10, 0, 40))
		await _frames(10)
		var gait := await _swing_of(dog, "Leg_FL", 2.0)
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
