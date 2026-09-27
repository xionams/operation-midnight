extends Node

## Phase 1 / item 1: infantry fight everything a soldier should be able
## to fight - infantry, vehicles AND structures - through the same
## targeting path the player uses. Orders are given with a real
## right-click on the target's screen position, not by poking the
## AttackerComponent directly, so the input resolver is covered too.

const SOLDIER_STATS := preload("res://config/units/rifle_soldier.tres")
const DOG_STATS := preload("res://config/units/attack_dog.tres")
const TANK_STATS := preload("res://config/units/assault_vehicle.tres")
const BARRACKS_STATS := preload("res://config/buildings/barracks.tres")
const POWER_STATS := preload("res://config/buildings/power_plant.tres")
const FACTORY_STATS := preload("res://config/buildings/war_factory.tres")

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
	## The strategic AI walks loose units away mid-test; not under test.
	var director = get_parent().get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	await _run()
	Engine.time_scale = 1.0
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-56s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn_unit(stats: UnitStats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = pos
	return u

func _spawn_building(stats: BuildingStats, player: bool, pos: Vector3) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = pos
	## Same signal a real placement raises: re-bakes the navmesh so the
	## structure is an obstacle units must path around, as in play.
	EventBus.building_placed.emit(b)
	return b

func _disarm(unit: Node) -> void:
	var attacker = unit.get_node_or_null("AttackerComponent")
	if attacker != null:
		attacker.set_physics_process(false)

func _camera() -> Camera3D:
	return get_tree().get_first_node_in_group("rts_camera") as Camera3D

## A genuine right-click, resolved by SelectionManager exactly as in play.
func _right_click_on(node: Node3D) -> void:
	var cam := _camera()
	cam.focus_on(node.global_position)
	await get_tree().process_frame
	await get_tree().physics_frame
	## Aim just under the top of the collider - what a player clicks on.
	## Units snap to the rolling surface while the ground collider is flat,
	## so the middle of a man standing in a hollow can be below the pick.
	var height: float = node.stats.body_size.y if node.get("stats") != null else 1.0
	var aim: Vector3 = node.global_position + Vector3.UP * (height - 0.1)
	var pos: Vector2 = cam.unproject_position(aim)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	var hit := SelectionManager._raycast(pos)
	_check("Right-click ray lands on %s" % node.name.get_slice("@", 0),
		hit.get("collider") == node, "(hit %s)" % str(hit.get("collider")))
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _select(units: Array) -> void:
	SelectionManager.clear_selection()
	for u in units:
		SelectionManager._select_unit(u)

func _hp(node) -> float:
	if not is_instance_valid(node):
		return 0.0
	return node.get_node("HealthComponent").current_health

func _wait_seconds(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	## Speeds the long engagements up; physics still steps every frame.
	Engine.time_scale = 4.0
	var origin := Vector3(-20, 0, 0)

	# --- rules: what may be targeted at all ---
	var rifle_w: WeaponStats = SOLDIER_STATS.weapon_stats
	_check("Small arms do real work against structures",
		rifle_w.multiplier_for(Armor.Type.STRUCTURE) >= Weapon.MIN_USEFUL_MULTIPLIER,
		"(x%.2f, floor %.2f)" % [rifle_w.multiplier_for(Armor.Type.STRUCTURE), Weapon.MIN_USEFUL_MULTIPLIER])
	_check("Structures stay below the AI's siege-unit threshold",
		rifle_w.multiplier_for(Armor.Type.STRUCTURE) < 0.5)

	# --- 1. infantry vs infantry ---
	var squad: Array = []
	for i in 3:
		squad.append(_spawn_unit(SOLDIER_STATS, true, origin + Vector3(i * 1.5, 0, 12)))
	var foe = _spawn_unit(SOLDIER_STATS, false, origin + Vector3(1.5, 0, -2))
	await get_tree().process_frame
	_disarm(foe)
	var foe_hp: float = _hp(foe)
	_select(squad)
	await _right_click_on(foe)
	_check("Right-click on enemy infantry gives an attack order",
		squad[0].get_node("AttackerComponent").target == foe)
	await _wait_seconds(6.0)
	_check("Infantry kill enemy infantry", not is_instance_valid(foe) or _hp(foe) < foe_hp,
		"(hp %.0f -> %.0f)" % [foe_hp, _hp(foe)])

	# --- 2. infantry vs vehicle ---
	var tank = _spawn_unit(TANK_STATS, false, origin + Vector3(1.5, 0, -2))
	await get_tree().process_frame
	_disarm(tank)
	var tank_hp: float = _hp(tank)
	_select(squad)
	await _right_click_on(tank)
	_check("Right-click on an enemy vehicle gives an attack order",
		squad[0].get_node("AttackerComponent").target == tank)
	await _wait_seconds(5.0)
	_check("Infantry damage an enemy vehicle", _hp(tank) < tank_hp,
		"(hp %.0f -> %.0f)" % [tank_hp, _hp(tank)])
	if is_instance_valid(tank):
		tank.queue_free()
	await get_tree().process_frame

	# --- 3. infantry vs building: explicit order, walk into range, raze ---
	var barracks = _spawn_building(BARRACKS_STATS, false, origin + Vector3(0, 0, -20))
	for u in squad:
		u.issue_command(CommandTypes.Type.MOVE, u.global_position)
	await _wait_seconds(1.0)
	var start_dist: float = CombatTarget.distance(squad[0].global_position, barracks)
	var b_hp: float = _hp(barracks)
	_select(squad)
	await _right_click_on(barracks)
	var accepted: int = 0
	for u in squad:
		if u.get_node("AttackerComponent").target == barracks:
			accepted += 1
	_check("Right-click on an enemy building gives every rifleman the target",
		accepted == squad.size(), "(%d of %d)" % [accepted, squad.size()])
	_check("Squad starts out of weapon range", start_dist > rifle_w.attack_range,
		"(%.1fm > %.1fm)" % [start_dist, rifle_w.attack_range])
	await _wait_seconds(4.0)
	var closest: float = INF
	for u in squad:
		closest = minf(closest, CombatTarget.distance(u.global_position, barracks))
	_check("Infantry move into weapon range of the building",
		closest <= rifle_w.attack_range + 0.1, "(%.1fm)" % closest)
	_check("Building takes damage from infantry fire", _hp(barracks) < b_hp,
		"(hp %.0f -> %.0f)" % [b_hp, _hp(barracks)])
	var waited: float = 0.0
	while is_instance_valid(barracks) and waited < 120.0:
		await _wait_seconds(1.0)
		waited += 1.0
	_check("Infantry destroy the building", not is_instance_valid(barracks),
		"(after %.0fs game time)" % waited)

	# --- 4. attack-move acquires a hostile building ---
	var plant = _spawn_building(POWER_STATS, false, origin + Vector3(20, 0, -20))
	await _wait_seconds(0.5)
	var p_hp: float = _hp(plant)
	for u in squad:
		u.issue_command(CommandTypes.Type.ATTACK_MOVE, origin + Vector3(20, 0, -8))
	await _wait_seconds(8.0)
	var on_plant: bool = false
	for u in squad:
		if is_instance_valid(u) and u.get_node("AttackerComponent").target == plant:
			on_plant = true
	_check("Attack-move acquires a hostile building",
		on_plant or not is_instance_valid(plant) or _hp(plant) < p_hp)
	_check("Attack-moving infantry damage the building", _hp(plant) < p_hp,
		"(hp %.0f -> %.0f)" % [p_hp, _hp(plant)])

	# --- 5. a large structure is still engaged (edge, not centre, range) ---
	var factory = _spawn_building(FACTORY_STATS, false, origin + Vector3(-25, 0, -20))
	await _wait_seconds(0.5)
	var f_hp: float = _hp(factory)
	for u in squad:
		u.attack_target(factory)
	await _wait_seconds(10.0)
	_check("Infantry engage a 10m Vehicle Factory from its edge", _hp(factory) < f_hp,
		"(hp %.0f -> %.0f)" % [f_hp, _hp(factory)])

	# --- 6. dogs still refuse buildings, still bite infantry ---
	var dog = _spawn_unit(DOG_STATS, true, origin + Vector3(-25, 0, -5))
	await get_tree().process_frame
	dog.attack_target(factory)
	_check("Attack Dog refuses a building order",
		not dog.get_node("AttackerComponent").has_target())
	_check("Attack Dog weapon opts out of structures",
		not dog.get_node("Weapon").can_damage(factory))

	# --- 7. regression: vehicles still attack buildings ---
	var my_tank = _spawn_unit(TANK_STATS, true, origin + Vector3(-10, 0, -8))
	await get_tree().process_frame
	var f_hp2: float = _hp(factory)
	my_tank.attack_target(factory)
	await _wait_seconds(5.0)
	_check("Vehicles still attack buildings", _hp(factory) < f_hp2,
		"(hp %.0f -> %.0f)" % [f_hp2, _hp(factory)])

	# --- 8. the AI side uses the same rules against player structures ---
	var my_plant = _spawn_building(POWER_STATS, true, origin + Vector3(40, 0, 20))
	var raider = _spawn_unit(SOLDIER_STATS, false, origin + Vector3(40, 0, 35))
	await _wait_seconds(0.5)
	var mp_hp: float = _hp(my_plant)
	raider.issue_command(CommandTypes.Type.ATTACK_MOVE, origin + Vector3(40, 0, 25))
	await _wait_seconds(8.0)
	_check("Enemy infantry attack-move onto a player building and damage it",
		_hp(my_plant) < mp_hp, "(hp %.0f -> %.0f)" % [mp_hp, _hp(my_plant)])
