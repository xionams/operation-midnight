extends Node

## Phase 1 / item 4: what the Scout Vehicle actually is.
##
## Pins the answer to "can infantry get in?" (no - there is no passenger
## code, and a right-click onto it is an escort order) and the things
## that make it a recon unit: fastest vehicle, widest vision, light armour,
## a machine gun that hurts infantry but not armour, and a role line the
## player can read.

const SCOUT := preload("res://config/units/scout_vehicle.tres")
const ASSAULT := preload("res://config/units/assault_vehicle.tres")
const SOLDIER := preload("res://config/units/rifle_soldier.tres")

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

func _wait_seconds(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _right_click_on(node: Node3D) -> void:
	var cam := get_tree().get_first_node_in_group("rts_camera") as Camera3D
	cam.focus_on(node.global_position)
	await get_tree().process_frame
	await get_tree().physics_frame
	var pos: Vector2 = cam.unproject_position(node.global_position + Vector3.UP * (node.stats.body_size.y - 0.1))
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _run() -> void:
	# --- data: what makes it a scout, compared with everything else ---
	var fastest_other_vehicle: float = 0.0
	var widest_other_vision: float = 0.0
	for category in BuildCatalog.categories():
		for stats in BuildCatalog.items(category):
			if not (stats is UnitStats) or stats == SCOUT:
				continue
			widest_other_vision = maxf(widest_other_vision, stats.vision_range)
			if not stats.is_infantry:
				fastest_other_vehicle = maxf(fastest_other_vehicle, stats.move_speed)
	_check("Fastest vehicle in the game", SCOUT.move_speed > fastest_other_vehicle,
		"(%.1f vs next %.1f)" % [SCOUT.move_speed, fastest_other_vehicle])
	_check("Widest vision of any unit", SCOUT.vision_range > widest_other_vision * 1.4,
		"(%.0fm vs next %.0fm)" % [SCOUT.vision_range, widest_other_vision])
	_check("Lightly armoured", SCOUT.armor_type == Armor.Type.LIGHT)
	_check("Armed with small arms (anti-infantry)",
		SCOUT.weapon_stats != null and SCOUT.weapon_stats.damage_type == DamageTypes.Type.SMALL_ARMS)
	_check("Crushes infantry", SCOUT.can_crush)
	_check("No cargo capacity (that field is harvester ore)", SCOUT.cargo_capacity == 0.0)
	_check("Has a role line the player can read", not SCOUT.role.is_empty(), "(%s)" % SCOUT.role)

	# --- it has no passenger hold, so infantry cannot board ---
	var scout = _spawn(SCOUT, true, Vector3(-40, 0, -10))
	var rifle = _spawn(SOLDIER, true, Vector3(-40, 0, 0))
	await get_tree().process_frame
	var has_hold: bool = false
	for child in scout.get_children():
		if child is OccupantHold:
			has_hold = true
	_check("Scout carries no passenger hold", not has_hold)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(rifle)
	await _right_click_on(scout)
	_check("Right-clicking infantry onto a Scout is an escort, not boarding",
		rifle.current_command == CommandTypes.Type.GUARD,
		"(%s)" % CommandTypes.type_name(rifle.current_command))
	await _wait_seconds(3.0)
	_check("The soldier is still on the field afterwards", rifle.is_inside_tree()
		and get_tree().get_nodes_in_group("player_units").has(rifle))

	# --- measured speed against the Assault Vehicle ---
	var tank = _spawn(ASSAULT, true, Vector3(-40, 0, 20))
	await get_tree().process_frame
	var s0: Vector3 = scout.global_position
	var t0: Vector3 = tank.global_position
	scout.issue_command(CommandTypes.Type.MOVE, s0 + Vector3(40, 0, 0))
	tank.issue_command(CommandTypes.Type.MOVE, t0 + Vector3(40, 0, 0))
	await _wait_seconds(3.0)
	var scout_run: float = _flat(scout.global_position, s0)
	var tank_run: float = _flat(tank.global_position, t0)
	_check("Out-runs the Assault Vehicle in practice", scout_run > tank_run * 1.3,
		"(%.1fm vs %.1fm in 3s)" % [scout_run, tank_run])

	# --- the gun: kills infantry, will not pick a fight with armour ---
	var enemy_rifle = _spawn(SOLDIER, false, scout.global_position + Vector3(6, 0, 0))
	var enemy_tank = _spawn(ASSAULT, false, scout.global_position + Vector3(0, 0, 7))
	await get_tree().process_frame
	enemy_rifle.get_node("AttackerComponent").set_physics_process(false)
	enemy_tank.get_node("AttackerComponent").set_physics_process(false)
	scout.issue_command(CommandTypes.Type.STOP)
	await _wait_seconds(3.0)
	var target = scout.get_node("AttackerComponent").target
	_check("Scout picks the infantry, not the tank",
		not is_instance_valid(enemy_rifle) or target == enemy_rifle,
		"(target %s)" % str(target))
	_check("Scout's gun hurts infantry",
		not is_instance_valid(enemy_rifle) or enemy_rifle.health.current_health < enemy_rifle.health.max_health)

	# --- the info panel says what it is for ---
	SelectionManager.clear_selection()
	SelectionManager._select_unit(scout)
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	var panel_text: String = hud._info_panel.text if hud != null else ""
	_check("Selecting a Scout shows its role", panel_text.contains("Recon"), "")
