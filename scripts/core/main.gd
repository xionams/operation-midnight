extends Node3D

## Assembles the Milestone 1 sandbox: ground + navmesh, both bases,
## resource fields, camera, HUD, and the building placer. Everything
## here is wiring — stat values live in config/*.tres, behavior lives
## in the unit/building/combat scripts. Swapping a map later means
## replacing this spawn layout, not touching gameplay code.

const ASSAULT_VEHICLE_SCENE: PackedScene = preload("res://scenes/units/assault_vehicle.tscn")
const SCOUT_VEHICLE_SCENE: PackedScene = preload("res://scenes/units/scout_vehicle.tscn")
const COMMAND_HQ_SCENE: PackedScene = preload("res://scenes/buildings/command_hq.tscn")
const RESOURCE_NODE_SCENE: PackedScene = preload("res://scenes/resources/resource_node.tscn")

const ASSAULT_VEHICLE_STATS: UnitStats = preload("res://config/units/assault_vehicle.tres")
const SCOUT_VEHICLE_STATS: UnitStats = preload("res://config/units/scout_vehicle.tres")
const COMMAND_HQ_STATS: BuildingStats = preload("res://config/buildings/command_hq.tres")
const POWER_PLANT_STATS: BuildingStats = preload("res://config/buildings/power_plant.tres")
const REFINERY_STATS: BuildingStats = preload("res://config/buildings/refinery.tres")
const WAR_FACTORY_STATS: BuildingStats = preload("res://config/buildings/war_factory.tres")
const BARRACKS_STATS: BuildingStats = preload("res://config/buildings/barracks.tres")
const HARVESTER_STATS: UnitStats = preload("res://config/units/harvester.tres")
const SOLDIER_STATS: UnitStats = preload("res://config/units/rifle_soldier.tres")
const ENGINEER_STATS: UnitStats = preload("res://config/units/engineer.tres")
const SPY_STATS: UnitStats = preload("res://config/units/spy.tres")
const DOG_STATS: UnitStats = preload("res://config/units/attack_dog.tres")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const COMMS_OUTPOST_STATS: BuildingStats = preload("res://config/buildings/comms_outpost.tres")
const REPAIR_DEPOT_STATS: BuildingStats = preload("res://config/buildings/repair_depot.tres")
const SUPPLY_DEPOT_STATS: BuildingStats = preload("res://config/buildings/supply_depot.tres")
const CIVILIAN_STATS: BuildingStats = preload("res://config/buildings/civilian_structure.tres")

## Empty buildings near the routes between bases. Infantry inside one is
## far harder to shift than infantry in the open, so they turn a corridor
## into a position worth holding.
const CIVILIAN_POSITIONS: Array[Vector3] = [
	Vector3(-14, 0, 18), Vector3(2, 0, -24), Vector3(38, 0, -6), Vector3(-46, 0, -30),
]
const RIFLE_SOLDIER_SCENE: PackedScene = preload("res://scenes/units/rifle_soldier.tscn")
const ECONOMY_CONFIG: EconomyConfig = preload("res://config/economy/default_economy.tres")

const DEFAULT_MAP: MapDefinition = preload("res://config/maps/ridgeline.tres")

@export var map_size: float = 220.0
@export var bounds_margin: float = 6.0

## The battlefield being played. Set by the skirmish setup screen through
## GameState; falls back to Ridgeline, which is the layout this project
## had when the positions below were constants.
var map: MapDefinition = DEFAULT_MAP

## Layout is deliberately spread across the full battlefield: nothing but
## the player's own corner is within opening vision, so every resource
## field, the neutral structure and the enemy base have to be found.
const PLAYER_BASE_POS: Vector3 = Vector3(-78, 0, 62)
const ENEMY_BASE_POS: Vector3 = Vector3(76, 0, -70)

