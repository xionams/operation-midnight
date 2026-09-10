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
const ECONOMY_CONFIG: EconomyConfig = preload("res://config/economy/default_economy.tres")

const HARVESTER_COST: int = 1200

@export var map_size: float = 120.0
@export var bounds_margin: float = 6.0

const PLAYER_BASE_POS: Vector3 = Vector3(-42, 0, -42)
const ENEMY_BASE_POS: Vector3 = Vector3(42, 0, 42)
const RESOURCE_NODE_A_POS: Vector3 = Vector3(-15, 0, 8)
const RESOURCE_NODE_B_POS: Vector3 = Vector3(16, 0, -6)

var _level: Node3D
var _nav_region: NavigationRegion3D
var _bounds_min: Vector2
var _bounds_max: Vector2

func _ready() -> void:
	var half_size: float = map_size / 2.0 - bounds_margin
	_bounds_min = Vector2(-half_size, -half_size)
	_bounds_max = Vector2(half_size, half_size)

	_build_environment()
	_build_level_and_ground()
	_spawn_player_base()
	_spawn_enemy_base()
	_spawn_resource_fields()
	_nav_region.bake_navigation_mesh(false)

	var camera := _build_camera()
	camera.zoom_distance = 38.0
	camera.focus_on(PLAYER_BASE_POS.lerp(Vector3.ZERO, 0.35))

	var placer := _build_placer()
	_build_hud(placer)

	EventBus.building_placed.connect(func(_building): _nav_region.bake_navigation_mesh(true))

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
	navmesh.agent_radius = 1.0
	navmesh.agent_height = 2.0
	navmesh.agent_max_climb = 0.5
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
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
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.34, 0.2)
	mesh_instance.material_override = material
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
	_spawn_building(COMMAND_HQ_SCENE, COMMAND_HQ_STATS, true, PLAYER_BASE_POS)
	_spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, true, PLAYER_BASE_POS + Vector3(9, 0, 0))
	_spawn_unit(SCOUT_VEHICLE_SCENE, SCOUT_VEHICLE_STATS, true, PLAYER_BASE_POS + Vector3(0, 0, 9))

func _spawn_enemy_base() -> void:
	_spawn_building(COMMAND_HQ_SCENE, COMMAND_HQ_STATS, false, ENEMY_BASE_POS)
	var enemy_a := _spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, false, ENEMY_BASE_POS + Vector3(-9, 0, 0))
	_attach_enemy_ai(enemy_a)
	var enemy_b := _spawn_unit(ASSAULT_VEHICLE_SCENE, ASSAULT_VEHICLE_STATS, false, ENEMY_BASE_POS + Vector3(0, 0, -9))
	_attach_enemy_ai(enemy_b)

func _attach_enemy_ai(unit: Node) -> void:
	var ai := EnemyAIController.new()
	ai.name = "AI"
	unit.add_child(ai)

func _spawn_resource_fields() -> void:
	var per_node_amount: float = float(ECONOMY_CONFIG.resource_node_amount) / 2.0
	_spawn_resource_node(RESOURCE_NODE_A_POS, per_node_amount)
	_spawn_resource_node(RESOURCE_NODE_B_POS, per_node_amount)

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

func _build_hud(placer: BuildingPlacer) -> void:
	var hud := HUD.new()
	hud.name = "HUD"
	hud.power_plant_stats = POWER_PLANT_STATS
	hud.refinery_stats = REFINERY_STATS
	hud.harvester_cost = HARVESTER_COST
	hud.placer = placer
	add_child(hud)
