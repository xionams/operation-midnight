extends Node

## Phase 1 / item 2: infantry RUN / CROUCH posture.
##
## Measures behaviour rather than reading config back: two identical
## soldiers race over the same ground, two identical soldiers shoot the
## same target, and the difference is what is asserted. The posture is
## switched with the real C key and the real sidebar button.

const SOLDIER_STATS := preload("res://config/units/rifle_soldier.tres")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")
const RUN := preload("res://config/stances/infantry_run.tres")
const CROUCH := preload("res://config/stances/infantry_crouch.tres")

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	_main = get_parent()
	await get_tree().process_frame
	var hud = get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	var director = get_parent().get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-56s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _disarm(unit: Node) -> void:
	var attacker = unit.get_node_or_null("AttackerComponent")
	if attacker != null:
		attacker.set_physics_process(false)

func _wait_seconds(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _run() -> void:
	# --- configuration shape ---
	_check("CROUCH moves 50-70% of RUN",
		CROUCH.move_speed_multiplier / RUN.move_speed_multiplier >= 0.5
		and CROUCH.move_speed_multiplier / RUN.move_speed_multiplier <= 0.7,
		"(%.2f)" % (CROUCH.move_speed_multiplier / RUN.move_speed_multiplier))
	_check("CROUCH hits 125-150% of RUN",
		CROUCH.damage_multiplier / RUN.damage_multiplier >= 1.25
		and CROUCH.damage_multiplier / RUN.damage_multiplier <= 1.5,
		"(%.2f)" % (CROUCH.damage_multiplier / RUN.damage_multiplier))

	var a = _spawn(SOLDIER_STATS, true, Vector3(-30, 0, 20))
	var b = _spawn(SOLDIER_STATS, true, Vector3(-30, 0, 24))
	var tank = _spawn(TANK_STATS, true, Vector3(-40, 0, 30))
	await get_tree().process_frame
	_check("Infantry carry a posture", InfantryStance.of(a) != null)
	_check("Vehicles have no posture", InfantryStance.of(tank) == null)
	_check("Infantry start in RUN", not InfantryStance.of(a).is_crouched())

	# --- switching through the player's controls ---
	SelectionManager.clear_selection()
	SelectionManager._select_unit(a)
	SelectionManager._select_unit(tank)
	var hud = _main.get_node_or_null("HUD")
	var button: Button = hud.find_child("PostureButton", true, false) if hud else null
	_check("Sidebar has a posture button", button != null)
	if button != null:
		_check("Button offers Crouch while running", button.text == "Crouch" and not button.disabled,
			"(%s)" % button.text)
	await _key(KEY_C)
	_check("C key crouches the selected infantry", InfantryStance.of(a).is_crouched())
	_check("Mixed selection: the vehicle is untouched", InfantryStance.of(tank) == null)
	if button != null:
		_check("Button now offers Run", button.text == "Run", "(%s)" % button.text)
		button.pressed.emit()
		await get_tree().process_frame
		_check("Sidebar button stands them back up", not InfantryStance.of(a).is_crouched())
	SelectionManager.clear_selection()
	SelectionManager._select_unit(tank)
	if button != null:
		_check("Button is disabled with no infantry selected", button.disabled)
	SelectionManager.clear_selection()

	# --- speed: race two identical soldiers over the same distance ---
	InfantryStance.of(a).set_mode(InfantryStance.Mode.RUN)
	InfantryStance.of(b).set_mode(InfantryStance.Mode.CROUCH)
	_check("Crouched soldier's nav agent is capped to its crouched pace",
		is_equal_approx(b.nav_agent.max_speed, SOLDIER_STATS.move_speed * CROUCH.move_speed_multiplier),
		"(%.2f)" % b.nav_agent.max_speed)
	var a0: Vector3 = a.global_position
	var b0: Vector3 = b.global_position
	a.issue_command(CommandTypes.Type.MOVE, a0 + Vector3(40, 0, 0))
	b.issue_command(CommandTypes.Type.MOVE, b0 + Vector3(40, 0, 0))
	await _wait_seconds(4.0)
	var ran: float = _flat(a.global_position, a0)
	var crept: float = _flat(b.global_position, b0)
	_check("RUN clearly covers more ground than CROUCH", ran > crept * 1.3,
		"(run %.1fm vs crouch %.1fm in 4s)" % [ran, crept])
	_check("Measured speed ratio matches the profile",
		absf(crept / maxf(ran, 0.01) - CROUCH.move_speed_multiplier) < 0.12,
		"(%.2f vs %.2f)" % [crept / maxf(ran, 0.01), CROUCH.move_speed_multiplier])

	# --- switching mid-move does not break the order ---
	InfantryStance.of(a).set_mode(InfantryStance.Mode.CROUCH)
	await _wait_seconds(1.0)
	var mid: Vector3 = a.global_position
	await _wait_seconds(1.0)
	var slowed: float = _flat(a.global_position, mid)
	_check("Crouching mid-move slows the soldier but keeps him moving",
		slowed > 0.5 and slowed < ran / 4.0 * 0.85, "(%.1fm/s)" % slowed)
	InfantryStance.of(a).set_mode(InfantryStance.Mode.RUN)
	var arrived := false
	for i in 20:
		await _wait_seconds(0.5)
		if _flat(a.global_position, a0 + Vector3(40, 0, 0)) < 2.0:
			arrived = true
			break
	_check("Standing back up, he still reaches his destination", arrived,
		"(%.1fm short)" % _flat(a.global_position, a0 + Vector3(40, 0, 0)))

	# --- damage: same weapon, same target, different posture ---
	var dummy = _spawn(SOLDIER_STATS, false, Vector3(-10, 0, -20))
	var shooter_run = _spawn(SOLDIER_STATS, true, Vector3(-14, 0, -20))
	var shooter_crouch = _spawn(SOLDIER_STATS, true, Vector3(-14, 0, -24))
	await get_tree().process_frame
	for u in [dummy, shooter_run, shooter_crouch]:
		_disarm(u)
	InfantryStance.of(shooter_crouch).set_mode(InfantryStance.Mode.CROUCH)
	var hp: HealthComponent = dummy.get_node("HealthComponent")
	## Armed for a frame before being disarmed, so they may already have
	## fired - clear the cooldown so the deliberate shot is the one counted.
	hp.current_health = hp.max_health
	var before: float = hp.current_health
	shooter_run.get_node("Weapon")._cooldown_remaining = 0.0
	shooter_run.get_node("Weapon").fire_at(dummy, shooter_run.global_position)
	var run_dmg: float = before - hp.current_health
	before = hp.current_health
	shooter_crouch.get_node("Weapon")._cooldown_remaining = 0.0
	shooter_crouch.get_node("Weapon").fire_at(dummy, shooter_crouch.global_position)
	var crouch_dmg: float = before - hp.current_health
	_check("CROUCH deals more damage per shot than RUN", crouch_dmg > run_dmg,
		"(%.1f vs %.1f)" % [crouch_dmg, run_dmg])
	_check("Damage ratio matches the profile",
		is_equal_approx(crouch_dmg / run_dmg, CROUCH.damage_multiplier / RUN.damage_multiplier),
		"(%.2f)" % (crouch_dmg / run_dmg))

	# --- switching mid-fight does not break combat ---
	var fighter = _spawn(SOLDIER_STATS, true, Vector3(20, 0, -20))
	var victim = _spawn(TANK_STATS, false, Vector3(28, 0, -20))
	await get_tree().process_frame
	_disarm(victim)
	fighter.attack_target(victim)
	await _wait_seconds(1.5)
	var v_hp: HealthComponent = victim.get_node("HealthComponent")
	var mid_hp: float = v_hp.current_health
	InfantryStance.of(fighter).set_mode(InfantryStance.Mode.CROUCH)
	await _wait_seconds(2.0)
	_check("Target kept after crouching mid-fight",
		fighter.get_node("AttackerComponent").target == victim)
	_check("Still firing after crouching mid-fight", v_hp.current_health < mid_hp,
		"(%.0f -> %.0f)" % [mid_hp, v_hp.current_health])
	InfantryStance.of(fighter).set_mode(InfantryStance.Mode.RUN)
	var mid_hp2: float = v_hp.current_health
	await _wait_seconds(2.0)
	_check("Still firing after standing up mid-fight", v_hp.current_health < mid_hp2)

	# --- posture survives a save ---
	var entry: Dictionary = SaveGame._capture_unit(b)
	_check("Save records the posture", int(entry.get("posture", -1)) == InfantryStance.Mode.CROUCH)