## Close enough to the player's base to be found almost immediately - the
## opening economy should not require a scouting run.
const RESOURCE_NODE_A_POS: Vector3 = Vector3(-56, 0, 34)
## Rewards a short scouting trip.
const RESOURCE_NODE_B_POS: Vector3 = Vector3(-18, 0, -44)
## The contested prize in the middle of the map.
const RESOURCE_NODE_CENTRAL_POS: Vector3 = Vector3(6, 0, 6)
## The enemy's home field, mirroring the player's. Without it the map is
## simply unfair: the AI would start ~100m from the nearest ore and its
## economy would never start, which reads as a broken opponent rather
## than an easy one.
const RESOURCE_NODE_ENEMY_POS: Vector3 = Vector3(54, 0, -42)
## Contested map control, spread so no one side starts near all of them.
const COMMS_OUTPOST_POS: Vector3 = Vector3(-30, 0, -6)
const REPAIR_DEPOT_POS: Vector3 = Vector3(30, 0, 34)
const SUPPLY_DEPOT_POS: Vector3 = Vector3(-8, 0, 48)

## How much of their own ground the player starts knowing.
const START_REVEAL_RADIUS: float = 34.0

var _level: Node3D
var _nav_region: NavigationRegion3D
var _construction: ConstructionQueue
var _scenery: Scenery
var _bounds_min: Vector2
var _bounds_max: Vector2

func _ready() -> void:
	if GameState.selected_map != null:
		map = GameState.selected_map
	map_size = map.size
	var half_size: float = map_size / 2.0 - bounds_margin
	_bounds_min = Vector2(-half_size, -half_size)
	_bounds_max = Vector2(half_size, half_size)

	FogOfWar.configure(map_size)

	_build_environment()
	_build_level_and_ground()
	_spawn_player_base()
	_spawn_enemy_base()
	_spawn_resource_fields()
	_spawn_neutral_structure()
	_spawn_terrain_blockers()
	## OM_NO_SCENERY skips the decoration pass; see UnitBase._build_visual.
	if OS.get_environment("OM_NO_SCENERY").is_empty():
		_dress_battlefield()
	_nav_region.bake_navigation_mesh(false)

	## Seed the player's own ground as explored, then run one vision pass
	## so the opening frame is correct before the first fog tick.
	FogOfWar.reveal_area(map.player_base, map.start_reveal_radius)
	FogOfWar.update_now()

	var camera := _build_camera()
	camera.zoom_distance = 38.0
	camera.focus_on(map.player_base)

	_construction = ConstructionQueue.new()
	_construction.name = "ConstructionQueue"
	_construction.is_player = true
	add_child(_construction)

	var objectives := Objectives.new()
	objectives.name = "Objectives"
	add_child(objectives)

	_build_ai_director()

	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	add_child(overlay)

	var placer := _build_placer()
	_build_hud(placer, overlay)

	EventBus.building_placed.connect(func(_building): _nav_region.bake_navigation_mesh(true))
	EventBus.command_issued.connect(func(type, position): CommandMarker.spawn(_level, position, type))

const FOG_SHADER: Shader = preload("res://shaders/fog_terrain.gdshader")

## Terrain materials all share the one fog texture the visibility grid
## publishes, so the picture the player reads and the rules the game
## enforces come from the same source.
func _make_fog_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOG_SHADER
	material.set_shader_parameter("fog_tex", FogOfWar.get_texture())
	material.set_shader_parameter("map_size", map_size)
	material.set_shader_parameter("base_color", color)
	return material

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.15
	light.shadow_enabled = false
	add_child(light)

	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.65, 0.78)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	environment.ambient_light_energy = 0.65
	env_node.environment = environment
	add_child(env_node)

func _build_level_and_ground() -> void:
	_level = Node3D.new()
	_level.name = "Level"
	add_child(_level)

	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavRegion"
	_level.add_child(_nav_region)

	var navmesh := NavigationMesh.new()
	## Must be at least the widest unit's nav_radius (Harvester, 1.4) or
	## paths hug obstacles more closely than the unit physically fits, and
	## it wedges against terrain and never recovers.
	navmesh.agent_radius = 1.7
	navmesh.agent_height = 2.0
	navmesh.agent_max_climb = 0.5
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	## Ground(1) + buildings(4) block movement. Resource nodes (8) must not:
	## they would carve a hole around the ore that harvesters then cannot
	## path into, leaving them circling the thing they came to collect.
	navmesh.geometry_collision_mask = 1 | 4
	_nav_region.navigation_mesh = navmesh

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.add_to_group("ground")
	ground.collision_layer = 1
	ground.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(map_size, 1.0, map_size)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Visual only, and deliberately wider than the collision box below: the
	# ground the player can reach stays map_size (collision drives the navmesh
	# and every ground raycast), while the extra skirt keeps the map edge and
	# the void beyond it out of frame at the camera's shallowest angle.
	plane.size = Vector2(map_size * 2.4, map_size * 2.4)
	mesh_instance.mesh = plane
	mesh_instance.material_override = _make_fog_material(Color(0.24, 0.34, 0.2))
	ground.add_child(mesh_instance)

	_nav_region.add_child(ground)

