extends Node

## Getting unjammed must never become a way through something solid.
##
## The old recovery was a blind random nudge: as likely to shove a unit
## deeper into whatever had caught it as out of it, so a harvester pinned
## in a corner could jitter there indefinitely, and it moved the body
## without checking what it crossed. These tests pin down both halves -
## that the escape is deterministic and actually frees units, and that it
## cannot pass through a wall, a building, or a shoreline.
##
## Coastline on purpose: it is the only map with a sea, so the land/water
## domain guard is exercised rather than trivially true.

const COAST := preload("res://config/maps/coastline.tres")
const HARVESTER := preload("res://config/units/harvester.tres")
const TANK := preload("res://config/units/assault_vehicle.tres")
const BOAT := preload("res://config/units/patrol_boat.tres")
const REFINERY := preload("res://config/buildings/refinery.tres")
const WALL := preload("res://config/buildings/wall.tres")

var _main: Node3D
var _fails: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-60s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name)

func _wait(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += get_process_delta_time()
		await get_tree().process_frame

func _spawn(stats, player: bool, pos: Vector3) -> Node:
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	u.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	return u

func _build(stats, pos: Vector3) -> Node:
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = true
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(pos.x, Terrain.height_at(pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
	var region = _main.get_node("Level/NavRegion")
	var waited: float = 0.0
	while region.is_baking() and waited < 8.0:
		waited += get_process_delta_time()
		await get_tree().process_frame
	for i in 6:
		await get_tree().physics_frame

func _ready() -> void:
	GameState.selected_map = COAST
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	FogOfWar.enabled = false
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	GameState.add_credits(60000)
	await _settle()

	await _never_crosses_solid_ground()
	await _deterministic_and_keeps_its_orders()
	await _frees_units_from_real_jams()

	GameState.selected_map = null
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	print("TEST| DONE")
	get_tree().quit()

# ------------------------------------------- the escape cannot cheat

func _never_crosses_solid_ground() -> void:
	var base: Vector3 = COAST.player_base
	var tank = _spawn(TANK, true, base + Vector3(10, 0, 6))
	await _settle()

	## The sea. A land unit may not step into it however jammed it is.
	var shore := Vector3(base.x, 0.0, 40.0)
	while not Water.is_water(shore.x, shore.z) and shore.z < 100.0:
		shore.z += 2.0
	_check("Found the sea to test against", Water.is_water(shore.x, shore.z),
		"%s" % shore)
	tank.global_position = Vector3(shore.x, Terrain.height_at(shore.x, shore.z - 8.0),
		shore.z - 8.0)
	await _settle()
	_check("A land unit will not slip into the sea",
		not tank._can_slip_to(Vector3(shore.x, tank.global_position.y, shore.z + 4.0)))

	## A wall. Build a run, stand against it, and try to slip across.
	var spot: Vector3 = base + Vector3(0, 0, 12)
	var walls: Array = []
	for i in range(-4, 5):
		walls.append(_build(WALL, spot + Vector3(float(i) * 1.9, 0, 0)))
	await _settle()
	tank.global_position = Vector3(spot.x, Terrain.height_at(spot.x, spot.z - 3.0), spot.z - 3.0)
	await _settle()
	var across := Vector3(spot.x, tank.global_position.y, spot.z + 3.0)
	_check("A unit will not slip through a wall it is pressed against",
		not tank._can_slip_to(across),
		"from %s to %s" % [tank.global_position, across])
	## ...but open ground on its own side is still available.
	_check("Open ground on its own side is still reachable",
		tank._can_slip_to(Vector3(spot.x + 6.0, tank.global_position.y, spot.z - 3.0)))
	for w in walls:
		if is_instance_valid(w):
			w.queue_free()
	await _settle()

	## A ship's escape must stay wet.
	var sea: Vector3 = Water.nearest_water(Vector3(base.x, 0, 60.0), 120.0)
	if Water.is_navigable(sea.x, sea.z):
		var boat = _spawn(BOAT, true, sea)
		boat.global_position = Vector3(sea.x, Water.level, sea.z)
		await _settle()
		var ashore := Vector3(base.x, Water.level, base.z)
		_check("A ship will not slip ashore", not boat._can_slip_to(ashore))
		boat.queue_free()
	tank.queue_free()
	await _settle()

# ----------------------------------- deterministic, and keeps its job

func _deterministic_and_keeps_its_orders() -> void:
	var base: Vector3 = COAST.player_base
	var tank = _spawn(TANK, true, base + Vector3(14, 0, 0))
	await _settle()
	var destination: Vector3 = base + Vector3(40, 0, 0)

	## The same jam must always resolve the same way: a random nudge made
	## every run different and every failure unreproducible.
	var a: Vector3 = tank._escape_step(destination)
	var b: Vector3 = tank._escape_step(destination)
	var c: Vector3 = tank._escape_step(destination)
	_check("The escape step is deterministic", a == b and b == c,
		"%s / %s / %s" % [a, b, c])
	_check("The escape step is a real move", a.length() > 0.5, "%.2fm" % a.length())

	## Recovery must not lose the order the unit was carrying out.
	tank.move_to(destination)
	await _settle()
	tank._stuck_strikes = 2
	tank._stuck_timer = 999.0
	tank._stuck_reference = tank.global_position
	tank._tick_unstick(0.016)
	_check("Recovery restores the original destination",
		tank.nav_agent.target_position.distance_to(destination) < 0.01,
		"%s" % tank.nav_agent.target_position)
	tank.queue_free()
	await _settle()

# --------------------------------------------- real jams, real units

func _frees_units_from_real_jams() -> void:
	var base: Vector3 = COAST.player_base

	## (a) A narrow base exit: a wall box with a single gap.
	var box: Vector3 = base + Vector3(-26, 0, 0)
	var pen: Array = []
	## The gap has to clear the navmesh's own erosion, not just the wall
	## footprint: agent_radius is 1.7m, so a one-segment 1.9m hole leaves
	## NO walkable ground at all and the pen is simply sealed. Three
	## segments out is the narrowest exit a unit can actually use.
	for i in range(-4, 5):
		if absi(i) > 1:
			pen.append(_build(WALL, box + Vector3(float(i) * 1.9, 0, 5.0)))
		pen.append(_build(WALL, box + Vector3(float(i) * 1.9, 0, -5.0)))
	for i in range(-2, 3):
		pen.append(_build(WALL, box + Vector3(-7.6, 0, float(i) * 1.9)))
		pen.append(_build(WALL, box + Vector3(7.6, 0, float(i) * 1.9)))
	await _settle()
	var penned: Array = []
	for i in 3:
		penned.append(_spawn(TANK, true, box + Vector3(float(i) * 2.2 - 2.2, 0, 0)))
	await _settle()
	var out_target: Vector3 = base + Vector3(-26, 0, 26)
	for t in penned:
		t.move_to(out_target)
	await _wait(26.0)
	var escaped: int = 0
	for t in penned:
		if is_instance_valid(t) and t.global_position.z > box.z + 6.0:
			escaped += 1
	_check("Units find the one gap in a walled pen", escaped >= 2,
		"%d of 3 got out" % escaped)
	for t in penned:
		if is_instance_valid(t):
			t.queue_free()
	for w in pen:
		if is_instance_valid(w):
			w.queue_free()
	await _settle()

	## (b) Refinery congestion and harvesters blocking one another: four
	## harvesters, one refinery, all told to dock at once.
	var refinery = _build(REFINERY, base + Vector3(16, 0, -14))
	await _settle()
	var fleet: Array = []
	for i in 4:
		fleet.append(_spawn(HARVESTER, true, base + Vector3(16 + float(i) * 2.0, 0, -8)))
	await _settle()
	for h in fleet:
		h._refinery = refinery
		h.cargo = 300.0
		h.state = Harvester.State.TO_REFINERY
		h.move_to(refinery.global_position)
	var before: int = GameState.credits
	## Watch for each one REACHING the dock rather than sampling cargo at
	## the end: a harvester that delivered has already driven off and
	## picked up the next load, so an end-of-window cargo check reports
	## the ones still working as failures.
	var docked: Dictionary = {}
	var t: float = 0.0
	while t < 30.0:
		t += get_process_delta_time()
		for h in fleet:
			if is_instance_valid(h) and h.state == Harvester.State.UNLOADING:
				docked[h] = true
		await get_tree().process_frame
	var delivered: int = docked.size()
	var still_stuck: int = 0
	for h in fleet:
		if is_instance_valid(h) and h._stuck_strikes >= UnitBase.STUCK_GIVE_UP:
			still_stuck += 1
	_check("A congested refinery still gets unloaded", delivered >= 3,
		"%d of 4 reached the dock" % delivered)
	_check("Credits actually arrived", GameState.credits > before,
		"+%d" % (GameState.credits - before))
	_check("No harvester is left permanently jammed", still_stuck == 0,
		"%d still jammed" % still_stuck)

	## (c) Every harvester stays on land and out of the buildings.
	var misplaced: int = 0
	for h in fleet:
		if not is_instance_valid(h):
			continue
		if Water.is_water(h.global_position.x, h.global_position.z):
			misplaced += 1
	_check("Recovery never put a harvester in the sea", misplaced == 0)

	## (d) Congestion clears: they go back to work rather than idling.
	var working: int = 0
	for h in fleet:
		if is_instance_valid(h) and h.state != Harvester.State.IDLE:
			working += 1
	_check("Harvesters resume their round trip afterwards", working >= 3,
		"%d of 4 working" % working)
