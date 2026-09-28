extends Node

## Phase 3's visual systems, proved in the running game on Coastline:
## the modelled kit is what spawns, named parts animate, the Naval Yard's
## berth faces the sea, damage darkens real models, ships leave wakes,
## submerged submarines bubble, vehicles face where they drive, and the
## sea is the depth-shaded water rather than a flat plane.

const MAJOR_UNITS: Array = ["scout_vehicle", "main_battle_tank", "assault_vehicle",
	"artillery_vehicle", "harvester", "patrol_boat", "submarine"]
const MAJOR_BUILDINGS: Array = ["command_hq", "power_plant", "barracks", "refinery",
	"war_factory", "wall", "gate", "naval_yard", "sonar_buoy", "civilian_house",
	"civilian_structure", "civilian_warehouse"]

var _main: Node3D
var _fails: Array = []

func _ready() -> void:
	GameState.selected_map = load("res://config/maps/coastline.tres")
	_main = get_parent()
	await get_tree().process_frame
	var hud = _main.get_node_or_null("HUD")
	if hud and hud.has_method("_begin_match"):
		hud._begin_match()
	await get_tree().process_frame
	var director = _main.get_node_or_null("AIDirector")
	if director != null:
		director.enabled = false
	await _run()
	print("TEST| ---- %d failure(s) ----" % _fails.size())
	for f in _fails:
		print("TEST| FAIL ", f)
	print("TEST| DONE")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("TEST| %-62s %s %s" % [name, "PASS" if cond else "FAIL", detail])
	if not cond:
		_fails.append(name + " " + detail)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _spawn(id: String, player: bool, pos: Vector3) -> Node:
	var stats: UnitStats = load("res://config/units/%s.tres" % id)
	var u = stats.unit_scene.instantiate()
	u.stats = stats
	u.is_player_faction = player
	_main.get_node("Level").add_child(u)
	var y: float = Water.level if stats.movement_domain == PlacementDomain.Domain.WATER \
		else Terrain.height_at(pos.x, pos.z)
	u.global_position = Vector3(pos.x, y, pos.z)
	return u

func _build(id: String, player: bool, pos: Vector3) -> Node:
	var stats: BuildingStats = load("res://config/buildings/%s.tres" % id)
	var b = stats.scene.instantiate()
	b.stats = stats
	b.is_player_faction = player
	_main.get_node("Level/NavRegion").add_child(b)
	b.global_position = Vector3(pos.x, PlacementDomain.surface_y(stats, pos.x, pos.z), pos.z)
	EventBus.building_placed.emit(b)
	return b

func _overlaid(root: Node) -> bool:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_overlay != null:
			return true
	return false