func _spawn_building(scene: PackedScene, stats: BuildingStats, is_player: bool, pos: Vector3) -> Node:
	var building = scene.instantiate()
	building.stats = stats
	building.is_player_faction = is_player
	_nav_region.add_child(building)
	building.global_position = pos
	return building

func _spawn_unit(scene: PackedScene, stats: UnitStats, is_player: bool, pos: Vector3) -> Node:
	var unit = scene.instantiate()
	unit.stats = stats
	unit.is_player_faction = is_player
	_level.add_child(unit)
	unit.global_position = pos
	return unit

func _spawn_player_base() -> void:
	_spawn_building(COMMAND_HQ_SCENE, COMMAND_HQ_STATS, true, map.player_base)
	_spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, true, map.player_base + Vector3(9, 0, 0))
	_spawn_unit(SCOUT_VEHICLE_SCENE, SCOUT_VEHICLE_STATS, true, map.player_base + Vector3(0, 0, 9))

func _spawn_enemy_base() -> void:
	_spawn_building(COMMAND_HQ_SCENE, COMMAND_HQ_STATS, false, map.enemy_base)
	## A second enemy structure gives Engineers something worth capturing
	## and Spies something worth infiltrating, rather than a base whose
	## only building is the one that ends the match.
	_spawn_building(BARRACKS_SCENE, BARRACKS_STATS, false, map.enemy_base + Vector3(-14, 0, 6))
	var enemy_a := _spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, false, map.enemy_base + Vector3(-9, 0, 0))
	_attach_enemy_ai(enemy_a)
	var enemy_b := _spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, false, map.enemy_base + Vector3(0, 0, -9))
	_attach_enemy_ai(enemy_b)
	## Infantry on defence, so an unescorted Engineer or Spy is a real
	## risk rather than a guaranteed win.
	var guard := _spawn_unit(RIFLE_SOLDIER_SCENE, SOLDIER_STATS, false, map.enemy_base + Vector3(-12, 0, 3))
	_attach_enemy_ai(guard)

## The enemy commander runs the same economy and production the player
## does, so everything it fields had to be paid for and built.
func _build_ai_director() -> void:
	var director := AIDirector.new()
	director.name = "AIDirector"
	add_child(director)
	director.setup(_nav_region, _level, map.enemy_base, map.player_base)

func _attach_enemy_ai(unit: Node) -> void:
	var ai := EnemyAIController.new()
	ai.name = "AI"
	unit.add_child(ai)

## Ore comes from the map: x and z position the field, y is how much it
## holds. How much sits at home versus in the open is the main thing that
## makes one battlefield play differently from another.
func _spawn_resource_fields() -> void:
	for field in map.resource_fields:
		_spawn_resource_node(Vector3(field.x, 0.0, field.z), field.y)

## Genuinely neutral map control: nobody owns these until an Engineer
## walks in. Each pays a different benefit, so which one is worth the
## detour depends on how the match is going.
func _spawn_neutral_structure() -> void:
	_spawn_strategic(COMMS_OUTPOST_STATS, map.comms_outpost, StrategicStructure.Benefit.VISION)
	_spawn_strategic(REPAIR_DEPOT_STATS, map.repair_depot, StrategicStructure.Benefit.REPAIR)
	_spawn_strategic(SUPPLY_DEPOT_STATS, map.supply_depot, StrategicStructure.Benefit.SUPPLY)
	for position in map.civilian_positions:
		var civilian = CIVILIAN_STATS.scene.instantiate()
		civilian.stats = CIVILIAN_STATS
		civilian.is_neutral = true
		_nav_region.add_child(civilian)
		civilian.global_position = position

func _spawn_strategic(stats: BuildingStats, pos: Vector3, benefit: int) -> void:
	var structure = stats.scene.instantiate()
	structure.stats = stats
	structure.is_neutral = true
	structure.benefit = benefit
	_nav_region.add_child(structure)
	structure.global_position = pos

