extends Node

## Phase 2 / part 3: the sea as a gameplay layer, on the Coastline map.
##
## Land and sea movement domains, the Naval Yard's shore rule, naval
## production through the sidebar, patrol boat and submarine behaviour,
## the naval combat rules, sonar, fog and save/load. Orders go through
## real clicks wherever the player would use one.

const COAST := preload("res://config/maps/coastline.tres")
const TANK := preload("res://config/units/assault_vehicle.tres")
const SOLDIER := preload("res://config/units/rifle_soldier.tres")
const BOAT := preload("res://config/units/patrol_boat.tres")
const SUB := preload("res://config/units/submarine.tres")
const YARD := preload("res://config/buildings/naval_yard.tres")
const BUOY := preload("res://config/buildings/sonar_buoy.tres")
const BARRACKS := preload("res://config/buildings/barracks.tres")
const POWER := preload("res://config/buildings/power_plant.tres")

var _main: Node3D
var _fails: Array = []
var _feedback: Array = []

func _ready() -> void:
	## Children are ready before their parent: set the map before Main builds.
	GameState.selected_map = COAST
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
	for u in get_tree().get_nodes_in_group("player_units"):
		var gun = u.get_node_or_null("AttackerComponent")
		if gun != null:
			gun.set_physics_process(false)
	EventBus.feedback.connect(func(text, kind, pos): _feedback.append([text, kind, pos]))
	GameState.add_credits(40000)
	await _run()
	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-62s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _spawn(stats: UnitStats, player: bool, pos: Vector3) -> Node:
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
	b.global_position = Vector3(pos.x, PlacementDomain.surface_y(stats, pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _disarm(u: Node) -> Node:
	var gun = u.get_node_or_null("AttackerComponent")
	if gun != null:
		gun.set_physics_process(false)
	return u

func _cam() -> Camera3D:
	return get_tree().get_first_node_in_group("rts_camera") as Camera3D

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	Input.parse_input_event(m)
	await get_tree().process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await get_tree().process_frame

## Screen point of a world position on the flat pick ground. The camera
## must already be looking there (see _look).
func _screen(world: Vector3) -> Vector2:
	return _cam().unproject_position(Vector3(world.x, 0.0, world.z))

func _look(world: Vector3) -> void:
	_cam().focus_on(world)
	_cam().snap()
	await _frames(4)

func _settle_nav() -> void:
	for i in 600:
		await get_tree().physics_frame
		if not _main._nav_dirty and not _main._water_baking \
			and not _main.get_node("Level/NavRegion").is_baking() and i > 10:
			break
	await _frames(4)

func _wet(p: Vector3) -> bool:
	return Water.is_water(p.x, p.z)

func _last() -> Array:
	return _feedback[-1] if not _feedback.is_empty() else ["", -1, Vector3.INF]

func _run() -> void:
	var water_nav: NavigationRegion3D = _main.get_node_or_null("Level/WaterNav")
	var map_rid: RID = _main.get_viewport().get_world_3d().navigation_map

	# --- 1. the sea exists as a gameplay layer ---
	_check("Coastline has a sea", Water.has_water() and _wet(Vector3(0, 0, 60)) and not _wet(Vector3(0, 0, -20)))
	_check("A sea navmesh exists on its own layer",
		water_nav != null and water_nav.navigation_layers == NavLayers.WATER
		and water_nav.navigation_mesh != null and water_nav.navigation_mesh.get_polygon_count() > 0,
		"(%d polys)" % (water_nav.navigation_mesh.get_polygon_count() if water_nav and water_nav.navigation_mesh else -1))
	var land_path := NavigationServer3D.map_get_path(map_rid, Vector3(-60, 0, -5), Vector3(-60, 0, 60), true, NavLayers.LAND)
	var sea_path := NavigationServer3D.map_get_path(map_rid, Vector3(-78, 0, 40), Vector3(78, 0, 40), true, NavLayers.WATER)
	_check("The land navmesh stops at the waterline",
		land_path.size() > 0 and not _wet(land_path[-1]) and Water.distance_to_shore(land_path[-1].x, land_path[-1].z) < 4.0,
		"(ends %s)" % str(land_path[-1] if land_path.size() > 0 else "none"))
	var sea_ok := sea_path.size() > 0 and Vector2(sea_path[-1].x, sea_path[-1].z).distance_to(Vector2(78, 40)) < 2.0
	for p in sea_path:
		sea_ok = sea_ok and _wet(p)
	_check("The sea navmesh crosses the map without touching land", sea_ok, "(%d points)" % sea_path.size())

	# --- 2. a tank ordered into the sea stops at the shore, and is told ---
	var tank = _spawn(TANK, true, Vector3(-70, 0, 2))
	await _wait(0.3)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(tank)
	_feedback.clear()
	await _look(Vector3(-70, 0, 30))
	await _click(_screen(Vector3(-70, 0, 45)), MOUSE_BUTTON_RIGHT)
	_check("Ordering a tank into the sea warns that land units can't enter it",
		String(_last()[0]).begins_with("Land units can't enter the sea"), "(%s)" % _last()[0])
	var tank_wet := false
	for i in 24:
		await _wait(0.25)
		tank_wet = tank_wet or _wet(tank.global_position)
	_check("The tank never enters the water", not tank_wet)
	_check("...and ends on the beach", Water.distance_to_shore(tank.global_position.x, tank.global_position.z) < 5.0,
		"(%.1fm from the water)" % Water.distance_to_shore(tank.global_position.x, tank.global_position.z))

	# --- 3. naval structures: placement rules with reasons ---
	var placer: BuildingPlacer = _main.get_node("BuildingPlacer")
	_spawn_building(BARRACKS, true, Vector3(-80, 0, 7))
	## Power, or the yard builds at the low-power half speed.
	_spawn_building(POWER, true, Vector3(-92, 0, -6))
	await _frames(2)
	placer.start_placement(YARD)
	_check("Naval Yard on land is refused",
		placer.placement_error(Vector3(-60, 0, -10)) == "Must be built entirely on water",
		"(%s)" % placer.placement_error(Vector3(-60, 0, -10)))
	_check("Naval Yard straddling the beach is refused",
		placer.placement_error(Vector3(-80, 0, 16)) == "Must be built entirely on water",
		"(%s)" % placer.placement_error(Vector3(-80, 0, 16)))
	var yard_at := Vector3(-80, 0, 24)
	_check("Naval Yard on water against the shore is legal", placer.placement_error(yard_at) == "",
		"(%s)" % placer.placement_error(yard_at))
	## Placed with a real click through the placer.
	placer.construction_queue = null
	await _look(yard_at)
	var yard_click := _screen(yard_at)
	await _frames(2)
	var mm := InputEventMouseMotion.new()
	mm.position = yard_click
	mm.global_position = yard_click
	Input.parse_input_event(mm)
	await _frames(3)
	await _click(yard_click)
	placer.cancel_placement()
	await _frames(2)
	var yard: Node = null
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if b.stats == YARD:
			yard = b
	_check("A real click places the Naval Yard", yard != null)
	if yard == null:
		return
	_check("It floats at the waterline, not on the sea floor",
		absf(yard.global_position.y - Water.level) < 0.05, "(y %.2f)" % yard.global_position.y)
	_check("It counts as a naval target", CombatTarget.domain_of(yard) == CombatTarget.Domain.NAVAL)
	placer.start_placement(YARD)
	var open_sea := Vector3(-80, 0, 40)
	_check("A second yard out at sea is refused: must touch the shore",
		placer.placement_error(open_sea).begins_with("Must be built against the shore"),
		"(%s)" % placer.placement_error(open_sea))
	placer.start_placement(BUOY)
	_check("Sonar Buoy on land is refused",
		placer.placement_error(Vector3(-70, 0, -2)) == "Must be built entirely on water")
	_check("Sonar Buoy on open water in territory is legal",
		placer.placement_error(Vector3(-68, 0, 36)) == "", "(%s)" % placer.placement_error(Vector3(-68, 0, 36)))
	placer.cancel_placement()
	await _settle_nav()
	var through := NavigationServer3D.map_get_path(map_rid, Vector3(-95, 0, 26), Vector3(-65, 0, 26), true, NavLayers.WATER)
	var blocked := true
	for p in through:
		if absf(p.x - yard_at.x) < 4.0 and absf(p.z - yard_at.z) < 4.0:
			blocked = false
	_check("Ships path around the yard, not through it", blocked)

	# --- 4. naval production from the sidebar ---
	var hud = _main.get_node("HUD")
	hud._set_category("NAVAL")
	await _frames(2)
	var boat_tile: Button = null
	var sub_tile: Button = null
	for b in hud.find_children("*", "Button", true, false):
		for l in b.find_children("*", "Label", true, false):
			if l.text == "Patrol Boat":
				boat_tile = b
			elif l.text == "Attack Submarine":
				sub_tile = b
	_check("The SEA tab lists the Patrol Boat and the Submarine", boat_tile != null and sub_tile != null)
	var boats_before := _count(BOAT, true)
	if boat_tile != null:
		boat_tile.pressed.emit()
	if sub_tile != null:
		sub_tile.pressed.emit()
		print("TEST| (sidebar said: %s)" % str(_last()[0]))
	var boat: Node = null
	var sub: Node = null
	for i in 60:
		await _wait(0.5)
		boat = _first(BOAT, true)
		sub = _first(SUB, true)
		if boat != null and sub != null:
			break
	_check("The Naval Yard launches a Patrol Boat", boat != null and _count(BOAT, true) > boats_before)
	_check("The Naval Yard launches an Attack Submarine", sub != null)
	if boat == null or sub == null:
		return
	await _wait(0.3)
	_check("Both are launched onto water", _wet(boat.global_position) and _wet(sub.global_position))
	_check("The boat rides the surface; the sub sits lower",
		absf(boat.global_position.y - Water.level) < 0.1 and sub.global_position.y < boat.global_position.y - 0.3,
		"(boat y %.2f, sub y %.2f)" % [boat.global_position.y, sub.global_position.y])
	## Our submarine would otherwise torpedo whatever the tests put near
	## it before the test asks it to; its gun is held until ordered.
	_disarm(sub)
	_check("Naval agents use only the sea layer",
		boat.nav_agent.navigation_layers == NavLayers.WATER and sub.nav_agent.navigation_layers == NavLayers.WATER)

	# --- 5. select and move a boat; it stays on water ---
	await _look(boat.global_position)
	SelectionManager.clear_selection()
	await _click(_cam().unproject_position(boat.global_position + Vector3.UP * 0.8))
	_check("A left click selects the boat", SelectionManager.selected_units == [boat],
		"(%d selected)" % SelectionManager.selected_units.size())
	var sea_dest := Vector3(-30, 0, 60)
	await _look(sea_dest)
	await _click(_screen(sea_dest), MOUSE_BUTTON_RIGHT)
	var boat_dry := false
	var boat_track: Array = []
	for i in 80:
		await _wait(0.25)
		boat_dry = boat_dry or not _wet(boat.global_position)
		if i % 8 == 0:
			boat_track.append("(%d,%d)" % [int(boat.global_position.x), int(boat.global_position.z)])
		if boat.global_position.distance_to(Vector3(sea_dest.x, boat.global_position.y, sea_dest.z)) < 3.0:
			break
	_check("The boat sails to the ordered point", Vector2(boat.global_position.x, boat.global_position.z)
		.distance_to(Vector2(sea_dest.x, sea_dest.z)) < 3.5, "(at %s, track %s)" % [str(boat.global_position), " ".join(boat_track)])
	_check("...never touching land on the way", not boat_dry)
	_feedback.clear()
	await _look(Vector3(-30, 0, 10))
	await _click(_screen(Vector3(-30, 0, -10)), MOUSE_BUTTON_RIGHT)
	_check("Ordering it ashore warns that ships can't go ashore",
		String(_last()[0]).begins_with("Ships can't go ashore"), "(%s)" % _last()[0])
	for i in 24:
		await _wait(0.25)
		boat_dry = boat_dry or not _wet(boat.global_position)
	_check("...and it stops at the coast, still afloat", not boat_dry)

	# --- 6. fog of war works for ships ---
	FogOfWar.enabled = true
	var far_enemy_boat = _disarm(_spawn(BOAT, false, Vector3(60, 0, 70)))
	await _wait(0.3)
	FogOfWar.update_now()
	await _frames(2)
	_check("A ship grants vision around itself", FogOfWar.is_visible_at(boat.global_position + Vector3(10, 0, 0)))
	_check("An enemy ship out of sight is hidden by fog", FogHideable.is_hidden(far_enemy_boat))
	far_enemy_boat.global_position = boat.global_position + Vector3(8, 0, 6)
	await _wait(0.3)
	FogOfWar.update_now()
	await _frames(2)
	_check("...and appears once our ship can see it", not FogHideable.is_hidden(far_enemy_boat))
	far_enemy_boat.queue_free()
	FogOfWar.enabled = false
	FogOfWar.update_now()

	# --- 7. naval combat rules ---
	## Boat vs a tank on the beach and a building on the shore.
	var beach_tank = _disarm(_spawn(TANK, false, Vector3(-40, 0, 20)))
	var shore_plant = _spawn_building(POWER, false, Vector3(-30, 0, 16))
	boat.global_position = Vector3(-38, Water.level, 33)
	boat.issue_command(CommandTypes.Type.STOP)
	await _wait(0.3)
	var t_hp: float = beach_tank.health.current_health
	boat.attack_target(beach_tank)
	await _wait(3.0)
	_check("RULE boats shell land units on the shore", beach_tank.health.current_health < t_hp,
		"(%.0f -> %.0f)" % [t_hp, beach_tank.health.current_health])
	var p_hp: float = shore_plant.health.current_health
	boat.global_position = Vector3(-30, Water.level, 34)
	boat.attack_target(shore_plant)
	await _wait(3.0)
	_check("RULE boats shell buildings on the shore", shore_plant.health.current_health < p_hp,
		"(%.0f -> %.0f)" % [p_hp, shore_plant.health.current_health])
	beach_tank.queue_free()
	shore_plant.queue_free()

	## Land guns vs a surface ship.
	var gunner = _spawn(TANK, true, Vector3(-10, 0, 20))
	var enemy_boat = _disarm(_spawn(BOAT, false, Vector3(-10, 0, 30)))
	await _wait(0.3)
	var eb_hp: float = enemy_boat.health.current_health
	gunner.attack_target(enemy_boat)
	await _wait(3.0)
	_check("RULE land units and defences can hit surface ships", enemy_boat.health.current_health < eb_hp,
		"(%.0f -> %.0f)" % [eb_hp, enemy_boat.health.current_health])
	gunner.issue_command(CommandTypes.Type.STOP)
	_disarm(gunner)

	## Boat vs boat.
	boat.global_position = Vector3(-10, Water.level, 42)
	eb_hp = enemy_boat.health.current_health
	boat.attack_target(enemy_boat)
	await _wait(3.0)
	_check("RULE ships fight ships", enemy_boat.health.current_health < eb_hp)
	boat.issue_command(CommandTypes.Type.STOP)
	enemy_boat.queue_free()
	await _frames(2)

	# --- 8. the submarine ---
	var enemy_sub = _disarm(_spawn(SUB, false, Vector3(30, 0, 60)))
	await _wait(0.6)
	FogOfWar.update_now()
	await _frames(2)
	_check("An enemy submarine far from sonar is hidden", FogHideable.is_hidden(enemy_sub)
		and not Stealth.visible_to(enemy_sub, true))
	var shore_gun = _spawn(TANK, true, Vector3(30, 0, 26))
	await _wait(0.3)
	shore_gun.attack_target(enemy_sub)
	_check("A hidden submarine cannot be targeted", shore_gun.get_node("AttackerComponent").target != enemy_sub)
	boat.global_position = Vector3(30, Water.level, 50)
	boat.issue_command(CommandTypes.Type.STOP)
	await _wait(0.6)
	FogOfWar.update_now()
	await _frames(2)
	_check("A Patrol Boat's sonar exposes it within 12m",
		Stealth.visible_to(enemy_sub, true) and not FogHideable.is_hidden(enemy_sub))
	_check("RULE exposed but submerged: land guns still cannot reach it",
		not shore_gun.get_node("Weapon").can_attack(enemy_sub))
	var es_hp: float = enemy_sub.health.current_health
	boat.attack_target(enemy_sub)
	await _wait(3.0)
	_check("RULE a Patrol Boat can hit a submarine its sonar has found",
		enemy_sub.health.current_health < es_hp, "(%.0f -> %.0f)" % [es_hp, enemy_sub.health.current_health])
	boat.issue_command(CommandTypes.Type.STOP)
	boat.global_position = Vector3(-60, Water.level, 60)
	await _wait(0.6)
	_check("Once the boat leaves, the submarine is hidden again", not Stealth.visible_to(enemy_sub, true))
	shore_gun.queue_free()

	## Our submarine against a ship: hidden until it fires, surfaces to fire.
	var target_ship = _disarm(_spawn(BOAT, false, Vector3(10, 0, 70)))
	sub.global_position = Vector3(10 - 13.0, Water.level, 70)
	sub.issue_command(CommandTypes.Type.STOP)
	await _wait(0.6)
	_check("Our submarine is hidden from the enemy while submerged",
		not Stealth.visible_to(sub, false))
	var ts_hp: float = target_ship.health.current_health
	sub.get_node("AttackerComponent").set_physics_process(true)
	sub.attack_target(target_ship)
	await _wait(0.6)
	_check("RULE torpedoes hit ships", target_ship.health.current_health < ts_hp,
		"(%.0f -> %.0f)" % [ts_hp, target_ship.health.current_health])
	_check("Firing surfaces it: the enemy can see and shoot it", Stealth.visible_to(sub, false)
		and CombatTarget.domain_of(sub) == CombatTarget.Domain.NAVAL)
	sub.issue_command(CommandTypes.Type.STOP)
	sub.get_node("AttackerComponent").set_physics_process(false)
	await _wait(Stealth.SURFACE_TIME + 0.6)
	_check("...and it dives out of sight again afterwards", not Stealth.visible_to(sub, false))
	## A submarine has no sonar of its own: an undetected enemy sub
	## cannot be targeted even by torpedoes.
	sub.global_position = enemy_sub.global_position + Vector3(-13, 0, 0)
	await _wait(0.4)
	sub.attack_target(enemy_sub)
	_check("A submarine cannot target a hidden submarine (it has no sonar)",
		sub.get_node("AttackerComponent").target != enemy_sub)
	sub.issue_command(CommandTypes.Type.STOP)

	## ...and cannot touch land.
	var beach_soldier = _disarm(_spawn(SOLDIER, false, Vector3(-10, 0, 18)))
	await _wait(0.3)
	SelectionManager.clear_selection()
	SelectionManager._select_unit(sub)
	_feedback.clear()
	await _look(beach_soldier.global_position)
	await _click(_cam().unproject_position(beach_soldier.global_position + Vector3.UP * 1.6), MOUSE_BUTTON_RIGHT)
	_check("RULE a submarine cannot attack land: the order is refused with a reason",
		_last()[1] == Feedback.Kind.REJECT and String(_last()[0]).contains("can attack"), "(%s)" % _last()[0])
	var card: String = hud._describe_one(sub)
	_check("The card shows the submarine's state",
		card.contains("SUBMERGED") or card.contains("SURFACED"), "")

	## Sonar buoy.
	var buoy = _spawn_building(BUOY, true, Vector3(-68, 0, 36))
	enemy_sub.global_position = Vector3(-68 + 15, Water.level, 44)
	await _wait(0.6)
	_check("A Sonar Buoy exposes submarines within 22m", Stealth.visible_to(enemy_sub, true))
	sub.get_node("AttackerComponent").set_physics_process(false)
	sub.global_position = enemy_sub.global_position + Vector3(-13, 0, 0)
	sub.issue_command(CommandTypes.Type.STOP)
	await _wait(3.4)
	var es_hp2: float = enemy_sub.health.current_health
	sub.get_node("AttackerComponent").set_physics_process(true)
	sub.get_node("Weapon")._cooldown_remaining = 0.0
	sub.attack_target(enemy_sub)
	await _wait(0.6)
	_check("RULE torpedoes hit a submarine that sonar has found", enemy_sub.health.current_health < es_hp2,
		"(%.0f -> %.0f)" % [es_hp2, enemy_sub.health.current_health])
	_disarm(sub)

	# --- 9. save / load keeps the navy ---
	var data := {"buildings": [SaveGame._capture_building(yard), SaveGame._capture_building(buoy)],
		"units": [SaveGame._capture_unit(boat), SaveGame._capture_unit(sub)],
		"credits": GameState.credits, "enemy_credits": GameState.enemy_credits}
	var yards_before := _count_buildings(YARD)
	SaveGame.restore(_main, data,
		func(stats, is_player, position): return _main._spawn_unit(stats.unit_scene, stats, is_player, position),
		func(stats, is_player, position, neutral): return _main._spawn_saved_building(stats, is_player, position, neutral),
		func(position, amount): _main._spawn_resource_node(position, amount))
	var restored_sub: Node = null
	for u in get_tree().get_nodes_in_group("player_units"):
		if u.stats == SUB and u != sub:
			restored_sub = u
	if restored_sub != null:
		_disarm(restored_sub)
	await _wait(0.5)
	_check("Save/restore brings back the Naval Yard", _count_buildings(YARD) == yards_before + 1)
	_check("...and the ships, afloat", restored_sub != null and _wet(restored_sub.global_position)
		and _count(BOAT, true) >= 2)
	_check("...and the restored submarine is still a stealthy submarine",
		restored_sub != null and restored_sub.get_node_or_null("Stealth") != null
		and not Stealth.visible_to(restored_sub, false))

func _count(stats: UnitStats, player: bool) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("player_units" if player else "enemy_units"):
		if is_instance_valid(u) and u.stats == stats:
			n += 1
	return n

func _first(stats: UnitStats, player: bool) -> Node:
	for u in get_tree().get_nodes_in_group("player_units" if player else "enemy_units"):
		if is_instance_valid(u) and u.stats == stats:
			return u
	return null

func _count_buildings(stats: BuildingStats) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("player_buildings"):
		if is_instance_valid(b) and b.stats == stats and not b.is_queued_for_deletion():
			n += 1
	return n