func _run() -> void:
	# --- the modelled kit is what the game spawns ---------------------------
	var stale: Array = []
	for id in MAJOR_UNITS:
		var s: UnitStats = load("res://config/units/%s.tres" % id)
		if s.visual_scene == null or s.visual_scene.resource_path.get_base_dir() == "res://assets/models":
			stale.append(id)
	for id in MAJOR_BUILDINGS:
		var s: BuildingStats = load("res://config/buildings/%s.tres" % id)
		if s.visual_scene == null or s.visual_scene.resource_path.get_base_dir() == "res://assets/models":
			stale.append(id)
	_check("Every major unit and building uses a Phase 3 model", stale.is_empty(), str(stale))
	var house: BuildingStats = load("res://config/buildings/civilian_house.tres")
	var warehouse: BuildingStats = load("res://config/buildings/civilian_warehouse.tres")
	_check("Civilian buildings are distinct models, not a rescaled cube",
		house.visual_scene != warehouse.visual_scene and house.visual_scale == Vector3.ONE
		and warehouse.visual_scale == Vector3.ONE)

	# --- named parts animate -----------------------------------------------
	## Powered, because radars (and refinery machinery) stop without power.
	for i in 3:
		_build("power_plant", true, Vector3(-60 + i * 8, 0, -56))
	var hq = _build("command_hq", true, Vector3(-40, 0, -40))
	var refinery = _build("refinery", true, Vector3(-24, 0, -40))
	var yard = _build("naval_yard", true, Vector3(-80, 0, 28))
	await _wait(0.3)
	var radar: Node3D = hq.find_child("Radar", true, false)
	var r0: float = radar.rotation.y if radar else 0.0
	var crane: Node3D = yard.find_child("Crane", true, false)
	var c0: float = crane.rotation.y if crane else 0.0
	var gantry: Node3D = yard.find_child("Gantry", true, false)
	var g0: Vector3 = gantry.position if gantry else Vector3.ZERO
	await _wait(1.5)
	_check("HQ radar spins while the base has power", radar != null and absf(radar.rotation.y - r0) > 0.3,
		"(power %d/%d)" % [GameState.power_consumed, GameState.power_generated])
	GameState.register_power_consumption(2000)
	await _wait(0.2)
	var r1: float = radar.rotation.y if radar else 0.0
	await _wait(1.0)
	_check("...and stops in LOW POWER", radar != null and absf(radar.rotation.y - r1) < 0.001)
	GameState.unregister_power_consumption(2000)
	_check("Naval Yard crane slews and the gantry travels",
		crane != null and gantry != null and absf(crane.rotation.y - c0) > 0.01
		and gantry.position.distance_to(g0) > 0.01)
	_check("Refinery carries its machinery animator",
		refinery.get_node_or_null("ModelAnimator") != null and refinery.find_child("Machinery", true, false) != null)

	# --- the berth faces the sea, and ships leave through it -----------------
	var a: float = (yard._visual_root as Node3D).rotation.y
	var mouth: Vector3 = yard.global_position + Vector3(cos(a), 0, -sin(a)) * 9.0
	_check("Naval Yard berth opens onto open water", Water.is_water(mouth.x, mouth.z),
		"(mouth %s)" % str(mouth))
	yard.produce(load("res://config/units/patrol_boat.tres"))
	GameState.add_credits(2000)
	var launched: Node = null
	for i in 200:
		await get_tree().process_frame
		for u in get_tree().get_nodes_in_group("player_units"):
			if is_instance_valid(u) and u.stats != null and u.stats.display_name == "Patrol Boat":
				launched = u
		if launched != null:
			break
		await _wait(0.1)
	_check("A ship is launched out of the berth mouth", launched != null
		and launched.global_position.distance_to(yard.global_position + Vector3(cos(a), 0, -sin(a)) * 9.0) < 6.0,
		"(%s)" % (str(launched.global_position) if launched else "none"))

	# --- ships ride the swell and leave a wake; subs bubble when down --------
	var boat = _spawn("patrol_boat", true, Vector3(-40, 0, 50))
	await _wait(0.5)
	var wake: CPUParticles3D = boat.find_child("Wake", true, false)
	_check("A patrol boat has a wake emitter, idle when stopped", wake != null and not wake.emitting)
	boat.issue_command(CommandTypes.Type.MOVE, Vector3(0, 0, 50))
	await _wait(2.0)
	_check("...which runs while it is under way", wake != null and wake.emitting)
	var visual: Node3D = boat.get("_model")
	var y0: float = visual.position.y if visual else 0.0
	await _wait(0.7)
	_check("The hull rides the swell", visual != null and absf(visual.position.y - y0) > 0.001)

	var sub = _spawn("submarine", true, Vector3(-30, 0, 70))
	await _wait(1.0)
	var bubbles: CPUParticles3D = sub.find_child("Bubbles", true, false)
	_check("A submerged submarine bubbles", bubbles != null and bubbles.emitting
		and Stealth.is_submerged(sub))
	sub.get_node("Stealth").surface()
	await _wait(0.4)
	_check("...and stops when it surfaces", bubbles != null and not bubbles.emitting)

	# --- damage darkens real models, repair clears it -----------------------
	var plant = _build("power_plant", true, Vector3(-40, 0, -24))
	await _wait(0.2)
	_check("A healthy model carries no damage tint", not _overlaid(plant))
	plant.health.take_damage(plant.health.max_health * 0.5)
	await _wait(0.2)
	_check("At half health the model is darkened", _overlaid(plant))
	plant.health.heal_to_full()
	await _wait(0.2)
	_check("Repaired, the tint is gone", not _overlaid(plant))
	var tank = _spawn("main_battle_tank", true, Vector3(-50, 0, -10))
	await _wait(0.2)
	tank.health.take_damage(tank.health.max_health * 0.8)
	await _wait(0.2)
	_check("A badly damaged vehicle is darkened too", _overlaid(tank))

	# --- vehicles face where they drive ------------------------------------
	var scout = _spawn("scout_vehicle", true, Vector3(-60, 0, -8))
	await _wait(0.3)
	scout.issue_command(CommandTypes.Type.MOVE, Vector3(-30, 0, -8))
	await _wait(1.5)
	var fwd: Vector3 = -scout.global_transform.basis.z
	_check("A moving vehicle's nose (-Z) points along its travel", fwd.x > 0.8, "(%s)" % str(fwd))

	# --- the sea and the shore ---------------------------------------------
	var surface: MeshInstance3D = _main.find_child("WaterSurface", true, false)
	var mat := surface.material_override as ShaderMaterial if surface else null
	_check("The sea uses the water shader", mat != null and mat.shader.resource_path.ends_with("water.gdshader"))
	var arrays: Array = surface.mesh.surface_get_arrays(0) if surface else []
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays.size() > 0 and arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var shallow: bool = false
	var deep: bool = false
	for c in colors:
		shallow = shallow or c.r < 0.2
		deep = deep or c.r > 0.9
	_check("The sea mesh carries baked depth, shallows to open sea", shallow and deep,
		"(%d vertices)" % colors.size())