## Rock formations and barriers, so the battlefield has routes and choke
## points rather than being one open rectangle. Placeholder boxes: they
## exist to shape navigation, not to look like anything yet.
## Presentation only: pads, roads and props, none of which collide, so
## the navmesh and every existing path are unchanged.
func _dress_battlefield() -> void:
	_scenery = Scenery.new()
	_scenery.name = "Scenery"
	_scenery.map_size = map_size
	_level.add_child(_scenery)

	for field in map.resource_fields:
		_scenery._exclude(Vector3(field.x, 0.0, field.z), 11.0)
	for position in map.civilian_positions:
		_scenery._exclude(position, 9.0)
	for position in [map.comms_outpost, map.repair_depot, map.supply_depot]:
		_scenery._exclude(position, 9.0)
	for entry in _blocker_layout():
		_scenery.dress_blocker(entry[0], entry[1])

	_scenery.decorate_base(map.player_base, true)
	_scenery.decorate_base(map.enemy_base, false)
	## The road runs base to base through whatever sits in the middle, so
	## the route most fighting happens along is legible on any layout.
	var midpoint: Vector3 = (map.player_base + map.enemy_base) * 0.5
	if not map.resource_fields.is_empty():
		var best: Vector3 = midpoint
		var nearest: float = INF
		for field in map.resource_fields:
			var point := Vector3(field.x, 0.0, field.z)
			if point.distance_to(midpoint) < nearest:
				nearest = point.distance_to(midpoint)
				best = point
		midpoint = best
	var to_mid: Vector3 = (midpoint - map.player_base).normalized() * 20.0
	var from_mid: Vector3 = (midpoint - map.enemy_base).normalized() * 20.0
	_scenery.lay_road(map.player_base + to_mid, midpoint)
	_scenery.lay_road(midpoint, map.enemy_base + from_mid)
	_scenery.scatter(map_size, 90)

func _blocker_layout() -> Array:
	return map.blocker_pairs()

func _unused_blocker_layout() -> Array:
	return [
		[Vector3(-34, 0, 30), Vector3(30, 7, 10)],
		[Vector3(-4, 0, 40), Vector3(10, 7, 34)],
		[Vector3(34, 0, 26), Vector3(36, 7, 10)],
		[Vector3(-58, 0, -18), Vector3(10, 7, 40)],
		[Vector3(24, 0, -26), Vector3(10, 7, 44)],
		[Vector3(58, 0, 6), Vector3(34, 7, 10)],
		[Vector3(-10, 0, -74), Vector3(46, 7, 10)],
		## Kept clear of the line between the enemy base and its ore field;
		## sitting across it wedged their harvesters against the rock.
		[Vector3(74, 0, -22), Vector3(10, 7, 22)],
	]

func _spawn_terrain_blockers() -> void:
	for entry in _blocker_layout():
		_spawn_blocker(entry[0], entry[1])

func _spawn_blocker(pos: Vector3, size: Vector3) -> void:
	var rock := StaticBody3D.new()
	rock.name = "Blocker"
	rock.collision_layer = 1
	rock.collision_mask = 0
	rock.add_to_group("terrain_blockers")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y / 2.0, 0)
	rock.add_child(shape)

	## No mesh: Scenery.dress_blocker() puts rock faces on this footprint.
	## The collision box below is what actually blocks movement, and it is
	## unchanged.

	_nav_region.add_child(rock)
	rock.global_position = pos

func _spawn_resource_node(pos: Vector3, amount: float) -> void:
	var node = RESOURCE_NODE_SCENE.instantiate()
	node.total_amount = amount
	_nav_region.add_child(node)
	node.global_position = pos

func _build_camera() -> RTSCamera:
	var camera := RTSCamera.new()
	camera.name = "RTSCamera"
	camera.bounds_min = _bounds_min
	camera.bounds_max = _bounds_max
	camera.current = true
	add_child(camera)
	return camera

func _build_placer() -> BuildingPlacer:
	var placer := BuildingPlacer.new()
	placer.name = "BuildingPlacer"
	placer.bounds_min = _bounds_min
	placer.bounds_max = _bounds_max
	add_child(placer)
	return placer

func _build_hud(placer: BuildingPlacer, overlay: DebugOverlay) -> void:
	var hud := HUD.new()
	hud.name = "HUD"
	hud.placer = placer
	hud.debug_overlay = overlay
	hud.construction = _construction
	add_child(hud)
